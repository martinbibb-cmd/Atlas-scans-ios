import SwiftUI
import Combine

// MARK: - VisitCaptureViewModel

/// Orchestrates the single-session visit capture surface.
///
/// Owns:
///   - `VisitCaptureStore`   — the single source of truth for session state
///   - `activeScreen`        — which capture surface is currently shown
///   - Selection state       — current room / object in focus
///   - Photo attachment target
///
/// Design:
///   - Screen switching never fragments the session.
///   - All child screens receive this ViewModel and mutate through it.
///   - Autosave is handled by `VisitCaptureStore` on every mutation.
@MainActor
final class VisitCaptureViewModel: ObservableObject {

    // MARK: Screen navigation

    @Published var activeScreen: VisitCaptureScreen = .overview

    // MARK: Selection state

    @Published private(set) var selectedRoomID: UUID?
    @Published private(set) var selectedObjectID: UUID?
    @Published private(set) var pendingPhotoTarget: PhotoAttachmentTarget = .session

    // MARK: Store

    let store: VisitCaptureStore
    let atlasSync: AtlasSync

    // MARK: Computed — session shortcut

    var session: PropertyScanSession {
        store.session
    }

    var saveState: VisitCaptureStore.SaveState {
        store.saveState
    }

    // MARK: Init

    init(session: PropertyScanSession, sessionStore: ScanSessionStore, atlasSync: AtlasSync) {
        self.store = VisitCaptureStore(session: session, sessionStore: sessionStore)
        self.atlasSync = atlasSync
        // Mark session active when the capture surface opens.
        if session.scanState == .notStarted {
            store.update { $0.scanState = .inProgress }
        }
    }

    // MARK: - Screen navigation

    func navigate(to screen: VisitCaptureScreen) {
        activeScreen = screen
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
        store.update { session in
            session.addRoom(room)
        }
        selectedRoomID = room.id
        pendingPhotoTarget = .room(room.id)
        if room.geometryCaptured {
            let evidence = RoomScanEvidenceBuilder.buildMetadataOnly(
                from: room,
                propertySessionID: session.id
            )
            store.update { $0.addRoomScanEvidence(evidence) }
        }
        recordEvent("room_added", detail: room.name)
    }

    func removeRoom(id: UUID) {
        store.update { $0.removeRoom(id: id) }
        if selectedRoomID == id {
            selectedRoomID = nil
            selectedObjectID = nil
            pendingPhotoTarget = .session
        }
    }

    func updateRoom(_ room: ScannedRoom) {
        store.update { $0.updateRoom(room) }
    }

    // MARK: - Object management

    func addObject(_ obj: TaggedObject) {
        var updated = obj
        store.update { session in
            if let roomID = self.selectedRoomID,
               let idx = session.rooms.firstIndex(where: { $0.id == roomID }) {
                updated.roomID = roomID
                session.rooms[idx].addTaggedObject(updated)
            } else {
                session.addTaggedObject(updated)
            }
        }
        selectedObjectID = updated.id
        pendingPhotoTarget = .object(updated.id)
        recordEvent("object_added", detail: updated.displayLabel)
    }

    func removeObject(id: UUID) {
        store.update { session in
            for i in session.rooms.indices {
                session.rooms[i].removeTaggedObject(id: id)
            }
            session.removeTaggedObject(id: id)
        }
        if selectedObjectID == id {
            selectedObjectID = nil
            pendingPhotoTarget = selectedRoomID.map { .room($0) } ?? .session
        }
    }

    func updateObject(_ updated: TaggedObject) {
        store.update { session in
            if session.taggedObjects.contains(where: { $0.id == updated.id }) {
                session.updateTaggedObject(updated)
            } else {
                for i in session.rooms.indices where session.rooms[i].taggedObjects.contains(where: { $0.id == updated.id }) {
                    session.rooms[i].updateTaggedObject(updated)
                    break
                }
            }
        }
    }

    var selectedObject: TaggedObject? {
        guard let id = selectedObjectID else { return nil }
        return session.allTaggedObjects.first { $0.id == id }
    }

    var selectedRoom: ScannedRoom? {
        guard let id = selectedRoomID else { return nil }
        return session.rooms.first { $0.id == id }
    }

    var sessionLevelObjects: [TaggedObject] {
        session.taggedObjects
    }

    // MARK: - Photo management

    func addPhoto(_ photo: TaggedPhoto) {
        var p = photo
        store.update { session in
            switch self.pendingPhotoTarget {
            case .session:
                session.addPhoto(p)

            case .room(let roomID):
                p.roomID = roomID
                if let idx = session.rooms.firstIndex(where: { $0.id == roomID }) {
                    session.rooms[idx].addPhoto(p)
                } else {
                    session.addPhoto(p)
                }

            case .object(let objectID):
                p.taggedObjectID = objectID
                if let roomID = selectedRoomID,
                   let rIdx = session.rooms.firstIndex(where: { $0.id == roomID }) {
                    p.roomID = roomID
                    session.rooms[rIdx].addPhoto(p)
                } else {
                    session.addPhoto(p)
                }
            }
        }
        recordEvent("photo_added")
    }

    // MARK: - Voice note management

    func addVoiceNote(_ note: VoiceNote) {
        var n = note
        store.update { session in
            if let roomID = self.selectedRoomID,
               let idx = session.rooms.firstIndex(where: { $0.id == roomID }) {
                var updated = n
                updated.linkedRoomID = roomID
                n = updated
                session.rooms[idx].addVoiceNote(n)
            } else {
                session.addVoiceNote(n)
            }
        }
        recordEvent("voice_note_added")
    }

    func updateVoiceNote(_ note: VoiceNote) {
        store.update { session in
            if session.voiceNotes.contains(where: { $0.id == note.id }) {
                session.updateVoiceNote(note)
            } else {
                for i in session.rooms.indices where session.rooms[i].voiceNotes.contains(where: { $0.id == note.id }) {
                    session.rooms[i].updateVoiceNote(note)
                    break
                }
            }
        }
    }

    // MARK: - Session lifecycle

    func completeSession() {
        store.update { session in
            session.scanState = .completed
            session.reviewState = .inReview
        }
        store.saveNow()
        recordEvent("session_completed")
    }

    func markHandoffSent() {
        store.update { $0.handoffState = .sent }
        store.saveNow()
    }

    func markHandoffExported() {
        store.update { $0.handoffState = .exported }
        store.saveNow()
    }

    // MARK: - Event log

    // TODO: Replace with a first-class timeline model once the full event log
    // schema is defined.  Until then, capture events are tracked only in memory
    // and are not included in the handoff payload.
    private func recordEvent(_ type: String, detail: String? = nil) {}

    // MARK: - Validation

    var validationResult: VisitValidationResult {
        VisitSessionValidator.validate(session)
    }

    // MARK: - Helpers

    func makePlaceholderRoom() -> ScannedRoom {
        ScannedRoom(jobID: session.id, name: "New Room")
    }

    func voiceNotes(for roomID: UUID) -> [VoiceNote] {
        session.rooms.first(where: { $0.id == roomID })?.voiceNotes ?? []
    }

    func voiceNotes(forObject objectID: UUID) -> [VoiceNote] {
        session.allVoiceNotes.filter { $0.linkedObjectID == objectID }
    }

    var sessionLevelVoiceNotes: [VoiceNote] {
        session.voiceNotes
    }
}
