import XCTest
@testable import AtlasScan

// MARK: - LiDARClearanceMeasurementTests
//
// Unit tests for the pure data model layer of the LiDAR clearance feature.
// No ARKit or device hardware required; runs on any simulator.

final class LiDARClearanceMeasurementTests: XCTestCase {

    // MARK: - LiDARAxisMeasurement.status

    func test_status_belowRequired_isConflict() {
        let m = LiDARAxisMeasurement(axis: .front, measuredMetres: 0.30, requiredMetres: 0.60)
        XCTAssertEqual(m.status, .conflict)
    }

    func test_status_aboveRequiredBy20Percent_isClear() {
        let m = LiDARAxisMeasurement(axis: .front, measuredMetres: 1.00, requiredMetres: 0.60)
        XCTAssertEqual(m.status, .clear)
    }

    func test_status_tightWithin20Percent_isWarning() {
        // 0.65 < 0.60 × 1.20 = 0.72 → warning
        let m = LiDARAxisMeasurement(axis: .front, measuredMetres: 0.65, requiredMetres: 0.60)
        XCTAssertEqual(m.status, .warning)
    }

    func test_status_exactlyAtRequired_isWarning() {
        // equal to required → not a conflict, but < required × 1.20 → warning
        let m = LiDARAxisMeasurement(axis: .front, measuredMetres: 0.60, requiredMetres: 0.60)
        XCTAssertEqual(m.status, .warning)
    }

    func test_status_nilMeasured_isClear() {
        // No surface detected → nothing blocking clearance
        let m = LiDARAxisMeasurement(axis: .ceiling, measuredMetres: nil, requiredMetres: 2.00)
        XCTAssertEqual(m.status, .clear)
    }

    func test_status_sideAxis_conflict() {
        let m = LiDARAxisMeasurement(axis: .left, measuredMetres: 0.10, requiredMetres: 0.45)
        XCTAssertEqual(m.status, .conflict)
    }

    // MARK: - LiDARAxisMeasurement display helpers

    func test_displayMeasured_formatsToTwoDecimalPlaces() {
        let m = LiDARAxisMeasurement(axis: .front, measuredMetres: 1.234, requiredMetres: 0.60)
        XCTAssertEqual(m.displayMeasured, "1.23 m")
    }

    func test_displayMeasured_nilReturnsNoObstruction() {
        let m = LiDARAxisMeasurement(axis: .ceiling, measuredMetres: nil, requiredMetres: 2.00)
        XCTAssertEqual(m.displayMeasured, "No obstruction")
    }

    func test_displayRequired_includesMinPrefix() {
        let m = LiDARAxisMeasurement(axis: .rear, measuredMetres: 0.50, requiredMetres: 0.30)
        XCTAssertTrue(m.displayRequired.hasPrefix("min "), "displayRequired should start with 'min '")
        XCTAssertTrue(m.displayRequired.contains("0.30"), "displayRequired should contain the required value")
    }

    // MARK: - LiDARClearanceMeasurement.overallStatus

    func test_overall_anyConflict_isConflict() {
        let axes = [
            LiDARAxisMeasurement(axis: .front, measuredMetres: 0.20, requiredMetres: 0.60), // conflict
            LiDARAxisMeasurement(axis: .left,  measuredMetres: 1.50, requiredMetres: 0.45), // clear
        ]
        let m = LiDARClearanceMeasurement(category: .boiler, profileName: nil, axes: axes, capturedAt: Date())
        XCTAssertEqual(m.overallStatus, .conflict)
    }

    func test_overall_noConflictAnyWarning_isWarning() {
        let axes = [
            LiDARAxisMeasurement(axis: .front, measuredMetres: 0.65, requiredMetres: 0.60), // warning
            LiDARAxisMeasurement(axis: .left,  measuredMetres: 1.50, requiredMetres: 0.45), // clear
        ]
        let m = LiDARClearanceMeasurement(category: .boiler, profileName: nil, axes: axes, capturedAt: Date())
        XCTAssertEqual(m.overallStatus, .warning)
    }

    func test_overall_allClear_isClear() {
        let axes = [
            LiDARAxisMeasurement(axis: .front,   measuredMetres: 1.00, requiredMetres: 0.60),
            LiDARAxisMeasurement(axis: .rear,    measuredMetres: 0.50, requiredMetres: 0.30),
            LiDARAxisMeasurement(axis: .left,    measuredMetres: 0.80, requiredMetres: 0.45),
            LiDARAxisMeasurement(axis: .right,   measuredMetres: 0.80, requiredMetres: 0.45),
            LiDARAxisMeasurement(axis: .ceiling, measuredMetres: 2.50, requiredMetres: 2.00),
        ]
        let m = LiDARClearanceMeasurement(category: .boiler, profileName: nil, axes: axes, capturedAt: Date())
        XCTAssertEqual(m.overallStatus, .clear)
    }

    func test_overall_conflictTakesPriorityOverWarning() {
        let axes = [
            LiDARAxisMeasurement(axis: .front, measuredMetres: 0.65, requiredMetres: 0.60), // warning
            LiDARAxisMeasurement(axis: .left,  measuredMetres: 0.10, requiredMetres: 0.45), // conflict
        ]
        let m = LiDARClearanceMeasurement(category: .boiler, profileName: nil, axes: axes, capturedAt: Date())
        XCTAssertEqual(m.overallStatus, .conflict, "Conflict takes precedence over warning")
    }

    func test_overall_emptyAxes_isClear() {
        let m = LiDARClearanceMeasurement(category: .boiler, profileName: nil, axes: [], capturedAt: Date())
        XCTAssertEqual(m.overallStatus, .clear)
    }

    // MARK: - LiDARMeasurementAxis display properties

    func test_allAxes_haveNonEmptyDisplayName() {
        for axis in LiDARMeasurementAxis.allCases {
            XCTAssertFalse(axis.displayName.isEmpty, "\(axis.rawValue) displayName is empty")
        }
    }

    func test_allAxes_haveNonEmptySymbolName() {
        for axis in LiDARMeasurementAxis.allCases {
            XCTAssertFalse(axis.symbolName.isEmpty, "\(axis.rawValue) symbolName is empty")
        }
    }
}
