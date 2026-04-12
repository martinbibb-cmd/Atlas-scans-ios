import Foundation
import simd
import AtlasContracts

// MARK: - ExternalClearanceScene
//
// Local (offline-first) model for an outdoor flue-clearance AR capture session.
// Mirrors AtlasContracts.ExternalClearanceSceneV1 for the canonical handoff.
//
// Design rules:
//   • Compliance must be evaluated from `measurements` and `nearbyFeatures` only.
//   • `rawMeshURL` and `pointCloudURL` are optional evidence assets — they must
//     not be parsed for compliance decisions or report rendering.
//   • All heavy assets live on-device at local URLs; metadata is Codable / Sendable.
//   • Block survey / report flow must not depend on this scene being present.

/// An outdoor AR scene capturing flue-terminal position, tagged compliance features,
/// and measured clearance distances.
struct ExternalClearanceScene: Identifiable, Codable, Equatable {

    // MARK: Identity

    var id: UUID

    /// UUID of the originating `PropertyScanSession`.
    var propertySessionID: UUID

    /// Stable identifier for the AR capture session that produced this record.
    var captureSessionID: UUID

    // MARK: Evidence asset URLs (optional heavy blobs)

    /// Local file URL string for a preview / hero image.
    var previewImageURLString: String?

    /// Local file URL string for an optional 3-D mesh / USDZ export (evidence only).
    var rawMeshURLString: String?

    /// Local file URL string for an optional point-cloud export (evidence only).
    var pointCloudURLString: String?

    // MARK: Flue terminal

    /// Measured position and orientation of the flue terminal.
    /// Nil until the engineer has placed the terminal anchor.
    var flueTerminal: FlueTerminalCapture?

    // MARK: Nearby features

    /// Tagged features near the flue terminal (openings, boundaries, obstacles).
    var nearbyFeatures: [NearbyFeatureCapture]

    // MARK: Measurements

    /// Structured measured distances between the terminal and nearby features.
    /// Compliance logic must use this array, not raw geometry.
    var measurements: [ClearanceMeasurementCapture]

    // MARK: Compliance

    /// Compliance summary derived from `measurements` and `nearbyFeatures`.
    /// Nil until the scene has been evaluated.
    var compliance: ComplianceSummaryCapture?

    // MARK: Timestamps

    var createdAt: Date
    var updatedAt: Date

    // MARK: Init

    init(
        id: UUID = UUID(),
        propertySessionID: UUID,
        captureSessionID: UUID,
        previewImageURLString: String? = nil,
        rawMeshURLString: String? = nil,
        pointCloudURLString: String? = nil,
        flueTerminal: FlueTerminalCapture? = nil,
        nearbyFeatures: [NearbyFeatureCapture] = [],
        measurements: [ClearanceMeasurementCapture] = [],
        compliance: ComplianceSummaryCapture? = nil
    ) {
        self.id = id
        self.propertySessionID = propertySessionID
        self.captureSessionID = captureSessionID
        self.previewImageURLString = previewImageURLString
        self.rawMeshURLString = rawMeshURLString
        self.pointCloudURLString = pointCloudURLString
        self.flueTerminal = flueTerminal
        self.nearbyFeatures = nearbyFeatures
        self.measurements = measurements
        self.compliance = compliance
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - FlueTerminalCapture

/// World-space position and orientation of the flue terminal anchor.
struct FlueTerminalCapture: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double
    var normalX: Double?
    var normalY: Double?
    var normalZ: Double?
    var heightAboveGroundM: Double?
}

// MARK: - NearbyFeatureCapture

/// A tagged compliance feature near the flue terminal.
struct NearbyFeatureCapture: Identifiable, Codable, Equatable {

    var id: UUID

    /// The type of compliance feature.
    var kind: ClearanceFeatureKind

    /// World-space x position in metres (ARKit coordinate space).
    var x: Double?
    /// World-space y position in metres.
    var y: Double?
    /// World-space z position in metres.
    var z: Double?

    /// Shortest measured distance from the terminal to this feature in metres.
    /// Computed by `ExternalFlueCaptureSession` from the world positions.
    var distanceToTerminalM: Double?

    /// Free-text engineer notes about this feature.
    var notes: String?

