import Foundation

// MARK: - AtlasVec3V1
//
// A 3-D world-space vector used in spatial evidence contracts.
// Coordinate convention: metres, right-handed Y-up (same as RoomPlan / ARKit).

/// A 3-D world-space point or direction in metres.
public struct AtlasVec3V1: Codable, Sendable, Equatable {

    /// X component (metres, rightward).
    public let x: Double

    /// Y component (metres, upward).
    public let y: Double

    /// Z component (metres, outward / depth).
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: - SpatialEvidence3D
//
// Evidence record for an indoor RoomPlan room scan.
//
// Design rules:
//   • This is evidence only — no derived maths may be performed from the asset.
//   • AtlasRoomV1 (heat-loss canonical model) must NOT be mutated from this record.
//   • The heavy asset (USDZ / GLB) is stored externally; only the URL is carried here.
//   • All fields are optional except `id`, `propertyID`, `sourceSessionId`,
//     `kind`, and `format` so that partially-captured evidence can still be
//     persisted and displayed.

/// An indoor room-scan evidence record produced by RoomPlan capture.
///
/// Stores a reference to the 3-D model file (USDZ / GLB / RealityKit) together
/// with preview and spatial metadata so downstream surfaces (engineer portal,
/// reports) can show the evidence without parsing raw geometry.
public struct SpatialEvidence3D: Codable, Sendable {

    // MARK: Identity

    /// UUID of this evidence record.
    public let id: String

    /// UUID of the property session this evidence belongs to.
    public let propertyID: String

    /// UUID of the scan capture session that produced this asset.
    public let sourceSessionId: String

    // MARK: Type discriminator

    /// Always `"internal_room_scan"` for this type.
    public let kind: String

    // MARK: Asset references

    /// Asset format hint: `"usdz"` | `"glb"` | `"realitykit"`.
    public let format: String

    /// URL of the 3-D model file (may be a local file URL or a remote URL after upload).
    public let fileUrl: String

    /// URL of a preview thumbnail image. Nil when not yet generated.
    public let previewImageUrl: String?

    // MARK: Linkage

    /// UUIDs of rooms this scan is linked to. May be empty when the link is not yet set.
    public let linkedRoomIds: [String]

    /// UUIDs of zones (floor-plan zones, heat-loss zones) this scan is linked to.
    public let linkedZoneIds: [String]

    // MARK: Spatial bounds

    /// Approximate axis-aligned bounding box of the captured room in metres.
    /// Nil when bounds were not available at capture time.
    public let bounds: Bounds?

    // MARK: Capture metadata

    /// Device and capture provenance metadata.
    public let captureMeta: CaptureMeta?

    // MARK: Init

    public init(
        id: String,
        propertyID: String,
        sourceSessionId: String,
        kind: String = "internal_room_scan",
        format: String,
        fileUrl: String,
        previewImageUrl: String? = nil,
        linkedRoomIds: [String] = [],
        linkedZoneIds: [String] = [],
        bounds: Bounds? = nil,
        captureMeta: CaptureMeta? = nil
    ) {
        self.id = id
        self.propertyID = propertyID
        self.sourceSessionId = sourceSessionId
        self.kind = kind
        self.format = format
        self.fileUrl = fileUrl
        self.previewImageUrl = previewImageUrl
        self.linkedRoomIds = linkedRoomIds
        self.linkedZoneIds = linkedZoneIds
        self.bounds = bounds
        self.captureMeta = captureMeta
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case propertyID
        case propertyId
        case sourceSessionId
        case kind
        case format
        case fileUrl
        case previewImageUrl
        case linkedRoomIds
        case linkedZoneIds
        case bounds
        case captureMeta
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        if let propertyID = try c.decodeIfPresent(String.self, forKey: .propertyID) {
            self.propertyID = propertyID
        } else {
            self.propertyID = try c.decode(String.self, forKey: .propertyId)
        }
        sourceSessionId = try c.decode(String.self, forKey: .sourceSessionId)
        kind = try c.decode(String.self, forKey: .kind)
        format = try c.decode(String.self, forKey: .format)
        fileUrl = try c.decode(String.self, forKey: .fileUrl)
        previewImageUrl = try c.decodeIfPresent(String.self, forKey: .previewImageUrl)
        linkedRoomIds = try c.decodeIfPresent([String].self, forKey: .linkedRoomIds) ?? []
        linkedZoneIds = try c.decodeIfPresent([String].self, forKey: .linkedZoneIds) ?? []
        bounds = try c.decodeIfPresent(Bounds.self, forKey: .bounds)
        captureMeta = try c.decodeIfPresent(CaptureMeta.self, forKey: .captureMeta)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(propertyID, forKey: .propertyID)
        try c.encode(sourceSessionId, forKey: .sourceSessionId)
        try c.encode(kind, forKey: .kind)
        try c.encode(format, forKey: .format)
        try c.encode(fileUrl, forKey: .fileUrl)
        try c.encodeIfPresent(previewImageUrl, forKey: .previewImageUrl)
        try c.encode(linkedRoomIds, forKey: .linkedRoomIds)
        try c.encode(linkedZoneIds, forKey: .linkedZoneIds)
        try c.encodeIfPresent(bounds, forKey: .bounds)
        try c.encodeIfPresent(captureMeta, forKey: .captureMeta)
    }
}

// MARK: - SpatialEvidence3D.Bounds

extension SpatialEvidence3D {

