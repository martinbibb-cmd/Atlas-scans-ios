import XCTest
import CoreGraphics
@testable import AtlasScan

// MARK: - ApplianceProfileTests
//
// Unit tests for ApplianceProfileLibrary and the profile-based evaluation path
// in ClearanceEngine.
// No RoomPlan or UIKit types required; runs on any simulator or device.

final class ApplianceProfileTests: XCTestCase {

    // MARK: - Library integrity

    func test_allProfiles_haveUniqueIDs() {
        let ids = ApplianceProfileLibrary.all.map(\.id)
        let unique = Set(ids)
        XCTAssertEqual(ids.count, unique.count, "All profile IDs must be unique")
    }

    func test_allProfiles_categoryMatchesGroup() {
        for profile in ApplianceProfileLibrary.all {
            XCTAssertTrue(
                ClearanceEngine.supportedCategories.contains(profile.category),
                "Profile '\(profile.id)' belongs to unsupported category '\(profile.category.rawValue)'"
            )
        }
    }

    func test_allProfiles_havePositiveDimensions() {
        for profile in ApplianceProfileLibrary.all {
            let rule = profile.rule
            XCTAssertGreaterThan(rule.footprintWidthMetres, 0, "\(profile.id): footprintWidth must be > 0")
            XCTAssertGreaterThan(rule.footprintDepthMetres, 0, "\(profile.id): footprintDepth must be > 0")
            XCTAssertGreaterThan(rule.frontClearanceMetres, 0, "\(profile.id): frontClearance must be > 0")
            XCTAssertGreaterThanOrEqual(rule.sideClearanceMetres, 0, "\(profile.id): sideClearance must be >= 0")
            XCTAssertGreaterThanOrEqual(rule.rearClearanceMetres, 0, "\(profile.id): rearClearance must be >= 0")
            XCTAssertGreaterThan(rule.minCeilingHeightMetres, 0, "\(profile.id): minCeilingHeight must be > 0")
        }
    }

    func test_allProfiles_haveNonEmptyDisplayName() {
        for profile in ApplianceProfileLibrary.all {
            XCTAssertFalse(profile.displayName.isEmpty, "\(profile.id) must have a non-empty displayName")
        }
    }

    func test_allProfiles_haveNonEmptyFamily() {
        for profile in ApplianceProfileLibrary.all {
            XCTAssertFalse(profile.family.isEmpty, "\(profile.id) must have a non-empty family")
        }
    }

    // MARK: - Profile counts per category

    func test_boilerProfiles_atLeastThree() {
        XCTAssertGreaterThanOrEqual(
            ApplianceProfileLibrary.profiles(for: .boiler).count, 3,
            "Should have at least combi, system, and regular boiler profiles"
        )
    }

    func test_cylinderProfiles_atLeastTwo() {
        XCTAssertGreaterThanOrEqual(
            ApplianceProfileLibrary.profiles(for: .cylinder).count, 2,
            "Should have at least unvented standard and slim profiles"
        )
    }

    func test_manifoldProfiles_atLeastThree() {
        XCTAssertGreaterThanOrEqual(
            ApplianceProfileLibrary.profiles(for: .manifold).count, 3,
            "Should have small, standard and large UFH manifold profiles"
        )
    }

    func test_radiatorProfiles_atLeastThree() {
        XCTAssertGreaterThanOrEqual(
            ApplianceProfileLibrary.profiles(for: .radiator).count, 3,
            "Should have compact, standard and wide radiator profiles"
        )
    }

    func test_unsupportedCategory_returnsEmpty() {
        XCTAssertTrue(ApplianceProfileLibrary.profiles(for: .thermostat).isEmpty)
        XCTAssertTrue(ApplianceProfileLibrary.profiles(for: .gasMeter).isEmpty)
    }

    // MARK: - Lookup

