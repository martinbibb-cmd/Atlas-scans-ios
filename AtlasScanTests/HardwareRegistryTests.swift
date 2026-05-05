import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - HardwareRegistryTests
//
// Tests for the shared hardware registry:
//   - ApplianceDefinitionV1 mm→m metric conversions
//   - MasterHardwareRegistry completeness and integrity
//   - HardwarePatchV1 merging (overrides, additions)
//   - ApplianceProfileLibrary wrapper integration with shared definitions
//   - VisitHandoffPackV1 round-trip with hardwarePatches

final class HardwareRegistryTests: XCTestCase {

    override func tearDown() {
        // Reset the library after any test that modifies the runtime registry
        ApplianceProfileLibrary.resetToMaster()
        super.tearDown()
    }

    // MARK: - ApplianceDefinitionV1 metric helpers

    func test_dimensions_mmToMetresConversion() {
        let dims = ApplianceDimensionsV1(widthMm: 440, depthMm: 360, heightMm: 750)
        XCTAssertEqual(dims.widthM,  0.440, accuracy: 0.0001)
        XCTAssertEqual(dims.depthM,  0.360, accuracy: 0.0001)
        XCTAssertEqual(dims.heightM, 0.750, accuracy: 0.0001)
    }

    func test_clearanceRules_mmToMetresConversion() {
        let rules = ApplianceClearanceRulesV1(
            installMinFrontMm: 300,
            frontMm:           600,
            sideMm:            150,
            rearMm:             50,
            topMm:             200,
            minCeilingHeightMm: 2000
        )
        XCTAssertEqual(rules.installMinFrontM, 0.300, accuracy: 0.0001)
        XCTAssertEqual(rules.frontM,           0.600, accuracy: 0.0001)
        XCTAssertEqual(rules.sideM,            0.150, accuracy: 0.0001)
        XCTAssertEqual(rules.rearM,            0.050, accuracy: 0.0001)
        XCTAssertEqual(rules.topM,             0.200, accuracy: 0.0001)
        XCTAssertEqual(rules.minCeilingHeightM, 2.000, accuracy: 0.0001)
    }

    // MARK: - ApplianceDefinitionV1 JSON round-trip

    func test_definition_encodesAndDecodes() throws {
        let def = ApplianceDefinitionV1(
            modelId:     "test_model",
            brand:       "TestBrand",
            family:      "Test Family",
            displayName: "Test Model",
            category:    "boiler",
            dimensions:  ApplianceDimensionsV1(widthMm: 500, depthMm: 400, heightMm: 700),
            clearanceRules: ApplianceClearanceRulesV1(
                installMinFrontMm: 300,
                frontMm: 600, sideMm: 150, rearMm: 50, topMm: 200,
                minCeilingHeightMm: 2000
            ),
            guidanceNote: "Test note",
            source: "static"
        )
        let data = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(ApplianceDefinitionV1.self, from: data)
        XCTAssertEqual(decoded.modelId, def.modelId)
        XCTAssertEqual(decoded.brand, def.brand)
        XCTAssertEqual(decoded.dimensions, def.dimensions)
        XCTAssertEqual(decoded.clearanceRules, def.clearanceRules)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    // MARK: - MasterHardwareRegistry

    func test_masterRegistry_containsBoilers() {
        let boilers = MasterHardwareRegistry.registry.definitions(forCategory: "boiler")
        XCTAssertGreaterThanOrEqual(boilers.count, 4, "Should have at least 4 boiler definitions")
    }

    func test_masterRegistry_containsCylinders() {
        let cylinders = MasterHardwareRegistry.registry.definitions(forCategory: "cylinder")
        XCTAssertGreaterThanOrEqual(cylinders.count, 2)
    }

    func test_masterRegistry_containsManifolds() {
        let manifolds = MasterHardwareRegistry.registry.definitions(forCategory: "manifold")
        XCTAssertGreaterThanOrEqual(manifolds.count, 3)
    }

    func test_masterRegistry_containsRadiators() {
        let radiators = MasterHardwareRegistry.registry.definitions(forCategory: "radiator")
        XCTAssertGreaterThanOrEqual(radiators.count, 3)
    }

    func test_masterRegistry_worcesterEntryPresent() {
        let def = MasterHardwareRegistry.registry.definition(for: "worcester_4000_combi_30")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.brand, "Worcester Bosch")
        XCTAssertEqual(def?.category, "boiler")
    }

    func test_masterRegistry_allDefinitionsHavePositiveDimensions() {
        for (_, def) in MasterHardwareRegistry.registry.definitions {
            XCTAssertGreaterThan(def.dimensions.widthMm, 0, "\(def.modelId): widthMm must be > 0")
            XCTAssertGreaterThan(def.dimensions.depthMm, 0, "\(def.modelId): depthMm must be > 0")
            XCTAssertGreaterThan(def.dimensions.heightMm, 0, "\(def.modelId): heightMm must be > 0")
            XCTAssertGreaterThan(def.clearanceRules.frontMm, 0, "\(def.modelId): frontMm must be > 0")
        }
    }