    /// Axis-aligned bounding dimensions of the captured room in metres.
    public struct Bounds: Codable, Sendable {
        /// Room width (x-axis) in metres.
        public let width: Double
        /// Room length (z-axis / depth) in metres.
        public let length: Double
        /// Room height (y-axis) in metres.
        public let height: Double

        public init(width: Double, length: Double, height: Double) {
            self.width = width
            self.length = length
            self.height = height
        }
    }
}

// MARK: - SpatialEvidence3D.CaptureMeta

extension SpatialEvidence3D {

    /// Provenance metadata recorded at capture time.
    public struct CaptureMeta: Codable, Sendable {
        /// Device hardware model string (e.g. `"iPhone 15 Pro"`).
        public let device: String
        /// ISO-8601 timestamp of when the scan was captured.
        public let timestamp: String
        /// Overall scan confidence (0–1), where available.
        public let confidence: Double?

        public init(device: String, timestamp: String, confidence: Double? = nil) {
            self.device = device
            self.timestamp = timestamp
            self.confidence = confidence
        }
    }
}

// MARK: - ExternalClearanceSceneV1
//
// Evidence record for an outdoor flue-clearance AR capture session.
//
// Design rules:
//   • Compliance logic must run from `measurements` and `nearbyFeatures`, NOT
//     from raw point-cloud or mesh geometry.
//   • The `evidence.pointCloudUrl` / `evidence.modelUrl` fields are optional
//     raw-geometry evidence assets only — they must not be used in report rendering
//     or deterministic compliance decisions.
//   • All 3-D position fields are world-space metres (ARKit right-handed Y-up).

/// An outdoor AR scene capturing flue-terminal position, nearby compliance features,
/// and measured clearance distances.
///
/// Produces a structured compliance record that downstream surfaces (engineer portal,
/// reports) can display as a preview image + structured measurement table without
/// ever parsing 3-D geometry.
public struct ExternalClearanceSceneV1: Codable, Sendable {

    // MARK: Identity

    /// UUID of this clearance scene record.
    public let id: String

    /// UUID of the property session this scene belongs to.
    public let propertyID: String

    /// UUID of the AR capture session that produced this scene.
    public let sourceSessionId: String

    /// Always `"external_flue_clearance"` for this type.
    public let kind: String

    // MARK: Evidence assets (optional heavy blobs — evidence only)

    /// References to raw capture evidence files.  All fields are optional
    /// because heavy assets may not be available offline or in all report contexts.
    public let evidence: Evidence

    // MARK: Flue terminal

    /// Position and orientation of the flue terminal in world space.
    /// Nil when the engineer has not yet placed the terminal marker.
    public let flueTerminal: FlueTerminal?

    // MARK: Nearby features

