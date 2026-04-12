import SwiftUI
import Combine

// MARK: - PhotoAttachmentTarget

/// Describes which entity a new photo should be attached to during a capture session.
enum PhotoAttachmentTarget: Equatable {
    case session
    case room(UUID)
    case object(UUID)

    var displayName: String {
        switch self {
        case .session: return "Session"
        case .room:    return "Room"
        case .object:  return "Object"
        }
    }
}

// MARK: - SessionCaptureViewModel

/// Coordinator ViewModel for the single-pass session capture surface.
///
/// Owns:
///   - active `PropertyScanSession`
///   - current room / object selection state
///   - photo attachment target (session / room / object)
///   - debounced autosave (800 ms)
///   - Atlas sync queue summary
///
/// Design:
///   Selection model is intentionally kept outside legacy ScanJob / export types.
///   All mutations go through this ViewModel so autosave is always triggered.
@MainActor
final class SessionCaptureViewModel: ObservableObject {

    // MARK: Session

    @Published private(set) var session: PropertyScanSession

    // MARK: Selection state

    /// The room currently in focus. Objects and photos default to this room context.
    @Published private(set) var selectedRoomID: UUID?

    /// The tagged object currently selected for clearance / photo attachment.
    @Published private(set) var selectedObjectID: UUID?

    /// Where the next captured photo will be attached.
    @Published private(set) var pendingPhotoTarget: PhotoAttachmentTarget = .session

    // MARK: Save state

    enum SaveState: Equatable {
        case saved
        case saving
        case unsaved
    }

    @Published private(set) var saveState: SaveState = .saved

    // MARK: Dependencies

    private(set) var store: ScanSessionStore
    let atlasSync: AtlasSync

    // MARK: Private

    private var autosaveTask: Task<Void, Never>?

    // MARK: Init

    init(session: PropertyScanSession, store: ScanSessionStore, atlasSync: AtlasSync) {
        self.session = session
        self.store = store
        self.atlasSync = atlasSync
        // Mark session as active the moment the capture surface opens.
        if session.scanState == .notStarted {
            self.session.scanState = .inProgress
        }
    }


    /// Unified multi-stream snapshot used by the capture UI.
    var unifiedSurveySnapshot: AtlasSurveySessionV2 {
        session.surveySessionV2
    }

    // MARK: - Selection

    func selectRoom(_ id: UUID?) {
        selectedRoomID = id
        selectedObjectID = nil
        pendingPhotoTarget = id.map { .room($0) } ?? .session
    }

    func selectObject(_ id: UUID?) {
        selectedObjectID = id
        if let id {
            pendingPhotoTarget = .object(id)
        } else if let roomID = selectedRoomID {
            pendingPhotoTarget = .room(roomID)
        } else {
            pendingPhotoTarget = .session
        }
    }

    // MARK: - Room management

    func addRoom(_ room: ScannedRoom) {
        session.addRoom(room)
        selectedRoomID = room.id
        pendingPhotoTarget = .room(room.id)
        // Auto-create a metadata-only room scan evidence record for geometry-captured rooms.
        if room.geometryCaptured {
            let evidence = RoomScanEvidenceBuilder.buildMetadataOnly(
                from: room,
                propertySessionID: session.id
            )
            session.addRoomScanEvidence(evidence)
        }
        scheduleAutosave()
    }

    func removeRoom(id: UUID) {
        session.removeRoom(id: id)
        if selectedRoomID == id {
            selectedRoomID = nil
            selectedObjectID = nil
            pendingPhotoTarget = .session
        }
        scheduleAutosave()
    }

    func updateRoom(_ room: ScannedRoom) {
        session.updateRoom(room)
        scheduleAutosave()
    }

    // MARK: - Object management

    /// Adds a tagged object, associating it with the selected room when one is active.
    /// After adding, automatically selects the object and updates the photo target.
    func addObject(_ obj: TaggedObject) {
        var updated = obj
        if let roomID = selectedRoomID,
           let idx = session.rooms.firstIndex(where: { $0.id == roomID }) {
            updated.roomID = roomID
            session.rooms[idx].addTaggedObject(updated)
        } else {
            session.addTaggedObject(updated)
        }
        selectedObjectID = updated.id
        pendingPhotoTarget = .object(updated.id)
        scheduleAutosave()
    }

    func removeObject(id: UUID) {
        // Remove from rooms before session-level; both paths are safe to call.
        for i in session.rooms.indices {
            session.rooms[i].removeTaggedObject(id: id)
        }
        session.removeTaggedObject(id: id)
        if selectedObjectID == id {
            selectedObjectID = nil
            pendingPhotoTarget = selectedRoomID.map { .room($0) } ?? .session
        }
        scheduleAutosave()
    }

