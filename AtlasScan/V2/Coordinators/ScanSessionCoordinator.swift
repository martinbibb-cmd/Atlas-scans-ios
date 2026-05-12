/// ScanSessionCoordinator — Drives the live scan session lifecycle.

import Foundation
import SwiftUI
import AtlasScanCore

@MainActor
public final class ScanSessionCoordinator: ObservableObject {
    @Published public var session: SessionCaptureV2
    @Published public var showHandoff = false
    @Published public var isSaving = false
    @Published public var saveError: Error?
    /// Current phase of the visit capture workflow.
    @Published public var lifecycleState: VisitCaptureLifecycleState = .noVisit
    /// True when the coordinator loaded an existing session from disk on launch
    /// (i.e. the user has a visit in progress that can be resumed).
    @Published public var isResumingExistingSession = false
    /// Timestamp of the most recent successful session save to disk.
    /// `nil` until the first save completes after launch.
    @Published public var lastSaveDate: Date?

    private let store: AtomicSessionStore
    /// 50ms debounce coalesces rapid evidence mutations into one write while
    /// still feeling immediate during live capture interactions.
    private let autoSaveDebounceNanoseconds: UInt64 = 50_000_000
    private let minimumRotationRadians = 0.0001
    private let minimumWallLengthForScoreM = 0.5
    /// Alignment score where lower is better (`0` is ideal). Candidate walls must
    /// score at or below this threshold to be treated as a valid connection.
    private let maximumWallMatchScoreForAlignment = 0.95
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingRoomConnectionHint: NextRoomConnectionHint?

    /// UserDefaults key that stores the active visit's UUID between app launches.
    static let activeVisitIdKey = "v2ActiveVisitId"
    /// UserDefaults key that stores the last-known lifecycle state string.
    static let activeLifecycleStateKey = "v2LifecycleState"

    public init(
        visitId: UUID? = nil,
        store: AtomicSessionStore = .shared
    ) {
        self.store = store

        if let visitId {
            // Caller-specified visitId — load if session file exists, otherwise create fresh.
            if let loaded = try? store.load(visitId: visitId) {
                self.session = loaded
                // Fall back to .choosingNextStep if the persisted state string is missing or
                // unrecognised — the user was in the middle of a visit, so choosing next step
                // is the safest recovery point (session is already loaded and rooms are intact).
                let rawState = UserDefaults.standard.string(forKey: Self.activeLifecycleStateKey) ?? ""
                self.lifecycleState = VisitCaptureLifecycleState(rawValue: rawState) ?? .choosingNextStep
                self.isResumingExistingSession = true
            } else {
                self.session = SessionCaptureV2(visitId: visitId)
                self.lifecycleState = .noVisit
                self.isResumingExistingSession = false
            }
        } else if
            let savedIdString = UserDefaults.standard.string(forKey: Self.activeVisitIdKey),
            let savedId = UUID(uuidString: savedIdString),
            let loaded = try? store.load(visitId: savedId)
        {
            // Resume an existing session recorded in UserDefaults.
            self.session = loaded
            // Fall back to .choosingNextStep if the persisted state string is missing or
            // unrecognised — the user was in the middle of a visit, so choosing next step
            // is the safest recovery point (session is already loaded and rooms are intact).
            let rawState = UserDefaults.standard.string(forKey: Self.activeLifecycleStateKey) ?? ""
            self.lifecycleState = VisitCaptureLifecycleState(rawValue: rawState) ?? .choosingNextStep
            self.isResumingExistingSession = true
        } else {
            // Fresh session.
            self.session = SessionCaptureV2(visitId: UUID())
            self.lifecycleState = .noVisit
            self.isResumingExistingSession = false
        }
    }

    // MARK: - Lifecycle transitions

    /// Transitions the coordinator to a new lifecycle state and persists it.
    public func transition(to state: VisitCaptureLifecycleState) {
        lifecycleState = state
        UserDefaults.standard.set(state.rawValue, forKey: Self.activeLifecycleStateKey)
        scheduleSave()
    }

