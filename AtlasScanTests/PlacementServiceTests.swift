import XCTest
import CoreGraphics
@testable import AtlasScan

// MARK: - PlacementServiceTests
//
// Unit tests for PlacementService geometry helpers.
// These tests use only CGPoint / NormalizedPoint2D / ScannedWall — no RoomPlan types,
// so they run on any simulator or device without the full RoomPlan stack.

final class PlacementServiceTests: XCTestCase {

    // MARK: - normalizedWallPolygon

    func test_normalizedWallPolygon_rectangularRoom_producesUnitSquare() {
        // 4-wall room: E(90°), S(180°), W(270°), N(0°) — equal-length walls
        let walls = [
            ScannedWall(index: 0, lengthMetres: 5.0, bearingDegrees: 90.0),
            ScannedWall(index: 1, lengthMetres: 4.0, bearingDegrees: 180.0),
            ScannedWall(index: 2, lengthMetres: 5.0, bearingDegrees: 270.0),
            ScannedWall(index: 3, lengthMetres: 4.0, bearingDegrees: 0.0),
        ]
        let poly = PlacementService.normalizedWallPolygon(from: walls)
        XCTAssertEqual(poly.count, 4)
        // All x values must be in 0...1
        for pt in poly {
            XCTAssertGreaterThanOrEqual(pt.x, -0.001)
            XCTAssertLessThanOrEqual(pt.x, 1.001)
            XCTAssertGreaterThanOrEqual(pt.y, -0.001)
            XCTAssertLessThanOrEqual(pt.y, 1.001)
        }
        // The bounding box should span the full 0–1 range in both axes
        let xs = poly.map(\.x)
        let ys = poly.map(\.y)
        XCTAssertEqual(xs.min() ?? 1, 0.0, accuracy: 0.001)
        XCTAssertEqual(xs.max() ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(ys.min() ?? 1, 0.0, accuracy: 0.001)
        XCTAssertEqual(ys.max() ?? 0, 1.0, accuracy: 0.001)
    }

    func test_normalizedWallPolygon_noWalls_returnsUnitSquare() {
        let poly = PlacementService.normalizedWallPolygon(from: [])
        XCTAssertEqual(poly.count, 4)
    }

    // MARK: - layoutPolygon

    func test_layoutPolygon_noBearingData_returnsUnitSquare() {
        let room = ScannedRoom(
            jobID: UUID(),
            name: "Test",
            walls: [
                ScannedWall(index: 0, lengthMetres: 3.0),
                ScannedWall(index: 1, lengthMetres: 3.0),
                ScannedWall(index: 2, lengthMetres: 3.0),
            ]
        )
        let poly = PlacementService.layoutPolygon(for: room)
        XCTAssertEqual(poly.count, 4, "Fallback should return the 4-point unit square")
    }

    func test_layoutPolygon_withBearingData_usesWallGeometry() {
        let walls = [
            ScannedWall(index: 0, lengthMetres: 4.0, bearingDegrees: 90.0),
            ScannedWall(index: 1, lengthMetres: 3.0, bearingDegrees: 180.0),
            ScannedWall(index: 2, lengthMetres: 4.0, bearingDegrees: 270.0),
            ScannedWall(index: 3, lengthMetres: 3.0, bearingDegrees: 0.0),
        ]
        let room = ScannedRoom(jobID: UUID(), name: "Room", walls: walls)
        let poly = PlacementService.layoutPolygon(for: room)
        XCTAssertEqual(poly.count, 4)
    }

    // MARK: - nearestWallIndex(to:in:)

    func test_nearestWallIndex_topEdge_returnsWall0() {
        // Point near top edge (y ≈ 0.05) should snap to wall 0 (top edge of unit square)
        let poly = unitSquarePolygon
        let idx = PlacementService.nearestWallIndex(to: CGPoint(x: 0.5, y: 0.05), in: poly)
        XCTAssertEqual(idx, 0)
    }

    func test_nearestWallIndex_rightEdge_returnsWall1() {
        // Point near right edge (x ≈ 0.95) should snap to wall 1 (right edge)
        let poly = unitSquarePolygon
        let idx = PlacementService.nearestWallIndex(to: CGPoint(x: 0.95, y: 0.5), in: poly)
        XCTAssertEqual(idx, 1)
    }

    func test_nearestWallIndex_bottomEdge_returnsWall2() {
        let poly = unitSquarePolygon
        let idx = PlacementService.nearestWallIndex(to: CGPoint(x: 0.5, y: 0.95), in: poly)
        XCTAssertEqual(idx, 2)
    }

    func test_nearestWallIndex_leftEdge_returnsWall3() {
        let poly = unitSquarePolygon
        let idx = PlacementService.nearestWallIndex(to: CGPoint(x: 0.05, y: 0.5), in: poly)
        XCTAssertEqual(idx, 3)
    }

    func test_nearestWallIndex_emptyPolygon_returnsZero() {
        let idx = PlacementService.nearestWallIndex(to: CGPoint(x: 0.5, y: 0.5), in: [])
        XCTAssertEqual(idx, 0)
    }

    // MARK: - nearestWall(to:in:)

    func test_nearestWall_returnsCorrectWallObject() {
        let walls = [
            ScannedWall(index: 0, lengthMetres: 5.0, bearingDegrees: 90.0),
            ScannedWall(index: 1, lengthMetres: 4.0, bearingDegrees: 180.0),
            ScannedWall(index: 2, lengthMetres: 5.0, bearingDegrees: 270.0),
            ScannedWall(index: 3, lengthMetres: 4.0, bearingDegrees: 0.0),
        ]
        let room = ScannedRoom(jobID: UUID(), name: "Room", walls: walls)
        let result = PlacementService.nearestWall(to: NormalizedPoint2D(x: 0.5, y: 0.02), in: room)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.index, 0, "Point near top edge should attach to wall at index 0")
    }

