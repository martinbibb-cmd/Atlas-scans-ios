/// HardwareRegistryV1 — Central database of boiler / heat-pump dimensions used
/// to drive the AR "Ghost Box" clearance volumes.
///
/// All measurements are in metric metres.

import Foundation

// MARK: - Clearance envelope (manufacturer-specified)

public struct ClearanceEnvelopeV1: Codable, Sendable {
    public let topM: Double
    public let bottomM: Double
    public let frontM: Double
    public let backM: Double
    public let leftM: Double
    public let rightM: Double

    public init(
        topM: Double,
        bottomM: Double,
        frontM: Double,
        backM: Double,
        leftM: Double,
        rightM: Double
    ) {
        self.topM = topM
        self.bottomM = bottomM
        self.frontM = frontM
        self.backM = backM
        self.leftM = leftM
        self.rightM = rightM
    }

    /// Minimum regulatory clearance (used when no manufacturer data exists).
    public static let regulatoryMinimum = ClearanceEnvelopeV1(
        topM: 0.025,
        bottomM: 0.025,
        frontM: 0.600,
        backM: 0.025,
        leftM: 0.025,
        rightM: 0.025
    )
}

// MARK: - Hardware type

public enum HardwareType: String, Codable, CaseIterable, Sendable {
    case boiler
    case heatPump
    case hotWaterCylinder
    case pressureVessel
}

// MARK: - Boiler / heat-pump specification

public struct HardwareSpecV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let type: HardwareType
    public let manufacturer: String
    public let modelName: String
    public let modelCode: String?

    // Physical dimensions (metres)
    public let widthM: Double
    public let heightM: Double
    public let depthM: Double

    // Manufacturer-specified clearances
    public let clearances: ClearanceEnvelopeV1

    // Ghost-box total volume (footprint + all clearances)
    public var ghostBoxWidthM:  Double { widthM  + clearances.leftM  + clearances.rightM  }
    public var ghostBoxHeightM: Double { heightM + clearances.topM   + clearances.bottomM }
    public var ghostBoxDepthM:  Double { depthM  + clearances.frontM + clearances.backM   }

    public init(
        id: UUID = UUID(),
        type: HardwareType,
        manufacturer: String,
        modelName: String,
        modelCode: String? = nil,
        widthM: Double,
        heightM: Double,
        depthM: Double,
        clearances: ClearanceEnvelopeV1
    ) {
        self.id = id
        self.type = type
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.modelCode = modelCode
        self.widthM = widthM
        self.heightM = heightM
        self.depthM = depthM
        self.clearances = clearances
    }
}

// MARK: - Registry

public final class HardwareRegistryV1: @unchecked Sendable {

    // Shared singleton backed by the bundled catalogue.
    public static let shared = HardwareRegistryV1(catalogue: .bundled)

    private var entries: [HardwareSpecV1]
    private let lock = NSLock()

    public init(catalogue: Catalogue) {
        self.entries = catalogue.entries
    }

    // MARK: Lookup

    public func spec(for modelCode: String) -> HardwareSpecV1? {
        lock.withLock { entries.first { $0.modelCode?.lowercased() == modelCode.lowercased() } }
    }

    public func specs(manufacturer: String) -> [HardwareSpecV1] {
        lock.withLock { entries.filter { $0.manufacturer.lowercased() == manufacturer.lowercased() } }
    }

    public func allSpecs(ofType type: HardwareType) -> [HardwareSpecV1] {
        lock.withLock { entries.filter { $0.type == type } }
    }

    public func register(_ spec: HardwareSpecV1) {
        lock.withLock {
            entries.removeAll { $0.id == spec.id }
            entries.append(spec)
        }
    }
}

// MARK: - Bundled catalogue

public extension HardwareRegistryV1 {

    struct Catalogue: Sendable {
        public let entries: [HardwareSpecV1]

        /// Factory-default catalogue — 31 baseline UK models.
        public static let bundled = Catalogue(entries: [

            // ── Worcester Bosch ──────────────────────────────────────────────
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Worcester Bosch",
                modelName: "Greenstar 8000 Life 30kW",
                modelCode: "GS8L-30",
                widthM: 0.390, heightM: 0.720, depthM: 0.370,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Worcester Bosch",
                modelName: "Greenstar 4000 25kW",
                modelCode: "GS4-25",
                widthM: 0.380, heightM: 0.700, depthM: 0.360,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Worcester Bosch",
                modelName: "Greenstar 8000 Style 35kW",
                modelCode: "GS8S-35",
                widthM: 0.390, heightM: 0.720, depthM: 0.370,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Worcester Bosch",
                modelName: "Greenstar 2000 24kW",
                modelCode: "GS2-24",
                widthM: 0.380, heightM: 0.698, depthM: 0.360,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Worcester Bosch",
                modelName: "Greenstar CDi Classic 30kW",
                modelCode: "GSCDI-30",
                widthM: 0.390, heightM: 0.720, depthM: 0.370,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Worcester Bosch",
                modelName: "Greenstar i System 30kW",
                modelCode: "GSIS-30",
                widthM: 0.390, heightM: 0.720, depthM: 0.370,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),

            // ── Vaillant ─────────────────────────────────────────────────────
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Vaillant",
                modelName: "ecoTEC plus 30kW",
                modelCode: "VU-306/5-5",
                widthM: 0.440, heightM: 0.720, depthM: 0.338,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.050, bottomM: 0.050,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Vaillant",
                modelName: "ecoTEC pure 25kW",
                modelCode: "VUW-256/7-2",
                widthM: 0.390, heightM: 0.700, depthM: 0.278,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.050, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Vaillant",
                modelName: "ecoTEC pro 28kW",
                modelCode: "VUW-286/5-3",
                widthM: 0.440, heightM: 0.720, depthM: 0.338,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.050, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Vaillant",
                modelName: "ecoFIT pure 30kW",
                modelCode: "VUW-306/7-2",
                widthM: 0.390, heightM: 0.720, depthM: 0.278,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.050, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),

