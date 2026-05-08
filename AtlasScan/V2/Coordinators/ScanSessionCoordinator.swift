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
    private var pendingSaveTask: Task<Void, Never>?

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
                capturePointId: pin.capturePointId,
                positionX: pin.positionX + dx,
                positionY: pin.positionY,
                positionZ: pin.positionZ + dz,
                screenPositionX: pin.screenPositionX,
                screenPositionY: pin.screenPositionY,
                objectType: pin.objectType,
                label: pin.label,
                anchorConfidence: pin.anchorConfidence,
                hardwareSpecId: pin.hardwareSpecId,
                modelId: pin.modelId
            )
        }
        return translatedRoom
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
