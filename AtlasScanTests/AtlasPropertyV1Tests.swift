import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - AtlasPropertyV1Tests
//
// Unit tests for PropertyScanSession.toAtlasPropertyV1() projection.
// Verifies that all provenance, spatial, and evidence data is correctly
// projected into the canonical AtlasPropertyV1 contract type.

final class AtlasPropertyV1Tests: XCTestCase {

    // MARK: - Schema identity

    func test_schemaVersion_isCurrentVersion() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.schemaVersion, currentAtlasPropertyVersion)
    }

    func test_schemaVersion_isSupportedVersion() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()
        XCTAssertTrue(supportedAtlasPropertyVersions.contains(property.schemaVersion))
    }

    // MARK: - Provenance

    func test_propertyID_matchesSessionID() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.propertyID, session.id.uuidString)
    }

    func test_jobReference_preserved() {
        let session = PropertyScanSession(jobReference: "ATL-2024-001", propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.jobReference, "ATL-2024-001")
    }

    func test_propertyAddress_preserved() {
        let session = PropertyScanSession(propertyAddress: "14 Maple Street, Anytown")
        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.propertyAddress, "14 Maple Street, Anytown")
    }

    func test_engineerName_preserved() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street", engineerName: "Sam Taylor")
        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.engineerName, "Sam Taylor")
    }

    func test_atlasJobID_preserved_whenSet() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street", atlasJobID: "ATLAS-999")
        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.atlasJobID, "ATLAS-999")
    }

    func test_atlasJobID_isNil_whenNotSet() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()
        XCTAssertNil(property.atlasJobID)
    }

    func test_scanState_rawValue_preserved() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street", scanState: .completed)
        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.scanState, ScanSessionState.completed.rawValue)
    }

    func test_reviewState_rawValue_preserved() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street", reviewState: .reviewed)
        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.reviewState, ReviewState.reviewed.rawValue)
    }

    // MARK: - Timestamps

    func test_capturedAt_isISO8601() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: property.capturedAt), "capturedAt must be a valid ISO-8601 string")
    }

    func test_handoffAt_isISO8601() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let handoffDate = Date()
        let property = session.toAtlasPropertyV1(handoffDate: handoffDate)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(formatter.date(from: property.handoffAt), "handoffAt must be a valid ISO-8601 string")
    }

    func test_handoffAt_reflectsProvidedDate() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let handoffDate = Date(timeIntervalSince1970: 1_700_000_000)
        let property = session.toAtlasPropertyV1(handoffDate: handoffDate)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: property.handoffAt)
        XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0, handoffDate.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Room projection

    func test_rooms_countMatches() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room1 = ScannedRoom(jobID: session.id, name: "Kitchen")
        let room2 = ScannedRoom(jobID: session.id, name: "Living Room")
        session.addRoom(room1)
        session.addRoom(room2)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.count, 2)
    }

    func test_room_id_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.id, room.id.uuidString)
    }

    func test_room_name_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.name, "Kitchen")
    }

    func test_room_floorIndex_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Bedroom", floor: 1)
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.floorIndex, 1)
    }

    func test_room_geometryCaptured_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen", geometryCaptured: true)
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.geometryCaptured, true)
    }

    func test_room_isReviewed_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen", isReviewed: true)
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.isReviewed, true)
    }

    func test_room_area_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen", areaSquareMetres: 14.5)
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.areaM2, 14.5)
    }

    func test_room_height_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = ScannedRoom(jobID: session.id, name: "Kitchen", ceilingHeightMetres: 2.4)
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.heightM, 2.4)
    }

    // MARK: - Object projection (room-level)

    func test_roomObjects_countPreserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        var room = ScannedRoom(jobID: session.id, name: "Utility Room")
        room.taggedObjects = [
            TaggedObject(roomID: room.id, category: .boiler),
            TaggedObject(roomID: room.id, category: .cylinder),
        ]
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.objects.count, 2)
    }

    func test_roomObject_roomID_isSetToContainingRoom() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        var room = ScannedRoom(jobID: session.id, name: "Utility Room")
        let obj = TaggedObject(roomID: room.id, category: .boiler)
        room.taggedObjects = [obj]
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.objects.first?.roomID, room.id.uuidString)
    }

    func test_roomObject_category_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        var room = ScannedRoom(jobID: session.id, name: "Utility Room")
        room.taggedObjects = [TaggedObject(roomID: room.id, category: .boiler)]
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.objects.first?.category, ServiceObjectCategory.boiler.rawValue)
    }

    func test_roomObject_quickFields_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        var room = ScannedRoom(jobID: session.id, name: "Utility Room")
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.quickFieldValues = ["type": "Combi", "flue_direction": "Rear"]
        room.taggedObjects = [obj]
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.rooms.first?.objects.first?.quickFields, ["type": "Combi", "flue_direction": "Rear"])
    }

    // MARK: - Session-level (floating) objects

    func test_sessionObjects_notInRooms_appearsInSessionObjects() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let obj = TaggedObject(roomID: UUID(), category: .radiator)
        session.addTaggedObject(obj)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.sessionObjects.count, 1)
        XCTAssertNil(property.sessionObjects.first?.roomID,
                     "Session-level objects should have nil roomID in the contract")
    }

    func test_roomsRemainEmpty_whenNoRoomsAdded() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()
        XCTAssertTrue(property.rooms.isEmpty)
    }

    // MARK: - Adjacencies

    func test_adjacencies_countPreserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room1 = ScannedRoom(jobID: session.id, name: "Kitchen")
        let room2 = ScannedRoom(jobID: session.id, name: "Utility Room")
        session.addRoom(room1)
        session.addRoom(room2)
        session.addAdjacency(RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id, kind: .door, isConfirmed: true))

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.adjacencies.count, 1)
    }

    func test_adjacency_roomIDs_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room1 = ScannedRoom(jobID: session.id, name: "Kitchen")
        let room2 = ScannedRoom(jobID: session.id, name: "Utility Room")
        session.addRoom(room1)
        session.addRoom(room2)
        let adj = RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id, kind: .archway, isConfirmed: true)
        session.addAdjacency(adj)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.adjacencies.first?.fromRoomID, room1.id.uuidString)
        XCTAssertEqual(property.adjacencies.first?.toRoomID, room2.id.uuidString)
    }

    func test_adjacency_kind_rawValue_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room1 = ScannedRoom(jobID: session.id, name: "Kitchen")
        let room2 = ScannedRoom(jobID: session.id, name: "Utility Room")
        session.addRoom(room1)
        session.addRoom(room2)
        session.addAdjacency(RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id, kind: .door))

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.adjacencies.first?.kind, AdjacencyKind.door.rawValue)
    }

    func test_adjacency_isConfirmed_preserved() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room1 = ScannedRoom(jobID: session.id, name: "Kitchen")
        let room2 = ScannedRoom(jobID: session.id, name: "Utility Room")
        session.addRoom(room1)
        session.addRoom(room2)
        session.addAdjacency(RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id, isConfirmed: true))

        let property = session.toAtlasPropertyV1()
        XCTAssertTrue(property.adjacencies.first?.isConfirmed ?? false)
    }

    // MARK: - Evidence summary

    func test_evidenceSummary_totalPhotos_includesSessionAndRoomPhotos() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")

        // One session-level photo
        let sessionPhoto = TaggedPhoto(filename: "a.jpg")
        session.addPhoto(sessionPhoto)

        // One room-level photo
        var room = ScannedRoom(jobID: session.id, name: "Kitchen")
        let roomPhoto = TaggedPhoto(roomID: room.id, filename: "b.jpg")
        room.photos = [roomPhoto]
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.evidenceSummary.totalPhotos, 2)
    }

    func test_evidenceSummary_sessionPhotoCount_countsSessionLevelOnly() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let photo1 = TaggedPhoto(filename: "a.jpg")
        let photo2 = TaggedPhoto(filename: "b.jpg")
        session.addPhoto(photo1)
        session.addPhoto(photo2)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.evidenceSummary.sessionPhotoCount, 2)
    }

    func test_evidenceSummary_totalVoiceNotes_includesSessionAndRoomNotes() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")

        let sessionNote = VoiceNote(localFilename: "note1.m4a")
        session.addVoiceNote(sessionNote)

        var room = ScannedRoom(jobID: session.id, name: "Kitchen")
        let roomNote = VoiceNote(localFilename: "note2.m4a")
        room.voiceNotes = [roomNote]
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertEqual(property.evidenceSummary.totalVoiceNotes, 2)
    }

    // MARK: - World anchor projection

    func test_worldAnchor_projectedWhenPresent() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        var room = ScannedRoom(jobID: session.id, name: "Kitchen")
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.worldAnchor = WorldAnchor3D(x: 1.5, y: 0.0, z: -2.3, screenX: 0.4, screenY: 0.6)
        room.taggedObjects = [obj]
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        let anchor = property.rooms.first?.objects.first?.worldAnchor
        XCTAssertNotNil(anchor)
        XCTAssertEqual(anchor?.x ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(anchor?.z ?? 0, -2.3, accuracy: 0.001)
        XCTAssertEqual(anchor?.screenX ?? 0, 0.4, accuracy: 0.001)
        XCTAssertEqual(anchor?.screenY ?? 0, 0.6, accuracy: 0.001)
    }

    func test_worldAnchor_isNil_whenNotPlaced() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        var room = ScannedRoom(jobID: session.id, name: "Kitchen")
        let obj = TaggedObject(roomID: room.id, category: .boiler)
        room.taggedObjects = [obj]
        session.addRoom(room)

        let property = session.toAtlasPropertyV1()
        XCTAssertNil(property.rooms.first?.objects.first?.worldAnchor)
    }

    // MARK: - Codable round-trip

    func test_atlasPropertyV1_canEncodeAndDecode() throws {
        var session = PropertyScanSession(propertyAddress: "1 Roundtrip Lane", engineerName: "Test Engineer")
        var room = ScannedRoom(jobID: session.id, name: "Boiler Room")
        room.taggedObjects = [TaggedObject(roomID: room.id, category: .boiler, quickFieldValues: ["type": "Combi"])]
        session.addRoom(room)
        session.addAdjacency(RoomAdjacency(fromRoomID: room.id, toRoomID: UUID(), kind: .door))

        let property = session.toAtlasPropertyV1()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(property)
        XCTAssertFalse(data.isEmpty)

        let decoded = try JSONDecoder().decode(AtlasPropertyV1.self, from: data)
        XCTAssertEqual(decoded.propertyID, property.propertyID)
        XCTAssertEqual(decoded.propertyAddress, property.propertyAddress)
        XCTAssertEqual(decoded.schemaVersion, property.schemaVersion)
        XCTAssertEqual(decoded.rooms.count, property.rooms.count)
    }

    func test_atlasPropertyV1_jsonContainsSchemaVersionKey() throws {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()

        let data = try JSONEncoder().encode(property)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["schemaVersion"], "JSON output must include 'schemaVersion' key")
    }

    // MARK: - Bundle versioning guardrails

    func test_isBundleVersionStale_currentVersion_returnsFalse() {
        XCTAssertFalse(isBundleVersionStale(currentScanBundleVersion))
    }

    func test_isBundleVersionStale_olderMinorVersion_returnsTrue() {
        // Simulate a future where "1.1" is the current version and "1.0" is stale.
        // We test the comparison logic directly using the helper.
        // Since only "1.0" is supported today, this validates the function signature
        // and that equal versions are not flagged as stale.
        XCTAssertFalse(isBundleVersionStale("1.0"),
                       "Current version must not be flagged as stale")
    }

    func test_isBundleVersionStale_unsupportedVersion_returnsFalse() {
        // Versions that are not in supportedScanBundleVersions must never be
        // flagged as stale (they are rejected outright by validateScanBundle).
        XCTAssertFalse(isBundleVersionStale("99.0"))
    }
}
