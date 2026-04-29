import XCTest
import CoreGraphics
@testable import AtlasScan

// MARK: - ClearanceEngineTests
//
// Unit tests for ClearanceEngine — clearance rule lookup, evaluation,
// geometry helpers, and issue detection.
// No RoomPlan or UIKit types required; runs on any simulator or device.
//
// Geometry notes
// ──────────────
// ClearanceEngine.determineFacing always treats the nearest wall as the "back" and
// faces the object away from it.  Front clearance conflicts therefore only arise
// when the room itself is too small for the required working space, not merely
// because the object is close to one wall.

final class ClearanceEngineTests: XCTestCase {

    // MARK: - Rule lookup

    func test_rule_boiler_hasExpectedClearances() {
        let rule = ClearanceEngine.rule(for: .boiler)
        XCTAssertNotNil(rule)
        XCTAssertGreaterThan(rule!.frontClearanceMetres, 0.5,
            "Boiler should require at least 500 mm front clearance")
        XCTAssertGreaterThan(rule!.footprintWidthMetres, 0.4)
        XCTAssertGreaterThan(rule!.minCeilingHeightMetres, 1.8)
    }

    func test_rule_cylinder_hasExpectedClearances() {
        let rule = ClearanceEngine.rule(for: .cylinder)
        XCTAssertNotNil(rule)
        XCTAssertGreaterThan(rule!.frontClearanceMetres, 0.3)
        XCTAssertGreaterThan(rule!.minCeilingHeightMetres, 1.8)
    }

    func test_rule_manifold_hasExpectedClearances() {
        let rule = ClearanceEngine.rule(for: .manifold)
        XCTAssertNotNil(rule)
        XCTAssertGreaterThan(rule!.frontClearanceMetres, 0.4)
    }

    func test_rule_radiator_hasExpectedClearances() {
        let rule = ClearanceEngine.rule(for: .radiator)
        XCTAssertNotNil(rule)
        XCTAssertGreaterThan(rule!.footprintWidthMetres, 0.3)
    }

    func test_rule_unsupportedCategory_returnsNil() {
        XCTAssertNil(ClearanceEngine.rule(for: .thermostat))
        XCTAssertNil(ClearanceEngine.rule(for: .other))
        XCTAssertNil(ClearanceEngine.rule(for: .gasMeter))
    }

    func test_allSupportedCategories_haveRules() {
        for cat in ClearanceEngine.supportedCategories {
            XCTAssertNotNil(ClearanceEngine.rule(for: cat),
                "\(cat.rawValue) is in supportedCategories but has no rule")
        }
    }

    // MARK: - determineFacing

    func test_determineFacing_nearTop_facesDown() {
        // distTop = 0.05 × 4 = 0.2 m, distBottom = 0.95 × 4 = 3.8 m → facing down
        let f = ClearanceEngine.determineFacing(
            pos: NormalizedPoint2D(x: 0.5, y: 0.05), roomWidth: 4, roomHeight: 4
        )
        XCTAssertEqual(f, .down)
    }

    func test_determineFacing_nearBottom_facesUp() {
        let f = ClearanceEngine.determineFacing(
            pos: NormalizedPoint2D(x: 0.5, y: 0.95), roomWidth: 4, roomHeight: 4
        )
        XCTAssertEqual(f, .up)
    }

    func test_determineFacing_nearLeft_facesRight() {
        let f = ClearanceEngine.determineFacing(
            pos: NormalizedPoint2D(x: 0.05, y: 0.5), roomWidth: 4, roomHeight: 4
        )
        XCTAssertEqual(f, .right)
    }

    func test_determineFacing_nearRight_facesLeft() {
        let f = ClearanceEngine.determineFacing(
            pos: NormalizedPoint2D(x: 0.95, y: 0.5), roomWidth: 4, roomHeight: 4
        )
        XCTAssertEqual(f, .left)
    }

    // MARK: - overlayRects

    func test_overlayRects_clearanceAlwaysLargerThanFootprint() {
        let rule = ClearanceEngine.rule(for: .boiler)!
        let pos  = NormalizedPoint2D(x: 0.5, y: 0.5)
        let (fp, _, cl) = ClearanceEngine.overlayRects(
            pos: pos, rule: rule, facing: .down,
            roomWidth: 5.0, roomHeight: 5.0
        )
        XCTAssertLessThanOrEqual(cl.minX, fp.minX)
        XCTAssertGreaterThanOrEqual(cl.maxX, fp.maxX)
        XCTAssertLessThanOrEqual(cl.minY, fp.minY)
        XCTAssertGreaterThanOrEqual(cl.maxY, fp.maxY)
    }

