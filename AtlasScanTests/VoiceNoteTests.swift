import XCTest
@testable import AtlasScan

// MARK: - VoiceNoteTests

final class VoiceNoteTests: XCTestCase {

    // MARK: - Model defaults

    func test_voiceNote_defaultKind_isOther() {
        let note = VoiceNote(localFilename: "test.m4a")
        XCTAssertEqual(note.kind, .other)
    }

    func test_voiceNote_defaultSyncState_isLocalOnly() {
        let note = VoiceNote(localFilename: "test.m4a")
        XCTAssertEqual(note.syncState, .localOnly)
    }

    func test_voiceNote_defaultTranscriptStatus_isNone() {
        let note = VoiceNote(localFilename: "test.m4a")
        XCTAssertEqual(note.transcriptStatus, .none)
    }

    func test_voiceNote_defaultLinkedRoomID_isNil() {
        let note = VoiceNote(localFilename: "test.m4a")
        XCTAssertNil(note.linkedRoomID)
    }

    func test_voiceNote_defaultLinkedObjectID_isNil() {
        let note = VoiceNote(localFilename: "test.m4a")
        XCTAssertNil(note.linkedObjectID)
    }

    func test_voiceNote_kind_stored() {
        let note = VoiceNote(localFilename: "test.m4a", kind: .customerNote)
        XCTAssertEqual(note.kind, .customerNote)
    }

    func test_voiceNote_linkedRoomID_stored() {
        let id = UUID()
        let note = VoiceNote(linkedRoomID: id, localFilename: "test.m4a")
        XCTAssertEqual(note.linkedRoomID, id)
    }

    func test_voiceNote_linkedObjectID_stored() {
        let id = UUID()
        let note = VoiceNote(linkedObjectID: id, localFilename: "test.m4a")
        XCTAssertEqual(note.linkedObjectID, id)
    }

    // MARK: - VoiceNoteKind display

