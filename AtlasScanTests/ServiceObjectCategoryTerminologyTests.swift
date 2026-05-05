import XCTest
@testable import AtlasScan

// MARK: - ServiceObjectCategoryTerminologyTests
//
// Verifies that no user-facing display strings expose the word "Plant"
// in a UK domestic heating survey context.
//
// Rationale: "Plant" is commercial/mechanical services terminology.
// The domestic survey UI must use plain language ("Heating equipment",
// "Heating cupboard / utility space", etc.) at all display boundaries.

final class ServiceObjectCategoryTerminologyTests: XCTestCase {

    // MARK: - ServiceObjectCategory display names

    func test_plantSpace_displayName_doesNotContainPlant() {
        XCTAssertFalse(
            ServiceObjectCategory.plantSpace.displayName.contains("Plant"),
            "plantSpace displayName must not expose 'Plant': got '\(ServiceObjectCategory.plantSpace.displayName)'"
        )
    }

    func test_plantSpace_displayName_isHeatingCupboard() {
        XCTAssertEqual(
            ServiceObjectCategory.plantSpace.displayName,
            "Heating cupboard / utility space"
        )
    }

    // MARK: - ServiceObjectCategory group names

    func test_heatSourceGroupName_doesNotContainPlant() {
        let heatSourceCases: [ServiceObjectCategory] = [
            .boiler, .heatPump, .cylinder, .thermalStore,
            .bufferVessel, .pump, .lowLossHeader, .expansionVessel,
            .manifold, .zoneValve
        ]
        for category in heatSourceCases {
            XCTAssertFalse(
                category.groupName.contains("Plant"),
                "\(category.rawValue).groupName must not contain 'Plant': got '\(category.groupName)'"
            )
        }
    }

    func test_heatSourceGroupName_isBoilerCylinderAndHeatingEquipment() {
        XCTAssertEqual(ServiceObjectCategory.boiler.groupName, "Boiler, cylinder & heating equipment")
        XCTAssertEqual(ServiceObjectCategory.heatPump.groupName, "Boiler, cylinder & heating equipment")
        XCTAssertEqual(ServiceObjectCategory.cylinder.groupName, "Boiler, cylinder & heating equipment")
    }

    func test_noCategory_hasGroupNameContainingPlant() {
        for category in ServiceObjectCategory.allCases {
            XCTAssertFalse(
                category.groupName.contains("Plant"),
                "\(category.rawValue).groupName must not contain 'Plant': got '\(category.groupName)'"
            )
        }
    }

    func test_noCategory_hasDisplayNameEqualToPlant() {
        for category in ServiceObjectCategory.allCases {
            XCTAssertNotEqual(
                category.displayName,
                "Plant",
                "\(category.rawValue).displayName must not be 'Plant'"
            )
            XCTAssertNotEqual(
                category.displayName,
                "Plant Space",
                "\(category.rawValue).displayName must not be 'Plant Space'"
            )
        }
    }

    // MARK: - CapturePhotoKind display names

    func test_capturePhotoKind_plant_displayName_doesNotContainPlant() {
        XCTAssertFalse(
            CapturePhotoKind.plant.displayName.contains("Plant"),
            "CapturePhotoKind.plant displayName must not expose 'Plant': got '\(CapturePhotoKind.plant.displayName)'"
        )
    }

    func test_capturePhotoKind_plant_displayName_isHeatingEquipment() {
        XCTAssertEqual(CapturePhotoKind.plant.displayName, "Heating equipment")
    }

    func test_noCapturePhotoKind_hasDisplayNameContainingPlant() {
        for kind in CapturePhotoKind.allCases {
            XCTAssertFalse(
                kind.displayName.contains("Plant"),
                "CapturePhotoKind.\(kind.rawValue).displayName must not contain 'Plant': got '\(kind.displayName)'"
            )
        }
    }

    // MARK: - Internal enum raw values are preserved

    func test_plantSpace_rawValue_isUnchanged() {
        // Internal raw value must stay stable for Codable backward compat.
        XCTAssertEqual(ServiceObjectCategory.plantSpace.rawValue, "plant_space")
    }

    func test_capturePhotoKind_plant_rawValue_isUnchanged() {
        XCTAssertEqual(CapturePhotoKind.plant.rawValue, "plant")
    }
}
