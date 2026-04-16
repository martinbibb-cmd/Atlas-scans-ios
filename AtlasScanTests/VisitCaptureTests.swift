import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - VisitCaptureTests
//
// Unit tests for the VisitCapture feature module.
// Covers:
//   - Session creation and initial state
//   - Screen switching without state loss
//   - Room addition updates shared session
//   - Photo attachment to correct room/object/session scope
//   - Object placement creates stable references
//   - Voice note addition and transcript mapping
//   - Summary validation logic
//   - AtlasPropertyV1 export shape
//   - Autosave / restore round-trip

final class VisitCaptureTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(address: String = "1 Test Street", reference: String = "JOB-TEST") -> PropertyScanSession {
        PropertyScanSession(jobReference: reference, propertyAddress: address)
    }

    private func makeViewModel(session: PropertyScanSession? = nil) -> VisitCaptureViewModel {
        let s = session ?? makeSession()
        return VisitCaptureViewModel(
            session: s,
            sessionStore: ScanSessionStore(),
            atlasSync: AtlasSync()
        )
    }

    // MARK: - Session creation

    func test_init_sessionStateBecomesInProgress() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.session.scanState, .inProgress)
    }

    func test_init_activeScreenIsOverview() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.activeScreen, .overview)
    }

    func test_init_sessionAddressPreserved() {
        let vm = makeViewModel(session: makeSession(address: "42 Example Road"))
        XCTAssertEqual(vm.session.propertyAddress, "42 Example Road")
    }

    func test_init_existingInProgressSessionNotReset() {
        var session = makeSession()
        session.scanState = .inProgress
        let vm = makeViewModel(session: session)
        XCTAssertEqual(vm.session.scanState, .inProgress)
    }

    func test_init_existingCompletedSessionNotReset() {
        var session = makeSession()
        session.scanState = .completed
        let vm = makeViewModel(session: session)
        XCTAssertEqual(vm.session.scanState, .completed)
    }

    // MARK: - Screen switching (no state loss)

    func test_navigate_switchesToRequestedScreen() {
        let vm = makeViewModel()
        vm.navigate(to: .lidar)
        XCTAssertEqual(vm.activeScreen, .lidar)
    }

    func test_navigate_switchingScreensDoesNotClearRooms() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Kitchen")
        vm.addRoom(room)

        vm.navigate(to: .photos)
        vm.navigate(to: .voice)
        vm.navigate(to: .objects)

        XCTAssertEqual(vm.session.rooms.count, 1, "Room must survive screen switches")
    }

    func test_navigate_switchingScreensDoesNotClearObjects() {
        let vm = makeViewModel()
        var room = ScannedRoom(jobID: vm.session.id, name: "Boiler Room")
        vm.store.update { $0.addRoom(room) }
        vm.selectRoom(vm.session.rooms.first!.id)
        let obj = TaggedObject(roomID: vm.session.rooms.first!.id, category: .boiler)
        vm.addObject(obj)

        vm.navigate(to: .summary)
        vm.navigate(to: .overview)

        XCTAssertFalse(vm.session.allTaggedObjects.isEmpty, "Objects must survive screen switches")
    }

    func test_navigate_switchingScreensDoesNotClearPhotos() {
        let vm = makeViewModel()
        let photo = TaggedPhoto(filename: "test_photo.jpg")
        vm.addPhoto(photo)

        vm.navigate(to: .lidar)
        vm.navigate(to: .summary)

        XCTAssertFalse(vm.session.allPhotos.isEmpty, "Photos must survive screen switches")
    }

    // MARK: - Room management

    func test_addRoom_appendsToSession() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Hallway")
        vm.addRoom(room)
        XCTAssertEqual(vm.session.rooms.count, 1)
        XCTAssertEqual(vm.session.rooms.first?.name, "Hallway")
    }

    func test_addRoom_setsSelectedRoomID() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Bathroom")
        vm.addRoom(room)
        XCTAssertEqual(vm.selectedRoomID, room.id)
    }

    func test_addRoom_lidarRoomCreatesRoomScanEvidence() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Living Room", geometryCaptured: true)
        vm.addRoom(room)
        XCTAssertFalse(vm.session.roomScanEvidence.isEmpty,
                       "LiDAR-captured room must produce RoomScanEvidence")
    }

    func test_addRoom_manualRoomDoesNotCreateRoomScanEvidence() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Study", geometryCaptured: false)
        vm.addRoom(room)
        XCTAssertTrue(vm.session.roomScanEvidence.isEmpty,
                      "Manual room must not produce RoomScanEvidence")
    }

    func test_removeRoom_removesFromSession() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Office")
        vm.addRoom(room)
        vm.removeRoom(id: room.id)
        XCTAssertTrue(vm.session.rooms.isEmpty)
    }

    func test_removeRoom_clearsSelectionIfSelected() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Garage")
        vm.addRoom(room)
        XCTAssertEqual(vm.selectedRoomID, room.id)
        vm.removeRoom(id: room.id)
        XCTAssertNil(vm.selectedRoomID)
    }

    // MARK: - Photo attachment scope

    func test_addPhoto_sessionScopeWhenNoRoomSelected() {
        let vm = makeViewModel()
        let photo = TaggedPhoto(filename: "p1.jpg")
        vm.addPhoto(photo)

        XCTAssertEqual(vm.session.photos.count, 1, "Photo should attach at session level")
        XCTAssertNil(vm.session.photos.first?.roomID)
    }

    func test_addPhoto_roomScopeWhenRoomSelected() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Kitchen")
        vm.addRoom(room)

        let photo = TaggedPhoto(filename: "kitchen_photo.jpg")
        vm.addPhoto(photo)

        XCTAssertTrue(vm.session.rooms.first?.photos.count == 1, "Photo should attach to selected room")
        XCTAssertEqual(vm.session.rooms.first?.photos.first?.roomID, room.id)
    }

    func test_addPhoto_objectScopeWhenObjectSelected() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Utility")
        vm.addRoom(room)
        let obj = TaggedObject(roomID: room.id, category: .cylinder)
        vm.addObject(obj)

        let photo = TaggedPhoto(filename: "cylinder_photo.jpg")
        vm.addPhoto(photo)

        let allPhotos = vm.session.allPhotos
        let objectPhoto = allPhotos.first { $0.taggedObjectID == obj.id }
        XCTAssertNotNil(objectPhoto, "Photo should link to the selected object")
    }

    // MARK: - Object placement

    func test_addObject_sessionLevelWhenNoRoomSelected() {
        let vm = makeViewModel()
        vm.selectRoom(nil)
        let obj = TaggedObject(roomID: UUID(), category: .boiler)
        vm.addObject(obj)

        XCTAssertFalse(vm.session.taggedObjects.isEmpty, "Session-level objects must be stored at session level")
    }

    func test_addObject_roomLevelWhenRoomSelected() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Plant Room")
        vm.addRoom(room)

        let obj = TaggedObject(roomID: room.id, category: .boiler)
        vm.addObject(obj)

        XCTAssertFalse(vm.session.rooms.first?.taggedObjects.isEmpty ?? true,
                       "Room-scoped object must be stored in the room")
    }

    func test_addObject_objectIDStableAfterAdd() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Boiler Room")
        vm.addRoom(room)
        let obj = TaggedObject(roomID: room.id, category: .boiler)
        vm.addObject(obj)

        let stored = vm.session.allTaggedObjects.first
        XCTAssertEqual(stored?.id, obj.id, "Object UUID must be stable after add")
    }

    func test_addObject_setsSelectedObjectID() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Room")
        vm.addRoom(room)
        let obj = TaggedObject(roomID: room.id, category: .radiator)
        vm.addObject(obj)
        XCTAssertEqual(vm.selectedObjectID, obj.id)
    }

    // MARK: - Voice notes

    func test_addVoiceNote_sessionLevelWhenNoRoomSelected() {
        let vm = makeViewModel()
        vm.selectRoom(nil)
        let note = VoiceNote(localFilename: "note1.m4a", duration: 5.0, kind: .observation)
        vm.addVoiceNote(note)

        XCTAssertEqual(vm.session.voiceNotes.count, 1)
        XCTAssertNil(vm.session.voiceNotes.first?.linkedRoomID)
    }

    func test_addVoiceNote_roomLevelWhenRoomSelected() {
        let vm = makeViewModel()
        let room = ScannedRoom(jobID: vm.session.id, name: "Living Room")
        vm.addRoom(room)

        let note = VoiceNote(localFilename: "note2.m4a", duration: 10.0, kind: .observation)
        vm.addVoiceNote(note)

        XCTAssertEqual(vm.session.rooms.first?.voiceNotes.count, 1)
        XCTAssertEqual(vm.session.rooms.first?.voiceNotes.first?.linkedRoomID, room.id)
    }

    func test_updateVoiceNote_attachesTranscript() {
        let vm = makeViewModel()
        var note = VoiceNote(localFilename: "note3.m4a", duration: 8.0, kind: .observation)
        vm.addVoiceNote(note)

        note.transcript = "The boiler is in the kitchen."
        note.transcriptStatus = .completed
        vm.updateVoiceNote(note)

        XCTAssertEqual(vm.session.voiceNotes.first?.transcript, "The boiler is in the kitchen.")
    }

    // MARK: - Validation

    func test_validate_missingAddressIsBlocking() {
        let session = makeSession(address: "")
        let result = VisitSessionValidator.validate(session)
        XCTAssertFalse(result.blockingIssues.isEmpty)
        XCTAssertFalse(result.isReadyForHandoff)
    }

    func test_validate_noRoomsIsBlocking() {
        let session = makeSession()
        let result = VisitSessionValidator.validate(session)
        XCTAssertTrue(result.blockingIssues.contains(where: { $0.contains("room") }))
    }

    func test_validate_noSpatialCaptureIsBlocking() {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen", geometryCaptured: false))
        let result = VisitSessionValidator.validate(session)
        XCTAssertTrue(result.blockingIssues.contains(where: { $0.contains("spatial") }))
    }

    func test_validate_readyWhenAddressRoomsAndSpatialPresent() {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen", geometryCaptured: true))
        let result = VisitSessionValidator.validate(session)
        XCTAssertTrue(result.isReadyForHandoff)
    }

    func test_validate_voiceNotesWithoutTranscriptIsWarning() {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Room", geometryCaptured: true))
        session.addVoiceNote(VoiceNote(localFilename: "n.m4a", duration: 5.0, kind: .observation))
        let result = VisitSessionValidator.validate(session)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("transcript") }))
    }

    func test_validate_noPhotosIsWarning() {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Room", geometryCaptured: true))
        let result = VisitSessionValidator.validate(session)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("photo") }))
    }

    func test_validate_fullyCleanWhenAllPresent() {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Room", geometryCaptured: true))
        session.addPhoto(TaggedPhoto(filename: "p.jpg"))
        var note = VoiceNote(localFilename: "n.m4a", duration: 5.0, kind: .observation)
        note.transcript = "Test transcript"
        note.transcriptStatus = .completed
        session.addVoiceNote(note)
        let result = VisitSessionValidator.validate(session)
        XCTAssertTrue(result.isReadyForHandoff)
        XCTAssertTrue(result.isFullyClean)
    }

    // MARK: - AtlasPropertyV1 export shape

    func test_mapper_schemaVersionIsCurrentVersion() {
        let session = makeSession()
        let property = VisitSessionMapper.toAtlasPropertyV1(session)
        XCTAssertEqual(property.schemaVersion, currentAtlasPropertyVersion)
    }

    func test_mapper_propertyIDMatchesSessionID() {
        let session = makeSession()
        let property = VisitSessionMapper.toAtlasPropertyV1(session)
        XCTAssertEqual(property.propertyID, session.id.uuidString)
    }

    func test_mapper_jobReferencePreserved() {
        let session = makeSession(reference: "MY-REF-001")
        let property = VisitSessionMapper.toAtlasPropertyV1(session)
        XCTAssertEqual(property.jobReference, "MY-REF-001")
    }

    func test_mapper_roomsMappedCorrectly() {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen", geometryCaptured: true))
        session.addRoom(ScannedRoom(jobID: session.id, name: "Bathroom"))

        let property = VisitSessionMapper.toAtlasPropertyV1(session)

        XCTAssertEqual(property.rooms.count, 2)
        XCTAssertTrue(property.rooms.contains(where: { $0.name == "Kitchen" && $0.geometryCaptured }))
        XCTAssertTrue(property.rooms.contains(where: { $0.name == "Bathroom" && !$0.geometryCaptured }))
    }

    func test_mapper_objectsMappedUnderCorrectRoom() {
        var session = makeSession()
        var room = ScannedRoom(jobID: session.id, name: "Plant Room", geometryCaptured: true)
        let obj = TaggedObject(roomID: room.id, category: .boiler)
        room.addTaggedObject(obj)
        session.addRoom(room)

        let property = VisitSessionMapper.toAtlasPropertyV1(session)

        let contractRoom = property.rooms.first(where: { $0.name == "Plant Room" })
        XCTAssertEqual(contractRoom?.objects.count, 1)
        XCTAssertEqual(contractRoom?.objects.first?.category, "boiler")
        XCTAssertEqual(contractRoom?.objects.first?.roomID, room.id.uuidString)
    }

    func test_mapper_sessionLevelObjectsInSessionObjects() {
        var session = makeSession()
        let obj = TaggedObject(roomID: session.id, category: .cylinder)
        session.addTaggedObject(obj)

        let property = VisitSessionMapper.toAtlasPropertyV1(session)

        XCTAssertEqual(property.sessionObjects.count, 1)
        XCTAssertNil(property.sessionObjects.first?.roomID)
    }

    func test_mapper_evidenceSummaryTotalsCorrect() {
        var session = makeSession()
        session.addPhoto(TaggedPhoto(filename: "p1.jpg"))
        session.addPhoto(TaggedPhoto(filename: "p2.jpg"))
        let note = VoiceNote(localFilename: "n.m4a", duration: 5.0, kind: .observation)
        session.addVoiceNote(note)

        let property = VisitSessionMapper.toAtlasPropertyV1(session)

        XCTAssertEqual(property.evidenceSummary.totalPhotos, 2)
        XCTAssertEqual(property.evidenceSummary.totalVoiceNotes, 1)
    }

    func test_mapper_encodesToValidJSON() throws {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Room", geometryCaptured: true))

        let property = VisitSessionMapper.toAtlasPropertyV1(session)
        let data = try VisitSessionMapper.encode(property)

        XCTAssertFalse(data.isEmpty)

        // Verify JSON can be decoded back
        let decoded = try JSONDecoder().decode(AtlasPropertyV1.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, currentAtlasPropertyVersion)
        XCTAssertEqual(decoded.propertyID, session.id.uuidString)
    }

    func test_mapper_noRawAudioInPayload() throws {
        var session = makeSession()
        let note = VoiceNote(localFilename: "note.m4a", duration: 8.0, kind: .observation)
        session.addVoiceNote(note)

        let property = VisitSessionMapper.toAtlasPropertyV1(session)
        let data = try VisitSessionMapper.encode(property)
        let jsonString = String(data: data, encoding: .utf8) ?? ""

        // The raw audio filename must not appear in the export payload
        XCTAssertFalse(jsonString.contains("note.m4a"),
                       "Raw audio filename must not appear in handoff payload")
    }

    func test_mapper_onlyMediumHighConfidenceFactsIncluded() {
        var session = makeSession()
        let lowFact = ExtractedSessionFact(
            category: .currentSystemType,
            value: "unknown",
            confidence: .low
        )
        let highFact = ExtractedSessionFact(
            category: .householdComposition,
            value: "Family of 4",
            confidence: .high
        )
        session.addExtractedFact(lowFact)
        session.addExtractedFact(highFact)

        let property = VisitSessionMapper.toAtlasPropertyV1(session)

        XCTAssertNotNil(property.sessionKnowledge)
        XCTAssertEqual(property.sessionKnowledge?.extractedFacts.count, 1)
        XCTAssertEqual(property.sessionKnowledge?.extractedFacts.first?.confidence, "high")
    }

    // MARK: - Autosave / restore

    func test_autosave_sessionCanBeEncodedAndDecoded() throws {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
        session.addPhoto(TaggedPhoto(filename: "photo.jpg"))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(PropertyScanSession.self, from: data)

        XCTAssertEqual(restored.id, session.id)
        XCTAssertEqual(restored.rooms.count, 1)
        XCTAssertEqual(restored.photos.count, 1)
    }

    func test_autosave_newFieldsDecodableFromOlderJSON() throws {
        // Ensure backward-safe decode: omit newer fields and verify defaults apply.
        let minimalJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "jobReference": "JOB-001",
            "propertyAddress": "1 Test Street",
            "engineerName": "",
            "rooms": [],
            "photos": [],
            "voiceNotes": [],
            "taggedObjects": [],
            "issues": [],
            "roomAdjacencies": [],
            "roomPlacements": [],
            "roomScanEvidence": [],
            "externalClearanceScenes": [],
            "installMarkupObjects": [],
            "installMarkupRoutes": [],
            "extractedFacts": [],
            "scanState": "in_progress",
            "reviewState": "pending",
            "syncState": "local_only",
            "handoffState": "not_sent",
            "createdAt": "2024-01-01T10:00:00Z",
            "updatedAt": "2024-01-01T10:00:00Z"
        }
        """
        let data = Data(minimalJSON.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PropertyScanSession.self, from: data)
        XCTAssertEqual(session.propertyAddress, "1 Test Street")
        XCTAssertEqual(session.scanState, .inProgress)
    }

    // MARK: - Link consistency

    func test_objectPhotoLinkConsistency_orphanedPhotoLinksAreWarned() {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Room", geometryCaptured: true))
        // Add a photo that references a non-existent object ID
        var photo = TaggedPhoto(filename: "orphan.jpg")
        photo.taggedObjectID = UUID() // points to nothing
        session.addPhoto(photo)

        let result = VisitSessionValidator.validate(session)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("missing") }),
                      "Orphaned photo link should produce a warning")
    }
}