    init(
        id: UUID = UUID(),
        kind: ClearanceFeatureKind,
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil,
        distanceToTerminalM: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.z = z
        self.distanceToTerminalM = distanceToTerminalM
        self.notes = notes
    }
}

// MARK: - ClearanceFeatureKind

/// Classification of a nearby compliance feature.
enum ClearanceFeatureKind: String, Codable, CaseIterable {
    case window         = "window"
    case door           = "door"
    case airBrick       = "air_brick"
    case boundary       = "boundary"
    case eaves          = "eaves"
    case gutter         = "gutter"
    case soilStack      = "soil_stack"
    case opening        = "opening"
    case adjacentFlue   = "adjacent_flue"
    case balcony        = "balcony"

    var displayName: String {
        switch self {
        case .window:       return "Window"
        case .door:         return "Door"
        case .airBrick:     return "Air Brick"
        case .boundary:     return "Boundary"
        case .eaves:        return "Eaves"
        case .gutter:       return "Gutter"
        case .soilStack:    return "Soil Stack"
        case .opening:      return "Opening"
        case .adjacentFlue: return "Adjacent Flue"
        case .balcony:      return "Balcony"
        }
    }

    var symbolName: String {
        switch self {
        case .window:       return "rectangle.split.3x1"
        case .door:         return "door.left.hand.closed"
        case .airBrick:     return "square.grid.3x3.fill"
        case .boundary:     return "square.dashed"
        case .eaves:        return "house.lodge"
        case .gutter:       return "arrow.down.to.line"
        case .soilStack:    return "pipe.and.drop"
        case .opening:      return "rectangle.open.below.fill"
        case .adjacentFlue: return "smoke"
        case .balcony:      return "square.topthird.inset.filled"
        }
    }

    /// Maps to the AtlasContracts `FeatureType` for handoff.
    var contractFeatureType: ExternalClearanceSceneV1.FeatureType {
        switch self {
        case .window:       return .window
        case .door:         return .door
        case .airBrick:     return .airBrick
        case .boundary:     return .boundary
        case .eaves:        return .eaves
        case .gutter:       return .gutter
        case .soilStack:    return .soilStack
        case .opening:      return .opening
        case .adjacentFlue: return .adjacentFlue
        case .balcony:      return .balcony
        }
    }
}

// MARK: - ClearanceMeasurementCapture

/// A single measured clearance distance used for compliance evaluation.
struct ClearanceMeasurementCapture: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: MeasurementKind
    /// Measured distance in metres.
    var valueM: Double
    var source: MeasurementSource

    init(
        id: UUID = UUID(),
        kind: MeasurementKind,
        valueM: Double,
        source: MeasurementSource = .measured
    ) {
        self.id = id
        self.kind = kind
        self.valueM = valueM
        self.source = source
    }

    enum MeasurementKind: String, Codable, CaseIterable {
        case terminalToOpening  = "terminal_to_opening"
        case terminalToBoundary = "terminal_to_boundary"
        case terminalToEaves    = "terminal_to_eaves"

        var displayName: String {
            switch self {
            case .terminalToOpening:  return "Terminal → Opening"
            case .terminalToBoundary: return "Terminal → Boundary"
            case .terminalToEaves:    return "Terminal → Eaves"
            }
        }

        /// Maps to the AtlasContracts measurement kind for handoff.
        var contractKind: ClearanceMeasurementV1.MeasurementKind {
            switch self {
            case .terminalToOpening:  return .terminalToOpening
            case .terminalToBoundary: return .terminalToBoundary
            case .terminalToEaves:    return .terminalToEaves
            }
        }
    }

    enum MeasurementSource: String, Codable {
        case measured = "measured"
        case derived  = "derived"
    }
}

// MARK: - ComplianceSummaryCapture

/// Overall compliance state derived from `measurements` and `nearbyFeatures`.
struct ComplianceSummaryCapture: Codable, Equatable {
    var standardRef: String?
    var warnings: [String]
    var pass: Bool?

    init(standardRef: String? = nil, warnings: [String] = [], pass: Bool? = nil) {
        self.standardRef = standardRef
        self.warnings = warnings
        self.pass = pass
    }
}

// MARK: - AtlasContracts projection

extension ExternalClearanceScene {