    /// Updates an existing tagged object in-place, searching both session-level and room-level lists.
    func updateObject(_ updated: TaggedObject) {
        if session.taggedObjects.contains(where: { $0.id == updated.id }) {
            session.updateTaggedObject(updated)
        } else {
            for i in session.rooms.indices {
                if session.rooms[i].taggedObjects.contains(where: { $0.id == updated.id }) {
                    session.rooms[i].updateTaggedObject(updated)
                    break
                }
            }
        }
        scheduleAutosave()
    }

    // MARK: - Photo management

    /// Saves a photo and attaches it to the current `pendingPhotoTarget`.
    /// The photo is always persisted locally; Atlas upload is handled separately.
    func addPhoto(_ photo: TaggedPhoto) {
        var p = photo
        switch pendingPhotoTarget {
        case .session:
            session.addPhoto(p)

        case .room(let roomID):
            p.roomID = roomID
            if let idx = session.rooms.firstIndex(where: { $0.id == roomID }) {
                session.rooms[idx].addPhoto(p)
            } else {
                session.addPhoto(p)
            }

        case .object(let objID):
            p.taggedObjectID = objID
            // Locate the object — check session-level first, then room-level.
            if let idx = session.taggedObjects.firstIndex(where: { $0.id == objID }) {
                p.roomID = session.taggedObjects[idx].roomID
                session.taggedObjects[idx].linkedPhotoIDs.append(p.id)
                session.addPhoto(p)
            } else {
                for ri in session.rooms.indices {
                    if let oi = session.rooms[ri].taggedObjects.firstIndex(where: { $0.id == objID }) {
                        p.roomID = session.rooms[ri].id
                        session.rooms[ri].taggedObjects[oi].linkedPhotoIDs.append(p.id)
                        session.rooms[ri].addPhoto(p)
                        break
                    }
                }
            }
        }
        scheduleAutosave()
    }

    // MARK: - Voice note management

    /// Saves a voice note and attaches it to the current target context.
    /// If a room is focused, attaches to that room; if an object is selected, also cross-links the object.
    /// Otherwise attaches at session level.
    func addVoiceNote(_ note: VoiceNote) {
        var n = note
        if let objectID = selectedObjectID {
            n.linkedObjectID = objectID
            n.linkedRoomID = selectedRoomID
            // Cross-link from the object side
            if let idx = session.taggedObjects.firstIndex(where: { $0.id == objectID }) {
                session.taggedObjects[idx].linkedVoiceNoteIDs.append(n.id)
            } else {
                for ri in session.rooms.indices {
                    if let oi = session.rooms[ri].taggedObjects.firstIndex(where: { $0.id == objectID }) {
                        session.rooms[ri].taggedObjects[oi].linkedVoiceNoteIDs.append(n.id)
                        break
                    }
                }
            }
            // Place note in room if one is selected, otherwise session level
            if let roomID = selectedRoomID,
               let ri = session.rooms.firstIndex(where: { $0.id == roomID }) {
                session.rooms[ri].addVoiceNote(n)
            } else {
                session.addVoiceNote(n)
            }
        } else if let roomID = selectedRoomID,
                  let ri = session.rooms.firstIndex(where: { $0.id == roomID }) {
            n.linkedRoomID = roomID
            session.rooms[ri].addVoiceNote(n)
        } else {
            session.addVoiceNote(n)
        }
        // Re-extract structured facts from the updated note set.
        session.refreshExtractedFacts()
        scheduleAutosave()
    }

    func removeVoiceNote(id: UUID) {
        session.removeVoiceNote(id: id)
        for i in session.rooms.indices {
            session.rooms[i].removeVoiceNote(id: id)
        }
        // Remove cross-links from objects
        for i in session.taggedObjects.indices {
            session.taggedObjects[i].linkedVoiceNoteIDs.removeAll { $0 == id }
        }
        for ri in session.rooms.indices {
            for oi in session.rooms[ri].taggedObjects.indices {
                session.rooms[ri].taggedObjects[oi].linkedVoiceNoteIDs.removeAll { $0 == id }
            }
        }
        scheduleAutosave()
    }