    /// Discards the current active session: clears UserDefaults, removes the
    /// session file from disk, and creates a fresh empty session in memory.
    public func discardActiveSession() {
        let oldVisitId = session.visitId
        UserDefaults.standard.removeObject(forKey: Self.activeVisitIdKey)
        UserDefaults.standard.removeObject(forKey: Self.activeLifecycleStateKey)
        try? store.delete(visitId: oldVisitId)
        session = SessionCaptureV2(visitId: UUID())
        lifecycleState = .noVisit
        isResumingExistingSession = false
    }

    // MARK: - Room management

    public func addRoom(_ room: RoomCaptureV2) {
        upsertRoom(room)
    }

    public func upsertRoom(_ room: RoomCaptureV2) {
        let resolvedRoom = resolvedPlacement(for: room)
        if let index = session.rooms.firstIndex(where: { $0.id == resolvedRoom.id }) {
            session.rooms[index] = resolvedRoom
        } else {
            session.rooms.append(resolvedRoom)
        }
        updateCeilingHeightQAFlag(for: resolvedRoom)
        updateGeometryQAFlags(for: resolvedRoom)
        scheduleSave()
    }

    public func room(withId roomId: UUID) -> RoomCaptureV2? {
        session.rooms.first(where: { $0.id == roomId })
    }

    public func updatePins(_ pins: [SpatialPinV1], for roomId: UUID) {
        guard let index = session.rooms.firstIndex(where: { $0.id == roomId }) else { return }
        session.rooms[index].pinnedObjects = pins
        scheduleSave()
    }

    public func addPhoto(_ photo: PhotoEvidenceV1) {
        session.photos.append(photo)
        scheduleSave()
    }

    public func addVoiceNote(_ note: VoiceNoteV1) {
        session.voiceNotes.append(note)
        session.transcripts.append(
            ProcessedTranscriptV1(
                visitId: note.visitId,
                roomId: note.roomId,
                capturePointId: note.capturePointId,
                linkedObjectId: note.linkedObjectId,
                transcript: note.processedTranscript,
                extractionHint: note.extractionHint
            )
        )
        scheduleSave()
    }

    public func updateEngineerNotes(_ notes: String?) {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.engineerNotes = (trimmed?.isEmpty == true) ? nil : trimmed
        scheduleSave()
    }

    // MARK: - Evidence deletion

    /// Removes a single evidence item from the session by its source evidence ID.
    ///
    /// Safe to call with pending (pre-room-save) evidence; those items simply
    /// will not be found in the session arrays and no change is made.
    /// The room record itself is never removed by this method.
    func deleteEvidenceItem(_ item: RecentCaptureItemV1) {
        switch item.evidenceType {
        case .photo:
            session.photos.removeAll { $0.id == item.sourceEvidenceId }

        case .voiceNote, .note:
            // Remove the companion transcript created by addVoiceNote.
            // Match by roomId + capturePointId + transcript content.
            // Limitation: if two notes in the same room+point share identical transcript
            // text, both companion transcripts are removed. This is an acceptable edge case
            // given how improbable identical free-text transcripts are in practice.
            if let note = session.voiceNotes.first(where: { $0.id == item.sourceEvidenceId }) {
                session.transcripts.removeAll {
                    $0.roomId == note.roomId &&
                    $0.capturePointId == note.capturePointId &&
                    $0.transcript == note.processedTranscript
                }
            }
            session.voiceNotes.removeAll { $0.id == item.sourceEvidenceId }

        case .objectPin:
            for i in session.rooms.indices {
                session.rooms[i].pinnedObjects.removeAll { $0.id == item.sourceEvidenceId }
            }

        case .ghostAppliance:
            for i in session.rooms.indices {
                session.rooms[i].ghostAppliancePlacements.removeAll { $0.id == item.sourceEvidenceId }
            }

        case .measurement:
            for i in session.rooms.indices {
                session.rooms[i].measurements.removeAll { $0.id == item.sourceEvidenceId }
            }
        }
        scheduleSave()
    }