    // MARK: - ClearanceStatus display properties

    func test_clearanceStatus_displayMessages_nonEmpty() {
        for status: ClearanceStatus in [.clear, .warning, .conflict] {
            XCTAssertFalse(status.displayMessage.isEmpty)
            XCTAssertFalse(status.symbolName.isEmpty)
            XCTAssertFalse(status.shortLabel.isEmpty)
        }
    }

    func test_clearanceStatus_shortLabels_matchExpected() {
        XCTAssertEqual(ClearanceStatus.clear.shortLabel,    "Pass")
        XCTAssertEqual(ClearanceStatus.warning.shortLabel,  "Tight fit")
        XCTAssertEqual(ClearanceStatus.conflict.shortLabel, "Blocked")
    }

    func test_clearanceStatus_displayMessages_outcomeFirst() {
        // Verify that each message starts with the outcome keyword, so the
        // most important information is readable at a glance.
        XCTAssertTrue(ClearanceStatus.clear.displayMessage.hasPrefix("Pass"),
            "Pass status message should start with 'Pass'")
        XCTAssertTrue(ClearanceStatus.warning.displayMessage.hasPrefix("Tight fit"),
            "Warning status message should start with 'Tight fit'")
        XCTAssertTrue(ClearanceStatus.conflict.displayMessage.hasPrefix("Blocked"),
            "Conflict status message should start with 'Blocked'")
    }

    func test_clearanceIssue_defaultInit_sideLabelIsNil() {
        // Verify the backward-compatible default: omitting sideLabel yields nil.
        let issue = ClearanceIssue(kind: .ceilingHeightLimiting, severity: .warning, message: "test")
        XCTAssertNil(issue.sideLabel, "Default sideLabel must be nil for backward compatibility")
    }

    // MARK: - ClearanceIssue source

    func test_clearanceIssue_defaultInit_sourceIsNil() {
        let issue = ClearanceIssue(kind: .enclosedInstallation, severity: .warning, message: "test")
        XCTAssertNil(issue.source, "Default source must be nil for backward compatibility")
    }

    func test_sourceDescription_wall() {
        let issue = ClearanceIssue(kind: .frontAccessRestricted, severity: .conflict,
                                   message: "test", source: .wall)
        XCTAssertEqual(issue.sourceDescription(), "Blocked by wall")
    }

    func test_sourceDescription_ceiling() {
        let issue = ClearanceIssue(kind: .ceilingHeightLimiting, severity: .conflict,
                                   message: "test", source: .ceiling)
        XCTAssertEqual(issue.sourceDescription(), "Blocked by ceiling")
    }

    func test_sourceDescription_unknown() {
        let issue = ClearanceIssue(kind: .enclosedInstallation, severity: .warning,
                                   message: "test", source: .unknown)
        XCTAssertEqual(issue.sourceDescription(), "Source not determined")
    }

    func test_sourceDescription_object_noName_usesAdjacentFallback() {
        let id = UUID()
        let issue = ClearanceIssue(kind: .objectIntrusion, severity: .conflict,
                                   message: "test", source: .object(id))
        let desc = issue.sourceDescription()
        XCTAssertNotNil(desc)
        XCTAssertEqual(desc, "Blocked by adjacent object",
            "Object source without a name should fall back to 'Blocked by adjacent object'")
    }

    func test_sourceDescription_object_withName_showsName() {
        let id = UUID()
        let issue = ClearanceIssue(kind: .objectIntrusion, severity: .conflict,
                                   message: "test", source: .object(id))
        let desc = issue.sourceDescription(objectName: "Hot Water Cylinder")
        XCTAssertEqual(desc, "Blocked by Hot Water Cylinder")
    }

    func test_sourceDescription_nilSource() {
        let issue = ClearanceIssue(kind: .enclosedInstallation, severity: .warning,
                                   message: "test")
        XCTAssertNil(issue.sourceDescription(),
            "Nil source should yield nil sourceDescription")
    }

}
