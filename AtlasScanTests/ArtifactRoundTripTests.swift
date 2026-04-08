import XCTest
@testable import AtlasScan

// MARK: - ArtifactRoundTripTests
//
// Validates that a captured PropertyScanSession survives a full encode→decode
// round trip with all cross-links (object→photo, object→voice-note,
// photo→room, note→room) intact.
//
// Also tests the ArtifactLinkReport integrity checker to ensure it catches
// broken or orphaned references and passes clean sessions without false positives.

final class ArtifactRoundTripTests: XCTestCase {

    // MARK: - Helpers

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func roundTrip(_ session: PropertyScanSession) throws -> PropertyScanSession {
        let data = try encoder.encode(session)
        return try decoder.decode(PropertyScanSession.self, from: data)
    }

    // MARK: - Basic round-trip

    func test_session_encodesAndDecodes_withNoChildren() throws {
        let original = PropertyScanSession(
            propertyAddress: "1 Test Street",
            engineerName: "A. Engineer"
        )
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.propertyAddress, original.propertyAddress)
        XCTAssertEqual(decoded.engineerName, original.engineerName)
        XCTAssertTrue(decoded.rooms.isEmpty)
        XCTAssertTrue(decoded.taggedObjects.isEmpty)
        XCTAssertTrue(decoded.photos.isEmpty)
        XCTAssertTrue(decoded.voiceNotes.isEmpty)
    }

    // MARK: - Voice notes round-trip

    func test_sessionLevelVoiceNote_survivesRoundTrip() throws {
        var session = PropertyScanSession(propertyAddress: "2 Test Road")
        let note = VoiceNote(localFilename: "obs_001.m4a", duration: 12.5, kind: .observation)
        session.addVoiceNote(note)

        let decoded = try roundTrip(session)

        XCTAssertEqual(decoded.voiceNotes.count, 1)
        let n = try XCTUnwrap(decoded.voiceNotes.first)
        XCTAssertEqual(n.id, note.id)
        XCTAssertEqual(n.localFilename, "obs_001.m4a")
        XCTAssertEqual(n.duration, 12.5)
        XCTAssertEqual(n.kind, .observation)
    }

    func test_roomLevelVoiceNote_survivesRoundTrip() throws {
        let roomID = UUID()
        var room = ScannedRoom(id: roomID, jobID: UUID(), name: "Living Room", floor: 0)
        let note = VoiceNote(linkedRoomID: roomID, localFilename: "room_note.m4a", kind: .constraint)
        room.addVoiceNote(note)

        var session = PropertyScanSession(propertyAddress: "3 Test Lane")
        session.rooms.append(room)

        let decoded = try roundTrip(session)

        XCTAssertEqual(decoded.rooms.count, 1)
        let decodedRoom = try XCTUnwrap(decoded.rooms.first)
        XCTAssertEqual(decodedRoom.voiceNotes.count, 1)
        let n = try XCTUnwrap(decodedRoom.voiceNotes.first)
        XCTAssertEqual(n.id, note.id)
        XCTAssertEqual(n.localFilename, "room_note.m4a")
        XCTAssertEqual(n.kind, .constraint)
        XCTAssertEqual(n.linkedRoomID, roomID)
    }

    func test_allVoiceNotes_aggregatesSessionAndRoomNotes() throws {
        let roomID = UUID()
        var room = ScannedRoom(id: roomID, jobID: UUID(), name: "Kitchen", floor: 0)
        let roomNote = VoiceNote(linkedRoomID: roomID, localFilename: "room.m4a")
        room.addVoiceNote(roomNote)

        let sessionNote = VoiceNote(localFilename: "session.m4a")
        var session = PropertyScanSession(propertyAddress: "4 Test Ave")
        session.rooms.append(room)
        session.addVoiceNote(sessionNote)

        let decoded = try roundTrip(session)

        XCTAssertEqual(decoded.totalVoiceNotes, 2)
        XCTAssertEqual(decoded.allVoiceNotes.count, 2)
        let ids = Set(decoded.allVoiceNotes.map(\.id))
        XCTAssertTrue(ids.contains(roomNote.id))
        XCTAssertTrue(ids.contains(sessionNote.id))
    }

    // MARK: - Object → voice note cross-link round-trip

    func test_objectVoiceNoteCrossLink_survivesRoundTrip() throws {
        let objID  = UUID()
        let roomID = UUID()
        var obj  = TaggedObject(id: objID, roomID: roomID, category: .boiler, normalizedPosition: .init(x: 0.5, y: 0.5))
        var note = VoiceNote(linkedRoomID: roomID, linkedObjectID: objID, localFilename: "boiler.m4a")
        obj.linkedVoiceNoteIDs.append(note.id)
        note.linkedObjectID = objID

        var room = ScannedRoom(id: roomID, jobID: UUID(), name: "Utility", floor: 0)
        room.taggedObjects.append(obj)
        room.addVoiceNote(note)

        var session = PropertyScanSession(propertyAddress: "5 Test Court")
        session.rooms.append(room)

        let decoded = try roundTrip(session)

        let decodedRoom = try XCTUnwrap(decoded.rooms.first)
        let decodedObj  = try XCTUnwrap(decodedRoom.taggedObjects.first)
        let decodedNote = try XCTUnwrap(decodedRoom.voiceNotes.first)

        // Forward cross-link: object knows its note
        XCTAssertTrue(decodedObj.linkedVoiceNoteIDs.contains(decodedNote.id))
        // Back link: note knows its object
        XCTAssertEqual(decodedNote.linkedObjectID, decodedObj.id)
        // Room link on note
        XCTAssertEqual(decodedNote.linkedRoomID, decodedRoom.id)
    }

    // MARK: - Object → photo cross-link round-trip

    func test_objectPhotoCrossLink_survivesRoundTrip() throws {
        let objID  = UUID()
        let roomID = UUID()
        var obj   = TaggedObject(id: objID, roomID: roomID, category: .boiler, normalizedPosition: .init(x: 0.5, y: 0.5))
        var photo = TaggedPhoto(roomID: roomID, taggedObjectID: objID, filename: "boiler.jpg")
        obj.linkedPhotoIDs.append(photo.id)
        photo.taggedObjectID = objID

        var room = ScannedRoom(id: roomID, jobID: UUID(), name: "Utility", floor: 0)
        room.taggedObjects.append(obj)
        room.addPhoto(photo)

        var session = PropertyScanSession(propertyAddress: "6 Test Place")
        session.rooms.append(room)

        let decoded = try roundTrip(session)

        let decodedRoom  = try XCTUnwrap(decoded.rooms.first)
        let decodedObj   = try XCTUnwrap(decodedRoom.taggedObjects.first)
        let decodedPhoto = try XCTUnwrap(decodedRoom.photos.first)

        XCTAssertTrue(decodedObj.linkedPhotoIDs.contains(decodedPhoto.id))
        XCTAssertEqual(decodedPhoto.taggedObjectID, decodedObj.id)
        XCTAssertEqual(decodedPhoto.roomID, decodedRoom.id)
    }

    // MARK: - ArtifactLinkReport: clean session

    func test_linkReport_cleanSession_hasNoIssues() {
        let objID  = UUID()
        let roomID = UUID()
        var obj   = TaggedObject(id: objID, roomID: roomID, category: .boiler, normalizedPosition: .init(x: 0.5, y: 0.5))
        var note  = VoiceNote(linkedRoomID: roomID, linkedObjectID: objID, localFilename: "clean.m4a")
        obj.linkedVoiceNoteIDs.append(note.id)
        note.linkedObjectID = objID

        var photo = TaggedPhoto(roomID: roomID, taggedObjectID: objID, filename: "clean.jpg")
        obj.linkedPhotoIDs.append(photo.id)
        photo.taggedObjectID = objID

        var room = ScannedRoom(id: roomID, jobID: UUID(), name: "Utility", floor: 0)
        room.taggedObjects.append(obj)
        room.addVoiceNote(note)
        room.addPhoto(photo)

        var session = PropertyScanSession(propertyAddress: "Clean Session")
        session.rooms.append(room)

        let report = ArtifactLinkReport.build(from: session)
        XCTAssertTrue(report.issues.isEmpty, "Clean session should produce no link issues. Got: \(report.issues.map(\.description))")
    }

    func test_linkReport_emptySession_hasNoIssues() {
        let session = PropertyScanSession(propertyAddress: "Empty Session")
        let report = ArtifactLinkReport.build(from: session)
        XCTAssertTrue(report.issues.isEmpty)
    }

    // MARK: - ArtifactLinkReport: broken object→photo link

    func test_linkReport_missingPhotoForObjectCrossLink_reportsError() {
        let roomID = UUID()
        let orphanPhotoID = UUID()  // never added to the session
        var obj = TaggedObject(id: UUID(), roomID: roomID, category: .boiler, normalizedPosition: .init(x: 0.5, y: 0.5))
        obj.linkedPhotoIDs.append(orphanPhotoID)

        var room = ScannedRoom(id: roomID, jobID: UUID(), name: "Room", floor: 0)
        room.taggedObjects.append(obj)

        var session = PropertyScanSession(propertyAddress: "Broken Photo Link")
        session.rooms.append(room)

        let report = ArtifactLinkReport.build(from: session)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertTrue(report.hasErrors)
        XCTAssertTrue(report.issues.contains(where: { $0.severity == .error }))
    }

    // MARK: - ArtifactLinkReport: broken object→voice note link

    func test_linkReport_missingNoteForObjectCrossLink_reportsError() {
        let roomID = UUID()
        let orphanNoteID = UUID()  // never added to the session
        var obj = TaggedObject(id: UUID(), roomID: roomID, category: .boiler, normalizedPosition: .init(x: 0.5, y: 0.5))
        obj.linkedVoiceNoteIDs.append(orphanNoteID)

        var room = ScannedRoom(id: roomID, jobID: UUID(), name: "Room", floor: 0)
        room.taggedObjects.append(obj)

        var session = PropertyScanSession(propertyAddress: "Broken Note Link")
        session.rooms.append(room)

        let report = ArtifactLinkReport.build(from: session)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertTrue(report.hasErrors)
    }

    // MARK: - ArtifactLinkReport: orphaned photo (points to missing object)

    func test_linkReport_photoLinksToMissingObject_reportsError() {
        let missingObjID = UUID()
        let photo = TaggedPhoto(taggedObjectID: missingObjID, filename: "orphan.jpg")

        var session = PropertyScanSession(propertyAddress: "Orphaned Photo")
        session.addPhoto(photo)

        let report = ArtifactLinkReport.build(from: session)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertTrue(report.hasErrors)
    }

    // MARK: - ArtifactLinkReport: orphaned voice note (points to missing object)

    func test_linkReport_voiceNoteLinksToMissingObject_reportsError() {
        let missingObjID = UUID()
        let note = VoiceNote(linkedObjectID: missingObjID, localFilename: "orphan.m4a")

        var session = PropertyScanSession(propertyAddress: "Orphaned Note")
        session.addVoiceNote(note)

        let report = ArtifactLinkReport.build(from: session)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertTrue(report.hasErrors)
    }

    // MARK: - ArtifactLinkReport: photo with missing room is only a warning

    func test_linkReport_photoLinksToMissingRoom_reportsWarning() {
        let missingRoomID = UUID()
        let photo = TaggedPhoto(roomID: missingRoomID, filename: "room_photo.jpg")

        var session = PropertyScanSession(propertyAddress: "Missing Room Photo")
        session.addPhoto(photo)

        let report = ArtifactLinkReport.build(from: session)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertFalse(report.hasErrors, "Missing room should be a warning, not an error")
        XCTAssertTrue(report.issues.allSatisfy { $0.severity == .warning })
    }
}
