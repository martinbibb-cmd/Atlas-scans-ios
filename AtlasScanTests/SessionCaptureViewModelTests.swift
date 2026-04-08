import XCTest
@testable import AtlasScan

// MARK: - SessionCaptureViewModelTests
//
// Unit tests for SessionCaptureViewModel:
//   - Initial state
//   - Selection (room / object) and photo attachment target transitions
//   - Room / object / photo management with correct attachment
//   - Autosave state transitions
//
// No UIKit, ARKit, or RoomPlan types required; runs on any simulator or device.

@MainActor
final class SessionCaptureViewModelTests: XCTestCase {

    private var session: PropertyScanSession!
    private var store: ScanSessionStore!
    private var atlasSync: AtlasSync!
    private var viewModel: SessionCaptureViewModel!

    override func setUp() async throws {
        try await super.setUp()
        session = PropertyScanSession(propertyAddress: "1 Test Street")
        store = ScanSessionStore()
        atlasSync = AtlasSync()
        viewModel = SessionCaptureViewModel(session: session, store: store, atlasSync: atlasSync)
    }

    override func tearDown() async throws {
        store.delete(viewModel.session)
        viewModel = nil
        atlasSync = nil
        store = nil
        session = nil
        try await super.tearDown()
    }

    // MARK: - Initial state

    func test_init_sessionStateIsInProgress() {
        XCTAssertEqual(viewModel.session.scanState, .inProgress,
            "Opening the capture surface should transition a notStarted session to inProgress")
    }

    func test_init_noRoomSelected() {
        XCTAssertNil(viewModel.selectedRoomID)
    }

    func test_init_noObjectSelected() {
        XCTAssertNil(viewModel.selectedObjectID)
    }

    func test_init_photoTargetIsSession() {
        XCTAssertEqual(viewModel.pendingPhotoTarget, .session)
    }

    func test_init_saveStateIsSaved() {
        XCTAssertEqual(viewModel.saveState, .saved)
    }

    // MARK: - Room selection

