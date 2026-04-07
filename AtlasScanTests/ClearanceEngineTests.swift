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

    // MARK: - evaluate — early returns

    func test_evaluate_unsupportedCategory_returnsNil() {
        let room = roomWithDimensions(width: 4, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .thermostat)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        XCTAssertNil(ClearanceEngine.evaluate(object: obj, in: room))
    }

    func test_evaluate_noPosition_returnsNil() {
        let room = roomWithDimensions(width: 4, height: 4)
        let obj = TaggedObject(roomID: room.id, category: .boiler)
        XCTAssertNil(obj.normalizedPosition, "Sanity: default boiler has no position")
        XCTAssertNil(ClearanceEngine.evaluate(object: obj, in: room))
    }

    // MARK: - evaluate — status outcomes

    func test_evaluate_boilerCentredInLargeRoom_returnsClear() {
        // 6 m × 5 m room; boiler centred — ample clearance on all sides
        let room = roomWithDimensions(width: 6, height: 5)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .clear)
    }

    func test_evaluate_boilerFrontClearanceInsufficient_returnsConflict() {
        // 1.5 m × 1.5 m room; boiler centred.
        // determineFacing: all edges equidistant (0.75 m), picks .down.
        // requiredFront = footprintDepthMetres/2 + frontClearanceMetres = 0.50/2 + 0.60 = 0.85 m
        // frontDist (distBottom) = 0.5 × 1.5 = 0.75 m < 0.85 m → conflict.
        let room = roomWithDimensions(width: 1.5, height: 1.5)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .conflict,
            "Boiler in a room too small for front clearance should be conflict")
    }

    func test_evaluate_boilerSideClearanceInsufficient_returnsConflict() {
        // 0.8 m wide × 5 m tall room; boiler near top wall (y = 0.05).
        // determineFacing: distTop = 0.05 × 5 = 0.25 m is nearest → facing = .down.
        // sideDist = 0.5 × 0.8 = 0.40 m < requiredSide (0.30 + 0.15 = 0.45 m) → conflict.
        let room = roomWithDimensions(width: 0.8, height: 5)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.05)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        let hasSideIssue = result?.issues.contains { $0.kind == .tooCloseToSideWall } ?? false
        XCTAssertTrue(hasSideIssue, "Narrow room should flag side wall clearance")
        XCTAssertEqual(result?.status, .conflict)
    }

    func test_evaluate_boilerJustAtMinimumFront_returnsWarning() {
        // 1.7 m × 1.7 m room; boiler centred.
        // frontDist (distBottom) = 0.5 × 1.7 = 0.85 m.
        // requiredFront = 0.85 m exactly → not < required, but < required × 1.2 = 1.02 m → warning.
        let room = roomWithDimensions(width: 1.7, height: 1.7)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .warning, "Boiler at minimum clearance should warn")
    }

    func test_evaluate_radiatorCentredOnTopWall_notConflict() {
        // 5 m × 4 m room; radiator near top (wall-mounted position).
        // Radiator only needs 0.05 m front clearance; centre of room is well clear.
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .radiator)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.05)
        obj.placementMode = .wallMounted
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result?.status, .conflict,
            "Radiator on top wall of a normal room should not produce a conflict")
    }

    // MARK: - evaluate — ceiling height

    func test_evaluate_lowCeiling_returnsConflict() {
        var room = roomWithDimensions(width: 5, height: 4)
        room.ceilingHeightMetres = 1.7   // boiler requires 2.0 m
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        let hasCeilingIssue = result?.issues.contains { $0.kind == .ceilingHeightLimiting } ?? false
        XCTAssertTrue(hasCeilingIssue, "Low ceiling should produce a ceiling issue")
        XCTAssertEqual(result?.status, .conflict)
    }

    func test_evaluate_noCeilingData_noCeilingIssue() {
        // ceilingHeightMetres is nil — engine should not manufacture a ceiling issue
        let room = roomWithDimensions(width: 5, height: 4)  // no ceilingHeightMetres set
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        let hasCeilingIssue = result?.issues.contains { $0.kind == .ceilingHeightLimiting } ?? false
        XCTAssertFalse(hasCeilingIssue, "Missing ceiling data should not produce a ceiling issue")
    }

    // MARK: - evaluate — enclosed installation

    func test_evaluate_enclosedBoiler_flagsEnclosed() {
        let room = roomWithDimensions(width: 6, height: 6)
        var obj = TaggedObject(
            roomID: room.id, category: .boiler,
            quickFieldValues: ["enclosed": "true"]
        )
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        let hasEnclosedIssue = result?.issues.contains { $0.kind == .enclosedInstallation } ?? false
        XCTAssertTrue(hasEnclosedIssue, "Enclosed boiler should flag enclosed installation concern")
    }

    func test_evaluate_cupboardCylinder_flagsEnclosed() {
        let room = roomWithDimensions(width: 6, height: 6)
        var obj = TaggedObject(
            roomID: room.id, category: .cylinder,
            quickFieldValues: ["cupboard": "true"]
        )
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        let hasEnclosedIssue = result?.issues.contains { $0.kind == .enclosedInstallation } ?? false
        XCTAssertTrue(hasEnclosedIssue, "'cupboard: true' should flag enclosed concern")
    }

    func test_evaluate_notEnclosed_noEnclosedIssue() {
        let room = roomWithDimensions(width: 6, height: 6)
        var obj = TaggedObject(
            roomID: room.id, category: .boiler,
            quickFieldValues: ["enclosed": "false"]
        )
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        let hasEnclosedIssue = result?.issues.contains { $0.kind == .enclosedInstallation } ?? false
        XCTAssertFalse(hasEnclosedIssue)
    }

    // MARK: - evaluate — opening proximity

    func test_evaluate_doorInClearanceZone_flagsOpening() {
        // 5 m × 5 m room. Boiler at (0.5, 0.04) — very close to top wall.
        // determineFacing: distTop = 0.04 × 5 = 0.2 m (nearest) → facing = .down.
        // clearanceRect extends upward from pos.y: top ≈ 0.04 – 0.05 – 0.01 = −0.02.
        // Door on wall index 0 (top edge [0,0]→[1,0]); midpoint = (0.5, 0.0).
        // (0.5, 0.0) is inside the clearanceRect whose minY ≈ −0.02 → opening flagged.
        var room = roomWithDimensions(width: 5, height: 5)
        room.ceilingHeightMetres = 2.5
        room.openings = [ScannedOpening(kind: .door, wallIndex: 0)]
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.04)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        let hasOpeningIssue = result?.issues.contains { $0.kind == .openingWithinAccessZone } ?? false
        XCTAssertTrue(hasOpeningIssue, "Door within clearance zone should produce an opening issue")
    }

    // MARK: - evaluate — confidence note

    func test_evaluate_noScanGeometry_addsConfidenceNote() {
        let room = ScannedRoom(jobID: UUID(), name: "Manual Room", geometryCaptured: false)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result?.confidenceNote,
            "Non-scanned room should always produce a confidence note")
        XCTAssertTrue(result?.confidenceNote?.contains("scanner") ?? false,
            "Confidence note should mention scanner geometry")
    }

    func test_evaluate_scannedGeometryHighConfidence_noNote() {
        var room = roomWithDimensions(width: 5, height: 4)
        room.geometryCaptured = true
        var obj = TaggedObject(roomID: room.id, category: .boiler, confidence: .high)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNil(result?.confidenceNote,
            "Scanned room with high confidence object should have no note")
    }

    func test_evaluate_lowConfidenceObject_addsConfidenceNote() {
        var room = roomWithDimensions(width: 5, height: 4)
        room.geometryCaptured = true
        var obj = TaggedObject(roomID: room.id, category: .boiler, confidence: .low)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result?.confidenceNote,
            "Low-confidence object should produce a confidence note")
    }

    // MARK: - evaluate — overlay geometry

    func test_evaluate_footprintRect_containsObjectPosition() {
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        XCTAssertTrue(result.footprintRect.contains(CGPoint(x: 0.5, y: 0.5)),
            "Footprint rect must contain the object's normalised position")
    }

    func test_evaluate_clearanceRectContainsFootprintRect() {
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        XCTAssertTrue(
            result.clearanceRect.contains(result.footprintRect),
            "Service access rect should fully contain the footprint rect"
        )
        XCTAssertTrue(
            result.installMinimumRect.contains(result.footprintRect),
            "Install minimum rect should fully contain the footprint rect"
        )
        XCTAssertTrue(
            result.serviceAccessRect.contains(result.installMinimumRect),
            "Service access rect should fully contain the install minimum rect"
        )
    }

    // MARK: - Room dimension estimation

    func test_estimateRoomDimensions_withWallGeometry_usesRawExtents() {
        // 5 m × 4 m rectangular room
        let walls = [
            ScannedWall(index: 0, lengthMetres: 5.0, bearingDegrees:  90.0),
            ScannedWall(index: 1, lengthMetres: 4.0, bearingDegrees: 180.0),
            ScannedWall(index: 2, lengthMetres: 5.0, bearingDegrees: 270.0),
            ScannedWall(index: 3, lengthMetres: 4.0, bearingDegrees:   0.0),
        ]
        let room = ScannedRoom(jobID: UUID(), name: "Test", walls: walls)
        let (w, h) = ClearanceEngine.estimateRoomDimensions(room)
        XCTAssertEqual(w, 5.0, accuracy: 0.1)
        XCTAssertEqual(h, 4.0, accuracy: 0.1)
    }

    func test_estimateRoomDimensions_withAreaOnly_usesSquareRoot() {
        let room = ScannedRoom(jobID: UUID(), name: "Test", areaSquareMetres: 16.0)
        let (w, h) = ClearanceEngine.estimateRoomDimensions(room)
        XCTAssertEqual(w, 4.0, accuracy: 0.01)
        XCTAssertEqual(h, 4.0, accuracy: 0.01)
    }

    func test_estimateRoomDimensions_noData_returnsDefault() {
        let room = ScannedRoom(jobID: UUID(), name: "Empty")
        let (w, h) = ClearanceEngine.estimateRoomDimensions(room)
        XCTAssertEqual(w, 4.0, accuracy: 0.01)
        XCTAssertEqual(h, 4.0, accuracy: 0.01)
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

    // MARK: - ClearanceIssue sideLabel

    func test_frontIssue_hasFrontSideLabel() {
        // 1.5 m × 1.5 m room — boiler centred triggers a front conflict.
        let room = roomWithDimensions(width: 1.5, height: 1.5)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let frontIssue = result.issues.first { $0.kind == .frontAccessRestricted }
        XCTAssertNotNil(frontIssue, "Boiler in tiny room should have a front issue")
        XCTAssertEqual(frontIssue?.sideLabel, "front",
            "Front-access issue should carry sideLabel 'front'")
    }

    func test_sideIssue_hasSideSideLabel() {
        // 0.8 m wide × 5 m tall room — boiler near top wall triggers side conflict.
        let room = roomWithDimensions(width: 0.8, height: 5)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.05)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let sideIssue = result.issues.first { $0.kind == .tooCloseToSideWall }
        XCTAssertNotNil(sideIssue, "Narrow room should produce a side-wall issue")
        // Object is centred horizontally, so left and right distances are equal.
        // Either "left" or "right" is acceptable — just verify a label is set.
        XCTAssertNotNil(sideIssue?.sideLabel,
            "Side-wall issue should carry a sideLabel (left or right)")
        let validSideLabels: Set<String> = ["left", "right", "top", "bottom"]
        XCTAssertTrue(validSideLabels.contains(sideIssue?.sideLabel ?? ""),
            "sideLabel must be one of left / right / top / bottom")
    }

    func test_ceilingIssue_hasNilSideLabel() {
        var room = roomWithDimensions(width: 5, height: 4)
        room.ceilingHeightMetres = 1.7   // boiler requires 2.0 m
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let ceilingIssue = result.issues.first { $0.kind == .ceilingHeightLimiting }
        XCTAssertNotNil(ceilingIssue)
        XCTAssertNil(ceilingIssue?.sideLabel,
            "Ceiling issue is not side-specific — sideLabel should be nil")
    }

    func test_enclosedIssue_hasNilSideLabel() {
        let room = roomWithDimensions(width: 6, height: 6)
        var obj = TaggedObject(
            roomID: room.id, category: .boiler,
            quickFieldValues: ["enclosed": "true"]
        )
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let enclosedIssue = result.issues.first { $0.kind == .enclosedInstallation }
        XCTAssertNotNil(enclosedIssue)
        XCTAssertNil(enclosedIssue?.sideLabel,
            "Enclosed-installation issue is not side-specific — sideLabel should be nil")
    }

    func test_sideIssue_nearLeftWall_hasLeftLabel() {
        // 1.5 m wide × 5 m tall room — boiler near top wall (facing .down).
        // x = 0.1 → distLeft = 0.1 × 1.5 = 0.15 m, distRight = 0.9 × 1.5 = 1.35 m.
        // Left side is tighter → sideLabel should be "left".
        let room = roomWithDimensions(width: 1.5, height: 5)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.1, y: 0.05)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let sideIssue = result.issues.first { $0.kind == .tooCloseToSideWall }
        XCTAssertNotNil(sideIssue, "Object near left wall in narrow room should produce side issue")
        XCTAssertEqual(sideIssue?.sideLabel, "left",
            "Tighter left side should produce sideLabel 'left'")
    }

    func test_sideIssue_nearRightWall_hasRightLabel() {
        // 1.5 m wide × 5 m tall room — boiler near top wall (facing .down).
        // x = 0.9 → distLeft = 0.9 × 1.5 = 1.35 m, distRight = 0.1 × 1.5 = 0.15 m.
        // Right side is tighter → sideLabel should be "right".
        let room = roomWithDimensions(width: 1.5, height: 5)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.9, y: 0.05)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let sideIssue = result.issues.first { $0.kind == .tooCloseToSideWall }
        XCTAssertNotNil(sideIssue, "Object near right wall in narrow room should produce side issue")
        XCTAssertEqual(sideIssue?.sideLabel, "right",
            "Tighter right side should produce sideLabel 'right'")
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

    func test_wallProximityIssue_hasWallSource() {
        // 1.5 m × 1.5 m room — triggers front conflict against a wall.
        let room = roomWithDimensions(width: 1.5, height: 1.5)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let frontIssue = result.issues.first { $0.kind == .frontAccessRestricted }
        XCTAssertNotNil(frontIssue, "Should have a front access issue")
        XCTAssertEqual(frontIssue?.source, .wall,
            "Wall-proximity issue should have source .wall")
    }

    func test_sideWallIssue_hasWallSource() {
        // 0.8 m wide × 5 m tall room — triggers side-wall conflict.
        let room = roomWithDimensions(width: 0.8, height: 5)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.05)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let sideIssue = result.issues.first { $0.kind == .tooCloseToSideWall }
        XCTAssertNotNil(sideIssue, "Should have a side-wall issue")
        XCTAssertEqual(sideIssue?.source, .wall,
            "Side-wall issue should have source .wall")
    }

    func test_ceilingIssue_hasCeilingSource() {
        var room = roomWithDimensions(width: 5, height: 4)
        room.ceilingHeightMetres = 1.7   // boiler requires 2.0 m
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let ceilingIssue = result.issues.first { $0.kind == .ceilingHeightLimiting }
        XCTAssertNotNil(ceilingIssue, "Should have a ceiling issue")
        XCTAssertEqual(ceilingIssue?.source, .ceiling,
            "Ceiling issue should have source .ceiling")
    }

    func test_enclosedIssue_hasUnknownSource() {
        let room = roomWithDimensions(width: 6, height: 6)
        var obj = TaggedObject(
            roomID: room.id, category: .boiler,
            quickFieldValues: ["enclosed": "true"]
        )
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let enclosedIssue = result.issues.first { $0.kind == .enclosedInstallation }
        XCTAssertNotNil(enclosedIssue, "Should have an enclosed issue")
        XCTAssertEqual(enclosedIssue?.source, .unknown,
            "Enclosed-installation issue should have source .unknown")
    }

    func test_openingIssue_hasWallSource() {
        // 5 m × 5 m room; boiler close to top wall; door on wall index 0.
        var room = roomWithDimensions(width: 5, height: 5)
        room.ceilingHeightMetres = 2.5
        room.openings = [ScannedOpening(kind: .door, wallIndex: 0)]
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.04)
        let result = ClearanceEngine.evaluate(object: obj, in: room)!
        let openingIssue = result.issues.first { $0.kind == .openingWithinAccessZone }
        XCTAssertNotNil(openingIssue, "Door in clearance zone should produce opening issue")
        XCTAssertEqual(openingIssue?.source, .wall,
            "Opening-within-access-zone issue should have source .wall")
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

    // MARK: - Object-to-object intrusion

    func test_evaluate_objectIntrudingInstallMinimum_producesConflict() {
        // 6 m × 6 m room. Boiler at (0.5, 0.5). Cylinder placed at (0.55, 0.5) —
        // extremely close, its footprint overlaps the boiler's install-minimum zone.
        let roomID = UUID()
        let room = roomWithDimensions(width: 6, height: 6)
        var boiler = TaggedObject(roomID: roomID, category: .boiler)
        boiler.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)

        var cylinder = TaggedObject(roomID: roomID, category: .cylinder)
        cylinder.normalizedPosition = NormalizedPoint2D(x: 0.55, y: 0.5)

        let result = ClearanceEngine.evaluate(
            object: boiler, in: room, otherObjects: [cylinder]
        )
        XCTAssertNotNil(result)
        let intrusionIssue = result?.issues.first { $0.kind == .objectIntrusion }
        XCTAssertNotNil(intrusionIssue,
            "Cylinder in the boiler's install zone should produce an objectIntrusion issue")
        XCTAssertEqual(intrusionIssue?.severity, .conflict)
        XCTAssertEqual(intrusionIssue?.source, .object(cylinder.id))
    }

    func test_evaluate_objectIntrudingServiceAccessOnly_producesWarning() {
        // 6 m × 6 m room. Boiler at (0.1, 0.5) — faces right (left wall is nearest).
        // The boiler's install-minimum zone ends before its service-access zone.
        // Cylinder placed just beyond the install-minimum boundary but still inside
        // the service-access zone: its footprint clears the install minimum (no conflict)
        // yet still overlaps the working space (warning).
        let roomID = UUID()
        let room = roomWithDimensions(width: 6, height: 6)
        var boiler = TaggedObject(roomID: roomID, category: .boiler)
        boiler.normalizedPosition = NormalizedPoint2D(x: 0.1, y: 0.5)

        // Verify that a cylinder at x=0.25 sits outside install minimum but inside
        // service access (both expressed in normalised coords for a 6m-wide room).
        // installMinimumRect.maxX = boilerX + fpHalfW + installMinFront/roomW
        //   = 0.1 + 0.05 + 0.30/6 = 0.200
        // serviceAccessRect.maxX  = boilerX + fpHalfW + frontClearance/roomW
        //   = 0.1 + 0.05 + 0.60/6 = 0.250
        // cylinderFootprint.minX  = 0.25 - cylinderHalfW = 0.25 - 0.0458 ≈ 0.204
        // 0.204 > 0.200 → outside install min; 0.204 < 0.250 → inside service zone.
        var cylinder = TaggedObject(roomID: roomID, category: .cylinder)
        cylinder.normalizedPosition = NormalizedPoint2D(x: 0.25, y: 0.5)

        let result = ClearanceEngine.evaluate(
            object: boiler, in: room, otherObjects: [cylinder]
        )
        XCTAssertNotNil(result)
        let intrusionIssue = result?.issues.first { $0.kind == .objectIntrusion }
        XCTAssertNotNil(intrusionIssue)
        XCTAssertEqual(intrusionIssue?.severity, .warning,
            "Object in service zone but not install minimum should produce a warning")
    }

    func test_evaluate_objectFarAway_noIntrusionIssue() {
        // Two objects at opposite ends of the room should not produce an intrusion issue.
        let roomID = UUID()
        let room = roomWithDimensions(width: 8, height: 8)
        var boiler = TaggedObject(roomID: roomID, category: .boiler)
        boiler.normalizedPosition = NormalizedPoint2D(x: 0.1, y: 0.5)

        var cylinder = TaggedObject(roomID: roomID, category: .cylinder)
        cylinder.normalizedPosition = NormalizedPoint2D(x: 0.9, y: 0.5)

        let result = ClearanceEngine.evaluate(
            object: boiler, in: room, otherObjects: [cylinder]
        )
        XCTAssertNotNil(result)
        let hasIntrusion = result?.issues.contains { $0.kind == .objectIntrusion } ?? false
        XCTAssertFalse(hasIntrusion,
            "Objects at opposite ends of the room should not produce an intrusion issue")
    }

    func test_evaluate_noOtherObjects_noIntrusionIssue() {
        // Passing an empty otherObjects array should never produce an objectIntrusion issue.
        let room = roomWithDimensions(width: 5, height: 5)
        var boiler = TaggedObject(roomID: room.id, category: .boiler)
        boiler.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)

        let result = ClearanceEngine.evaluate(object: boiler, in: room, otherObjects: [])
        let hasIntrusion = result?.issues.contains { $0.kind == .objectIntrusion } ?? false
        XCTAssertFalse(hasIntrusion, "No other objects means no intrusion issues")
    }

    func test_evaluate_objectIntrusionIssue_hasObjectSource() {
        let roomID = UUID()
        let room = roomWithDimensions(width: 6, height: 6)
        var boiler = TaggedObject(roomID: roomID, category: .boiler)
        boiler.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)

        var cylinder = TaggedObject(roomID: roomID, category: .cylinder)
        cylinder.normalizedPosition = NormalizedPoint2D(x: 0.55, y: 0.5)

        let result = ClearanceEngine.evaluate(
            object: boiler, in: room, otherObjects: [cylinder]
        )!
        let intrusionIssue = result.issues.first { $0.kind == .objectIntrusion }
        XCTAssertNotNil(intrusionIssue)
        if case .object(let id) = intrusionIssue?.source {
            XCTAssertEqual(id, cylinder.id,
                "Intrusion issue source should reference the intruding object's UUID")
        } else {
            XCTFail("Intrusion issue should have .object source")
        }
    }

    func test_evaluate_objectIntrusionIssue_sourceDescriptionUsesName() {
        let roomID = UUID()
        let room = roomWithDimensions(width: 6, height: 6)
        var boiler = TaggedObject(roomID: roomID, category: .boiler)
        boiler.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)

        var cylinder = TaggedObject(roomID: roomID, category: .cylinder, label: "Main Cylinder")
        cylinder.normalizedPosition = NormalizedPoint2D(x: 0.55, y: 0.5)

        let result = ClearanceEngine.evaluate(
            object: boiler, in: room, otherObjects: [cylinder]
        )!
        let intrusionIssue = result.issues.first { $0.kind == .objectIntrusion }
        XCTAssertNotNil(intrusionIssue)
        XCTAssertEqual(
            intrusionIssue?.sourceDescription(objectName: cylinder.displayLabel),
            "Blocked by Main Cylinder"
        )
    }

    func test_evaluate_defaultEvaluate_noObjectsParameterNeeded() {
        // Existing call-sites that do not pass otherObjects still compile and work.
        let room = roomWithDimensions(width: 5, height: 5)
        var boiler = TaggedObject(roomID: room.id, category: .boiler)
        boiler.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)

        let result = ClearanceEngine.evaluate(object: boiler, in: room)
        XCTAssertNotNil(result, "evaluate without otherObjects must still return a result")
        let hasIntrusion = result?.issues.contains { $0.kind == .objectIntrusion } ?? false
        XCTAssertFalse(hasIntrusion,
            "evaluate without otherObjects should not produce intrusion issues")
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
