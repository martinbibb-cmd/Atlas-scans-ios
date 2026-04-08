import XCTest
@testable import AtlasScan

// MARK: - PropertyScanSessionTests
//
// Unit tests for PropertyScanSession, ScanSessionState, ReviewState, SessionSyncState,
// PhotoSyncState, and CameraPose.
// No RoomPlan or UIKit types required; runs on any simulator or device.

final class PropertyScanSessionTests: XCTestCase {

    // MARK: - PropertyScanSession init

    func test_init_defaultsToNotStartedScanState() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertEqual(session.scanState, .notStarted)
    }

    func test_init_defaultsToLocalOnlySyncState() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertEqual(session.syncState, .localOnly)
    }

    func test_init_defaultsToPendingReviewState() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertEqual(session.reviewState, .pending)
    }

    func test_init_emptyJobReference_generatesAutoReference() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertFalse(session.jobReference.isEmpty, "Empty jobReference should be auto-generated")
        XCTAssertTrue(session.jobReference.hasPrefix("JOB-"), "Auto-generated reference should start with JOB-")
    }

    func test_init_nonEmptyJobReference_preserved() {
        let session = PropertyScanSession(jobReference: "MY-JOB-001", propertyAddress: "1 Test Street")
        XCTAssertEqual(session.jobReference, "MY-JOB-001")
    }

    func test_init_roomsPhotosObjectsIssues_defaultEmpty() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertTrue(session.rooms.isEmpty)
        XCTAssertTrue(session.photos.isEmpty)
        XCTAssertTrue(session.taggedObjects.isEmpty)
        XCTAssertTrue(session.issues.isEmpty)
    }

    // MARK: - Room management

    func test_addRoom_appendsRoom() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        session.addRoom(room)
        XCTAssertEqual(session.rooms.count, 1)
        XCTAssertEqual(session.rooms.first?.name, "Kitchen")
    }

    func test_removeRoom_removesById() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        session.addRoom(room)
        session.removeRoom(id: room.id)
        XCTAssertTrue(session.rooms.isEmpty)
    }

    func test_removeRoom_cascadesAdjacencies() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let roomA = ScannedRoom(jobID: session.id, name: "Kitchen")
        let roomB = ScannedRoom(jobID: session.id, name: "Lounge")
        session.addRoom(roomA)
        session.addRoom(roomB)
        session.addAdjacency(RoomAdjacency(fromRoomID: roomA.id, toRoomID: roomB.id))
        session.removeRoom(id: roomA.id)
        XCTAssertTrue(session.roomAdjacencies.isEmpty,
            "Removing a room should cascade remove its adjacencies")
    }

    func test_removeRoom_cascadesPhotos() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        session.addRoom(room)
        let photo = TaggedPhoto(roomID: room.id, filename: "photo1.jpg")
        session.addPhoto(photo)
        session.removeRoom(id: room.id)
        XCTAssertTrue(session.photos.isEmpty,
            "Removing a room should cascade remove session-level photos linked to it")
    }

    func test_updateRoom_updatesExistingRoom() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        session.addRoom(room)
        var updated = room
        updated.name = "Utility Room"
        session.updateRoom(updated)
        XCTAssertEqual(session.rooms.first?.name, "Utility Room")
    }

    // MARK: - Tagged object management

    func test_addTaggedObject_appendsObject() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        session.addTaggedObject(obj)
        XCTAssertEqual(session.taggedObjects.count, 1)
    }

    func test_removeTaggedObject_removesObjectAndLinkedPhotos() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let obj = TaggedObject(roomID: session.id, category: .boiler)
        session.addTaggedObject(obj)
        let photo = TaggedPhoto(taggedObjectID: obj.id, filename: "boiler_photo.jpg")
        session.addPhoto(photo)
        session.removeTaggedObject(id: obj.id)
        XCTAssertTrue(session.taggedObjects.isEmpty)
        XCTAssertTrue(session.photos.isEmpty,
            "Removing an object should cascade remove linked session-level photos")
    }

    // MARK: - Photo management

    func test_addPhoto_appendsPhoto() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let photo = TaggedPhoto(filename: "site_photo.jpg")
        session.addPhoto(photo)
        XCTAssertEqual(session.photos.count, 1)
    }

    func test_removePhoto_removesById() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let photo = TaggedPhoto(filename: "site_photo.jpg")
        session.addPhoto(photo)
        session.removePhoto(id: photo.id)
        XCTAssertTrue(session.photos.isEmpty)
    }

    // MARK: - Aggregates

    func test_allTaggedObjects_includesRoomLevelObjects() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let sessionObj = TaggedObject(roomID: session.id, category: .boiler)
        session.addTaggedObject(sessionObj)
        var room = ScannedRoom(jobID: session.id, name: "Kitchen")
        let roomObj = TaggedObject(roomID: room.id, category: .radiator)
        room.addTaggedObject(roomObj)
        session.addRoom(room)
        XCTAssertEqual(session.allTaggedObjects.count, 2,
            "allTaggedObjects should include both session-level and room-level objects")
    }

    func test_allPhotos_includesRoomLevelPhotos() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let sessionPhoto = TaggedPhoto(filename: "site.jpg")
        session.addPhoto(sessionPhoto)
        var room = ScannedRoom(jobID: session.id, name: "Kitchen")
        let roomPhoto = TaggedPhoto(roomID: room.id, filename: "kitchen.jpg")
        room.addPhoto(roomPhoto)
        session.addRoom(room)
        XCTAssertEqual(session.allPhotos.count, 2,
            "allPhotos should include both session-level and room-level photos")
    }

    func test_isReadyToExport_falseWithNoRooms() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertFalse(session.isReadyToExport)
    }

    func test_isReadyToExport_falseWithUnreviewedRoom() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        session.addRoom(room)
        XCTAssertFalse(session.isReadyToExport,
            "Session with unreviewed room should not be ready to export")
    }

    func test_isReadyToExport_trueWhenAllRoomsReviewed() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        var room = ScannedRoom(jobID: session.id, name: "Kitchen")
        room.isReviewed = true
        session.addRoom(room)
        XCTAssertTrue(session.isReadyToExport,
            "Session with all rooms reviewed should be ready to export")
    }

    // MARK: - Issue management

    func test_addIssue_appendsIssue() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let issue = ValidationIssue(severity: .warning, message: "Test warning")
        session.addIssue(issue)
        XCTAssertEqual(session.issues.count, 1)
    }

    func test_clearIssues_removesAllIssues() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.addIssue(ValidationIssue(severity: .warning, message: "W1"))
        session.addIssue(ValidationIssue(severity: .blocking, message: "B1"))
        session.clearIssues()
        XCTAssertTrue(session.issues.isEmpty)
    }

    func test_hasBlockingIssues_falseWithNoIssues() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertFalse(session.hasBlockingIssues)
    }

    func test_hasBlockingIssues_trueWhenBlockingIssueExists() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.addIssue(ValidationIssue(severity: .blocking, message: "Blocker"))
        XCTAssertTrue(session.hasBlockingIssues)
    }

    // MARK: - Codable round-trip

    func test_codable_roundTrip_preservesAllFields() throws {
        var session = PropertyScanSession(
            jobReference: "RT-001",
            propertyAddress: "10 Round Trip Lane",
            engineerName: "Test Engineer",
            scanState: .inProgress,
            reviewState: .needsAttention,
            syncState: .queued
        )
        let room = ScannedRoom(jobID: session.id, name: "Lounge")
        session.addRoom(room)
        let photo = TaggedPhoto(filename: "photo.jpg")
        session.addPhoto(photo)
        let issue = ValidationIssue(severity: .warning, message: "Round trip warning")
        session.addIssue(issue)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PropertyScanSession.self, from: data)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.jobReference, "RT-001")
        XCTAssertEqual(decoded.propertyAddress, "10 Round Trip Lane")
        XCTAssertEqual(decoded.engineerName, "Test Engineer")
        XCTAssertEqual(decoded.scanState, .inProgress)
        XCTAssertEqual(decoded.reviewState, .needsAttention)
        XCTAssertEqual(decoded.syncState, .queued)
        XCTAssertEqual(decoded.rooms.count, 1)
        XCTAssertEqual(decoded.photos.count, 1)
        XCTAssertEqual(decoded.issues.count, 1)
    }

    // MARK: - toScanJob conversion

    func test_toScanJob_preservesCoreFields() {
        let session = PropertyScanSession(
            jobReference: "TJ-001",
            propertyAddress: "10 Test Lane",
            engineerName: "John Engineer"
        )
        let job = session.toScanJob()
        XCTAssertEqual(job.id, session.id)
        XCTAssertEqual(job.jobReference, "TJ-001")
        XCTAssertEqual(job.propertyAddress, "10 Test Lane")
        XCTAssertEqual(job.engineerName, "John Engineer")
    }

    func test_toScanJob_preservesRooms() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.addRoom(ScannedRoom(jobID: session.id, name: "Lounge"))
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
        let job = session.toScanJob()
        XCTAssertEqual(job.rooms.count, 2)
    }

    // MARK: - safeFileNameReference

    func test_safeFileNameReference_replacesSlashesAndSpaces() {
        let session = PropertyScanSession(jobReference: "JOB / 2024 TEST", propertyAddress: "1 Test Street")
        let safe = session.safeFileNameReference
        XCTAssertFalse(safe.contains("/"), "Safe file name should not contain /")
        XCTAssertFalse(safe.contains(" "), "Safe file name should not contain spaces")
    }

    // MARK: - ScanSessionState display properties

    func test_scanSessionState_allCases_haveDisplayName() {
        for state in ScanSessionState.allCases {
            XCTAssertFalse(state.displayName.isEmpty, "\(state.rawValue) must have a displayName")
            XCTAssertFalse(state.symbolName.isEmpty, "\(state.rawValue) must have a symbolName")
        }
    }

    // MARK: - ReviewState display properties

    func test_reviewState_allCases_haveDisplayName() {
        for state in ReviewState.allCases {
            XCTAssertFalse(state.displayName.isEmpty, "\(state.rawValue) must have a displayName")
            XCTAssertFalse(state.symbolName.isEmpty, "\(state.rawValue) must have a symbolName")
        }
    }

    // MARK: - SessionSyncState display properties

    func test_sessionSyncState_allCases_haveDisplayName() {
        for state in SessionSyncState.allCases {
            XCTAssertFalse(state.displayName.isEmpty, "\(state.rawValue) must have a displayName")
            XCTAssertFalse(state.symbolName.isEmpty, "\(state.rawValue) must have a symbolName")
        }
    }

    // MARK: - PhotoSyncState

    func test_photoSyncState_canQueue_onlyForLocalAndFailed() {
        XCTAssertTrue(PhotoSyncState.localOnly.canQueue)
        XCTAssertTrue(PhotoSyncState.failed.canQueue)
        XCTAssertFalse(PhotoSyncState.queued.canQueue)
        XCTAssertFalse(PhotoSyncState.uploading.canQueue)
        XCTAssertFalse(PhotoSyncState.uploaded.canQueue)
        XCTAssertFalse(PhotoSyncState.archived.canQueue)
    }

    func test_photoSyncState_allCases_haveDisplayName() {
        for state in PhotoSyncState.allCases {
            XCTAssertFalse(state.displayName.isEmpty)
            XCTAssertFalse(state.symbolName.isEmpty)
        }
    }

    // MARK: - TaggedPhoto sync fields

    func test_taggedPhoto_defaultSyncStateIsLocalOnly() {
        let photo = TaggedPhoto(filename: "test.jpg")
        XCTAssertEqual(photo.syncState, .localOnly)
    }

    func test_taggedPhoto_remoteAssetIDDefaultsToNil() {
        let photo = TaggedPhoto(filename: "test.jpg")
        XCTAssertNil(photo.remoteAssetID)
    }

    func test_taggedPhoto_cameraPoseDefaultsToNil() {
        let photo = TaggedPhoto(filename: "test.jpg")
        XCTAssertNil(photo.cameraPose)
    }

    func test_taggedPhoto_codable_preservesSyncState() throws {
        var photo = TaggedPhoto(filename: "test.jpg")
        photo.syncState = .uploaded
        photo.remoteAssetID = "remote_abc123"
        photo.cameraPose = CameraPose(
            positionX: 1.0, positionY: 2.0, positionZ: 3.0,
            directionX: 0.0, directionY: 0.0, directionZ: -1.0
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(photo)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TaggedPhoto.self, from: data)

        XCTAssertEqual(decoded.syncState, .uploaded)
        XCTAssertEqual(decoded.remoteAssetID, "remote_abc123")
        XCTAssertNotNil(decoded.cameraPose)
        XCTAssertEqual(decoded.cameraPose?.positionX, 1.0, accuracy: 0.001)
        XCTAssertEqual(decoded.cameraPose?.directionZ, -1.0, accuracy: 0.001)
    }

    func test_taggedPhoto_backwardCompatible_decodesOldFormatWithoutSyncFields() throws {
        // Simulate a photo record saved before PhotoSyncState was introduced
        let oldFormat = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "filename": "legacy.jpg",
            "caption": "old photo",
            "kind": "overview",
            "isKeyEvidence": false,
            "capturedAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let photo = try decoder.decode(TaggedPhoto.self, from: oldFormat)

        XCTAssertEqual(photo.syncState, .localOnly,
            "Old photo records without syncState should default to .localOnly")
        XCTAssertNil(photo.remoteAssetID)
        XCTAssertNil(photo.cameraPose)
    }

    // MARK: - TaggedObject new fields

    func test_taggedObject_linkedPhotoIDsDefaultEmpty() {
        let obj = TaggedObject(roomID: UUID(), category: .boiler)
        XCTAssertTrue(obj.linkedPhotoIDs.isEmpty)
    }

    func test_taggedObject_linkedIssueIDsDefaultEmpty() {
        let obj = TaggedObject(roomID: UUID(), category: .boiler)
        XCTAssertTrue(obj.linkedIssueIDs.isEmpty)
    }

    func test_taggedObject_clearanceProfileIDDefaultNil() {
        let obj = TaggedObject(roomID: UUID(), category: .boiler)
        XCTAssertNil(obj.clearanceProfileID)
    }

    func test_taggedObject_codable_preservesNewFields() throws {
        var obj = TaggedObject(roomID: UUID(), category: .boiler)
        let photoID = UUID()
        let issueID = UUID()
        obj.linkedPhotoIDs = [photoID]
        obj.linkedIssueIDs = [issueID]
        obj.clearanceProfileID = "combi_compact"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(obj)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TaggedObject.self, from: data)

        XCTAssertEqual(decoded.linkedPhotoIDs, [photoID])
        XCTAssertEqual(decoded.linkedIssueIDs, [issueID])
        XCTAssertEqual(decoded.clearanceProfileID, "combi_compact")
    }

    // MARK: - ClearanceResult layered halos

    func test_clearanceResult_layeredHalos_serviceAccessContainsInstallMinimum() {
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        XCTAssertTrue(
            result.serviceAccessRect.contains(result.installMinimumRect),
            "Service access zone must fully contain install minimum zone"
        )
    }

    func test_clearanceResult_layeredHalos_installMinimumContainsFootprint() {
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        XCTAssertTrue(
            result.installMinimumRect.contains(result.footprintRect),
            "Install minimum zone must fully contain the physical footprint"
        )
    }

    func test_clearanceResult_clearanceRectIsServiceAccessRect() {
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        XCTAssertEqual(result.clearanceRect, result.serviceAccessRect,
            "clearanceRect should be a backward-compat alias for serviceAccessRect")
    }

    func test_clearanceRule_installMinFrontLessThanServiceFront() {
        for cat in ClearanceEngine.supportedCategories {
            guard let rule = ClearanceEngine.rule(for: cat) else { continue }
            XCTAssertLessThanOrEqual(
                rule.installMinFrontMetres,
                rule.frontClearanceMetres,
                "\(cat.rawValue): installMinFront must be <= frontClearance (service access)"
            )
        }
    }

    // MARK: - PropertyScanSession Hashable

    func test_propertyScanSession_hashable_sameIDIsEqual() {
        let s1 = PropertyScanSession(propertyAddress: "1 Test St")
        var s2 = s1                         // same id
        s2.engineerName = "Different Name"  // different content
        // Two sessions with the same id must be equal regardless of other fields
        XCTAssertEqual(s1, s2)
    }

    func test_propertyScanSession_hashable_differentIDNotEqual() {
        let s1 = PropertyScanSession(propertyAddress: "1 Test St")
        let s2 = PropertyScanSession(propertyAddress: "1 Test St")
        XCTAssertNotEqual(s1, s2, "Sessions with different UUIDs must not be equal")
    }

    func test_propertyScanSession_canBeUsedInSet() {
        let s1 = PropertyScanSession(propertyAddress: "1 Test St")
        let s2 = PropertyScanSession(propertyAddress: "2 Test St")
        var s3 = s1
        s3.engineerName = "Updated"
        let set: Set<PropertyScanSession> = [s1, s2, s3]
        // s1 and s3 have the same id → set should contain only 2 elements
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - PlacementSize / boundingSize

    func test_taggedObject_boundingSizeDefaultsToNil() {
        let obj = TaggedObject(roomID: UUID(), category: .boiler)
        XCTAssertNil(obj.boundingSize)
    }

    func test_taggedObject_boundingSize_codableRoundTrip() throws {
        var obj = TaggedObject(roomID: UUID(), category: .boiler)
        obj.boundingSize = PlacementSize(widthMetres: 0.6, depthMetres: 0.5)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(obj)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TaggedObject.self, from: data)

        XCTAssertNotNil(decoded.boundingSize)
        XCTAssertEqual(decoded.boundingSize?.widthMetres ?? 0, 0.6, accuracy: 0.001)
        XCTAssertEqual(decoded.boundingSize?.depthMetres ?? 0, 0.5, accuracy: 0.001)
    }

    func test_placementSize_init_clampsNegativeValues() {
        let size = PlacementSize(widthMetres: -1.0, depthMetres: -0.5)
        XCTAssertEqual(size.widthMetres, 0.0, "Negative width should be clamped to 0")
        XCTAssertEqual(size.depthMetres, 0.0, "Negative depth should be clamped to 0")
    }

    // MARK: - Helpers

    private func roomWithDimensions(width: Double, height: Double) -> ScannedRoom {
        let walls = [
            ScannedWall(index: 0, lengthMetres: width,  bearingDegrees:  90.0),
            ScannedWall(index: 1, lengthMetres: height, bearingDegrees: 180.0),
            ScannedWall(index: 2, lengthMetres: width,  bearingDegrees: 270.0),
            ScannedWall(index: 3, lengthMetres: height, bearingDegrees:   0.0),
        ]
        return ScannedRoom(
            jobID: UUID(),
            name: "Test Room",
            areaSquareMetres: width * height,
            walls: walls,
            geometryCaptured: true
        )
    }
}