    func test_nearestWall_noWalls_returnsNil() {
        let room = ScannedRoom(jobID: UUID(), name: "Empty", walls: [])
        let result = PlacementService.nearestWall(to: NormalizedPoint2D(x: 0.5, y: 0.5), in: room)
        XCTAssertNil(result)
    }

    // MARK: - snapToWall

    func test_snapToWall_topWall_snapsInsideRoom() {
        // Top wall segment: (0,0)→(1,0). Tapping above it should produce a point with y slightly > 0.
        let poly = unitSquarePolygon
        let result = PlacementService.snapToWall(point: CGPoint(x: 0.5, y: 0.0), wallIndex: 0, in: poly)
        XCTAssertGreaterThan(result.y, 0.0, "Snapped position should be inward (y > 0)")
        XCTAssertLessThan(result.y, 0.1, "Snapped position should be close to wall")
        XCTAssertEqual(result.x, 0.5, accuracy: 0.05)
    }

    func test_snapToWall_rightWall_snapsInsideRoom() {
        let poly = unitSquarePolygon
        let result = PlacementService.snapToWall(point: CGPoint(x: 1.0, y: 0.5), wallIndex: 1, in: poly)
        XCTAssertLessThan(result.x, 1.0, "Snapped position should be inward (x < 1)")
    }

    func test_snapToWall_positionClampedAwayFromCorners() {
        let poly = unitSquarePolygon
        // Tap at corner should be clamped to 5% from the ends
        let result = PlacementService.snapToWall(point: CGPoint(x: 0.0, y: 0.0), wallIndex: 0, in: poly)
        // x should be clamped to at least 5% of wall length
        XCTAssertGreaterThanOrEqual(result.x, 0.04)
    }

    // MARK: - place(object:at:in:)

    func test_place_wallMountedObject_snapsToNearestWall() {
        let walls = unitSquareWalls
        var room = ScannedRoom(jobID: UUID(), name: "Room", walls: walls)
        var obj = TaggedObject(roomID: room.id, category: .radiator)  // .wallMounted by default
        room.addTaggedObject(obj)

        // Tap near top edge
        let tapPos = NormalizedPoint2D(x: 0.4, y: 0.02)
        PlacementService.place(object: &obj, at: tapPos, in: room)

        XCTAssertNotNil(obj.normalizedPosition)
        XCTAssertEqual(obj.wallIndex, 0, "Radiator near top edge should attach to wall 0")
        // Position should be snapped inward
        XCTAssertGreaterThan(obj.normalizedPosition!.y, 0.0)
    }

    func test_place_floorObject_usesDirectPosition() {
        let walls = unitSquareWalls
        let room = ScannedRoom(jobID: UUID(), name: "Room", walls: walls)
        var obj = TaggedObject(roomID: room.id, category: .boiler)  // .floorPlaced by default
        XCTAssertEqual(obj.placementMode, .floorPlaced)

        let tapPos = NormalizedPoint2D(x: 0.3, y: 0.4)
        PlacementService.place(object: &obj, at: tapPos, in: room)

        XCTAssertEqual(obj.normalizedPosition?.x ?? -1, 0.3, accuracy: 0.001)
        XCTAssertEqual(obj.normalizedPosition?.y ?? -1, 0.4, accuracy: 0.001)
        XCTAssertNil(obj.wallIndex, "Floor-placed object should not have a wall index")
    }