    /// Tagged features near the flue terminal (windows, doors, air bricks, etc.).
    public let nearbyFeatures: [NearbyFeature]

    // MARK: Measurements

    /// Structured measurements from the terminal to nearby features or boundaries.
    /// Compliance logic runs from this array.
    public let measurements: [ClearanceMeasurementV1]

    // MARK: Compliance summary

    /// Overall compliance summary derived from `measurements` and `nearbyFeatures`.
    /// Nil when the scene has not been evaluated against a standard.
    public let compliance: ComplianceSummary?

    // MARK: Init

    public init(
        id: String,
        propertyID: String,
        sourceSessionId: String,
        kind: String = "external_flue_clearance",
        evidence: Evidence = Evidence(),
        flueTerminal: FlueTerminal? = nil,
        nearbyFeatures: [NearbyFeature] = [],
        measurements: [ClearanceMeasurementV1] = [],
        compliance: ComplianceSummary? = nil
    ) {
        self.id = id
        self.propertyID = propertyID
        self.sourceSessionId = sourceSessionId
        self.kind = kind
        self.evidence = evidence
        self.flueTerminal = flueTerminal
        self.nearbyFeatures = nearbyFeatures
        self.measurements = measurements
        self.compliance = compliance
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case propertyID
        case propertyId
        case sourceSessionId
        case kind
        case evidence
        case flueTerminal
        case nearbyFeatures
        case measurements
        case compliance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        if let propertyID = try c.decodeIfPresent(String.self, forKey: .propertyID) {
            self.propertyID = propertyID
        } else {
            self.propertyID = try c.decode(String.self, forKey: .propertyId)
        }
        sourceSessionId = try c.decode(String.self, forKey: .sourceSessionId)
        kind = try c.decode(String.self, forKey: .kind)
        evidence = try c.decode(Evidence.self, forKey: .evidence)
        flueTerminal = try c.decodeIfPresent(FlueTerminal.self, forKey: .flueTerminal)
        nearbyFeatures = try c.decodeIfPresent([NearbyFeature].self, forKey: .nearbyFeatures) ?? []
        measurements = try c.decodeIfPresent([ClearanceMeasurementV1].self, forKey: .measurements) ?? []
        compliance = try c.decodeIfPresent(ComplianceSummary.self, forKey: .compliance)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(propertyID, forKey: .propertyID)
        try c.encode(sourceSessionId, forKey: .sourceSessionId)
        try c.encode(kind, forKey: .kind)
        try c.encode(evidence, forKey: .evidence)
        try c.encodeIfPresent(flueTerminal, forKey: .flueTerminal)
        try c.encode(nearbyFeatures, forKey: .nearbyFeatures)
        try c.encode(measurements, forKey: .measurements)
        try c.encodeIfPresent(compliance, forKey: .compliance)
    }
}

// MARK: - ExternalClearanceSceneV1.Evidence

extension ExternalClearanceSceneV1 {

    /// Optional raw evidence asset URLs.  Not used for compliance logic.
    public struct Evidence: Codable, Sendable {
        /// URL of a preview / hero image captured during the session.
        public let previewImageUrl: String?
        /// URL of a 3-D scene mesh or USDZ export (optional evidence).
        public let modelUrl: String?
        /// URL of a raw point-cloud export (optional evidence).
        public let pointCloudUrl: String?

        public init(
            previewImageUrl: String? = nil,
            modelUrl: String? = nil,
            pointCloudUrl: String? = nil
        ) {
            self.previewImageUrl = previewImageUrl
            self.modelUrl = modelUrl
            self.pointCloudUrl = pointCloudUrl
        }
    }
}

// MARK: - ExternalClearanceSceneV1.FlueTerminal

extension ExternalClearanceSceneV1 {

    /// World-space position and orientation of the flue terminal.
    public struct FlueTerminal: Codable, Sendable {
        /// World-space position of the terminal (metres, ARKit Y-up).
        public let position3D: AtlasVec3V1?
        /// Outward normal vector of the terminal opening.
        public let normal: AtlasVec3V1?
        /// Measured height of the terminal above ground level in metres.
        public let heightAboveGroundM: Double?