    /// Updates an existing voice note in-place, searching both session-level and room-level lists.
    func updateVoiceNote(_ updated: VoiceNote) {
        if session.voiceNotes.contains(where: { $0.id == updated.id }) {
            session.updateVoiceNote(updated)
        } else {
            for i in session.rooms.indices {
                if session.rooms[i].voiceNotes.contains(where: { $0.id == updated.id }) {
                    session.rooms[i].updateVoiceNote(updated)
                    break
                }
            }
        }
        scheduleAutosave()
    }

    // MARK: - Autosave

    /// Schedules a debounced save (800 ms). Cancels any pending save task first.
    private func scheduleAutosave() {
        saveState = .unsaved
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    /// Saves the session to disk immediately. Updates `saveState` around the write.
    func saveNow() {
        saveState = .saving
        store.save(session)
        saveState = .saved
    }

    // MARK: - Atlas sync

    /// Enqueues the session, all unsynced photos, and all unsynced voice notes for Atlas upload.
    func queueForAtlasSync() {
        atlasSync.enqueueSession(session)
        atlasSync.enqueuePhotos(session.allPhotos.filter { $0.syncState.canQueue })
        atlasSync.enqueueVoiceNotes(session.allVoiceNotes.filter { $0.syncState.canQueue })
        atlasSync.processQueue()
    }

    // MARK: - Handoff state

    /// Marks the session as sent to Atlas Mind and saves.
    func markHandoffSent() {
        session.handoffState = .sent
        saveNow()
    }

    /// Marks the session as exported (JSON saved to Files) and saves.
    func markHandoffExported() {
        session.handoffState = .exported
        saveNow()
    }

    // MARK: - Computed helpers

    var selectedRoom: ScannedRoom? {
        guard let id = selectedRoomID else { return nil }
        return session.rooms.first { $0.id == id }
    }

    var selectedObject: TaggedObject? {
        guard let id = selectedObjectID else { return nil }
        return session.allTaggedObjects.first { $0.id == id }
    }

    /// Objects not assigned to any specific room (floating / session-level).
    var sessionLevelObjects: [TaggedObject] {
        session.taggedObjects
    }

    /// Session-level voice notes (not assigned to any room).
    var sessionLevelVoiceNotes: [VoiceNote] {
        session.voiceNotes
    }

    /// Voice notes for a specific room.
    func voiceNotes(for roomID: UUID) -> [VoiceNote] {
        session.rooms.first { $0.id == roomID }?.voiceNotes ?? []
    }

    /// All voice notes linked to a specific object, gathered across session and room lists.
    func voiceNotes(forObject objectID: UUID) -> [VoiceNote] {
        let ids: Set<UUID>
        if let obj = session.allTaggedObjects.first(where: { $0.id == objectID }) {
            ids = Set(obj.linkedVoiceNoteIDs)
        } else {
            return []
        }
        return session.allVoiceNotes.filter { ids.contains($0.id) }
    }

    var syncQueueCount: Int {
        atlasSync.uploadQueue.count
    }

    /// A placeholder room used by `AddObjectSheet` when no real room is selected.
    /// Provides a unit-square canvas for rough placement; exact position can be
    /// refined once the room is scanned.
    func makePlaceholderRoom() -> ScannedRoom {
        ScannedRoom(
            jobID: session.id,
            name: selectedRoom?.name ?? session.propertyAddress,
            floor: selectedRoom?.floor ?? 0
        )
    }

    // MARK: - Room scan evidence

    /// Adds a room-scan evidence record to the session.
    func addRoomScanEvidence(_ evidence: RoomScanEvidence) {
        session.addRoomScanEvidence(evidence)
        scheduleAutosave()
    }

    /// Removes a room-scan evidence record by ID.
    func removeRoomScanEvidence(id: UUID) {
        session.removeRoomScanEvidence(id: id)
        scheduleAutosave()
    }

    /// Links a room-scan evidence record to a room ID.
    func linkRoomScanEvidence(id: UUID, toRoomID roomID: UUID) {
        guard let index = session.roomScanEvidence.firstIndex(where: { $0.id == id }) else { return }
        if !session.roomScanEvidence[index].linkedRoomIDs.contains(roomID) {
            session.roomScanEvidence[index].linkedRoomIDs.append(roomID)
        }
        scheduleAutosave()
    }

    // MARK: - External clearance scene management

    /// Adds an external flue-clearance scene to the session.
    func addExternalClearanceScene(_ scene: ExternalClearanceScene) {
        session.addExternalClearanceScene(scene)
        scheduleAutosave()
    }

    /// Removes an external clearance scene by ID.
    func removeExternalClearanceScene(id: UUID) {
        session.removeExternalClearanceScene(id: id)
        scheduleAutosave()
    }
}