    func test_voiceNoteKind_allCases_haveDisplayName() {
        for kind in VoiceNoteKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind.rawValue) has empty displayName")
        }
    }

    func test_voiceNoteKind_allCases_haveSymbolName() {
        for kind in VoiceNoteKind.allCases {
            XCTAssertFalse(kind.symbolName.isEmpty, "\(kind.rawValue) has empty symbolName")
        }
    }

    // MARK: - VoiceNoteSyncState

    func test_voiceNoteSyncState_canQueue_trueForLocalOnly() {
        XCTAssertTrue(VoiceNoteSyncState.localOnly.canQueue)
    }

    func test_voiceNoteSyncState_canQueue_trueForFailed() {
        XCTAssertTrue(VoiceNoteSyncState.failed.canQueue)
    }

    func test_voiceNoteSyncState_canQueue_falseForUploaded() {
        XCTAssertFalse(VoiceNoteSyncState.uploaded.canQueue)
    }

    func test_voiceNoteSyncState_allCases_haveDisplayName() {
        for state in VoiceNoteSyncState.allCases {
            XCTAssertFalse(state.displayName.isEmpty, "\(state.rawValue) has empty displayName")
        }
    }

    // MARK: - Codable round-trip

    func test_voiceNote_codableRoundTrip() throws {
        let roomID = UUID()
        let objID = UUID()
        let note = VoiceNote(
            linkedRoomID: roomID,
            linkedObjectID: objID,
            localFilename: "abc123.m4a",
            duration: 12.5,
            caption: "Boiler clearance observation",
            kind: .observation,
            transcriptStatus: .none,
            syncState: .localOnly
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(note)
        let decoded = try decoder.decode(VoiceNote.self, from: data)

        XCTAssertEqual(decoded.id, note.id)
        XCTAssertEqual(decoded.linkedRoomID, roomID)
        XCTAssertEqual(decoded.linkedObjectID, objID)
        XCTAssertEqual(decoded.localFilename, "abc123.m4a")
        XCTAssertEqual(decoded.duration, 12.5, accuracy: 0.001)
        XCTAssertEqual(decoded.caption, "Boiler clearance observation")
        XCTAssertEqual(decoded.kind, .observation)
        XCTAssertEqual(decoded.syncState, .localOnly)
    }

    // MARK: - Backward-compatible decode (missing fields)

    func test_voiceNote_decodesWithoutKindField_defaultsToOther() throws {
        let json = """
        {
          "id": "A1B2C3D4-0000-0000-0000-000000000001",
          "localFilename": "old_note.m4a",
          "createdAt": "2024-01-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let note = try decoder.decode(VoiceNote.self, from: json)

        XCTAssertEqual(note.kind, .other, "Notes without 'kind' should default to .other")
        XCTAssertEqual(note.syncState, .localOnly, "Notes without 'syncState' should default to .localOnly")
        XCTAssertEqual(note.transcriptStatus, .none)
        XCTAssertNil(note.linkedRoomID)
        XCTAssertNil(note.linkedObjectID)
        XCTAssertEqual(note.caption, "")
        XCTAssertEqual(note.duration, 0, accuracy: 0.001)
    }
}

// MARK: - PropertyScanSession Voice Note Tests

final class PropertyScanSessionVoiceNoteTests: XCTestCase {

    func test_addVoiceNote_appendsNote() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let note = VoiceNote(localFilename: "n1.m4a")
        session.addVoiceNote(note)
        XCTAssertEqual(session.voiceNotes.count, 1)
    }

    func test_removeVoiceNote_byID() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let note = VoiceNote(localFilename: "n1.m4a")
        session.addVoiceNote(note)
        session.removeVoiceNote(id: note.id)
        XCTAssertEqual(session.voiceNotes.count, 0)
    }

    func test_allVoiceNotes_aggregatesSessionAndRoomNotes() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.addVoiceNote(VoiceNote(localFilename: "session.m4a"))

        var room = ScannedRoom(jobID: session.id, name: "Kitchen")
        room.addVoiceNote(VoiceNote(localFilename: "room.m4a"))
        session.addRoom(room)

        XCTAssertEqual(session.allVoiceNotes.count, 2)
    }

    func test_totalVoiceNotes_includesRoomNotes() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.addVoiceNote(VoiceNote(localFilename: "a.m4a"))
        session.addVoiceNote(VoiceNote(localFilename: "b.m4a"))

        var room = ScannedRoom(jobID: session.id, name: "Utility")
        room.addVoiceNote(VoiceNote(localFilename: "c.m4a"))
        session.addRoom(room)

        XCTAssertEqual(session.totalVoiceNotes, 3)
    }

    func test_sessionDecodesWithoutVoiceNotes_yieldsEmptyArray() throws {
        let json = """
        {
          "id": "A1B2C3D4-0000-0000-0000-000000000050",
          "jobReference": "JOB-50",
          "propertyAddress": "50 Old Street",
          "engineerName": "Legacy",
          "rooms": [],
          "taggedObjects": [],
          "photos": [],
          "issues": [],
          "createdAt": "2024-01-01T12:00:00Z",
          "updatedAt": "2024-01-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PropertyScanSession.self, from: json)

        XCTAssertTrue(session.voiceNotes.isEmpty,
                      "Sessions without 'voiceNotes' key should default to empty array")
    }
}

// MARK: - ScannedRoom Voice Note Tests

final class ScannedRoomVoiceNoteTests: XCTestCase {

    func test_addVoiceNote_updatesCount() {
        var room = ScannedRoom(jobID: UUID(), name: "Kitchen")
        let note = VoiceNote(linkedRoomID: room.id, localFilename: "n1.m4a")
        room.addVoiceNote(note)
        XCTAssertEqual(room.voiceNotes.count, 1)
    }

    func test_removeVoiceNote_byID() {
        var room = ScannedRoom(jobID: UUID(), name: "Kitchen")
        let note = VoiceNote(linkedRoomID: room.id, localFilename: "n1.m4a")
        room.addVoiceNote(note)
        room.removeVoiceNote(id: note.id)
        XCTAssertEqual(room.voiceNotes.count, 0)
    }

    func test_roomDecodesWithoutVoiceNotes_yieldsEmptyArray() throws {
        let json = """
        {
          "id": "A1B2C3D4-0000-0000-0000-000000000060",
          "jobID": "A1B2C3D4-0000-0000-0000-000000000061",
          "name": "Living Room",
          "floor": 0,
          "walls": [],
          "openings": [],
          "geometryCaptured": false,
          "taggedObjects": [],
          "photos": [],
          "notes": "",
          "isReviewed": false,
          "createdAt": "2024-01-01T12:00:00Z",
          "updatedAt": "2024-01-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let room = try decoder.decode(ScannedRoom.self, from: json)

        XCTAssertTrue(room.voiceNotes.isEmpty,
                      "Rooms without 'voiceNotes' key should default to empty array")
    }
}

// MARK: - TaggedObject linkedVoiceNoteIDs Tests

final class TaggedObjectVoiceNoteIDTests: XCTestCase {

    func test_taggedObject_defaultLinkedVoiceNoteIDs_isEmpty() {
        let obj = TaggedObject(roomID: UUID(), category: .boiler)
        XCTAssertTrue(obj.linkedVoiceNoteIDs.isEmpty)
    }

    func test_taggedObject_decodesWithoutLinkedVoiceNoteIDs_yieldsEmptyArray() throws {
        let json = """
        {
          "id": "A1B2C3D4-0000-0000-0000-000000000070",
          "roomID": "A1B2C3D4-0000-0000-0000-000000000071",
          "category": "boiler",
          "label": "Boiler",
          "placementMode": "floor",
          "rotation": 0,
          "linkedPhotoIDs": [],
          "linkedIssueIDs": [],
          "quickFieldValues": {},
          "notes": "",
          "isConfirmed": false,
          "confidence": "medium",
          "createdAt": "2024-01-01T12:00:00Z",
          "updatedAt": "2024-01-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let obj = try decoder.decode(TaggedObject.self, from: json)

        XCTAssertTrue(obj.linkedVoiceNoteIDs.isEmpty,
                      "Objects without 'linkedVoiceNoteIDs' should default to empty array")
    }
}

// MARK: - AtlasSync Voice Note Queue Tests

@MainActor
final class AtlasSyncVoiceNoteTests: XCTestCase {

    private var atlasSync: AtlasSync!
    private let enabledConfig = AtlasSyncConfiguration(apiBaseURL: URL(string: "https://api.example.com")!)

    override func setUp() async throws {
        try await super.setUp()
        atlasSync = AtlasSync(configuration: enabledConfig)
    }

    override func tearDown() async throws {
        atlasSync.cancelAll()
        atlasSync = nil
        try await super.tearDown()
    }

    // MARK: - enqueueVoiceNote

    func test_enqueueVoiceNote_localOnly_addsToQueue() {
        let note = VoiceNote(localFilename: "n1.m4a", syncState: .localOnly)
        atlasSync.enqueueVoiceNote(note)
        XCTAssertEqual(atlasSync.uploadQueue.count, 1)
        XCTAssertEqual(atlasSync.uploadQueue.first?.voiceNoteID, note.id)
    }

    func test_enqueueVoiceNote_failed_addsToQueue() {
        let note = VoiceNote(localFilename: "n2.m4a", syncState: .failed)
        atlasSync.enqueueVoiceNote(note)
        XCTAssertEqual(atlasSync.uploadQueue.count, 1)
    }

    func test_enqueueVoiceNote_uploaded_isNoOp() {
        let note = VoiceNote(localFilename: "n3.m4a", syncState: .uploaded)
        atlasSync.enqueueVoiceNote(note)
        XCTAssertTrue(atlasSync.uploadQueue.isEmpty,
                      "Already-uploaded notes must not be re-queued")
    }

    func test_enqueueVoiceNote_queued_isNoOp() {
        let note = VoiceNote(localFilename: "n4.m4a", syncState: .queued)
        atlasSync.enqueueVoiceNote(note)
        XCTAssertTrue(atlasSync.uploadQueue.isEmpty)
    }

    func test_enqueueVoiceNotes_onlyQueuesEligibleNotes() {
        let eligible = VoiceNote(localFilename: "a.m4a", syncState: .localOnly)
        let ineligible = VoiceNote(localFilename: "b.m4a", syncState: .uploaded)
        atlasSync.enqueueVoiceNotes([eligible, ineligible])
        XCTAssertEqual(atlasSync.uploadQueue.count, 1)
        XCTAssertEqual(atlasSync.uploadQueue.first?.voiceNoteID, eligible.id)
    }

    func test_enqueueVoiceNote_syncDisabled_isNoOp() {
        let disabledSync = AtlasSync()  // no apiBaseURL → disabled
        let note = VoiceNote(localFilename: "n5.m4a", syncState: .localOnly)
        disabledSync.enqueueVoiceNote(note)
        XCTAssertTrue(disabledSync.uploadQueue.isEmpty,
                      "Voice notes must not be queued when Atlas sync is not configured")
    }

    // MARK: - ItemKind.voiceNoteID

    func test_uploadItem_voiceNoteID_returnsNoteID() {
        let note = VoiceNote(localFilename: "n6.m4a")
        let item = AtlasSyncUploadItem(kind: .voiceNote(note))
        XCTAssertEqual(item.voiceNoteID, note.id)
    }

    func test_uploadItem_photoItem_voiceNoteID_isNil() {
        let photo = TaggedPhoto(filename: "p.jpg")
        let item = AtlasSyncUploadItem(kind: .photo(photo))
        XCTAssertNil(item.voiceNoteID)
    }

    // MARK: - ItemKind description

    func test_voiceNoteItemKind_description_containsNoteID() {
        let note = VoiceNote(localFilename: "n7.m4a")
        let kind = AtlasSyncUploadItem.ItemKind.voiceNote(note)
        XCTAssertTrue(kind.description.contains(note.id.uuidString))
        XCTAssertTrue(kind.description.hasPrefix("voiceNote("))
    }

    // MARK: - cancelAll clears voice notes

    func test_cancelAll_removesVoiceNoteItems() {
        atlasSync.enqueueVoiceNote(VoiceNote(localFilename: "a.m4a"))
        atlasSync.enqueueVoiceNote(VoiceNote(localFilename: "b.m4a"))
        atlasSync.cancelAll()
        XCTAssertTrue(atlasSync.uploadQueue.isEmpty)
        XCTAssertFalse(atlasSync.isUploading)
    }
}