    public func discardUnfinishedRoomEvidence(for roomId: UUID) {
        // Intentionally safe when called before a room is saved; missing array
        // elements simply result in no removals while orphaned evidence is cleared.
        session.rooms.removeAll { $0.id == roomId }
        session.photos.removeAll { $0.roomId == roomId }
        session.voiceNotes.removeAll { $0.roomId == roomId }
        session.transcripts.removeAll { $0.roomId == roomId }
        scheduleSave()
    }

    public func emitQAFlag(_ flag: QAFlagV1) {
        session.emitQAFlag(flag)
        scheduleSave()
    }

    // MARK: - Handoff

    public func handOffToMind() {
        showHandoff = true
    }

    // MARK: - Persistence

    public func saveSession() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        // Persist the visit ID pointer whenever the session has a reference so the
        // app can resume after being killed.
        let hasReference = !(session.visitReference?.isEmpty ?? true)
        if hasReference || !session.rooms.isEmpty {
            UserDefaults.standard.set(session.visitId.uuidString, forKey: Self.activeVisitIdKey)
            UserDefaults.standard.set(lifecycleState.rawValue, forKey: Self.activeLifecycleStateKey)
        }
        do {
            try store.save(session)
            lastSaveDate = Date()
        } catch {
            saveError = error
        }
    }

    public func loadRecalledSession(_ recalled: SessionCaptureV2) {
        session = recalled
    }

    public func prepareNextRoomConnection(
        fromRoomId: UUID,
        wallIndex: Int?,
        kind: NextRoomConnectionKind
    ) {
        guard kind != .separate, let wallIndex else {
            pendingRoomConnectionHint = nil
            return
        }
        pendingRoomConnectionHint = NextRoomConnectionHint(
            sourceRoomId: fromRoomId,
            sourceWallIndex: wallIndex,
            kind: kind
        )
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [autoSaveDebounceNanoseconds] in
            do {
                try await Task.sleep(nanoseconds: autoSaveDebounceNanoseconds)
            } catch {
                return
            }
            await self.saveSession()
        }
    }

    private func resolvedPlacement(for room: RoomCaptureV2) -> RoomCaptureV2 {
        guard session.rooms.allSatisfy({ $0.id != room.id }) else { return room }
        guard !session.rooms.isEmpty else { return room }
        var pendingRoom = room

        if let hint = pendingRoomConnectionHint,
           let sourceRoom = session.rooms.first(where: { $0.id == hint.sourceRoomId }) {
            pendingRoomConnectionHint = nil
            if let connectedPlacement = connectedPlacement(for: pendingRoom, sourceRoom: sourceRoom, hint: hint) {
                var connectedRoom = connectedPlacement
                connectedRoom.incomingConnectionReview = connectionReview(
                    from: hint,
                    status: hint.kind == .throughOpening ? .sharedWallCandidate : .attached,
                    note: hint.kind == .throughOpening
                        ? "Shared wall candidate found"
                        : "Next room will attach to this wall"
                )
                return connectedRoom
            }
            pendingRoom.incomingConnectionReview = connectionReview(
                from: hint,
                status: .needsReview,
                note: "No shared wall match yet"
            )
        }

        pendingRoomConnectionHint = nil

        let roomBounds = bounds(for: pendingRoom)
        let existingBounds = combinedBounds(for: session.rooms)
        let needsOffset =
            roomBounds.minX < existingBounds.maxX + 0.1 &&
            roomBounds.maxX > existingBounds.minX - 0.1 &&
            roomBounds.minZ < existingBounds.maxZ + 0.1 &&
            roomBounds.maxZ > existingBounds.minZ - 0.1

        guard needsOffset else { return pendingRoom }
        let dx = existingBounds.maxX - roomBounds.minX + 0.8
        return translated(pendingRoom, dx: dx, dz: 0)
    }

    private func translated(_ room: RoomCaptureV2, dx: Double, dz: Double) -> RoomCaptureV2 {
        var translatedRoom = room
        translatedRoom.polygonVertices = room.polygonVertices.map {
            Vertex2D(x: $0.x + dx, z: $0.z + dz)
        }
        translatedRoom.pinnedObjects = room.pinnedObjects.map { pin in
            SpatialPinV1(
                id: pin.id,
                roomId: pin.roomId,
                visitId: pin.visitId,
                externalAreaId: pin.externalAreaId,
                locationContext: pin.locationContext,
                capturePointId: pin.capturePointId,
                anchorId: pin.anchorId,
                worldTransform: pin.worldTransform,
                positionX: pin.positionX + dx,
                positionY: pin.positionY,
                positionZ: pin.positionZ + dz,
                screenPositionX: pin.screenPositionX,
                screenPositionY: pin.screenPositionY,
                objectType: pin.objectType,
                label: pin.label,
                objectCategory: pin.objectCategory,
                selectedTemplateId: pin.selectedTemplateId,
                manualEntry: pin.manualEntry,
                anchorConfidence: pin.anchorConfidence,
                reviewStatus: pin.reviewStatus,
                provenance: pin.provenance,
                hardwareSpecId: pin.hardwareSpecId,
                modelId: pin.modelId,
                surfaceSemantic: pin.surfaceSemantic
            )
        }
        translatedRoom.ghostAppliancePlacements = room.ghostAppliancePlacements.map { placement in
            translated(placement, dx: dx, dz: dz)
        }
        translatedRoom.measurements = room.measurements.map { translated($0, dx: dx, dz: dz) }
        return translatedRoom
    }

    private func translated(_ placement: GhostAppliancePlacementV1, dx: Double, dz: Double) -> GhostAppliancePlacementV1 {
        placement.translated(dx: dx, dz: dz)
    }

    private func translated(_ measurement: SpatialMeasurementV1, dx: Double, dz: Double) -> SpatialMeasurementV1 {
        transformedMeasurement(
            measurement,
            start: SIMD3(
                measurement.startWorldPosition.x + dx,
                measurement.startWorldPosition.y,
                measurement.startWorldPosition.z + dz
            ),
            end: SIMD3(
                measurement.endWorldPosition.x + dx,
                measurement.endWorldPosition.y,
                measurement.endWorldPosition.z + dz
            )
        )
    }

    private func connectedPlacement(
        for room: RoomCaptureV2,
        sourceRoom: RoomCaptureV2,
        hint: NextRoomConnectionHint
    ) -> RoomCaptureV2? {
        guard !room.wallSegments.isEmpty else { return nil }
        let sourceWalls = sourceRoom.wallSegments
        guard sourceWalls.indices.contains(hint.sourceWallIndex) else { return nil }
        let sourceWall = sourceWalls[hint.sourceWallIndex]

        guard let candidate = bestMatchingWallCandidate(in: room, for: sourceWall),
              candidate.score <= maximumWallMatchScoreForAlignment
        else {
            return nil
        }
        let candidateIndex = candidate.index
        let candidateWall = room.wallSegments[candidateIndex]
        let sourceVector = wallVector(sourceWall)
        let candidateVector = wallVector(candidateWall)
        let desiredAngle = atan2(-sourceVector.dz, -sourceVector.dx)
        let candidateAngle = atan2(candidateVector.dz, candidateVector.dx)
        let rotation = desiredAngle - candidateAngle

        let rotatedRoom = rotated(room, by: rotation)
        let rotatedWall = rotatedRoom.wallSegments[candidateIndex]
        let rotatedMidpoint = v2WallMidpoint(rotatedWall)
        let sourceMidpoint = v2WallMidpoint(sourceWall)
        let dx = sourceMidpoint.x - rotatedMidpoint.x
        let dz = sourceMidpoint.z - rotatedMidpoint.z
        return translated(rotatedRoom, dx: dx, dz: dz)
    }

    private func bestMatchingWallCandidate(in room: RoomCaptureV2, for sourceWall: WallSegmentV1) -> (index: Int, score: Double)? {
        let sourceLength = sourceWall.lengthM
        let sourceVector = wallVector(sourceWall)
        let desiredAngle = atan2(-sourceVector.dz, -sourceVector.dx)

        return room.wallSegments.enumerated().map { indexedWall in
            (index: indexedWall.offset, score: wallMatchScore(indexedWall.element, targetLength: sourceLength, desiredAngle: desiredAngle))
        }.min { lhs, rhs in
            lhs.score < rhs.score
        }
    }

    private func connectionReview(
        from hint: NextRoomConnectionHint,
        status: RoomConnectionReviewStatusV1,
        note: String
    ) -> RoomConnectionReviewV1 {
        RoomConnectionReviewV1(
            sourceRoomId: hint.sourceRoomId,
            sourceWallIndex: hint.sourceWallIndex,
            connectionKind: hint.kind.rawValue,
            status: status,
            note: note
        )
    }

    private func wallMatchScore(
        _ wall: WallSegmentV1,
        targetLength: Double,
        desiredAngle: Double
    ) -> Double {
        let vector = wallVector(wall)
        let angle = atan2(vector.dz, vector.dx)
        let normalizedAngleDelta = abs(v2SmallestAngleDifference(angle, desiredAngle)) / .pi
        let normalizedLengthDelta = abs(wall.lengthM - targetLength) / max(targetLength, minimumWallLengthForScoreM)
        return normalizedLengthDelta + normalizedAngleDelta
    }

    private func rotated(_ room: RoomCaptureV2, by angle: Double) -> RoomCaptureV2 {
        guard abs(angle) > minimumRotationRadians else { return room }
        let centre = roomCentroid(room)
        let angleDegrees = degreesFromRadians(angle)
        var rotatedRoom = room
        rotatedRoom.polygonVertices = room.polygonVertices.map {
            rotate(vertex: $0, around: centre, by: angle)
        }
        rotatedRoom.pinnedObjects = room.pinnedObjects.map { rotate(pin: $0, around: centre, by: angle) }
        rotatedRoom.ghostAppliancePlacements = room.ghostAppliancePlacements.map {
            rotate(placement: $0, around: centre, by: angle, angleDegrees: angleDegrees)
        }
        rotatedRoom.measurements = room.measurements.map { rotate(measurement: $0, around: centre, by: angle) }
        return rotatedRoom
    }

    private func roomCentroid(_ room: RoomCaptureV2) -> Vertex2D {
        guard !room.polygonVertices.isEmpty else { return Vertex2D(x: 0, z: 0) }
        let sum = room.polygonVertices.reduce((x: 0.0, z: 0.0)) { partial, vertex in
            (partial.x + vertex.x, partial.z + vertex.z)
        }
        let count = Double(room.polygonVertices.count)
        return Vertex2D(x: sum.x / count, z: sum.z / count)
    }

    private func rotate(vertex: Vertex2D, around centre: Vertex2D, by angle: Double) -> Vertex2D {
        let dx = vertex.x - centre.x
        let dz = vertex.z - centre.z
        let cosAngle = cos(angle)
        let sinAngle = sin(angle)
        return Vertex2D(
            x: centre.x + (dx * cosAngle) - (dz * sinAngle),
            z: centre.z + (dx * sinAngle) + (dz * cosAngle)
        )
    }

    private func rotate(pin: SpatialPinV1, around centre: Vertex2D, by angle: Double) -> SpatialPinV1 {
        let rotated = rotate(x: pin.positionX, z: pin.positionZ, around: centre, by: angle)
        return SpatialPinV1(
            id: pin.id,
            roomId: pin.roomId,
            visitId: pin.visitId,
            externalAreaId: pin.externalAreaId,
            locationContext: pin.locationContext,
            capturePointId: pin.capturePointId,
            anchorId: pin.anchorId,
            worldTransform: pin.worldTransform,
            positionX: rotated.x,
            positionY: pin.positionY,
            positionZ: rotated.z,
            screenPositionX: pin.screenPositionX,
            screenPositionY: pin.screenPositionY,
            objectType: pin.objectType,
            label: pin.label,
            objectCategory: pin.objectCategory,
            selectedTemplateId: pin.selectedTemplateId,
            manualEntry: pin.manualEntry,
            anchorConfidence: pin.anchorConfidence,
            reviewStatus: pin.reviewStatus,
            provenance: pin.provenance,
            hardwareSpecId: pin.hardwareSpecId,
            modelId: pin.modelId,
            surfaceSemantic: pin.surfaceSemantic
        )
    }

    private func rotate(
        placement: GhostAppliancePlacementV1,
        around centre: Vertex2D,
        by angle: Double,
        angleDegrees: Double
    ) -> GhostAppliancePlacementV1 {
        let rotated = rotate(x: placement.worldPositionX, z: placement.worldPositionZ, around: centre, by: angle)
        return GhostAppliancePlacementV1(
            id: placement.id,
            roomId: placement.roomId,
            capturePointId: placement.capturePointId,
            applianceModelId: placement.applianceModelId,
            customApplianceDefinitionId: placement.customApplianceDefinitionId,
            screenPoint: placement.screenPoint,
            placementPlane: placement.placementPlane,
            surfaceSemantic: placement.surfaceSemantic,
            planeNormalX: placement.planeNormalX,
            planeNormalY: placement.planeNormalY,
            planeNormalZ: placement.planeNormalZ,
            worldPositionX: rotated.x,
            worldPositionY: placement.worldPositionY,
            worldPositionZ: rotated.z,
            rotationYaw: normalizedDegrees(placement.rotationYaw + angleDegrees),
            dimensionsMm: placement.dimensionsMm,
            clearanceOffsetsMm: placement.clearanceOffsetsMm,
            anchorConfidence: placement.anchorConfidence,
            createdAt: placement.createdAt,
            notes: placement.notes
        )
    }

    private func rotate(
        measurement: SpatialMeasurementV1,
        around centre: Vertex2D,
        by angle: Double
    ) -> SpatialMeasurementV1 {
        let start = rotate(x: measurement.startWorldPosition.x, z: measurement.startWorldPosition.z, around: centre, by: angle)
        let end = rotate(x: measurement.endWorldPosition.x, z: measurement.endWorldPosition.z, around: centre, by: angle)
        return transformedMeasurement(
            measurement,
            start: SIMD3(start.x, measurement.startWorldPosition.y, start.z),
            end: SIMD3(end.x, measurement.endWorldPosition.y, end.z)
        )
    }

    private func rotate(x: Double, z: Double, around centre: Vertex2D, by angle: Double) -> Vertex2D {
        rotate(vertex: Vertex2D(x: x, z: z), around: centre, by: angle)
    }

    private func transformedMeasurement(
        _ measurement: SpatialMeasurementV1,
        start: SIMD3<Double>,
        end: SIMD3<Double>
    ) -> SpatialMeasurementV1 {
        SpatialMeasurementV1(
            id: measurement.id,
            roomId: measurement.roomId,
            startCapturePointId: measurement.startCapturePointId,
            endCapturePointId: measurement.endCapturePointId,
            startWorldPosition: start,
            endWorldPosition: end,
            startSurfaceSemantic: measurement.startSurfaceSemantic,
            endSurfaceSemantic: measurement.endSurfaceSemantic,
            anchorConfidence: measurement.anchorConfidence,
            createdAt: measurement.createdAt,
            notes: measurement.notes
        )
    }

    private func wallVector(_ wall: WallSegmentV1) -> (dx: Double, dz: Double) {
        (wall.endVertex.x - wall.startVertex.x, wall.endVertex.z - wall.startVertex.z)
    }

    private func combinedBounds(for rooms: [RoomCaptureV2]) -> (minX: Double, maxX: Double, minZ: Double, maxZ: Double) {
        rooms.reduce((Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)) { partial, room in
            let roomBounds = bounds(for: room)
            return (
                min(partial.0, roomBounds.minX),
                max(partial.1, roomBounds.maxX),
                min(partial.2, roomBounds.minZ),
                max(partial.3, roomBounds.maxZ)
            )
        }
    }

    private func bounds(for room: RoomCaptureV2) -> (minX: Double, maxX: Double, minZ: Double, maxZ: Double) {
        let xs = room.polygonVertices.map(\.x)
        let zs = room.polygonVertices.map(\.z)
        return (
            xs.min() ?? 0,
            xs.max() ?? 0,
            zs.min() ?? 0,
            zs.max() ?? 0
        )
    }

    /// Minimum floor area (m²) below which a captured room polygon is flagged
    /// as low-confidence. Rooms under 1 m² are almost certainly partial scans.
    private let minimumTypicalRoomAreaM2 = 1.0

    /// Inspects the room's floor polygon and emits geometry QA flags for
    /// degenerate or suspicious shapes. Called every time a room is upserted.
    private func updateGeometryQAFlags(for room: RoomCaptureV2) {
        session.qaFlags.removeAll {
            ($0.type == .polygonCollapsed || $0.type == .lowConfidenceRoomShape)
                && $0.roomId == room.id
        }
        let vertexCount = room.polygonVertices.count
        if vertexCount < 3 {
            session.emitQAFlag(
                QAFlagV1(
                    type: .polygonCollapsed,
                    roomId: room.id,
                    detail: "Room polygon has \(vertexCount) vertices — too few to form a valid room shape."
                )
            )
        } else if vertexCount == 3 {
            session.emitQAFlag(
                QAFlagV1(
                    type: .lowConfidenceRoomShape,
                    roomId: room.id,
                    detail: "Room polygon is a triangle (\(vertexCount) vertices) — capture may be incomplete."
                )
            )
        } else {
            let area = room.floorAreaM2
            if area < minimumTypicalRoomAreaM2 {
                session.emitQAFlag(
                    QAFlagV1(
                        type: .lowConfidenceRoomShape,
                        roomId: room.id,
                        detail: String(format: "Captured room area %.2f m² is unusually small.", area)
                    )
                )
            }
        }
    }

    private func updateCeilingHeightQAFlag(for room: RoomCaptureV2) {
        session.qaFlags.removeAll { $0.type == .abnormalCeilingHeight && $0.roomId == room.id }

        let sampledHeight = room.rawCapturedCeilingHeightM ?? room.ceilingHeightM
        let domesticRange = 1.9...3.5
        guard !domesticRange.contains(sampledHeight) else { return }

        session.emitQAFlag(
            QAFlagV1(
                type: .abnormalCeilingHeight,
                roomId: room.id,
                detail: String(format: "Captured ceiling height %.2f m is outside normal domestic range.", sampledHeight)
            )
        )
    }
}

