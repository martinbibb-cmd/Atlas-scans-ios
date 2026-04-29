import Foundation

// MARK: - ApplianceProfile

/// A named appliance profile providing model-specific clearance dimensions
/// for use in ClearanceEngine evaluations.
///
/// Profiles represent practical appliance families (e.g., compact combi, slim cylinder).
/// They are not full manufacturer records — dimensions are approximate guidance only.
struct ApplianceProfile: Identifiable {

    /// Stable identifier stored in a capture session's appliance profile ID field.
    let id: String

    /// Category this profile belongs to.
    let category: ServiceObjectCategory

    /// Short family description shown as a group header in pickers (e.g., "Combi Boiler").
    let family: String

    /// Human-readable profile name shown in the picker UI.
    let displayName: String

    /// Clearance dimensions for this profile.
    let rule: ClearanceRule

    /// Optional plain-English guidance note surfaced alongside the clearance result.
    /// Wording is deliberately hedged to avoid false certainty.
    let guidanceNote: String?
}

// MARK: - ApplianceProfileLibrary

/// Static library of practical appliance profiles for ClearanceEngine.
///
/// Scope: a handful of profile families per supported category.
/// Category-default rules in ClearanceEngine remain as the generic fallback when
/// no profile is selected.
///
/// Architecture: local to AtlasScan; no external dependencies; designed to grow
/// incrementally without touching AtlasContracts or ExportBuilder.
enum ApplianceProfileLibrary {

    // MARK: - All profiles

    static let all: [ApplianceProfile] =
        boilerProfiles + cylinderProfiles + manifoldProfiles + radiatorProfiles

    // MARK: - Lookup

    /// Returns all profiles for the given category, sorted by display name.
    static func profiles(for category: ServiceObjectCategory) -> [ApplianceProfile] {
        all.filter { $0.category == category }
    }

    /// Returns the profile with the given identifier, or `nil`.
    static func profile(id: String) -> ApplianceProfile? {
        all.first { $0.id == id }
    }

    // MARK: - Boiler profiles

    static let boilerProfiles: [ApplianceProfile] = [
        ApplianceProfile(
            id: "combi_generic",
            category: .boiler,
            family: "Combi Boiler",
            displayName: "Generic combi",
            rule: ClearanceRule(
                footprintWidthMetres:   0.60,
                footprintDepthMetres:   0.50,
                installMinFrontMetres:  0.30,
                frontClearanceMetres:   0.60,
                sideClearanceMetres:    0.15,
                rearClearanceMetres:    0.05,
                minCeilingHeightMetres: 2.00
            ),
            guidanceNote: "Typical wall-hung combi. Verify manufacturer spec for exact clearances."
        ),
        ApplianceProfile(
            id: "combi_compact",
            category: .boiler,
            family: "Combi Boiler",
            displayName: "Compact combi",
            rule: ClearanceRule(
                footprintWidthMetres:   0.44,
                footprintDepthMetres:   0.36,
                installMinFrontMetres:  0.30,
                frontClearanceMetres:   0.60,
                sideClearanceMetres:    0.10,
                rearClearanceMetres:    0.05,
                minCeilingHeightMetres: 2.00
            ),
            guidanceNote: "Compact wall-hung combi. Smaller body but same front service clearance required."
        ),
        ApplianceProfile(
            id: "system_generic",
            category: .boiler,
            family: "System Boiler",
            displayName: "Generic system boiler",
            rule: ClearanceRule(
                footprintWidthMetres:   0.70,
                footprintDepthMetres:   0.50,
                installMinFrontMetres:  0.30,
                frontClearanceMetres:   0.60,
                sideClearanceMetres:    0.15,
                rearClearanceMetres:    0.05,
                minCeilingHeightMetres: 2.00
            ),
            guidanceNote: "System boiler — typically wider than a combi. Check system pump clearance too."
        ),
        ApplianceProfile(
            id: "regular_generic",
            category: .boiler,
            family: "Regular Boiler",
            displayName: "Regular (heat-only) boiler",
            rule: ClearanceRule(
                footprintWidthMetres:   0.70,
                footprintDepthMetres:   0.55,
                installMinFrontMetres:  0.35,
                frontClearanceMetres:   0.70,
                sideClearanceMetres:    0.20,
                rearClearanceMetres:    0.05,
                minCeilingHeightMetres: 2.00
            ),
            guidanceNote: "Regular boiler. Typically more side room needed for pipework and zone valves."
        ),
    ]

    // MARK: - Cylinder profiles

