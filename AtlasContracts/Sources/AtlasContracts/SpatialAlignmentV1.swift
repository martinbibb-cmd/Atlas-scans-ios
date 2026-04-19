import Foundation

// MARK: - SpatialAlignmentV1
//
// Canonical spatial alignment contract types for Atlas Scan → Atlas Mind handoff.
//
// Design rules:
//   • AtlasSpatialModelV1 carries ONLY captured/confirmed anchor positions and
//     explicitly-flagged inferred routes — no ghost data.
//   • Every inferred element MUST carry a human-readable `reason` string so that
//     downstream consumers can display provenance, not just conclusions.
//   • Confidence values must be set accurately; consumers must NOT render
//     `inferred` positions as confirmed facts.
//   • AtlasWorldPositionV1 is distinct from AtlasVec3V1 because it carries
//     provenance (confidence + source) alongside geometry.
//   • Coordinate convention: metres, right-handed Y-up (ARKit / RoomPlan).

// MARK: - AtlasWorldPositionV1

/// A 3-D world-space position annotated with provenance.
///
/// Used to represent the known or inferred location of a physical object within
/// the site coordinate grid.  All values are in metres using the ARKit right-handed
/// Y-up convention (x = rightward, y = upward, z = outward / depth).
public struct AtlasWorldPositionV1: Codable, Sendable, Equatable {

    // MARK: Geometry

    /// Horizontal position (metres, rightward).
    public let x: Double

    /// Vertical height (metres, upward from floor/origin).
    public let y: Double

    /// Depth position (metres, outward / depth).
    public let z: Double

    // MARK: Provenance

    /// Positional confidence level.
    public let confidence: PositionConfidence

    /// How this position was obtained.
    public let source: PositionSource

    // MARK: Init

    public init(
        x: Double,
        y: Double,
        z: Double,
        confidence: PositionConfidence,
        source: PositionSource
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.confidence = confidence
        self.source = source
    }

    /// Confidence level for a world-space position.
    public enum PositionConfidence: String, Codable, Sendable, CaseIterable {
        /// Measured directly and confirmed by the engineer.
        case confirmed = "confirmed"
        /// Computed or estimated from other confirmed data.
        case inferred  = "inferred"
    }

    /// Method by which a world-space position was captured.
    public enum PositionSource: String, Codable, Sendable, CaseIterable {
        /// Captured via LiDAR depth scan.
        case lidar   = "lidar"
        /// Placed manually by the engineer.
        case manual  = "manual"
        /// Derived algorithmically from other positions.
        case derived = "derived"
    }
}

// MARK: - AtlasAnchorV1

/// A spatially-placed, labelled object anchor within the site coordinate grid.
///
/// Anchors represent known physical objects (boilers, cylinders, consumer units, etc.)
/// whose world-space positions have been captured or confirmed during the survey.
/// Downstream consumers use anchors to compute relative positions, routing estimates,
/// and alignment visualisations.
public struct AtlasAnchorV1: Codable, Sendable, Identifiable {

    /// UUID for this anchor record.
    public let id: String

    /// Human-readable label identifying the object (e.g. "boiler", "cylinder",
    /// "consumer_unit", "radiator").
    public let label: String

    /// World-space position of this anchor.
    public let worldPosition: AtlasWorldPositionV1

    /// UUID of the room this anchor belongs to; nil for anchors not assigned to a room.
    public let roomId: String?

    public init(
        id: String,
        label: String,
        worldPosition: AtlasWorldPositionV1,
        roomId: String? = nil
    ) {
        self.id = id
        self.label = label
        self.worldPosition = worldPosition
        self.roomId = roomId
    }
}

// MARK: - AtlasVerticalRelationV1

/// A vertical spatial relationship between two anchors.
///
/// Captures whether one anchor is above, below, or at the same height as another,
/// and the measured or inferred vertical distance between them.  This is the primary
/// input for vertical stacking analysis and pipe-rise calculations.
public struct AtlasVerticalRelationV1: Codable, Sendable {

    /// UUID of the anchor that is the reference point (the "from" object).
    public let fromAnchorId: String

    /// UUID of the anchor that is being related to the reference (the "to" object).
    public let toAnchorId: String

    /// Vertical distance between the two anchors in metres (always positive).
    public let verticalDistanceM: Double

    /// Directional relationship from `fromAnchorId` to `toAnchorId`.
    public let relation: VerticalRelation

    public init(
        fromAnchorId: String,
        toAnchorId: String,
        verticalDistanceM: Double,
        relation: VerticalRelation
    ) {
        self.fromAnchorId = fromAnchorId
        self.toAnchorId = toAnchorId
        self.verticalDistanceM = verticalDistanceM
        self.relation = relation
    }