    func test_profileLookup_knownID_returnsProfile() {
        let profile = ApplianceProfileLibrary.profile(id: "combi_generic")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.category, .boiler)
        XCTAssertEqual(profile?.family, "Combi Boiler")
    }

    func test_profileLookup_unknownID_returnsNil() {
        XCTAssertNil(ApplianceProfileLibrary.profile(id: "nonexistent_profile"))
    }

    func test_profileLookup_allKnownIDs_found() {
        for profile in ApplianceProfileLibrary.all {
            XCTAssertNotNil(
                ApplianceProfileLibrary.profile(id: profile.id),
                "Profile '\(profile.id)' must be retrievable by ID"
            )
        }
    }

    // MARK: - Profile-specific dimension checks

    func test_combiCompact_isNarrowerThanCombiGeneric() {
        let compact = ApplianceProfileLibrary.profile(id: "combi_compact")!
        let generic = ApplianceProfileLibrary.profile(id: "combi_generic")!
        XCTAssertLessThan(compact.rule.footprintWidthMetres, generic.rule.footprintWidthMetres,
            "Compact combi should have smaller footprint width than generic combi")
    }

    func test_regularBoiler_hasMoreSideClearanceThanCombi() {
        let regular = ApplianceProfileLibrary.profile(id: "regular_generic")!
        let combi   = ApplianceProfileLibrary.profile(id: "combi_generic")!
        XCTAssertGreaterThan(regular.rule.sideClearanceMetres, combi.rule.sideClearanceMetres,
            "Regular boiler should require more side clearance than a combi")
    }

    func test_slimCylinder_isNarrowerThanStandard() {
        let slim     = ApplianceProfileLibrary.profile(id: "cylinder_unvented_slim")!
        let standard = ApplianceProfileLibrary.profile(id: "cylinder_unvented_standard")!
        XCTAssertLessThan(slim.rule.footprintWidthMetres, standard.rule.footprintWidthMetres,
            "Slim cylinder should have smaller footprint width than standard unvented")
    }

    func test_manifoldProfiles_smallerThanLarger() {
        let small    = ApplianceProfileLibrary.profile(id: "manifold_ufh_small")!
        let standard = ApplianceProfileLibrary.profile(id: "manifold_ufh_standard")!
        let large    = ApplianceProfileLibrary.profile(id: "manifold_ufh_large")!
        XCTAssertLessThan(small.rule.footprintWidthMetres, standard.rule.footprintWidthMetres)
        XCTAssertLessThan(standard.rule.footprintWidthMetres, large.rule.footprintWidthMetres)
    }

    func test_radiatorWide_isWiderThanStandard() {
        let wide     = ApplianceProfileLibrary.profile(id: "radiator_wide")!
        let standard = ApplianceProfileLibrary.profile(id: "radiator_standard")!
        XCTAssertGreaterThan(wide.rule.footprintWidthMetres, standard.rule.footprintWidthMetres)
    }

    func test_doublePanel_isDeeperThanSinglePanel() {
        let dbl = ApplianceProfileLibrary.profile(id: "radiator_double_panel")!
        let std = ApplianceProfileLibrary.profile(id: "radiator_standard")!
        XCTAssertGreaterThan(dbl.rule.footprintDepthMetres, std.rule.footprintDepthMetres,
            "Double panel radiator should be deeper (front-to-back) than a single panel")
    }

    // MARK: - Profile-based ClearanceEngine evaluation

    func test_evaluate_withValidProfile_usesProfileRule() {
        // Place a compact combi in a room that would normally be fine for a generic combi.
        // The compact combi is narrower, so side clearance should be easier.
        // We verify that a profile result is returned and has no profileNote nil/non-nil mismatch.
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.1)
        obj.applianceProfileID = "combi_compact"

        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result, "Evaluation with known profile should return a result")
        // Compact combi has a guidanceNote — verify it is surfaced
        XCTAssertNotNil(result?.profileNote,
            "compact combi profile has a guidanceNote; it should appear in the result")
    }

    func test_evaluate_withNilProfile_usesGenericRule() {
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        // applianceProfileID is nil by default

        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.profileNote,
            "No profile set — profileNote should be nil")
    }

    func test_evaluate_withUnknownProfileID_fallsBackToGeneric() {
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .boiler)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.5)
        obj.applianceProfileID = "totally_unknown_profile_xyz"

        // Should still evaluate using the category default rule (not return nil)
        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result, "Unknown profileID should fall back to generic rule, not return nil")
        XCTAssertNil(result?.profileNote, "Unknown profileID has no note")
    }

    func test_evaluate_slimCylinder_inNarrowCupboard_producesResult() {
        // Slim cylinder (0.40 m wide) in a 0.9 m wide space.
        // With generic rule (0.55 m) side conflicts are expected; with slim profile they should clear.
        let room = roomWithDimensions(width: 0.90, height: 2.0)
        var obj = TaggedObject(roomID: room.id, category: .cylinder)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.1)
        obj.applianceProfileID = "cylinder_unvented_slim"

        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        // Slim cylinder (0.40 + 0.20 side = 0.60 m total); room is 0.90 m wide — just fits
        let hasSideConflict = result?.issues.contains {
            $0.kind == .tooCloseToSideWall && $0.severity == .conflict
        } ?? false
        XCTAssertFalse(hasSideConflict,
            "Slim cylinder in a 900 mm wide space should not produce a side-clearance conflict")
    }

    func test_evaluate_wideRadiator_inNarrowRoom_conflictsSideWall() {
        // Wide radiator (1.05 m wide + side) in a 1.0 m wide room
        let room = roomWithDimensions(width: 1.0, height: 4.0)
        var obj = TaggedObject(roomID: room.id, category: .radiator)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.05)
        obj.applianceProfileID = "radiator_wide"

        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        let hasSideIssue = result?.issues.contains { $0.kind == .tooCloseToSideWall } ?? false
        XCTAssertTrue(hasSideIssue, "Wide radiator in a 1 m wide room should flag side clearance")
    }

    func test_evaluate_largeManifoldsInNarrowSpace_producesConflict() {
        // Large manifold (0.80 m wide) centred in a 0.8 m wide room
        let room = roomWithDimensions(width: 0.8, height: 3.0)
        var obj = TaggedObject(roomID: room.id, category: .manifold)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.1)
        obj.applianceProfileID = "manifold_ufh_large"

        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        let hasSideIssue = result?.issues.contains { $0.kind == .tooCloseToSideWall } ?? false
        XCTAssertTrue(hasSideIssue, "Large UFH manifold in 0.8 m wide room should flag side clearance")
    }

    func test_evaluate_profileWithoutGuidanceNote_profileNoteIsNil() {
        // Compact radiator profile has no guidanceNote
        let room = roomWithDimensions(width: 5, height: 4)
        var obj = TaggedObject(roomID: room.id, category: .radiator)
        obj.normalizedPosition = NormalizedPoint2D(x: 0.5, y: 0.05)
        obj.applianceProfileID = "radiator_compact"

        let result = ClearanceEngine.evaluate(object: obj, in: room)
        XCTAssertNotNil(result)
        XCTAssertNil(result?.profileNote,
            "Compact radiator profile has no guidanceNote — profileNote should be nil")
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
