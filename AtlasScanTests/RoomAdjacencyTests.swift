import XCTest
@testable import AtlasScan

// MARK: - RoomAdjacencyTests

final class RoomAdjacencyTests: XCTestCase {

    // MARK: - RoomAdjacency model

    func test_adjacency_defaults() {
        let adj = RoomAdjacency(fromRoomID: UUID(), toRoomID: UUID())
        XCTAssertEqual(adj.kind, .door)
        XCTAssertFalse(adj.isConfirmed)
        XCTAssertTrue(adj.notes.isEmpty)
        XCTAssertNil(adj.openingID)
    }

    func test_adjacency_connects_bothDirections() {
        let roomA = UUID()
        let roomB = UUID()
        let adj = RoomAdjacency(fromRoomID: roomA, toRoomID: roomB)
        XCTAssertTrue(adj.connects(roomA, to: roomB))
        XCTAssertTrue(adj.connects(roomB, to: roomA))
    }

    func test_adjacency_connects_returnsFalse_forUnrelatedRooms() {
        let adj = RoomAdjacency(fromRoomID: UUID(), toRoomID: UUID())
        XCTAssertFalse(adj.connects(UUID(), to: UUID()))
    }

    func test_adjacencyKind_allCases_haveDisplayName() {
        for kind in AdjacencyKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind.rawValue) has empty displayName")
        }
    }

    func test_adjacencyKind_allCases_haveSymbolName() {
        for kind in AdjacencyKind.allCases {
            XCTAssertFalse(kind.symbolName.isEmpty, "\(kind.rawValue) has empty symbolName")
        }
    }

    // MARK: - RoomPlacementOverride

    func test_roomPlacementOverride_clampedCoordinates() {
        let over = RoomPlacementOverride(id: UUID(), x: 1.5, y: -0.3)
        XCTAssertEqual(over.x, 1.0)
        XCTAssertEqual(over.y, 0.0)
    }

    func test_roomPlacementOverride_validCoordinates() {
        let over = RoomPlacementOverride(id: UUID(), x: 0.3, y: 0.7)
        XCTAssertEqual(over.x, 0.3)
        XCTAssertEqual(over.y, 0.7)
    }

    // MARK: - ScanJob adjacency helpers

    func test_addAdjacency_updatesCount() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room1 = ScannedRoom(jobID: job.id, name: "Room 1")
        let room2 = ScannedRoom(jobID: job.id, name: "Room 2")
        job.rooms = [room1, room2]
        let adj = RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id)
        job.addAdjacency(adj)
        XCTAssertEqual(job.roomAdjacencies.count, 1)
    }

    func test_removeAdjacency_decreasesCount() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room1 = ScannedRoom(jobID: job.id, name: "Room 1")
        let room2 = ScannedRoom(jobID: job.id, name: "Room 2")
        job.rooms = [room1, room2]
        let adj = RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id)
        job.addAdjacency(adj)
        job.removeAdjacency(id: adj.id)
        XCTAssertEqual(job.roomAdjacencies.count, 0)
    }

    func test_updateAdjacency_replacesInPlace() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room1 = ScannedRoom(jobID: job.id, name: "Room 1")
        let room2 = ScannedRoom(jobID: job.id, name: "Room 2")
        job.rooms = [room1, room2]
        var adj = RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id, kind: .door, isConfirmed: false)
        job.addAdjacency(adj)

        adj.isConfirmed = true
        job.updateAdjacency(adj)

        XCTAssertTrue(job.roomAdjacencies.first?.isConfirmed == true)
        XCTAssertEqual(job.roomAdjacencies.count, 1, "Update should not add a duplicate")
    }

    func test_removeRoom_alsoCleansAdjacencies() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room1 = ScannedRoom(jobID: job.id, name: "Room 1")
        let room2 = ScannedRoom(jobID: job.id, name: "Room 2")
        job.rooms = [room1, room2]
        job.addAdjacency(RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id))
        XCTAssertEqual(job.roomAdjacencies.count, 1)

        job.removeRoom(id: room1.id)

        XCTAssertEqual(job.roomAdjacencies.count, 0,
            "Removing a room must remove its adjacencies")
    }

    func test_removeRoom_cleansAdjacencies_whenRoomIsTarget() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room1 = ScannedRoom(jobID: job.id, name: "Room 1")
        let room2 = ScannedRoom(jobID: job.id, name: "Room 2")
        job.rooms = [room1, room2]
        job.addAdjacency(RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id))

        // Removing the to-room should also clean up the adjacency.
        job.removeRoom(id: room2.id)

        XCTAssertEqual(job.roomAdjacencies.count, 0,
            "Removing the to-room must also remove its adjacencies")
    }

    func test_adjacencies_forRoom_returnsCorrectSubset() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room1 = ScannedRoom(jobID: job.id, name: "Room 1")
        let room2 = ScannedRoom(jobID: job.id, name: "Room 2")
        let room3 = ScannedRoom(jobID: job.id, name: "Room 3")
        job.rooms = [room1, room2, room3]
        job.addAdjacency(RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id))
        job.addAdjacency(RoomAdjacency(fromRoomID: room2.id, toRoomID: room3.id))

        let forRoom1 = job.adjacencies(for: room1.id)
        let forRoom2 = job.adjacencies(for: room2.id)
        let forRoom3 = job.adjacencies(for: room3.id)

        XCTAssertEqual(forRoom1.count, 1)
        XCTAssertEqual(forRoom2.count, 2)
        XCTAssertEqual(forRoom3.count, 1)
    }

    // MARK: - Room placement helpers

    func test_setRoomPlacement_storesOverride() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let roomID = UUID()
        XCTAssertNil(job.roomPlacement(for: roomID))

        job.setRoomPlacement(RoomPlacementOverride(id: roomID, x: 0.3, y: 0.7))

        let stored = job.roomPlacement(for: roomID)
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored?.x, 0.3)
        XCTAssertEqual(stored?.y, 0.7)
    }

    func test_setRoomPlacement_updatesExistingOverride() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let roomID = UUID()
        job.setRoomPlacement(RoomPlacementOverride(id: roomID, x: 0.3, y: 0.7))
        job.setRoomPlacement(RoomPlacementOverride(id: roomID, x: 0.6, y: 0.2))

        XCTAssertEqual(job.roomPlacements.count, 1,
            "Updating a placement override should not add a duplicate")
        XCTAssertEqual(job.roomPlacement(for: roomID)?.x, 0.6)
        XCTAssertEqual(job.roomPlacement(for: roomID)?.y, 0.2)
    }

    func test_removeRoom_alsoCleansRoomPlacements() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room = ScannedRoom(jobID: job.id, name: "Room 1")
        job.rooms = [room]
        job.setRoomPlacement(RoomPlacementOverride(id: room.id, x: 0.5, y: 0.5))
        XCTAssertEqual(job.roomPlacements.count, 1)

        job.removeRoom(id: room.id)

        XCTAssertEqual(job.roomPlacements.count, 0,
            "Removing a room must remove its placement override")
    }

    // MARK: - Codable round-trips

    func test_adjacency_codableRoundTrip() throws {
        let adj = RoomAdjacency(
            fromRoomID: UUID(),
            toRoomID: UUID(),
            openingID: UUID(),
            kind: .archway,
            isConfirmed: true,
            notes: "Main hallway arch"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(adj)
        let decoded = try decoder.decode(RoomAdjacency.self, from: data)

        XCTAssertEqual(decoded.id, adj.id)
        XCTAssertEqual(decoded.fromRoomID, adj.fromRoomID)
        XCTAssertEqual(decoded.toRoomID, adj.toRoomID)
        XCTAssertEqual(decoded.openingID, adj.openingID)
        XCTAssertEqual(decoded.kind, .archway)
        XCTAssertTrue(decoded.isConfirmed)
        XCTAssertEqual(decoded.notes, "Main hallway arch")
    }

    func test_scanJob_decodesWithoutAdjacencyFields() throws {
        // Simulate a job file saved before multi-room linking was added.
        // The JSON will not contain 'roomAdjacencies' or 'roomPlacements' keys.
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

        XCTAssertTrue(job.roomAdjacencies.isEmpty,
            "Jobs without roomAdjacencies key should default to an empty array")
        XCTAssertTrue(job.roomPlacements.isEmpty,
            "Jobs without roomPlacements key should default to an empty array")
    }

    func test_scanJob_adjacencyFieldsSurviveRoundTrip() throws {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room1 = ScannedRoom(jobID: job.id, name: "Room 1")
        let room2 = ScannedRoom(jobID: job.id, name: "Room 2")
        job.rooms = [room1, room2]
        job.addAdjacency(
            RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id, kind: .door, isConfirmed: true)
        )
        job.setRoomPlacement(RoomPlacementOverride(id: room1.id, x: 0.2, y: 0.8))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(job)
        let decoded = try decoder.decode(ScanJob.self, from: data)

        XCTAssertEqual(decoded.roomAdjacencies.count, 1)
        XCTAssertEqual(decoded.roomAdjacencies.first?.kind, .door)
        XCTAssertEqual(decoded.roomPlacements.count, 1)
        XCTAssertEqual(decoded.roomPlacements.first?.x, 0.2)
    }
}

