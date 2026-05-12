import XCTest
import AtlasScanCore
@testable import AtlasScan

// MARK: - GeometryQAFlagTests
//
// Tests for geometry QA flag emission in ScanSessionCoordinator.upsertRoom
// and for the completionStatus field in ScanToMindHandoffV1.
//
// Covers:
//   - Triangle polygon (3 vertices) → lowConfidenceRoomShape flag
//   - Degenerate polygon (< 3 vertices) → polygonCollapsed flag
//   - Normal polygon (≥ 4 vertices, adequate area) → no geometry QA flag
//   - Very small area (< 1 m²) → lowConfidenceRoomShape flag
//   - Repeated upsert replaces stale flags (idempotent)
//   - completionStatus is .complete when readiness is fully satisfied
//   - completionStatus is .incompleteDraft when session evidence is missing
//   - completionStatus round-trips correctly via JSON encode/decode

@MainActor
final class GeometryQAFlagTests: XCTestCase {

    // MARK: - Setup

    private var store: AtomicSessionStore!
    private var coordinator: ScanSessionCoordinator!
    private var visitId: UUID!

    override func setUp() {
        super.setUp()
        visitId = UUID()
        store = AtomicSessionStore()
        coordinator = ScanSessionCoordinator(visitId: visitId, store: store)
    }