            // ── Ideal Boilers ────────────────────────────────────────────────
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Ideal",
                modelName: "Logic Max Combi 30",
                modelCode: "ILM-C30",
                widthM: 0.380, heightM: 0.690, depthM: 0.350,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Ideal",
                modelName: "Logic Max Combi 24",
                modelCode: "ILM-C24",
                widthM: 0.380, heightM: 0.690, depthM: 0.350,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Ideal",
                modelName: "Logic Plus Combi 30",
                modelCode: "ILP-C30",
                widthM: 0.380, heightM: 0.690, depthM: 0.350,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Ideal",
                modelName: "Vogue Max Combi 32",
                modelCode: "IVM-C32",
                widthM: 0.440, heightM: 0.780, depthM: 0.360,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Ideal",
                modelName: "Vogue Max System 32",
                modelCode: "IVM-S32",
                widthM: 0.440, heightM: 0.780, depthM: 0.360,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),

            // ── Glow-worm ────────────────────────────────────────────────────
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Glow-worm",
                modelName: "Energy Combi 30",
                modelCode: "GW-EC30",
                widthM: 0.390, heightM: 0.700, depthM: 0.280,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Glow-worm",
                modelName: "Energy Combi 25",
                modelCode: "GW-EC25",
                widthM: 0.390, heightM: 0.700, depthM: 0.280,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Glow-worm",
                modelName: "Ultimate 3 30kW",
                modelCode: "GW-U3-30",
                widthM: 0.390, heightM: 0.700, depthM: 0.280,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Glow-worm",
                modelName: "Energy System 30",
                modelCode: "GW-ES30",
                widthM: 0.390, heightM: 0.700, depthM: 0.280,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Glow-worm",
                modelName: "Betacom 4 30C",
                modelCode: "GW-B4-30C",
                widthM: 0.390, heightM: 0.700, depthM: 0.280,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),

            // ── Viessmann ────────────────────────────────────────────────────
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Viessmann",
                modelName: "Vitodens 100-W 26kW",
                modelCode: "B1HF-26",
                widthM: 0.400, heightM: 0.700, depthM: 0.350,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.700, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Viessmann",
                modelName: "Vitodens 100-W 35kW",
                modelCode: "B1HF-35",
                widthM: 0.400, heightM: 0.700, depthM: 0.350,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.700, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Viessmann",
                modelName: "Vitodens 200-W 35kW",
                modelCode: "B2HF-35",
                widthM: 0.450, heightM: 0.850, depthM: 0.350,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.700, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Viessmann",
                modelName: "Vitodens 111-W 35kW",
                modelCode: "B1LD-35",
                widthM: 0.600, heightM: 1.820, depthM: 0.600,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.100, bottomM: 0.025,
                    frontM: 0.700, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),

            // ── Heat pumps ───────────────────────────────────────────────────
            HardwareSpecV1(
                type: .heatPump,
                manufacturer: "Vaillant",
                modelName: "aroTHERM plus 7kW",
                modelCode: "VWL-7-5AS",
                widthM: 1.100, heightM: 1.255, depthM: 0.470,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.500, bottomM: 0.100,
                    frontM: 1.000, backM: 0.200,
                    leftM: 0.200, rightM: 0.200
                )
            ),
            HardwareSpecV1(
                type: .heatPump,
                manufacturer: "Vaillant",
                modelName: "aroTHERM plus 12kW",
                modelCode: "VWL-12-5AS",
                widthM: 1.200, heightM: 1.350, depthM: 0.530,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.500, bottomM: 0.100,
                    frontM: 1.000, backM: 0.200,
                    leftM: 0.200, rightM: 0.200
                )
            ),
            HardwareSpecV1(
                type: .heatPump,
                manufacturer: "Mitsubishi Electric",
                modelName: "Ecodan 8.5kW ASHP",
                modelCode: "PUHZ-SW85VHA",
                widthM: 0.940, heightM: 1.390, depthM: 0.380,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.300, bottomM: 0.100,
                    frontM: 0.600, backM: 0.050,
                    leftM: 0.100, rightM: 0.100
                )
            ),
            HardwareSpecV1(
                type: .heatPump,
                manufacturer: "Worcester Bosch",
                modelName: "Compress 7000i AW 7kW",
                modelCode: "WB-C7K-7",
                widthM: 1.060, heightM: 1.080, depthM: 0.390,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.500, bottomM: 0.100,
                    frontM: 1.000, backM: 0.200,
                    leftM: 0.300, rightM: 0.300
                )
            ),

            // ── Hot water cylinders ──────────────────────────────────────────
            HardwareSpecV1(
                type: .hotWaterCylinder,
                manufacturer: "Gledhill",
                modelName: "StainlessLite Plus 210L",
                modelCode: "SLP-210",
                widthM: 0.550, heightM: 1.380, depthM: 0.550,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.300, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .hotWaterCylinder,
                manufacturer: "Megaflo",
                modelName: "Eco 125i Unvented",
                modelCode: "MF-ECO-125I",
                widthM: 0.440, heightM: 1.250, depthM: 0.440,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.300, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .hotWaterCylinder,
                manufacturer: "Ideal",
                modelName: "Tribune XE 150L",
                modelCode: "ITB-XE-150",
                widthM: 0.450, heightM: 1.300, depthM: 0.450,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.300, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            )
        ])
    }
}
