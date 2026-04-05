import XCTest
import simd
@testable import AtlasScan

// MARK: - RoomPlanMapperTests
//
// Unit tests for the geometry helper functions in RoomPlanMapper.
// These helpers use only simd / primitive types (no RoomPlan framework objects), so
// they compile and run on any simulator or device without the full RoomPlan stack.

final class RoomPlanMapperTests: XCTestCase {

    // MARK: - wallBearing(from:)

    func test_wallBearing_northRunningWall() {
        // Column 0 aligned with +Z → wall runs north → bearing 0°
        var t = matrix_identity_float4x4
        t.columns.0 = SIMD4<Float>(0, 0, 1, 0)
        XCTAssertEqual(RoomPlanMapper.wallBearing(from: t), 0.0, accuracy: 0.001)
    }

    func test_wallBearing_eastRunningWall() {
        // Identity matrix: column 0 = (1, 0, 0, 0) → wall runs east → bearing 90°
        let t = matrix_identity_float4x4
        XCTAssertEqual(RoomPlanMapper.wallBearing(from: t), 90.0, accuracy: 0.001)
    }

    func test_wallBearing_southRunningWall() {
        // Column 0 aligned with -Z → wall runs south → bearing 180°
        var t = matrix_identity_float4x4
        t.columns.0 = SIMD4<Float>(0, 0, -1, 0)
        XCTAssertEqual(RoomPlanMapper.wallBearing(from: t), 180.0, accuracy: 0.001)
    }

    func test_wallBearing_westRunningWall() {
        // Column 0 aligned with -X → wall runs west → bearing 270°
        var t = matrix_identity_float4x4
        t.columns.0 = SIMD4<Float>(-1, 0, 0, 0)
        XCTAssertEqual(RoomPlanMapper.wallBearing(from: t), 270.0, accuracy: 0.001)
    }

    func test_wallBearing_alwaysNonNegative() {
        // Every cardinal and ordinal direction should produce a bearing in [0, 360)
        for angleDeg: Float in stride(from: 0, to: 360, by: 45) {
            let rad = angleDeg * .pi / 180
            var t = matrix_identity_float4x4
            t.columns.0 = SIMD4<Float>(sin(rad), 0, cos(rad), 0)
            let bearing = RoomPlanMapper.wallBearing(from: t)
            XCTAssertGreaterThanOrEqual(bearing, 0,
                "Bearing should be ≥ 0 for input angle \(angleDeg)°")
            XCTAssertLessThan(bearing, 360,
                "Bearing should be < 360 for input angle \(angleDeg)°")
        }
    }

    func test_wallBearing_diagonalNorthEast() {
        // 45° between north and east → bearing ~45°
        let rad = Float(45) * .pi / 180
        var t = matrix_identity_float4x4
        t.columns.0 = SIMD4<Float>(sin(rad), 0, cos(rad), 0)
        XCTAssertEqual(RoomPlanMapper.wallBearing(from: t), 45.0, accuracy: 0.01)
    }

    // MARK: - nearestWallIndex(surfaceX:surfaceZ:wallCentres:)

    func test_nearestWallIndex_picksClosestWall() {
        // Surface at (1, 0) — wall A at (0, 0), wall B at (5, 0) → nearest is A (index 0)
        let index = RoomPlanMapper.nearestWallIndex(
            surfaceX: 1.0, surfaceZ: 0.0,
            wallCentres: [(x: 0.0, z: 0.0), (x: 5.0, z: 0.0)]
        )
        XCTAssertEqual(index, 0)
    }

    func test_nearestWallIndex_picksSecondWallWhenCloser() {
        // Surface at (4, 0) — wall A at (0, 0), wall B at (5, 0) → nearest is B (index 1)
        let index = RoomPlanMapper.nearestWallIndex(
            surfaceX: 4.0, surfaceZ: 0.0,
            wallCentres: [(x: 0.0, z: 0.0), (x: 5.0, z: 0.0)]
        )
        XCTAssertEqual(index, 1)
    }

    func test_nearestWallIndex_singleWall_returnsZero() {
        let index = RoomPlanMapper.nearestWallIndex(
            surfaceX: 3.0, surfaceZ: 2.0,
            wallCentres: [(x: 0.0, z: 0.0)]
        )
        XCTAssertEqual(index, 0)
    }

    func test_nearestWallIndex_emptyWalls_returnsZero() {
        let index = RoomPlanMapper.nearestWallIndex(
            surfaceX: 3.0, surfaceZ: 2.0,
            wallCentres: []
        )
        XCTAssertEqual(index, 0)
    }

    func test_nearestWallIndex_diagonalDistance() {
        // Surface at (2, 2) — wall A at (0, 0) distance √8 ≈ 2.83, wall B at (3, 3) distance √2 ≈ 1.41
        let index = RoomPlanMapper.nearestWallIndex(
            surfaceX: 2.0, surfaceZ: 2.0,
            wallCentres: [(x: 0.0, z: 0.0), (x: 3.0, z: 3.0)]
        )
        XCTAssertEqual(index, 1)
    }

    func test_nearestWallIndex_tieBreak_favorsEarlierIndex() {
        // Surface equidistant from both walls → should return the first one (index 0)
        let index = RoomPlanMapper.nearestWallIndex(
            surfaceX: 2.5, surfaceZ: 0.0,
            wallCentres: [(x: 0.0, z: 0.0), (x: 5.0, z: 0.0)]
        )
        XCTAssertEqual(index, 0)
    }
}