// MARK: - ExportBuilder adjacency flag tests

final class ExportBuilderAdjacencyTests: XCTestCase {

    private var builder: ExportBuilder!

    override func setUp() {
        super.setUp()
        builder = ExportBuilder()
    }

    func test_buildBundle_withAdjacencies_emitsQAFlags() {
        var job = makeValidJob()
        let room1 = job.rooms[0]
        let room2 = job.rooms[1]
        job.addAdjacency(
            RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id, kind: .door, isConfirmed: true)
        )

        let bundle = builder.buildBundle(from: job)

        let adjacencyFlags = bundle.qaFlags.filter { $0.code == "atlas.room_adjacency" }
        XCTAssertEqual(adjacencyFlags.count, 1,
            "One confirmed adjacency should produce one atlas.room_adjacency QA flag")
        XCTAssertEqual(adjacencyFlags.first?.severity, "info")
        XCTAssertTrue(adjacencyFlags.first?.message.contains("door") == true)
    }

    func test_buildBundle_unconfirmedAdjacency_emitsWarningSeverity() {
        var job = makeValidJob()
        let room1 = job.rooms[0]
        let room2 = job.rooms[1]
        job.addAdjacency(
            RoomAdjacency(fromRoomID: room1.id, toRoomID: room2.id, kind: .door, isConfirmed: false)
        )

        let bundle = builder.buildBundle(from: job)

        let flag = bundle.qaFlags.first { $0.code == "atlas.room_adjacency" }
        XCTAssertEqual(flag?.severity, "warning",
            "Unconfirmed adjacency should produce a warning-severity QA flag")
    }

    func test_buildBundle_noAdjacencies_emitsNoAdjacencyFlags() {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let adjacencyFlags = bundle.qaFlags.filter { $0.code == "atlas.room_adjacency" }
        XCTAssertTrue(adjacencyFlags.isEmpty,
            "A job with no adjacencies should produce no atlas.room_adjacency flags")
    }

    // MARK: Helpers

    private func makeValidJob(roomCount: Int = 2) -> ScanJob {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        job.rooms = (0..<roomCount).map { i in
            var room = ScannedRoom(jobID: job.id, name: "Room \(i + 1)")
            room.isReviewed = true
            return room
        }
        return job
    }
}