    override func tearDown() {
        try? store.delete(visitId: visitId)
        coordinator = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Builds a rectangular room polygon with `sideM` metre sides.
    private func squareRoom(id: UUID = UUID(), sideM: Double = 4.0) -> RoomCaptureV2 {
        let h = sideM / 2
        var room = RoomCaptureV2(id: id, displayName: "Test Room")
        room.polygonVertices = [
            Vertex2D(x: -h, z: -h),
            Vertex2D(x:  h, z: -h),
            Vertex2D(x:  h, z:  h),
            Vertex2D(x: -h, z:  h),
        ]
        return room
    }

    /// Builds a triangle room (3 vertices).
    private func triangleRoom(id: UUID = UUID()) -> RoomCaptureV2 {
        var room = RoomCaptureV2(id: id, displayName: "Triangle Room")
        room.polygonVertices = [
            Vertex2D(x: 0,   z: 0),
            Vertex2D(x: 3,   z: 0),
            Vertex2D(x: 1.5, z: 2),
        ]
        return room
    }

    /// Builds a room with no polygon vertices.
    private func emptyPolygonRoom(id: UUID = UUID()) -> RoomCaptureV2 {
        RoomCaptureV2(id: id, displayName: "Empty Polygon Room")
    }

    // MARK: - Geometry QA flag tests

    func test_upsertRoom_trianglePolygon_emitsLowConfidenceShapeFlag() {
        let room = triangleRoom()
        coordinator.upsertRoom(room)

        let flags = coordinator.session.qaFlags.filter { $0.roomId == room.id }
        XCTAssertTrue(
            flags.contains { $0.type == .lowConfidenceRoomShape },
            "Triangle polygon must emit lowConfidenceRoomShape flag"
        )
        XCTAssertFalse(
            flags.contains { $0.type == .polygonCollapsed },
            "Triangle polygon must NOT emit polygonCollapsed flag"
        )
    }

    func test_upsertRoom_emptyPolygon_emitsPolygonCollapsedFlag() {
        let room = emptyPolygonRoom()
        coordinator.upsertRoom(room)

        XCTAssertTrue(
            coordinator.session.qaFlags.contains {
                $0.type == .polygonCollapsed && $0.roomId == room.id
            },
            "Empty polygon must emit polygonCollapsed flag"
        )
    }

    func test_upsertRoom_normalSquareRoom_noGeometryQAFlag() {
        let room = squareRoom(sideM: 4.0)   // 16 m² — well above threshold
        coordinator.upsertRoom(room)

        let geometryFlags = coordinator.session.qaFlags.filter {
            ($0.type == .polygonCollapsed || $0.type == .lowConfidenceRoomShape)
            && $0.roomId == room.id
        }
        XCTAssertTrue(geometryFlags.isEmpty, "Normal room must not emit any geometry QA flags")
    }

    func test_upsertRoom_verySmallRoom_emitsLowConfidenceShapeFlag() {
        // 4-vertex room with area = 0.1 × 0.1 = 0.01 m² — below the 1 m² threshold
        var room = RoomCaptureV2(id: UUID(), displayName: "Tiny Room")
        room.polygonVertices = [
            Vertex2D(x: 0,    z: 0),
            Vertex2D(x: 0.1,  z: 0),
            Vertex2D(x: 0.1,  z: 0.1),
            Vertex2D(x: 0,    z: 0.1),
        ]
        coordinator.upsertRoom(room)

        XCTAssertTrue(
            coordinator.session.qaFlags.contains {
                $0.type == .lowConfidenceRoomShape && $0.roomId == room.id
            },
            "Very small room must emit lowConfidenceRoomShape flag"
        )
    }

    func test_upsertRoom_replacesStaleGeometryFlags_onReUpsert() {
        let roomId = UUID()

        // First upsert: triangle → lowConfidenceRoomShape
        coordinator.upsertRoom(triangleRoom(id: roomId))
        XCTAssertTrue(coordinator.session.qaFlags.contains {
            $0.type == .lowConfidenceRoomShape && $0.roomId == roomId
        }, "Triangle must emit lowConfidenceRoomShape initially")

        // Second upsert: normal square — stale flag must be removed
        coordinator.upsertRoom(squareRoom(id: roomId, sideM: 4.0))
        let geometryFlags = coordinator.session.qaFlags.filter {
            ($0.type == .polygonCollapsed || $0.type == .lowConfidenceRoomShape)
            && $0.roomId == roomId
        }
        XCTAssertTrue(
            geometryFlags.isEmpty,
            "Stale geometry flags must be removed when room is re-upserted with valid geometry"
        )
    }

    // MARK: - completionStatus tests

    func test_handoffCompletionStatus_isIncompleteDraft_forEmptySession() throws {
        let session = SessionCaptureV2(visitId: UUID())
        let handoff = try ScanToMindPayloadEncoder.encode(session: session)
        XCTAssertEqual(
            handoff.completionStatus, .incompleteDraft,
            "Empty session must produce incompleteDraft completionStatus"
        )
    }

    func test_handoffCompletionStatus_isComplete_whenReadinessIsFullySatisfied() throws {
        let readiness = VisitReadinessV1(
            hasRooms: true,
            hasPhotos: true,
            hasBoilerDetails: true,
            hasFlueDetails: true,
            hasClearanceCheck: true,
            hasTranscripts: true,
            hasPropertyAddress: true
        )
        let session = SessionCaptureV2(visitId: UUID())
        let handoff = ScanToMindHandoffV1(session: session, readiness: readiness)
        XCTAssertEqual(
            handoff.completionStatus, .complete,
            "Fully ready readiness must produce complete completionStatus"
        )
    }

    func test_handoffCompletionStatus_isIncompleteDraft_whenReadinessFails() throws {
        let readiness = VisitReadinessV1(
            hasRooms: true,
            hasPhotos: false,   // missing photos
            hasBoilerDetails: true,
            hasFlueDetails: false,  // missing flue
            hasClearanceCheck: true,
            hasTranscripts: true,
            hasPropertyAddress: true
        )
        let session = SessionCaptureV2(visitId: UUID())
        let handoff = ScanToMindHandoffV1(session: session, readiness: readiness)
        XCTAssertEqual(
            handoff.completionStatus, .incompleteDraft,
            "Incomplete readiness must produce incompleteDraft completionStatus"
        )
    }

    func test_handoffCompletionStatus_roundTripsViaJSON() throws {
        let session = SessionCaptureV2(visitId: UUID())
        let handoff = try ScanToMindPayloadEncoder.encode(session: session)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(handoff)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanToMindHandoffV1.self, from: data)

        XCTAssertEqual(
            decoded.completionStatus, handoff.completionStatus,
            "completionStatus must survive JSON encode/decode round-trip"
        )
    }

    func test_handoffCompletionStatus_backwardCompat_defaultsToIncompleteDraftWhenAbsent() throws {
        // Build a minimal JSON payload without the completionStatus key,
        // simulating an older payload that pre-dates this field.
        let session = SessionCaptureV2(visitId: UUID())
        let handoff = try ScanToMindPayloadEncoder.encode(session: session)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var dict = try JSONSerialization.jsonObject(with: try encoder.encode(handoff)) as! [String: Any]
        dict.removeValue(forKey: "completionStatus")
        let stripped = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanToMindHandoffV1.self, from: stripped)

        // Absent field with incomplete session → incompleteDraft
        XCTAssertEqual(
            decoded.completionStatus, .incompleteDraft,
            "Absent completionStatus field must decode as incompleteDraft for backward compat"
        )
    }
}

