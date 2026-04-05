import XCTest
@testable import AtlasScan

// MARK: - TaggedPhotoTests

final class TaggedPhotoTests: XCTestCase {

    // MARK: - Model defaults

    func test_taggedPhoto_defaultKind_isOther() {
        let photo = TaggedPhoto(filename: "test.jpg")
        XCTAssertEqual(photo.kind, .other)
    }

    func test_taggedPhoto_defaultRoomID_isNil() {
        let photo = TaggedPhoto(filename: "test.jpg")
        XCTAssertNil(photo.roomID)
    }

    func test_taggedPhoto_roomID_stored() {
        let id = UUID()
        let photo = TaggedPhoto(roomID: id, filename: "test.jpg")
        XCTAssertEqual(photo.roomID, id)
    }

    func test_taggedPhoto_kind_stored() {
        let photo = TaggedPhoto(filename: "flue.jpg", kind: .flue)
        XCTAssertEqual(photo.kind, .flue)
    }

    func test_taggedPhoto_thumbnailPath_stored() {
        let photo = TaggedPhoto(filename: "test.jpg", thumbnailPath: "test_thumb.jpg")
        XCTAssertEqual(photo.thumbnailPath, "test_thumb.jpg")
    }

    // MARK: - EvidenceKind display

    func test_evidenceKind_allCases_haveDisplayName() {
        for kind in EvidenceKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind.rawValue) has empty displayName")
        }
    }

    func test_evidenceKind_allCases_haveSymbolName() {
        for kind in EvidenceKind.allCases {
            XCTAssertFalse(kind.symbolName.isEmpty, "\(kind.rawValue) has empty symbolName")
        }
    }

    // MARK: - Codable round-trip

    func test_taggedPhoto_codableRoundTrip() throws {
        let roomID = UUID()
        let objID = UUID()
        let photo = TaggedPhoto(
            roomID: roomID,
            taggedObjectID: objID,
            filename: "abc123.jpg",
            thumbnailPath: "abc123_thumb.jpg",
            caption: "Boiler clearance",
            kind: .plant,
            isKeyEvidence: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(photo)
        let decoded = try decoder.decode(TaggedPhoto.self, from: data)

        XCTAssertEqual(decoded.id, photo.id)
        XCTAssertEqual(decoded.roomID, roomID)
        XCTAssertEqual(decoded.taggedObjectID, objID)
        XCTAssertEqual(decoded.filename, "abc123.jpg")
        XCTAssertEqual(decoded.thumbnailPath, "abc123_thumb.jpg")
        XCTAssertEqual(decoded.caption, "Boiler clearance")
        XCTAssertEqual(decoded.kind, .plant)
        XCTAssertTrue(decoded.isKeyEvidence)
    }

    // MARK: - Backward-compatible decode (pre-EvidenceKind)

    func test_taggedPhoto_decodesWithoutKindField_defaultsToOther() throws {
        // Simulate a TaggedPhoto saved before EvidenceKind was introduced.
        let json = """
        {
          "id": "A1B2C3D4-0000-0000-0000-000000000010",
          "roomID": "A1B2C3D4-0000-0000-0000-000000000011",
          "filename": "old_photo.jpg",
          "caption": "Pre-kind photo",
          "isKeyEvidence": false,
          "capturedAt": "2024-01-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let photo = try decoder.decode(TaggedPhoto.self, from: json)

        XCTAssertEqual(photo.kind, .other,
            "Photos without a 'kind' field should default to .other")
        XCTAssertNil(photo.thumbnailPath,
            "Photos without a 'thumbnailPath' field should decode with nil thumbnail")
    }

    func test_taggedPhoto_decodesWithoutRoomID_yieldsNilRoomID() throws {
        // Job-level photos have no roomID.
        let json = """
        {
          "id": "A1B2C3D4-0000-0000-0000-000000000020",
          "filename": "site_photo.jpg",
          "caption": "Front elevation",
          "kind": "overview",
          "isKeyEvidence": false,
          "capturedAt": "2024-01-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let photo = try decoder.decode(TaggedPhoto.self, from: json)

        XCTAssertNil(photo.roomID)
        XCTAssertEqual(photo.kind, .overview)
    }
}

// MARK: - ScannedRoom Photo Helpers

final class ScannedRoomPhotoTests: XCTestCase {

    func test_addPhoto_updatesCount() {
        var room = ScannedRoom(jobID: UUID(), name: "Utility")
        let photo = TaggedPhoto(roomID: room.id, filename: "p1.jpg")
        room.addPhoto(photo)
        XCTAssertEqual(room.photos.count, 1)
    }

    func test_removePhoto_byID() {
        var room = ScannedRoom(jobID: UUID(), name: "Utility")
        let photo = TaggedPhoto(roomID: room.id, filename: "p1.jpg")
        room.addPhoto(photo)
        room.removePhoto(id: photo.id)
        XCTAssertEqual(room.photos.count, 0)
    }

    func test_removeTaggedObject_cascadesPhotoDeletion() {
        var room = ScannedRoom(jobID: UUID(), name: "Boiler Room")
        let object = TaggedObject(roomID: room.id, category: .boiler)
        room.addTaggedObject(object)

        let linkedPhoto = TaggedPhoto(roomID: room.id, taggedObjectID: object.id, filename: "boiler.jpg")
        let unlinkedPhoto = TaggedPhoto(roomID: room.id, filename: "general.jpg")
        room.addPhoto(linkedPhoto)
        room.addPhoto(unlinkedPhoto)
        XCTAssertEqual(room.photos.count, 2)

        room.removeTaggedObject(id: object.id)

        XCTAssertEqual(room.taggedObjects.count, 0,
            "Tagged object should be removed")
        XCTAssertEqual(room.photos.count, 1,
            "Photo linked to the deleted object should be removed")
        XCTAssertEqual(room.photos.first?.id, unlinkedPhoto.id,
            "Unlinked room photo should remain")
    }

    func test_removePhotos_forObjectID_removesOnlyLinkedPhotos() {
        var room = ScannedRoom(jobID: UUID(), name: "Kitchen")
        let objectID = UUID()
        let linked1 = TaggedPhoto(roomID: room.id, taggedObjectID: objectID, filename: "a.jpg")
        let linked2 = TaggedPhoto(roomID: room.id, taggedObjectID: objectID, filename: "b.jpg")
        let other   = TaggedPhoto(roomID: room.id, filename: "c.jpg")
        room.photos = [linked1, linked2, other]

        room.removePhotos(forObjectID: objectID)

        XCTAssertEqual(room.photos.count, 1)
        XCTAssertEqual(room.photos.first?.filename, "c.jpg")
    }
}

// MARK: - ScanJob Photo Helpers

final class ScanJobPhotoTests: XCTestCase {

    func test_addPhoto_jobLevel() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let photo = TaggedPhoto(filename: "site.jpg")
        job.addPhoto(photo)
        XCTAssertEqual(job.photos.count, 1)
    }

    func test_removePhoto_jobLevel() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let photo = TaggedPhoto(filename: "site.jpg")
        job.addPhoto(photo)
        job.removePhoto(id: photo.id)
        XCTAssertEqual(job.photos.count, 0)
    }

    func test_totalPhotos_sumsJobAndRoomPhotos() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = ScannedRoom(jobID: job.id, name: "Living Room")
        room.photos = [
            TaggedPhoto(roomID: room.id, filename: "r1.jpg"),
            TaggedPhoto(roomID: room.id, filename: "r2.jpg"),
        ]
        job.rooms = [room]
        job.addPhoto(TaggedPhoto(filename: "site.jpg"))

        XCTAssertEqual(job.totalPhotos, 3)
    }

    func test_removeRoom_cascadesJobLevelPhotos() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room = ScannedRoom(jobID: job.id, name: "Hall")
        job.addRoom(room)

        // A job-level photo explicitly linked to this room (e.g. room overview shot).
        let linked = TaggedPhoto(roomID: room.id, filename: "hall_overview.jpg")
        let unlinked = TaggedPhoto(filename: "front_elevation.jpg")  // no room
        job.addPhoto(linked)
        job.addPhoto(unlinked)
        XCTAssertEqual(job.photos.count, 2)

        job.removeRoom(id: room.id)

        XCTAssertEqual(job.photos.count, 1,
            "Job-level photo linked to the removed room should be deleted")
        XCTAssertEqual(job.photos.first?.id, unlinked.id,
            "Unlinked site photo should remain")
    }

    // MARK: - Backward-compatible decode (pre-photos field)

    func test_scanJob_decodesWithoutPhotosField() throws {
        let json = """
        {
          "id": "A1B2C3D4-0000-0000-0000-000000000099",
          "jobReference": "JOB-999",
          "propertyAddress": "14 Test Street",
          "engineerName": "Sam",
          "rooms": [],
          "status": "draft",
          "createdAt": "2024-01-01T12:00:00Z",
          "updatedAt": "2024-01-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let job = try decoder.decode(ScanJob.self, from: json)

        XCTAssertTrue(job.photos.isEmpty,
            "Jobs without the 'photos' key should default to an empty array")
    }

    func test_scanJob_photosFieldSurvivesRoundTrip() throws {
        var job = ScanJob(propertyAddress: "14 Test Street")
        job.addPhoto(TaggedPhoto(filename: "elev.jpg", kind: .overview))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(job)
        let decoded = try decoder.decode(ScanJob.self, from: data)

        XCTAssertEqual(decoded.photos.count, 1)
        XCTAssertEqual(decoded.photos.first?.filename, "elev.jpg")
        XCTAssertEqual(decoded.photos.first?.kind, .overview)
    }
}

// MARK: - ExportBuilder Evidence QA Flag Tests

final class ExportBuilderEvidenceTests: XCTestCase {

    private var builder: ExportBuilder!

    override func setUp() {
        super.setUp()
        builder = ExportBuilder()
    }

    func test_buildBundle_withRoomPhotos_emitsEvidenceCountFlag() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = ScannedRoom(jobID: job.id, name: "Utility")
        room.isReviewed = true
        room.photos = [
            TaggedPhoto(roomID: room.id, filename: "p1.jpg"),
            TaggedPhoto(roomID: room.id, filename: "p2.jpg"),
        ]
        job.rooms = [room]

        let bundle = builder.buildBundle(from: job)
        let evidenceFlags = bundle.qaFlags.filter { $0.code == "atlas.evidence_count" }

        XCTAssertEqual(evidenceFlags.count, 1)
        XCTAssertEqual(evidenceFlags.first?.severity, "info")
        XCTAssertTrue(evidenceFlags.first?.message.contains("\"photo_count\":2") == true)
        XCTAssertEqual(evidenceFlags.first?.entityId, room.id.uuidString)
    }

    func test_buildBundle_withJobPhotos_emitsJobScopeFlag() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = ScannedRoom(jobID: job.id, name: "Utility")
        room.isReviewed = true
        job.rooms = [room]
        job.addPhoto(TaggedPhoto(filename: "front.jpg"))

        let bundle = builder.buildBundle(from: job)
        let jobFlags = bundle.qaFlags.filter {
            $0.code == "atlas.evidence_count" && $0.entityId == nil
        }

        XCTAssertEqual(jobFlags.count, 1)
        XCTAssertTrue(jobFlags.first?.message.contains("\"scope\":\"job\"") == true)
        XCTAssertTrue(jobFlags.first?.message.contains("\"photo_count\":1") == true)
    }

    func test_buildBundle_withNoPhotos_emitsNoEvidenceFlags() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = ScannedRoom(jobID: job.id, name: "Utility")
        room.isReviewed = true
        job.rooms = [room]

        let bundle = builder.buildBundle(from: job)
        let evidenceFlags = bundle.qaFlags.filter { $0.code == "atlas.evidence_count" }

        XCTAssertTrue(evidenceFlags.isEmpty)
    }
}
