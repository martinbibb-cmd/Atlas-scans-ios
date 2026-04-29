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
