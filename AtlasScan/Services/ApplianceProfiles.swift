import Foundation
import AtlasContracts

// MARK: - ApplianceProfile

/// A named appliance profile providing model-specific clearance dimensions
/// for use in ClearanceEngine evaluations.
///
/// Profiles represent practical appliance families (e.g., compact combi, slim cylinder).
/// They are not full manufacturer records — dimensions are approximate guidance only.
///
/// Architecture: `ApplianceProfile` is a lightweight app-side projection of an
/// `ApplianceDefinitionV1` from the shared AtlasContracts registry.  All
/// authoritative data originates in `MasterHardwareRegistry`; this type is a
/// convenience wrapper that satisfies existing `ClearanceEngine` and UI call sites.
struct ApplianceProfile: Identifiable {

    /// Stable identifier stored in a capture session's appliance profile ID field.
    /// Matches `ApplianceDefinitionV1.modelId`.
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

    /// The underlying shared definition this profile was derived from.
    let definition: ApplianceDefinitionV1
}

// MARK: - ApplianceProfile init from ApplianceDefinitionV1

extension ApplianceProfile {

    /// Creates an `ApplianceProfile` from a shared `ApplianceDefinitionV1`.
    ///
    /// - Parameters:
    ///   - definition: The contract-level appliance definition.
    ///   - category: The resolved `ServiceObjectCategory`; caller must verify
    ///     that `definition.category` maps to a known category before passing.
    init?(definition: ApplianceDefinitionV1, category: ServiceObjectCategory) {
        self.id = definition.modelId
        self.category = category
        self.family = definition.family
        self.displayName = definition.displayName
        self.guidanceNote = definition.guidanceNote
        self.definition = definition
        self.rule = ClearanceRule(
            footprintWidthMetres:   definition.dimensions.widthM,
            footprintDepthMetres:   definition.dimensions.depthM,
            installMinFrontMetres:  definition.clearanceRules.installMinFrontM,
            frontClearanceMetres:   definition.clearanceRules.frontM,
            sideClearanceMetres:    definition.clearanceRules.sideM,
            rearClearanceMetres:    definition.clearanceRules.rearM,
            minCeilingHeightMetres: definition.clearanceRules.minCeilingHeightM
        )
    }
}

// MARK: - ApplianceProfileLibrary

/// Library of practical appliance profiles for ClearanceEngine and picker UI.
///
/// All profiles are derived from `MasterHardwareRegistry` in AtlasContracts,
/// ensuring the iOS app and Atlas Mind PWA share a single source of truth for
/// appliance dimensions.
///
/// A runtime registry merged with a `HardwarePatchV1` (received in a
/// `VisitHandoffPackV1`) can be applied via `ApplianceProfileLibrary.apply(patch:)`
/// to extend or override the static profiles for a specific visit.
enum ApplianceProfileLibrary {

    // MARK: - Runtime registry

    /// Current merged registry (static master + any applied patch).
    private(set) static var currentRegistry: HardwareRegistryV1 = MasterHardwareRegistry.registry

    /// Applies a hardware patch received from Atlas Mind, merging its overrides
    /// and additions into the runtime registry.  Call this once per visit, after
    /// decoding the incoming `VisitHandoffPackV1`.
    static func apply(patch: HardwarePatchV1) {
        currentRegistry = currentRegistry.applying(patch)
        _cachedAll = nil   // invalidate cache
    }

    /// Resets the runtime registry back to the static master.
    static func resetToMaster() {
        currentRegistry = MasterHardwareRegistry.registry
        _cachedAll = nil
    }

    // MARK: - All profiles

    /// All profiles derived from the current runtime registry.
    static var all: [ApplianceProfile] {
        if let cached = _cachedAll { return cached }
        let built = currentRegistry.definitions.values.compactMap { def -> ApplianceProfile? in
            guard let cat = ServiceObjectCategory(rawValue: def.category) else { return nil }
            return ApplianceProfile(definition: def, category: cat)
        }.sorted { lhs, rhs in
            // Sort by family first, then by displayName — matches profiles(for:).
            lhs.family == rhs.family
                ? lhs.displayName < rhs.displayName
                : lhs.family < rhs.family
        }
        _cachedAll = built
        return built
    }

    private static var _cachedAll: [ApplianceProfile]?

    // MARK: - Lookup

    /// Returns all profiles for the given category, sorted by family then display name.
    static func profiles(for category: ServiceObjectCategory) -> [ApplianceProfile] {
        all.filter { $0.category == category }
            .sorted { lhs, rhs in
                lhs.family == rhs.family
                    ? lhs.displayName < rhs.displayName
                    : lhs.family < rhs.family
            }
    }

    /// Returns the profile with the given model identifier, or `nil`.
    static func profile(id: String) -> ApplianceProfile? {
        guard let def = currentRegistry.definition(for: id),
              let cat = ServiceObjectCategory(rawValue: def.category) else { return nil }
        return ApplianceProfile(definition: def, category: cat)
    }

    /// Returns the `ApplianceDefinitionV1` for the given model identifier, or `nil`.
    static func definition(id: String) -> ApplianceDefinitionV1? {
        currentRegistry.definition(for: id)
    }
}