    func test_selectRoom_setsSelectedRoomID() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        let roomID = viewModel.session.rooms[0].id
        viewModel.selectRoom(roomID)
        XCTAssertEqual(viewModel.selectedRoomID, roomID)
    }

    func test_selectRoom_clearsSelectedObject() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        let obj = TaggedObject(roomID: room.id, category: .boiler)
        viewModel.addObject(obj)
        // selectObject is set by addObject; now switch room focus and clear object
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        XCTAssertNil(viewModel.selectedObjectID,
            "Selecting a room should clear any selected object")
    }

    func test_selectRoom_setsPhotoTargetToRoom() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        let roomID = viewModel.session.rooms[0].id
        viewModel.selectRoom(roomID)
        XCTAssertEqual(viewModel.pendingPhotoTarget, .room(roomID))
    }

    func test_selectRoom_nil_setsPhotoTargetToSession() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        viewModel.selectRoom(nil)
        XCTAssertEqual(viewModel.pendingPhotoTarget, .session)
    }

    // MARK: - Object selection

    func test_selectObject_setsSelectedObjectID() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        let id = viewModel.selectedObjectID!  // addObject selects it
        viewModel.selectObject(nil)           // deselect
        viewModel.selectObject(id)            // reselect
        XCTAssertEqual(viewModel.selectedObjectID, id)
    }

    func test_selectObject_setsPhotoTargetToObject() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        let id = viewModel.selectedObjectID!
        XCTAssertEqual(viewModel.pendingPhotoTarget, .object(id))
    }

    func test_selectObject_nil_withRoomFocused_setsPhotoTargetToRoom() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let obj = TaggedObject(roomID: room.id, category: .boiler)
        viewModel.addObject(obj)
        viewModel.selectObject(nil)
        let roomID = viewModel.session.rooms[0].id
        XCTAssertEqual(viewModel.pendingPhotoTarget, .room(roomID))
    }

    func test_selectObject_nil_withNoRoom_setsPhotoTargetToSession() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        viewModel.selectObject(nil)
        XCTAssertEqual(viewModel.pendingPhotoTarget, .session)
    }

    // MARK: - Room management

    func test_addRoom_appendsRoomToSession() {
        viewModel.addRoom(ScannedRoom(jobID: session.id, name: "Living Room"))
        XCTAssertEqual(viewModel.session.rooms.count, 1)
        XCTAssertEqual(viewModel.session.rooms[0].name, "Living Room")
    }

    func test_addRoom_selectsNewRoom() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        XCTAssertEqual(viewModel.selectedRoomID, viewModel.session.rooms[0].id)
    }

    func test_addRoom_setsPhotoTargetToRoom() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        let roomID = viewModel.session.rooms[0].id
        XCTAssertEqual(viewModel.pendingPhotoTarget, .room(roomID))
    }

    func test_removeRoom_removesRoom() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.removeRoom(id: viewModel.session.rooms[0].id)
        XCTAssertTrue(viewModel.session.rooms.isEmpty)
    }

    func test_removeRoom_clearsSelectionWhenRemovingFocusedRoom() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        let roomID = viewModel.session.rooms[0].id
        viewModel.selectRoom(roomID)
        viewModel.removeRoom(id: roomID)
        XCTAssertNil(viewModel.selectedRoomID)
        XCTAssertEqual(viewModel.pendingPhotoTarget, .session)
    }

    func test_removeRoom_doesNotClearSelectionForOtherRoom() {
        let roomA = ScannedRoom(jobID: session.id, name: "Kitchen")
        let roomB = ScannedRoom(jobID: session.id, name: "Lounge")
        viewModel.addRoom(roomA)
        let idA = viewModel.session.rooms[0].id
        viewModel.addRoom(roomB)
        let idB = viewModel.session.rooms[1].id
        viewModel.selectRoom(idA)
        viewModel.removeRoom(id: idB)
        XCTAssertEqual(viewModel.selectedRoomID, idA,
            "Removing a non-selected room should not affect the current selection")
    }

    // MARK: - Object management

    func test_addObject_withSelectedRoom_addsToRoom() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        XCTAssertEqual(viewModel.session.rooms[0].taggedObjects.count, 1,
            "Object should be added to the focused room")
    }

    func test_addObject_withSelectedRoom_rebindsRoomID() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        let roomID = viewModel.session.rooms[0].id
        viewModel.selectRoom(roomID)
        let obj = TaggedObject(roomID: UUID(), category: .boiler) // wrong roomID
        viewModel.addObject(obj)
        XCTAssertEqual(viewModel.session.rooms[0].taggedObjects[0].roomID, roomID,
            "Object roomID should be rebound to the focused room")
    }

    func test_addObject_withNoRoom_addsToSessionLevel() {
        let obj = TaggedObject(roomID: session.id, category: .cylinder)
        viewModel.addObject(obj)
        XCTAssertEqual(viewModel.session.taggedObjects.count, 1,
            "Object should be added at session level when no room is focused")
    }

    func test_addObject_selectsNewObject() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        XCTAssertNotNil(viewModel.selectedObjectID)
    }

    func test_addObject_setsPhotoTargetToObject() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        guard let id = viewModel.selectedObjectID else {
            XCTFail("selectedObjectID should be set after addObject")
            return
        }
        XCTAssertEqual(viewModel.pendingPhotoTarget, .object(id))
    }

    func test_removeObject_removesFromSession() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        let id = viewModel.selectedObjectID!
        viewModel.removeObject(id: id)
        XCTAssertTrue(viewModel.session.taggedObjects.isEmpty)
    }

    func test_removeObject_clearsSelectionIfRemovingSelectedObject() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        let id = viewModel.selectedObjectID!
        viewModel.removeObject(id: id)
        XCTAssertNil(viewModel.selectedObjectID)
    }

    // MARK: - Object update

    func test_updateObject_updatesSessionLevelObject() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        guard var toUpdate = viewModel.session.taggedObjects.first else {
            XCTFail("Expected a session-level object")
            return
        }
        toUpdate.label = "Updated Boiler"
        viewModel.updateObject(toUpdate)
        XCTAssertEqual(viewModel.session.taggedObjects.first?.label, "Updated Boiler")
    }

    func test_updateObject_updatesRoomLevelObject() {
        let room = ScannedRoom(jobID: session.id, name: "Utility")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let obj = TaggedObject(roomID: room.id, category: .cylinder)
        viewModel.addObject(obj)
        guard var toUpdate = viewModel.session.rooms[0].taggedObjects.first else {
            XCTFail("Expected a room-level object")
            return
        }
        toUpdate.label = "Updated Cylinder"
        viewModel.updateObject(toUpdate)
        XCTAssertEqual(viewModel.session.rooms[0].taggedObjects.first?.label, "Updated Cylinder",
            "updateObject should update room-level objects")
    }

    // MARK: - Photo management

    func test_addPhoto_sessionTarget_addsToSessionPhotos() {
        // Ensure target is .session (no room or object selected)
        viewModel.selectRoom(nil)
        let photo = TaggedPhoto(filename: "site.jpg")
        viewModel.addPhoto(photo)
        XCTAssertEqual(viewModel.session.photos.count, 1,
            "Photo with session target should be added to session.photos")
    }

    func test_addPhoto_roomTarget_addsToRoomPhotos() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let photo = TaggedPhoto(filename: "kitchen.jpg")
        viewModel.addPhoto(photo)
        XCTAssertEqual(viewModel.session.rooms[0].photos.count, 1,
            "Photo with room target should be added to the room's photos")
    }

    func test_addPhoto_roomTarget_setsRoomID() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        let roomID = viewModel.session.rooms[0].id
        viewModel.selectRoom(roomID)
        let photo = TaggedPhoto(filename: "kitchen.jpg")
        viewModel.addPhoto(photo)
        XCTAssertEqual(viewModel.session.rooms[0].photos[0].roomID, roomID)
    }

    func test_addPhoto_objectTarget_linksPhotoToObject() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)  // also selects obj and sets target = .object
        let photo = TaggedPhoto(filename: "boiler.jpg")
        viewModel.addPhoto(photo)
        let saved = viewModel.session.allTaggedObjects.first { $0.id == obj.id }
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.linkedPhotoIDs.count, 1,
            "Photo should be linked via TaggedObject.linkedPhotoIDs")
    }

    func test_addPhoto_objectTarget_setsTaggedObjectID() {
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        viewModel.addObject(obj)
        let objID = viewModel.selectedObjectID!
        let photo = TaggedPhoto(filename: "boiler.jpg")
        viewModel.addPhoto(photo)
        let savedPhoto = viewModel.session.allPhotos.first
        XCTAssertEqual(savedPhoto?.taggedObjectID, objID,
            "Photo taggedObjectID should be set to the selected object's ID")
    }

    // MARK: - Save state

    func test_saveNow_setsStateToSaved() {
        viewModel.saveNow()
        XCTAssertEqual(viewModel.saveState, .saved)
    }

    // MARK: - Computed helpers

    func test_selectedRoom_returnsNilWhenNotSelected() {
        XCTAssertNil(viewModel.selectedRoom)
    }

    func test_selectedRoom_returnsRoomWhenSelected() {
        let room = ScannedRoom(jobID: session.id, name: "Lounge")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        XCTAssertEqual(viewModel.selectedRoom?.name, "Lounge")
    }

    func test_selectedObject_returnsNilWhenNotSelected() {
        XCTAssertNil(viewModel.selectedObject)
    }

    func test_selectedObject_returnsObjectWhenSelected() {
        let obj = TaggedObject(roomID: session.id, category: .cylinder)
        viewModel.addObject(obj)
        XCTAssertNotNil(viewModel.selectedObject)
        XCTAssertEqual(viewModel.selectedObject?.category, .cylinder)
    }

    func test_sessionLevelObjects_returnsSessionObjects() {
        let obj = TaggedObject(roomID: session.id, category: .cylinder)
        viewModel.addObject(obj)  // no room focused → session-level
        XCTAssertEqual(viewModel.sessionLevelObjects.count, 1)
    }

    func test_sessionLevelObjects_excludesRoomObjects() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let obj = TaggedObject(roomID: room.id, category: .radiator)
        viewModel.addObject(obj)  // room focused → goes into room
        XCTAssertTrue(viewModel.sessionLevelObjects.isEmpty,
            "Room-level objects should not appear in sessionLevelObjects")
    }

    func test_makePlaceholderRoom_returnsRoomWithSessionID() {
        let placeholder = viewModel.makePlaceholderRoom()
        XCTAssertEqual(placeholder.jobID, session.id)
    }

    func test_makePlaceholderRoom_withFocusedRoom_usesRoomName() {
        let room = ScannedRoom(jobID: session.id, name: "Utility Room")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let placeholder = viewModel.makePlaceholderRoom()
        XCTAssertEqual(placeholder.name, "Utility Room")
    }

    // MARK: - Voice note management

    func test_addVoiceNote_sessionLevel_addsToSessionVoiceNotes() {
        let note = VoiceNote(localFilename: "n1.m4a")
        viewModel.addVoiceNote(note)
        XCTAssertEqual(viewModel.session.voiceNotes.count, 1)
    }

    func test_addVoiceNote_withRoomFocused_addsToRoom() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let note = VoiceNote(localFilename: "kitchen.m4a")
        viewModel.addVoiceNote(note)
        XCTAssertEqual(viewModel.session.rooms[0].voiceNotes.count, 1)
        XCTAssertTrue(viewModel.session.voiceNotes.isEmpty)
    }

    func test_addVoiceNote_withObjectSelected_crossLinksObject() {
        let room = ScannedRoom(jobID: session.id, name: "Utility")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let obj = TaggedObject(roomID: room.id, category: .boiler)
        viewModel.addObject(obj)
        let note = VoiceNote(localFilename: "boiler.m4a")
        viewModel.addVoiceNote(note)
        let savedObj = viewModel.session.rooms[0].taggedObjects.first
        XCTAssertEqual(savedObj?.linkedVoiceNoteIDs.count, 1)
    }

    func test_removeVoiceNote_removesFromSessionLevel() {
        let note = VoiceNote(localFilename: "n1.m4a")
        viewModel.addVoiceNote(note)
        viewModel.removeVoiceNote(id: note.id)
        XCTAssertTrue(viewModel.session.voiceNotes.isEmpty)
    }

    func test_removeVoiceNote_removesFromRoom() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let note = VoiceNote(localFilename: "n2.m4a")
        viewModel.addVoiceNote(note)
        viewModel.removeVoiceNote(id: note.id)
        XCTAssertTrue(viewModel.session.rooms[0].voiceNotes.isEmpty)
    }

    func test_updateVoiceNote_updatesSessionLevelNote() {
        let note = VoiceNote(localFilename: "n1.m4a", caption: "Original")
        viewModel.addVoiceNote(note)
        var updated = viewModel.session.voiceNotes[0]
        updated.caption = "Updated caption"
        viewModel.updateVoiceNote(updated)
        XCTAssertEqual(viewModel.session.voiceNotes[0].caption, "Updated caption")
    }

    func test_updateVoiceNote_updatesRoomLevelNote() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let note = VoiceNote(localFilename: "n2.m4a", caption: "Original")
        viewModel.addVoiceNote(note)
        var updated = viewModel.session.rooms[0].voiceNotes[0]
        updated.caption = "Updated room caption"
        viewModel.updateVoiceNote(updated)
        XCTAssertEqual(viewModel.session.rooms[0].voiceNotes[0].caption, "Updated room caption")
    }

    func test_sessionLevelVoiceNotes_returnsSessionNotes() {
        let note = VoiceNote(localFilename: "n1.m4a")
        viewModel.addVoiceNote(note)
        XCTAssertEqual(viewModel.sessionLevelVoiceNotes.count, 1)
    }

    func test_sessionLevelVoiceNotes_excludesRoomNotes() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let note = VoiceNote(localFilename: "room.m4a")
        viewModel.addVoiceNote(note)
        XCTAssertTrue(viewModel.sessionLevelVoiceNotes.isEmpty)
    }

    func test_voiceNotesForRoom_returnsRoomNotes() {
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        viewModel.addRoom(room)
        let roomID = viewModel.session.rooms[0].id
        viewModel.selectRoom(roomID)
        let note = VoiceNote(localFilename: "n.m4a")
        viewModel.addVoiceNote(note)
        XCTAssertEqual(viewModel.voiceNotes(for: roomID).count, 1)
    }

    func test_voiceNotesForObject_returnsLinkedNotes() {
        let room = ScannedRoom(jobID: session.id, name: "Utility")
        viewModel.addRoom(room)
        viewModel.selectRoom(viewModel.session.rooms[0].id)
        let obj = TaggedObject(roomID: room.id, category: .boiler)
        viewModel.addObject(obj)
        let objID = viewModel.selectedObjectID!
        let note = VoiceNote(localFilename: "boiler.m4a")
        viewModel.addVoiceNote(note)
        XCTAssertEqual(viewModel.voiceNotes(forObject: objID).count, 1)
    }

    func test_voiceNotesForObject_returnsEmptyForUnknownObject() {
        XCTAssertTrue(viewModel.voiceNotes(forObject: UUID()).isEmpty)
    }
}