        public init(
            position3D: AtlasVec3V1? = nil,
            normal: AtlasVec3V1? = nil,
            heightAboveGroundM: Double? = nil
        ) {
            self.position3D = position3D
            self.normal = normal
            self.heightAboveGroundM = heightAboveGroundM
        }
    }
}

// MARK: - ExternalClearanceSceneV1.NearbyFeature

extension ExternalClearanceSceneV1 {

    /// A tagged feature near the flue terminal that may affect clearance compliance.
    public struct NearbyFeature: Codable, Sendable, Identifiable {
        /// UUID of this feature record.
        public let id: String
        /// Feature classification.
        public let type: FeatureType
        /// World-space position of the feature (metres, ARKit Y-up). Nil when not measured.
        public let position3D: AtlasVec3V1?
        /// Shortest measured distance from the flue terminal to this feature in metres.
        public let distanceToTerminalM: Double?
        /// Free-text engineer notes about this feature.
        public let notes: String?

        public init(
            id: String,
            type: FeatureType,
            position3D: AtlasVec3V1? = nil,
            distanceToTerminalM: Double? = nil,
            notes: String? = nil
        ) {
            self.id = id
            self.type = type
            self.position3D = position3D
            self.distanceToTerminalM = distanceToTerminalM
            self.notes = notes
        }
    }

    /// Classification of a nearby compliance feature.
    public enum FeatureType: String, Codable, Sendable, CaseIterable {
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

        /// Human-readable display name.
        public var displayName: String {
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

        /// SF Symbol name for this feature type.
        public var symbolName: String {
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
    }
}

// MARK: - ClearanceMeasurementV1

/// A single measured clearance distance between the flue terminal and a reference
/// point, feature, or boundary.
///
/// Compliance logic must derive pass/fail from this type's `valueM` and `kind`.
/// Raw geometry must not be parsed to determine compliance.
public struct ClearanceMeasurementV1: Codable, Sendable, Identifiable {

    /// UUID of this measurement record.
    public let id: String

    /// The kind of measurement taken.
    public let kind: MeasurementKind

    /// Measured distance in metres.
    public let valueM: Double

    /// How the measurement was obtained.
    public let source: MeasurementSource

    public init(id: String, kind: MeasurementKind, valueM: Double, source: MeasurementSource) {
        self.id = id
        self.kind = kind
        self.valueM = valueM
        self.source = source
    }

    /// The kind of clearance measurement.
    public enum MeasurementKind: String, Codable, Sendable {
        case terminalToOpening  = "terminal_to_opening"
        case terminalToBoundary = "terminal_to_boundary"
        case terminalToEaves    = "terminal_to_eaves"

        /// Human-readable display name.
        public var displayName: String {
            switch self {
            case .terminalToOpening:  return "Terminal → Opening"
            case .terminalToBoundary: return "Terminal → Boundary"
            case .terminalToEaves:    return "Terminal → Eaves"
            }
        }
    }

    /// How a measurement value was obtained.
    public enum MeasurementSource: String, Codable, Sendable {
        /// Directly measured by the ARKit session raycasts or AR anchors.
        case measured = "measured"
        /// Derived or estimated from other measured values.
        case derived  = "derived"
    }
}

// MARK: - ExternalClearanceSceneV1.ComplianceSummary

extension ExternalClearanceSceneV1 {

    /// Overall compliance assessment derived from structured measurements.
    ///
    /// This is always computed from `measurements` and `nearbyFeatures` — never
    /// from raw point-cloud or mesh geometry.
    public struct ComplianceSummary: Codable, Sendable {
        /// Reference standard used for evaluation (e.g. `"BS 5440"`).
        public let standardRef: String?
        /// Human-readable warnings raised during evaluation.
        public let warnings: [String]
        /// `true` when all measurements pass the referenced standard.
        /// `nil` when evaluation has not been completed.
        public let pass: Bool?

        public init(standardRef: String? = nil, warnings: [String] = [], pass: Bool? = nil) {
            self.standardRef = standardRef
            self.warnings = warnings
            self.pass = pass
        }
    }
}