public enum NextRoomConnectionKind: String, Sendable {
    case throughOpening
    case adjacentWall
    case separate
}

private struct NextRoomConnectionHint: Sendable {
    let sourceRoomId: UUID
    let sourceWallIndex: Int
    let kind: NextRoomConnectionKind
}

internal func v2WallMidpoint(_ wall: WallSegmentV1) -> Vertex2D {
    Vertex2D(
        x: (wall.startVertex.x + wall.endVertex.x) / 2,
        z: (wall.startVertex.z + wall.endVertex.z) / 2
    )
}

internal func v2SmallestAngleDifference(_ lhs: Double, _ rhs: Double) -> Double {
    // Wrap the raw delta into [-π, π] so angles near the 0/2π seam compare correctly.
    let raw = fmod(lhs - rhs + .pi, 2 * .pi)
    let wrapped = raw < 0 ? raw + 2 * .pi : raw
    return wrapped - .pi
}

internal func degreesFromRadians(_ radians: Double) -> Double {
    radians * 180 / .pi
}

internal func normalizedDegrees(_ degrees: Double) -> Double {
    let fullCircleDegrees = 360.0
    let wrapped = degrees.truncatingRemainder(dividingBy: fullCircleDegrees)
    return wrapped < 0 ? wrapped + fullCircleDegrees : wrapped
}
