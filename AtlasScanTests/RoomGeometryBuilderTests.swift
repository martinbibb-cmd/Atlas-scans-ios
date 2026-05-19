import XCTest
import AtlasScanCore

// MARK: - RoomGeometryBuilderTests
//
// Unit tests for RoomGeometryBuilder.buildFloorPlan(from:snapToleranceM:).
//
// All tests are pure (no AR hardware, no simd) and run on any platform.
//
// Covers:
//   - Rectangular room → 4 connected segments and closed polygon
//   - L-shaped room → does NOT collapse into a triangle
//   - Open/incomplete scan → wallSegmentsOnly confidence
//   - Empty segment list → failed confidence
//   - Single segment → estimated confidence
//   - Pin roomFloorX/Z populated for spatially-anchored pins
//   - Pin roomFloorX/Z nil for screenOnly pins
//   - screenOnly pins counted but flagged via anchorConfidence

final class RoomGeometryBuilderTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a rectangular room: segments run CW from origin.
    ///
    ///  (0,0)──(W,0)──(W,D)──(0,D)──(0,0)
    ///
    private func rectangularSegments(width: Double = 4.0, depth: Double = 3.0) -> [RoomWallSegment2D] {
        return [
            RoomWallSegment2D(wallIndex: 0, start: Vertex2D(x: 0, z: 0),     end: Vertex2D(x: width, z: 0)),
            RoomWallSegment2D(wallIndex: 1, start: Vertex2D(x: width, z: 0), end: Vertex2D(x: width, z: depth)),
            RoomWallSegment2D(wallIndex: 2, start: Vertex2D(x: width, z: depth), end: Vertex2D(x: 0, z: depth)),
            RoomWallSegment2D(wallIndex: 3, start: Vertex2D(x: 0, z: depth), end: Vertex2D(x: 0, z: 0)),
        ]
    }

    /// L-shaped room, 6-wall polygon.
    ///
    ///  (0,0)──(4,0)──(4,2)──(2,2)──(2,4)──(0,4)──(0,0)
    ///
    private func lShapedSegments() -> [RoomWallSegment2D] {
        return [
            RoomWallSegment2D(wallIndex: 0, start: Vertex2D(x: 0, z: 0), end: Vertex2D(x: 4, z: 0)),
            RoomWallSegment2D(wallIndex: 1, start: Vertex2D(x: 4, z: 0), end: Vertex2D(x: 4, z: 2)),
            RoomWallSegment2D(wallIndex: 2, start: Vertex2D(x: 4, z: 2), end: Vertex2D(x: 2, z: 2)),
            RoomWallSegment2D(wallIndex: 3, start: Vertex2D(x: 2, z: 2), end: Vertex2D(x: 2, z: 4)),
            RoomWallSegment2D(wallIndex: 4, start: Vertex2D(x: 2, z: 4), end: Vertex2D(x: 0, z: 4)),
            RoomWallSegment2D(wallIndex: 5, start: Vertex2D(x: 0, z: 4), end: Vertex2D(x: 0, z: 0)),
        ]
    }

    /// 3 out of 4 walls — simulates an incomplete/open scan.
    private func openScanSegments() -> [RoomWallSegment2D] {
        let full = rectangularSegments()
        return Array(full.dropLast())   // drop the 4th wall
    }

    // MARK: - Rectangular room

    func test_rectangularRoom_producesClosedPolygon() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: rectangularSegments())
        XCTAssertEqual(result.confidence, .closedPolygon,
                       "Rectangular room must produce closedPolygon confidence")
    }

    func test_rectangularRoom_produces4Vertices() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: rectangularSegments())
        XCTAssertEqual(result.vertices.count, 4,
                       "Rectangular room must produce exactly 4 polygon vertices")
    }

    func test_rectangularRoom_orderedSegmentsContainsAll4() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: rectangularSegments())
        XCTAssertEqual(result.orderedSegments.count, 4,
                       "Rectangular room must have all 4 segments in ordered list")
    }

    func test_rectangularRoom_hasNoWarnings() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: rectangularSegments())
        XCTAssertTrue(result.warnings.isEmpty,
                      "Rectangular room with clean segments must produce no warnings")
    }

    // MARK: - L-shaped room

    func test_lShapedRoom_producesClosedPolygon() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: lShapedSegments())
        XCTAssertEqual(result.confidence, .closedPolygon,
                       "L-shaped room must produce closedPolygon confidence")
    }

    func test_lShapedRoom_doesNotCollapseIntoTriangle() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: lShapedSegments())
        XCTAssertGreaterThan(result.vertices.count, 3,
                             "L-shaped room must NOT collapse to a triangle — must have > 3 vertices")
    }

    func test_lShapedRoom_produces6Vertices() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: lShapedSegments())
        XCTAssertEqual(result.vertices.count, 6,
                       "L-shaped room (6 walls) must produce 6 polygon vertices")
    }

    func test_lShapedRoom_allSegmentsChained() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: lShapedSegments())
        XCTAssertEqual(result.orderedSegments.count, 6,
                       "All 6 L-shaped room segments must be chained")
    }

    // MARK: - Open / incomplete scan

    func test_openScan_returnsWallSegmentsOnly() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: openScanSegments())
        XCTAssertEqual(result.confidence, .wallSegmentsOnly,
                       "Open scan (3 of 4 walls) must return wallSegmentsOnly confidence")
    }

    func test_openScan_hasGapWarning() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: openScanSegments())
        let hasGapWarning = result.warnings.contains { $0.lowercased().contains("gap") }
        XCTAssertTrue(hasGapWarning,
                      "Open scan must include a warning about the room outline gap")
    }

    func test_openScan_stillProvidesVertices() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: openScanSegments())
        XCTAssertFalse(result.vertices.isEmpty,
                       "Open scan must still provide vertices for wall-line drawing")
    }

    // MARK: - Empty input

    func test_emptySegments_returnsFailed() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: [])
        XCTAssertEqual(result.confidence, .failed,
                       "No segments must return failed confidence")
    }

    func test_emptySegments_returnsNoVertices() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: [])
        XCTAssertTrue(result.vertices.isEmpty,
                      "No segments must return empty vertices")
    }

    func test_emptySegments_hasWarning() {
        let result = RoomGeometryBuilder.buildFloorPlan(from: [])
        XCTAssertFalse(result.warnings.isEmpty,
                       "No segments must include a warning")
    }

    // MARK: - Single segment

    func test_singleSegment_returnsEstimated() {
        let segs = [RoomWallSegment2D(wallIndex: 0,
                                      start: Vertex2D(x: 0, z: 0),
                                      end: Vertex2D(x: 3, z: 0))]
        let result = RoomGeometryBuilder.buildFloorPlan(from: segs)
        XCTAssertEqual(result.confidence, .estimated,
                       "Single segment must return estimated confidence")
    }

    func test_singleSegment_returnsNoVertices() {
        let segs = [RoomWallSegment2D(wallIndex: 0,
                                      start: Vertex2D(x: 0, z: 0),
                                      end: Vertex2D(x: 3, z: 0))]
        let result = RoomGeometryBuilder.buildFloorPlan(from: segs)
        XCTAssertTrue(result.vertices.isEmpty,
                      "Single segment must return empty vertices")
    }

    // MARK: - Never invents a triangle from four walls with a gap

    /// Regression test: ensures that four walls with a large gap between the
    /// last and first endpoint do NOT produce a fake 3-vertex closed polygon.
    func test_fourWallsWithGap_doesNotProduceTriangle() {
        // Wall 0 and 1 are connected; wall 2 and 3 have no connection to them.
        let segments: [RoomWallSegment2D] = [
            RoomWallSegment2D(wallIndex: 0, start: Vertex2D(x: 0, z: 0),   end: Vertex2D(x: 4, z: 0)),
            RoomWallSegment2D(wallIndex: 1, start: Vertex2D(x: 4, z: 0),   end: Vertex2D(x: 4, z: 3)),
            // disconnected pair
            RoomWallSegment2D(wallIndex: 2, start: Vertex2D(x: 10, z: 10), end: Vertex2D(x: 14, z: 10)),
            RoomWallSegment2D(wallIndex: 3, start: Vertex2D(x: 14, z: 10), end: Vertex2D(x: 14, z: 13)),
        ]
        let result = RoomGeometryBuilder.buildFloorPlan(from: segments)
        XCTAssertNotEqual(result.confidence, .closedPolygon,
                          "Disconnected wall pairs must NOT produce a closed polygon")
        XCTAssertNotEqual(result.vertices.count, 3,
                          "Disconnected walls must NOT produce a 3-vertex triangle")
    }

    // MARK: - Geometry confidence backward-compat decode

    func test_roomCaptureV2_legacyRecord_with4Vertices_decodesAsClosedPolygon() throws {
        // Simulate a legacy JSON record written before geometryConfidence was added.
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "displayName": "Kitchen",
            "polygonVertices": [
                {"x": 0, "z": 0}, {"x": 4, "z": 0},
                {"x": 4, "z": 3}, {"x": 0, "z": 3}
            ],
            "floorLevelY": 0.0,
            "ceilingHeightM": 2.4,
            "capturedAt": "2025-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let room = try decoder.decode(RoomCaptureV2.self, from: Data(json.utf8))
        XCTAssertEqual(room.geometryConfidence, .closedPolygon,
                       "Legacy room with 4 vertices must decode as closedPolygon")
    }

    func test_roomCaptureV2_legacyRecord_with3Vertices_decodesAsEstimated() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000002",
            "displayName": "Triangle Room",
            "polygonVertices": [
                {"x": 0, "z": 0}, {"x": 3, "z": 0}, {"x": 1.5, "z": 2}
            ],
            "floorLevelY": 0.0,
            "ceilingHeightM": 2.4,
            "capturedAt": "2025-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let room = try decoder.decode(RoomCaptureV2.self, from: Data(json.utf8))
        XCTAssertEqual(room.geometryConfidence, .estimated,
                       "Legacy room with 3 vertices must decode as estimated")
    }

    func test_roomCaptureV2_legacyRecord_with0Vertices_decodesAsFailed() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000003",
            "displayName": "Empty Room",
            "polygonVertices": [],
            "floorLevelY": 0.0,
            "ceilingHeightM": 2.4,
            "capturedAt": "2025-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let room = try decoder.decode(RoomCaptureV2.self, from: Data(json.utf8))
        XCTAssertEqual(room.geometryConfidence, .failed,
                       "Legacy room with no vertices must decode as failed")
    }

    // MARK: - Pin room-coordinate fields

    func test_spatialPin_withRoomCoordinates_hasRoomFloorXZ() {
        let pin = SpatialPinV1(
            roomId: UUID(),
            positionX: 1.5,
            positionY: 0.9,
            positionZ: 2.3,
            objectType: .boiler,
            anchorConfidence: .raycastEstimated,
            roomFloorX: 1.5,
            roomFloorZ: 2.3
        )
        XCTAssertEqual(pin.roomFloorX, 1.5, "roomFloorX must equal provided value")
        XCTAssertEqual(pin.roomFloorZ, 2.3, "roomFloorZ must equal provided value")
    }

    func test_spatialPin_screenOnly_hasNilRoomCoordinates() {
        let pin = SpatialPinV1(
            roomId: UUID(),
            positionX: 0, positionY: 0, positionZ: 0,
            objectType: .boiler,
            anchorConfidence: .screenOnly
            // roomFloorX/Z intentionally omitted → nil
        )
        XCTAssertNil(pin.roomFloorX, "screenOnly pin must have nil roomFloorX")
        XCTAssertNil(pin.roomFloorZ, "screenOnly pin must have nil roomFloorZ")
    }

    func test_spatialPin_screenOnly_isCountedButNeedsReview() {
        let pin = SpatialPinV1(
            roomId: UUID(),
            positionX: 0, positionY: 0, positionZ: 0,
            objectType: .boiler,
            anchorConfidence: .screenOnly
        )
        XCTAssertEqual(pin.anchorConfidence, .screenOnly,
                       "screenOnly pin must carry .screenOnly confidence")
        XCTAssertFalse(pin.hasResolvedWorldAnchor,
                       "screenOnly pin must not be considered spatially anchored")
    }

    // MARK: - Pin round-trip Codable

    func test_spatialPin_roundTripCodable_preservesRoomCoordinates() throws {
        let original = SpatialPinV1(
            roomId: UUID(),
            positionX: 2.0, positionY: 1.0, positionZ: 3.5,
            objectType: .boiler,
            anchorConfidence: .worldLocked,
            roomFloorX: 2.0,
            roomFloorZ: 3.5,
            attachedWallId: UUID()
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpatialPinV1.self, from: data)
        XCTAssertEqual(decoded.roomFloorX, original.roomFloorX)
        XCTAssertEqual(decoded.roomFloorZ, original.roomFloorZ)
        XCTAssertEqual(decoded.attachedWallId, original.attachedWallId)
    }

    func test_spatialPin_legacyRecord_withoutRoomCoordinates_decodesWithNils() throws {
        // Simulate a legacy pin written before roomFloorX/Z were added.
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000010",
            "roomId": "00000000-0000-0000-0000-000000000020",
            "positionX": 1.0, "positionY": 0.5, "positionZ": 2.0,
            "objectType": "boiler",
            "anchorConfidence": "world_locked",
            "reviewStatus": "confirmed",
            "provenance": "manual_capture",
            "objectCategory": "heating_system_components",
            "locationContext": "wall"
        }
        """
        let decoded = try JSONDecoder().decode(SpatialPinV1.self, from: Data(json.utf8))
        XCTAssertNil(decoded.roomFloorX, "Legacy pin without roomFloorX must decode as nil")
        XCTAssertNil(decoded.roomFloorZ, "Legacy pin without roomFloorZ must decode as nil")
        XCTAssertNil(decoded.attachedWallId, "Legacy pin without attachedWallId must decode as nil")
    }

    // MARK: - RoomWallSegment2D length and bearing

    func test_wallSegment_horizontalWall_hasCorrectLength() {
        let seg = RoomWallSegment2D(wallIndex: 0,
                                    start: Vertex2D(x: 0, z: 0),
                                    end: Vertex2D(x: 4, z: 0))
        XCTAssertEqual(seg.lengthM, 4.0, accuracy: 0.001, "Horizontal 4 m wall must have lengthM == 4")
    }

    func test_wallSegment_horizontalWall_hasBearing0() {
        let seg = RoomWallSegment2D(wallIndex: 0,
                                    start: Vertex2D(x: 0, z: 0),
                                    end: Vertex2D(x: 4, z: 0))
        XCTAssertEqual(seg.bearingDeg, 0.0, accuracy: 0.001, "Wall pointing in +X must have bearing 0°")
    }

    func test_wallSegment_verticalWall_hasBearing90() {
        let seg = RoomWallSegment2D(wallIndex: 0,
                                    start: Vertex2D(x: 0, z: 0),
                                    end: Vertex2D(x: 0, z: 3))
        XCTAssertEqual(seg.bearingDeg, 90.0, accuracy: 0.001, "Wall pointing in +Z must have bearing 90°")
    }

    // MARK: - GeometryConfidence helpers

    func test_closedPolygon_doesNotRequireReview() {
        XCTAssertFalse(GeometryConfidence.closedPolygon.requiresReview)
    }

    func test_wallSegmentsOnly_requiresReview() {
        XCTAssertTrue(GeometryConfidence.wallSegmentsOnly.requiresReview)
    }

    func test_estimated_requiresReview() {
        XCTAssertTrue(GeometryConfidence.estimated.requiresReview)
    }

    func test_failed_requiresReview() {
        XCTAssertTrue(GeometryConfidence.failed.requiresReview)
    }

    func test_geometryConfidence_roundTripsCodable() throws {
        for confidence in GeometryConfidence.allCases {
            let data = try JSONEncoder().encode(confidence)
            let decoded = try JSONDecoder().decode(GeometryConfidence.self, from: data)
            XCTAssertEqual(decoded, confidence, "\(confidence) must survive JSON round-trip")
        }
    }
}
