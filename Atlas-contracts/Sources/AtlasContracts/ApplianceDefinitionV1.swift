import Foundation

// MARK: - ApplianceDefinitionV1
//
// Shared hardware definition for a service appliance (boiler, cylinder, etc.).
//
// This type is the single source of truth for physical dimensions and required
// clearances, owned by the Atlas-contracts repo and consumed by both:
//   • Atlas Scan iOS  — renders the 3D ghost box and evaluates clearance
//   • Atlas Mind PWA  — drives the boiler-sizing / recommendation logic
//
// Dimension units: millimetres (integer) to avoid floating-point round-trip
// errors when the values are stored in a JSON registry or D1 database.
//
// Coordinate convention:
//   width  (W) — left/right when facing the appliance front
//   depth  (D) — front-to-back
//   height (H) — floor-to-ceiling direction
//
// Wire format: JSON, camelCase keys, schemaVersion = 1.

// MARK: - ApplianceDimensionsV1

/// Physical installed envelope of the appliance in millimetres.
public struct ApplianceDimensionsV1: Codable, Sendable, Equatable {

    /// Installed width in millimetres (left–right when facing the front).
    public let widthMm: Int

    /// Installed depth in millimetres (front to back).
    public let depthMm: Int

    /// Installed height in millimetres (floor to top of unit).
    public let heightMm: Int

    public init(widthMm: Int, depthMm: Int, heightMm: Int) {
        self.widthMm = widthMm
        self.depthMm = depthMm
        self.heightMm = heightMm
    }
}

// MARK: - ApplianceClearanceRulesV1

/// Required service and installation clearances around the appliance, in millimetres.
///
/// These represent the working space that must be kept free:
///   • `installMinFrontMm` — tightest front gap for physical installation (fit in place).
///   • `frontMm`           — full service-access space (engineer must be able to work).
///   • `sideMm`            — required on each side (symmetric).
///   • `rearMm`            — space behind the unit (often zero for wall-back installs).
///   • `topMm`             — space above the unit (flue, wiring, access).
///   • `minCeilingHeightMm`— minimum room ceiling height for safe installation.
public struct ApplianceClearanceRulesV1: Codable, Sendable, Equatable {

    /// Minimum front clearance that permits physical installation.
    public let installMinFrontMm: Int

    /// Full service-access clearance required in front of the appliance.
    public let frontMm: Int

    /// Required clearance on each side of the appliance.
    public let sideMm: Int

    /// Required clearance behind the appliance (zero for wall-back installs).
    public let rearMm: Int

    /// Required clearance above the appliance.
    public let topMm: Int

    /// Minimum room ceiling height for safe installation and servicing.
    public let minCeilingHeightMm: Int

    public init(
        installMinFrontMm: Int,
        frontMm: Int,
        sideMm: Int,
        rearMm: Int,
        topMm: Int,
        minCeilingHeightMm: Int
    ) {
        self.installMinFrontMm = installMinFrontMm
        self.frontMm = frontMm
        self.sideMm = sideMm
        self.rearMm = rearMm
        self.topMm = topMm
        self.minCeilingHeightMm = minCeilingHeightMm
    }
}

// MARK: - ApplianceDefinitionV1

/// Contract-level definition of a single appliance model or family.
///
/// Stable, versioned, and shared between Atlas Scan (iOS) and Atlas Mind (PWA).
/// The `modelId` is the durable key used to reference a definition across systems.
///
/// Definitions originate from two sources:
///   • `"static"`  — shipped in the `MasterHardwareRegistry` bundled with the contract.
///   • `"patch"`   — supplied at runtime via `HardwarePatchV1` in a `VisitHandoffPackV1`.
public struct ApplianceDefinitionV1: Codable, Sendable, Identifiable, Equatable {

    // MARK: Schema identity

    /// Contract schema version; always `1` for this generation.
    public let schemaVersion: Int

    // MARK: Identity

    /// Durable machine-readable identifier.
    ///
    /// Format: `<brand_slug>_<model_slug>`, e.g. `worcester_4000_combi_30`.
    /// Must be stable across registries and patches (used as a join key).
    public let modelId: String

    /// Manufacturer / brand name (human readable), e.g. `"Worcester Bosch"`.
    public let brand: String

    /// Short family name used as a grouping header in pickers, e.g. `"Combi Boiler"`.
    public let family: String

    /// Full human-readable model name, e.g. `"4000 Series Combi 30kW"`.
    public let displayName: String

    /// Service category matching `ServiceObjectCategory.rawValue`
    /// (e.g. `"boiler"`, `"cylinder"`, `"radiator"`).
    public let category: String

    // MARK: Physical specification

    /// Physical installed envelope of the appliance.
    public let dimensions: ApplianceDimensionsV1

    /// Required service and installation clearances.
    public let clearanceRules: ApplianceClearanceRulesV1

    // MARK: Metadata

    /// Optional plain-English note surfaced alongside the clearance result.
    /// Hedged wording — not a compliance statement.
    public let guidanceNote: String?

    /// Origin of this definition: `"static"` (master registry) or `"patch"` (Mind override).
    public let source: String

    // MARK: Identifiable

    public var id: String { modelId }

    // MARK: Init

    public init(
        modelId: String,
        brand: String,
        family: String,
        displayName: String,
        category: String,
        dimensions: ApplianceDimensionsV1,
        clearanceRules: ApplianceClearanceRulesV1,
        guidanceNote: String? = nil,
        source: String = "static"
    ) {
        self.schemaVersion = 1
        self.modelId = modelId
        self.brand = brand
        self.family = family
        self.displayName = displayName
        self.category = category
        self.dimensions = dimensions
        self.clearanceRules = clearanceRules
        self.guidanceNote = guidanceNote
        self.source = source
    }
}

// MARK: - Metric helpers

public extension ApplianceDimensionsV1 {
    /// Installed width in metres (derived from `widthMm`).
    var widthM: Double { Double(widthMm) / 1_000 }
    /// Installed depth in metres (derived from `depthMm`).
    var depthM: Double { Double(depthMm) / 1_000 }
    /// Installed height in metres (derived from `heightMm`).
    var heightM: Double { Double(heightMm) / 1_000 }
}

public extension ApplianceClearanceRulesV1 {
    /// Minimum front clearance in metres.
    var installMinFrontM: Double { Double(installMinFrontMm) / 1_000 }
    /// Full service-access front clearance in metres.
    var frontM: Double { Double(frontMm) / 1_000 }
    /// Side clearance in metres.
    var sideM: Double { Double(sideMm) / 1_000 }
    /// Rear clearance in metres.
    var rearM: Double { Double(rearMm) / 1_000 }
    /// Top clearance in metres.
    var topM: Double { Double(topMm) / 1_000 }
    /// Minimum ceiling height in metres.
    var minCeilingHeightM: Double { Double(minCeilingHeightMm) / 1_000 }
}