    func test_masterRegistry_allModelIDsAreUnique() {
        let ids = Array(MasterHardwareRegistry.registry.definitions.keys)
        let unique = Set(ids)
        XCTAssertEqual(ids.count, unique.count)
    }

    // MARK: - HardwareRegistryV1 patch merging

    func test_registry_applying_patch_overridesExisting() {
        let original = HardwareRegistryV1(definitions: [
            ApplianceDefinitionV1(
                modelId: "test_boiler", brand: "Old", family: "F", displayName: "Old Model",
                category: "boiler",
                dimensions: ApplianceDimensionsV1(widthMm: 600, depthMm: 500, heightMm: 750),
                clearanceRules: ApplianceClearanceRulesV1(
                    installMinFrontMm: 300, frontMm: 600, sideMm: 150,
                    rearMm: 50, topMm: 200, minCeilingHeightMm: 2000
                )
            )
        ])

        let patchDef = ApplianceDefinitionV1(
            modelId: "test_boiler", brand: "New", family: "F", displayName: "Patched Model",
            category: "boiler",
            dimensions: ApplianceDimensionsV1(widthMm: 500, depthMm: 400, heightMm: 700),
            clearanceRules: ApplianceClearanceRulesV1(
                installMinFrontMm: 250, frontMm: 500, sideMm: 100,
                rearMm: 50, topMm: 150, minCeilingHeightMm: 2000
            ),
            source: "patch"
        )

        let patch = HardwarePatchV1(
            patchId: UUID().uuidString,
            overrides: [patchDef],
            additions: [],
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )

        let merged = original.applying(patch)
        let result = merged.definition(for: "test_boiler")
        XCTAssertEqual(result?.brand, "New")
        XCTAssertEqual(result?.displayName, "Patched Model")
        XCTAssertEqual(result?.source, "patch")
    }

    func test_registry_applying_patch_addsNew() {
        let original = HardwareRegistryV1(definitions: [])

        let addition = ApplianceDefinitionV1(
            modelId: "rare_legacy_boiler", brand: "Legacy", family: "F", displayName: "Rare Legacy",
            category: "boiler",
            dimensions: ApplianceDimensionsV1(widthMm: 700, depthMm: 600, heightMm: 900),
            clearanceRules: ApplianceClearanceRulesV1(
                installMinFrontMm: 400, frontMm: 800, sideMm: 200,
                rearMm: 100, topMm: 300, minCeilingHeightMm: 2200
            ),
            source: "patch"
        )

        let patch = HardwarePatchV1(
            patchId: UUID().uuidString,
            overrides: [],
            additions: [addition],
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )

        let merged = original.applying(patch)
        XCTAssertNotNil(merged.definition(for: "rare_legacy_boiler"))
    }

    // MARK: - HardwarePatchV1 JSON round-trip

