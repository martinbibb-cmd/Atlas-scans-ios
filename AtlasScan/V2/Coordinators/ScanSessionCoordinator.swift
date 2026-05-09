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

    private let store: AtomicSessionStore
    /// 50ms debounce coalesces rapid evidence mutations into one write while
    /// still feeling immediate during live capture interactions.
    private let autoSaveDebounceNanoseconds: UInt64 = 50_000_000
    private let minimumRotationRadians = 0.0001
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingRoomConnectionHint: NextRoomConnectionHint?

    public init(
        visitId: UUID = UUID(),
        store: AtomicSessionStore = .shared
    ) {
        self.session = SessionCaptureV2(visitId: visitId)
        self.store = store
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
        do {
            try store.save(session)
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

        if let hint = pendingRoomConnectionHint,
           let sourceRoom = session.rooms.first(where: { $0.id == hint.sourceRoomId }),
           let connectedPlacement = connectedPlacement(for: room, sourceRoom: sourceRoom, hint: hint) {
            pendingRoomConnectionHint = nil
            return connectedPlacement
        }

        pendingRoomConnectionHint = nil

        let roomBounds = bounds(for: room)
        let existingBounds = combinedBounds(for: session.rooms)
        let needsOffset =
            roomBounds.minX < existingBounds.maxX + 0.1 &&
            roomBounds.maxX > existingBounds.minX - 0.1 &&
            roomBounds.minZ < existingBounds.maxZ + 0.1 &&
            roomBounds.maxZ > existingBounds.minZ - 0.1

        guard needsOffset else { return room }
        let dx = existingBounds.maxX - roomBounds.minX + 0.8
        return translated(room, dx: dx, dz: 0)
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
        SpatialMeasurementV1(
            id: measurement.id,
            roomId: measurement.roomId,
            startCapturePointId: measurement.startCapturePointId,
            endCapturePointId: measurement.endCapturePointId,
            startWorldPosition: SIMD3(
                measurement.startWorldPosition.x + dx,
                measurement.startWorldPosition.y,
                measurement.startWorldPosition.z + dz
            ),
            endWorldPosition: SIMD3(
                measurement.endWorldPosition.x + dx,
                measurement.endWorldPosition.y,
                measurement.endWorldPosition.z + dz
            ),
            startSurfaceSemantic: measurement.startSurfaceSemantic,
            endSurfaceSemantic: measurement.endSurfaceSemantic,
            anchorConfidence: measurement.anchorConfidence,
            createdAt: measurement.createdAt,
            notes: measurement.notes
        )
    }

    private func connectedPlacement(
        for room: RoomCaptureV2,
        sourceRoom: RoomCaptureV2,
        hint: NextRoomConnectionHint
    ) -> RoomCaptureV2? {
        let sourceWalls = sourceRoom.wallSegments
        guard sourceWalls.indices.contains(hint.sourceWallIndex) else { return nil }
        let sourceWall = sourceWalls[hint.sourceWallIndex]

        let candidateIndex = bestMatchingWallIndex(in: room, for: sourceWall)
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

    private func bestMatchingWallIndex(in room: RoomCaptureV2, for sourceWall: WallSegmentV1) -> Int {
        let sourceLength = sourceWall.lengthM
        let sourceVector = wallVector(sourceWall)
        let desiredAngle = atan2(-sourceVector.dz, -sourceVector.dx)

        return room.wallSegments.enumerated().min { lhs, rhs in
            let lhsScore = wallMatchScore(lhs.element, targetLength: sourceLength, desiredAngle: desiredAngle)
            let rhsScore = wallMatchScore(rhs.element, targetLength: sourceLength, desiredAngle: desiredAngle)
            return lhsScore < rhsScore
        }?.offset ?? 0
    }

    private func wallMatchScore(
        _ wall: WallSegmentV1,
        targetLength: Double,
        desiredAngle: Double
    ) -> Double {
        let vector = wallVector(wall)
        let angle = atan2(vector.dz, vector.dx)
        let angleDelta = abs(v2SmallestAngleDifference(angle, desiredAngle))
        let lengthDelta = abs(wall.lengthM - targetLength)
        return lengthDelta + angleDelta
    }

    private func rotated(_ room: RoomCaptureV2, by angle: Double) -> RoomCaptureV2 {
        guard abs(angle) > minimumRotationRadians else { return room }
        let centre = roomCentroid(room)
        var rotatedRoom = room
        rotatedRoom.polygonVertices = room.polygonVertices.map {
            rotate(vertex: $0, around: centre, by: angle)
        }
        rotatedRoom.pinnedObjects = room.pinnedObjects.map { rotate(pin: $0, around: centre, by: angle) }
        rotatedRoom.ghostAppliancePlacements = room.ghostAppliancePlacements.map {
            rotate(placement: $0, around: centre, by: angle)
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
        by angle: Double
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
            rotationYaw: placement.rotationYaw + angle * 180 / .pi,
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
        return SpatialMeasurementV1(
            id: measurement.id,
            roomId: measurement.roomId,
            startCapturePointId: measurement.startCapturePointId,
            endCapturePointId: measurement.endCapturePointId,
            startWorldPosition: SIMD3(start.x, measurement.startWorldPosition.y, start.z),
            endWorldPosition: SIMD3(end.x, measurement.endWorldPosition.y, end.z),
            startSurfaceSemantic: measurement.startSurfaceSemantic,
            endSurfaceSemantic: measurement.endSurfaceSemantic,
            anchorConfidence: measurement.anchorConfidence,
            createdAt: measurement.createdAt,
            notes: measurement.notes
        )
    }

    private func rotate(x: Double, z: Double, around centre: Vertex2D, by angle: Double) -> Vertex2D {
        rotate(vertex: Vertex2D(x: x, z: z), around: centre, by: angle)
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
    let raw = fmod(lhs - rhs + .pi, 2 * .pi)
    let wrapped = raw < 0 ? raw + 2 * .pi : raw
    return wrapped - .pi
}
