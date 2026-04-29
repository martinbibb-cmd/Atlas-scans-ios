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
}