    /// Projects this local record to an `ExternalClearanceSceneV1` for Atlas handoff.
    func toExternalClearanceSceneV1() -> ExternalClearanceSceneV1 {
        let evidence = ExternalClearanceSceneV1.Evidence(
            previewImageUrl: previewImageURLString,
            modelUrl: rawMeshURLString,
            pointCloudUrl: pointCloudURLString
        )

        let terminal = flueTerminal.map { t -> ExternalClearanceSceneV1.FlueTerminal in
            let pos = AtlasVec3V1(x: t.x, y: t.y, z: t.z)
            let norm: AtlasVec3V1? = (t.normalX != nil && t.normalY != nil && t.normalZ != nil)
                ? AtlasVec3V1(x: t.normalX!, y: t.normalY!, z: t.normalZ!)
                : nil
            return ExternalClearanceSceneV1.FlueTerminal(
                position3D: pos,
                normal: norm,
                heightAboveGroundM: t.heightAboveGroundM
            )
        }

        let contractFeatures = nearbyFeatures.map { f -> ExternalClearanceSceneV1.NearbyFeature in
            let pos: AtlasVec3V1? = (f.x != nil && f.y != nil && f.z != nil)
                ? AtlasVec3V1(x: f.x!, y: f.y!, z: f.z!)
                : nil
            return ExternalClearanceSceneV1.NearbyFeature(
                id: f.id.uuidString,
                type: f.kind.contractFeatureType,
                position3D: pos,
                distanceToTerminalM: f.distanceToTerminalM,
                notes: f.notes
            )
        }

        let contractMeasurements = measurements.map { m -> ClearanceMeasurementV1 in
            let src: ClearanceMeasurementV1.MeasurementSource =
                m.source == .measured ? .measured : .derived
            return ClearanceMeasurementV1(
                id: m.id.uuidString,
                kind: m.kind.contractKind,
                valueM: m.valueM,
                source: src
            )
        }

        let contractCompliance = compliance.map { c -> ExternalClearanceSceneV1.ComplianceSummary in
            ExternalClearanceSceneV1.ComplianceSummary(
                standardRef: c.standardRef,
                warnings: c.warnings,
                pass: c.pass
            )
        }

        return ExternalClearanceSceneV1(
            id: id.uuidString,
            propertyId: propertySessionID.uuidString,
            sourceSessionId: captureSessionID.uuidString,
            evidence: evidence,
            flueTerminal: terminal,
            nearbyFeatures: contractFeatures,
            measurements: contractMeasurements,
            compliance: contractCompliance
        )
    }
}

// MARK: - Compliance evaluation

extension ExternalClearanceScene {

    /// Evaluates the current measurements against Gas Safe / BS 5440 minimum clearances
    /// and returns an updated `ComplianceSummaryCapture`.
    ///
    /// Minimum clearances (BS 5440 Part 1 / Gas Safe guidance):
    ///   - Terminal to opening (window, door, air brick): 300 mm
    ///   - Terminal to boundary: 600 mm
    ///   - Terminal to eaves / gutter: 300 mm
    ///
    /// This function intentionally uses only `measurements` — raw geometry is
    /// never parsed to derive compliance.
    func evaluateCompliance() -> ComplianceSummaryCapture {
        var warnings: [String] = []
        var pass = true

        for m in measurements {
            switch m.kind {
            case .terminalToOpening:
                if m.valueM < 0.30 {
                    pass = false
                    warnings.append(
                        "Terminal is \(formattedM(m.valueM)) from an opening — minimum 300 mm required (BS 5440)."
                    )
                } else if m.valueM < 0.40 {
                    warnings.append(
                        "Terminal is \(formattedM(m.valueM)) from an opening — marginal; verify with manufacturer spec."
                    )
                }
            case .terminalToBoundary:
                if m.valueM < 0.60 {
                    pass = false
                    warnings.append(
                        "Terminal is \(formattedM(m.valueM)) from a boundary — minimum 600 mm required."
                    )
                }
            case .terminalToEaves:
                if m.valueM < 0.30 {
                    pass = false
                    warnings.append(
                        "Terminal is \(formattedM(m.valueM)) from eaves — minimum 300 mm required (BS 5440)."
                    )
                }
            }
        }

        return ComplianceSummaryCapture(
            standardRef: "BS 5440",
            warnings: warnings,
            pass: measurements.isEmpty ? nil : pass
        )
    }

    private func formattedM(_ value: Double) -> String {
        String(format: "%.0f mm", value * 1000)
    }
}