    func test_hardwarePatch_encodesAndDecodes() throws {
        let patchDef = ApplianceDefinitionV1(
            modelId: "custom_combi", brand: "Custom", family: "Combi", displayName: "Custom Combi",
            category: "boiler",
            dimensions: ApplianceDimensionsV1(widthMm: 450, depthMm: 380, heightMm: 730),
            clearanceRules: ApplianceClearanceRulesV1(
                installMinFrontMm: 300, frontMm: 600, sideMm: 100,
                rearMm: 50, topMm: 200, minCeilingHeightMm: 2000
            ),
            source: "patch"
        )
        let patch = HardwarePatchV1(
            patchId: "patch-001",
            overrides: [patchDef],
            additions: [],
            generatedAt: "2026-01-01T00:00:00Z"
        )

        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(HardwarePatchV1.self, from: data)
        XCTAssertEqual(decoded.kind, "hardware-patch")
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.patchId, "patch-001")
        XCTAssertEqual(decoded.overrides.first?.modelId, "custom_combi")
    }

    // MARK: - ApplianceProfileLibrary integration

    func test_profileLibrary_derivesFromMasterRegistry() {
        let profile = ApplianceProfileLibrary.profile(id: "worcester_4000_combi_30")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.definition.brand, "Worcester Bosch")
    }

    func test_profileLibrary_ruleMatchesDefinitionDimensions() {
        let profile = ApplianceProfileLibrary.profile(id: "combi_compact")!
        let def = ApplianceProfileLibrary.definition(id: "combi_compact")!
        XCTAssertEqual(profile.rule.footprintWidthMetres, def.dimensions.widthM, accuracy: 0.0001)
        XCTAssertEqual(profile.rule.footprintDepthMetres, def.dimensions.depthM, accuracy: 0.0001)
        XCTAssertEqual(profile.rule.frontClearanceMetres, def.clearanceRules.frontM, accuracy: 0.0001)
        XCTAssertEqual(profile.rule.sideClearanceMetres, def.clearanceRules.sideM, accuracy: 0.0001)
    }

    func test_profileLibrary_apply_patch_extendsCatalog() {
        let newDef = ApplianceDefinitionV1(
            modelId: "patch_test_boiler",
            brand: "Patch Brand",
            family: "Combi Boiler",
            displayName: "Patch Test Boiler",
            category: "boiler",
            dimensions: ApplianceDimensionsV1(widthMm: 480, depthMm: 380, heightMm: 760),
            clearanceRules: ApplianceClearanceRulesV1(
                installMinFrontMm: 300, frontMm: 600, sideMm: 100,
                rearMm: 50, topMm: 200, minCeilingHeightMm: 2000
            ),
            source: "patch"
        )
        let patch = HardwarePatchV1(
            patchId: "test-patch",
            overrides: [],
            additions: [newDef],
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
        ApplianceProfileLibrary.apply(patch: patch)
        XCTAssertNotNil(ApplianceProfileLibrary.profile(id: "patch_test_boiler"))
    }

    func test_profileLibrary_resetToMaster_removesPatches() {
        let newDef = ApplianceDefinitionV1(
            modelId: "transient_boiler",
            brand: "Transient",
            family: "Combi Boiler",
            displayName: "Transient Boiler",
            category: "boiler",
            dimensions: ApplianceDimensionsV1(widthMm: 500, depthMm: 400, heightMm: 750),
            clearanceRules: ApplianceClearanceRulesV1(
                installMinFrontMm: 300, frontMm: 600, sideMm: 150,
                rearMm: 50, topMm: 200, minCeilingHeightMm: 2000
            ),
            source: "patch"
        )
        let patch = HardwarePatchV1(
            patchId: "transient-patch",
            overrides: [],
            additions: [newDef],
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
        ApplianceProfileLibrary.apply(patch: patch)
        XCTAssertNotNil(ApplianceProfileLibrary.profile(id: "transient_boiler"))

        ApplianceProfileLibrary.resetToMaster()
        XCTAssertNil(ApplianceProfileLibrary.profile(id: "transient_boiler"),
            "Patch-only profiles should be removed after resetToMaster()")
    }

    // MARK: - VisitHandoffPackV1 hardwarePatches round-trip

    func test_visitHandoffPack_roundTrip_withoutPatches() throws {
        let pack = VisitHandoffPackV1(
            visitId: "VID-001",
            sourceApp: .mind,
            visitReference: "JOB-001",
            reviewStatus: .pendingCapture,
            hardwarePatches: nil,
            exportedAt: "2026-01-01T00:00:00Z"
        )
        let data = try JSONEncoder().encode(pack)
        let decoded = try JSONDecoder().decode(VisitHandoffPackV1.self, from: data)
        XCTAssertNil(decoded.hardwarePatches)
        XCTAssertEqual(decoded.visitId, "VID-001")
    }

    func test_visitHandoffPack_roundTrip_withPatches() throws {
        let patchDef = ApplianceDefinitionV1(
            modelId: "custom_model",
            brand: "CustomBrand",
            family: "System Boiler",
            displayName: "Custom System 35kW",
            category: "boiler",
            dimensions: ApplianceDimensionsV1(widthMm: 650, depthMm: 520, heightMm: 800),
            clearanceRules: ApplianceClearanceRulesV1(
                installMinFrontMm: 350, frontMm: 700, sideMm: 200,
                rearMm: 50, topMm: 250, minCeilingHeightMm: 2000
            ),
            source: "patch"
        )
        let patch = HardwarePatchV1(
            patchId: "visit-patch-1",
            overrides: [],
            additions: [patchDef],
            generatedAt: "2026-01-01T00:00:00Z"
        )
        let pack = VisitHandoffPackV1(
            visitId: "VID-002",
            sourceApp: .mind,
            visitReference: "JOB-002",
            reviewStatus: .pendingCapture,
            hardwarePatches: patch,
            exportedAt: "2026-01-01T00:00:00Z"
        )
        let data = try JSONEncoder().encode(pack)
        let decoded = try JSONDecoder().decode(VisitHandoffPackV1.self, from: data)
        XCTAssertEqual(decoded.hardwarePatches?.patchId, "visit-patch-1")
        XCTAssertEqual(decoded.hardwarePatches?.additions.first?.modelId, "custom_model")
        XCTAssertEqual(decoded.hardwarePatches?.kind, "hardware-patch")
    }

    func test_visitHandoffPack_existingDecodesWithoutPatch() throws {
        // Ensure backward compat: old payloads without hardwarePatches decode cleanly.
        let json = """
        {
          "schemaVersion": "1.0",
          "visitId": "VID-OLD",
          "sourceApp": "mind",
          "visitReference": "JOB-OLD",
          "reviewStatus": "pending_capture",
          "exportedAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VisitHandoffPackV1.self, from: json)
        XCTAssertEqual(decoded.visitId, "VID-OLD")
        XCTAssertNil(decoded.hardwarePatches, "Old payloads without hardwarePatches should decode with nil")
    }
}