    func test_place_wallMountedObject_setsAttachedWallID() {
        let walls = unitSquareWalls
        let room = ScannedRoom(jobID: UUID(), name: "Room", walls: walls)
        var obj = TaggedObject(roomID: room.id, category: .thermostat)  // .wallMounted

        PlacementService.place(object: &obj, at: NormalizedPoint2D(x: 0.5, y: 0.03), in: room)

        XCTAssertNotNil(obj.attachedWallID, "Wall-mounted object should record the wall UUID")
        XCTAssertEqual(obj.attachedWallID, walls[0].id)
    }

    // MARK: - Default placement mode per category

    func test_defaultPlacementMode_wallMountedCategories() {
        let wallMounted: [ServiceObjectCategory] = [
            .radiator, .towelRail, .thermostat, .programmer, .thermostatReceiver,
            .gasMeter, .electricMeter, .consumerUnit
        ]
        for cat in wallMounted {
            XCTAssertEqual(cat.defaultPlacementMode, .wallMounted,
                           "\(cat.rawValue) should be wall-mounted")
        }
    }

    func test_defaultPlacementMode_floorPlacedCategories() {
        let floorPlaced: [ServiceObjectCategory] = [
            .boiler, .heatPump, .cylinder, .manifold, .pump, .plantSpace
        ]
        for cat in floorPlaced {
            XCTAssertEqual(cat.defaultPlacementMode, .floorPlaced,
                           "\(cat.rawValue) should be floor-placed")
        }
    }

    func test_defaultPlacementMode_other_isUnplaced() {
        XCTAssertEqual(ServiceObjectCategory.other.defaultPlacementMode, .unplaced)
    }

    // MARK: - distanceFromPoint

    func test_distanceFromPoint_onSegment_isZero() {
        let dist = PlacementService.distanceFromPoint(
            CGPoint(x: 0.5, y: 0.0),
            toSegment: CGPoint(x: 0.0, y: 0.0),
            end: CGPoint(x: 1.0, y: 0.0)
        )
        XCTAssertEqual(dist, 0.0, accuracy: 1e-9)
    }

    func test_distanceFromPoint_perpendicularDistance() {
        // Point (0.5, 0.3) — segment (0,0)→(1,0) — distance should be 0.3
        let dist = PlacementService.distanceFromPoint(
            CGPoint(x: 0.5, y: 0.3),
            toSegment: CGPoint(x: 0.0, y: 0.0),
            end: CGPoint(x: 1.0, y: 0.0)
        )
        XCTAssertEqual(dist, 0.3, accuracy: 1e-9)
    }

    func test_distanceFromPoint_beyondEndpoint_usesEndpoint() {
        // Point (2, 0) — segment (0,0)→(1,0) — nearest endpoint is (1,0) → distance = 1
        let dist = PlacementService.distanceFromPoint(
            CGPoint(x: 2.0, y: 0.0),
            toSegment: CGPoint(x: 0.0, y: 0.0),
            end: CGPoint(x: 1.0, y: 0.0)
        )
        XCTAssertEqual(dist, 1.0, accuracy: 1e-9)
    }

    // MARK: - polygonCentroid

    func test_polygonCentroid_unitSquare_isCenter() {
        let centroid = PlacementService.polygonCentroid(unitSquarePolygon)
        XCTAssertEqual(centroid.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(centroid.y, 0.5, accuracy: 0.001)
    }

    // MARK: - Placement persistence (integration-level)

    func test_placeAndUpdateRoom_persistsPosition() {
        var room = ScannedRoom(jobID: UUID(), name: "Test Room", walls: unitSquareWalls)
        var obj = TaggedObject(roomID: room.id, category: .radiator)
        room.addTaggedObject(obj)

        PlacementService.place(object: &obj, at: NormalizedPoint2D(x: 0.3, y: 0.02), in: room)
        room.updateTaggedObject(obj)

        XCTAssertNotNil(room.taggedObjects.first?.normalizedPosition)
    }

    // MARK: - Private helpers

    private var unitSquarePolygon: [CGPoint] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
    }

    private var unitSquareWalls: [ScannedWall] {
        [
            ScannedWall(index: 0, lengthMetres: 5.0, bearingDegrees: 90.0),
            ScannedWall(index: 1, lengthMetres: 4.0, bearingDegrees: 180.0),
            ScannedWall(index: 2, lengthMetres: 5.0, bearingDegrees: 270.0),
            ScannedWall(index: 3, lengthMetres: 4.0, bearingDegrees: 0.0),
        ]
    }
}