    static let cylinderProfiles: [ApplianceProfile] = [
        ApplianceProfile(
            id: "cylinder_unvented_standard",
            category: .cylinder,
            family: "Unvented Cylinder",
            displayName: "Standard unvented cylinder",
            rule: ClearanceRule(
                footprintWidthMetres:   0.55,
                footprintDepthMetres:   0.55,
                installMinFrontMetres:  0.25,
                frontClearanceMetres:   0.50,
                sideClearanceMetres:    0.10,
                rearClearanceMetres:    0.05,
                minCeilingHeightMetres: 1.90
            ),
            guidanceNote: "Standard unvented cylinder ~450 mm dia. G3 — confirm tundish and pressure relief access."
        ),
        ApplianceProfile(
            id: "cylinder_unvented_slim",
            category: .cylinder,
            family: "Unvented Cylinder",
            displayName: "Slim unvented cylinder",
            rule: ClearanceRule(
                footprintWidthMetres:   0.40,
                footprintDepthMetres:   0.40,
                installMinFrontMetres:  0.25,
                frontClearanceMetres:   0.50,
                sideClearanceMetres:    0.10,
                rearClearanceMetres:    0.05,
                minCeilingHeightMetres: 1.90
            ),
            guidanceNote: "Slim-profile unvented cylinder. Same front access required; height likely exceeds 1.8 m."
        ),
        ApplianceProfile(
            id: "cylinder_vented_standard",
            category: .cylinder,
            family: "Vented Cylinder",
            displayName: "Standard vented cylinder",
            rule: ClearanceRule(
                footprintWidthMetres:   0.45,
                footprintDepthMetres:   0.45,
                installMinFrontMetres:  0.25,
                frontClearanceMetres:   0.50,
                sideClearanceMetres:    0.10,
                rearClearanceMetres:    0.05,
                minCeilingHeightMetres: 1.80
            ),
            guidanceNote: "Vented hot-water cylinder. Check cold-feed header tank location and overflow route."
        ),
    ]

    // MARK: - Manifold profiles

    static let manifoldProfiles: [ApplianceProfile] = [
        ApplianceProfile(
            id: "manifold_ufh_small",
            category: .manifold,
            family: "UFH Manifold",
            displayName: "Small UFH manifold (≤ 6 loops)",
            rule: ClearanceRule(
                footprintWidthMetres:   0.40,
                footprintDepthMetres:   0.15,
                installMinFrontMetres:  0.30,
                frontClearanceMetres:   0.60,
                sideClearanceMetres:    0.10,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.80
            ),
            guidanceNote: "Small manifold up to 6 UFH loops. Allow front access for flow/return valves and actuators."
        ),
        ApplianceProfile(
            id: "manifold_ufh_standard",
            category: .manifold,
            family: "UFH Manifold",
            displayName: "Standard UFH manifold (7–12 loops)",
            rule: ClearanceRule(
                footprintWidthMetres:   0.60,
                footprintDepthMetres:   0.15,
                installMinFrontMetres:  0.30,
                frontClearanceMetres:   0.60,
                sideClearanceMetres:    0.10,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.80
            ),
            guidanceNote: "Standard manifold up to 12 loops. Check cabinet width if the manifold is to be boxed in."
        ),
        ApplianceProfile(
            id: "manifold_ufh_large",
            category: .manifold,
            family: "UFH Manifold",
            displayName: "Large UFH manifold (13+ loops)",
            rule: ClearanceRule(
                footprintWidthMetres:   0.80,
                footprintDepthMetres:   0.15,
                installMinFrontMetres:  0.30,
                frontClearanceMetres:   0.60,
                sideClearanceMetres:    0.10,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.80
            ),
            guidanceNote: "Large manifold for 13+ loops. Significant wall width required — check available run."
        ),
    ]

    // MARK: - Radiator profiles

    static let radiatorProfiles: [ApplianceProfile] = [
        ApplianceProfile(
            id: "radiator_compact",
            category: .radiator,
            family: "Panel Radiator",
            displayName: "Compact radiator (up to 600 mm)",
            rule: ClearanceRule(
                footprintWidthMetres:   0.55,
                footprintDepthMetres:   0.12,
                installMinFrontMetres:  0.03,
                frontClearanceMetres:   0.05,
                sideClearanceMetres:    0.05,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.50
            ),
            guidanceNote: nil
        ),
        ApplianceProfile(
            id: "radiator_standard",
            category: .radiator,
            family: "Panel Radiator",
            displayName: "Standard radiator (600–900 mm)",
            rule: ClearanceRule(
                footprintWidthMetres:   0.75,
                footprintDepthMetres:   0.12,
                installMinFrontMetres:  0.03,
                frontClearanceMetres:   0.05,
                sideClearanceMetres:    0.05,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.50
            ),
            guidanceNote: nil
        ),
        ApplianceProfile(
            id: "radiator_wide",
            category: .radiator,
            family: "Panel Radiator",
            displayName: "Wide radiator (900–1200 mm)",
            rule: ClearanceRule(
                footprintWidthMetres:   1.05,
                footprintDepthMetres:   0.12,
                installMinFrontMetres:  0.03,
                frontClearanceMetres:   0.05,
                sideClearanceMetres:    0.05,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.50
            ),
            guidanceNote: "Wide radiator — check available wall run. Ensure no obstructions at either end."
        ),
        ApplianceProfile(
            id: "radiator_double_panel",
            category: .radiator,
            family: "Double Panel Radiator",
            displayName: "Double panel radiator",
            rule: ClearanceRule(
                footprintWidthMetres:   0.60,
                footprintDepthMetres:   0.18,
                installMinFrontMetres:  0.03,
                frontClearanceMetres:   0.05,
                sideClearanceMetres:    0.05,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.50
            ),
            guidanceNote: "Double panel — deeper than standard. Check against furniture and window sill depth."
        ),
    ]
}