    /// Directional relationship between two anchors on the vertical axis.
    public enum VerticalRelation: String, Codable, Sendable, CaseIterable {
        /// The `toAnchor` is above the `fromAnchor`.
        case above      = "above"
        /// The `toAnchor` is below the `fromAnchor`.
        case below      = "below"
        /// Both anchors are at the same height (within measurement tolerance).
        case sameLevel  = "same_level"
    }
}

// MARK: - AtlasInferredRouteV1

/// An algorithmically-inferred service route connecting two or more world-space points.
///
/// Inferred routes are estimates only — they must never be presented to the user
/// as confirmed fact.  Every route carries a `reason` string explaining the
/// inference rationale so that engineers and downstream systems can evaluate
/// plausibility.
///
/// Route path distances are used to derive pipe length estimates for heat-loss,
/// pump head, and install complexity calculations.
public struct AtlasInferredRouteV1: Codable, Sendable, Identifiable {

    /// UUID for this inferred route.
    public let id: String

    /// Service type this route represents.
    public let type: RouteType

    /// Ordered sequence of world-space waypoints defining the route path.
    ///
    /// Consumers should compute total route length as the sum of Euclidean
    /// distances between consecutive waypoints.
    public let path: [AtlasWorldPositionV1]

    /// Always `"inferred"` — reinforces the no-ghost-data rule at the schema level.
    public let confidence: String

    /// Human-readable explanation of how this route was inferred.
    ///
    /// Example: "Aligned kitchen tap + boiler position + standard routing"
    /// Must not be empty.
    public let reason: String

    public init(
        id: String,
        type: RouteType,
        path: [AtlasWorldPositionV1],
        reason: String
    ) {
        self.id = id
        self.type = type
        self.path = path
        self.confidence = "inferred"
        self.reason = reason
    }

    /// Service type for an inferred route.
    public enum RouteType: String, Codable, Sendable, CaseIterable {
        case pipe  = "pipe"
        case cable = "cable"
        case flue  = "flue"
    }
}

// MARK: - AtlasBuildingOriginV1

/// Optional geographic reference origin for the site coordinate grid.
///
/// When present, allows the local site grid to be aligned with real-world
/// geographic coordinates.  Both fields are optional because GPS-quality
/// location may not be available in all capture scenarios.
public struct AtlasBuildingOriginV1: Codable, Sendable, Equatable {

    /// Latitude of the site coordinate origin (WGS-84 decimal degrees), if known.
    public let lat: Double?

    /// Longitude of the site coordinate origin (WGS-84 decimal degrees), if known.
    public let lng: Double?

    public init(lat: Double? = nil, lng: Double? = nil) {
        self.lat = lat
        self.lng = lng
    }
}

// MARK: - AtlasSpatialModelV1

/// The complete spatial alignment model for one property survey.
///
/// Produced by Atlas Scan and consumed by Atlas Mind for alignment
/// visualisations, routing estimates, and install complexity analysis.
///
/// Architecture rules:
///   • `anchors` contains only positions with `confidence = confirmed` or
///     `confidence = inferred` where the source is explicitly known.
///   • `inferredRoutes` must each carry a non-empty `reason` string.
///   • Downstream consumers must visually distinguish confirmed from inferred
///     data (e.g. solid vs dashed lines).
public struct AtlasSpatialModelV1: Codable, Sendable {

    // MARK: Anchors

    /// Tagged object anchors whose world-space positions have been captured
    /// or derived during the survey.
    public let anchors: [AtlasAnchorV1]

    // MARK: Vertical relationships

    /// Explicit vertical relationships between pairs of anchors.
    ///
    /// Computed from the Y-axis difference of their `worldPosition` values.
    /// Nil / empty when no multi-floor relationships have been analysed.
    public let verticalRelations: [AtlasVerticalRelationV1]

    // MARK: Inferred routes

    /// Algorithmically-inferred service routes between anchors.
    ///
    /// Always empty unless route inference has been run.
    /// Each route must carry a non-empty `reason` string.
    public let inferredRoutes: [AtlasInferredRouteV1]

    // MARK: Building origin

    /// Optional geographic reference for the site coordinate grid.
    public let buildingOrigin: AtlasBuildingOriginV1?

    // MARK: Init

    public init(
        anchors: [AtlasAnchorV1] = [],
        verticalRelations: [AtlasVerticalRelationV1] = [],
        inferredRoutes: [AtlasInferredRouteV1] = [],
        buildingOrigin: AtlasBuildingOriginV1? = nil
    ) {
        self.anchors = anchors
        self.verticalRelations = verticalRelations
        self.inferredRoutes = inferredRoutes
        self.buildingOrigin = buildingOrigin
    }

    /// Returns `true` when the model carries no anchors, relations, or routes.
    public var isEmpty: Bool {
        anchors.isEmpty && verticalRelations.isEmpty && inferredRoutes.isEmpty
    }
}
