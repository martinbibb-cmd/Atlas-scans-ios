import Foundation

// MARK: - QuotePlannerEvidenceV1
//
// Quote-planner evidence contract — carries candidate location anchors recorded
// by the engineer during a visit.  Produced by Atlas Scan and consumed by Atlas
// Mind for quote planning.
//
// Design:
//   • One CandidateLocationAnchorV1 = one candidate install/service location.
//   • Carried as an optional field in ``SessionCaptureV2``.
//   • Raw observation only — no pricing, no scope, no recommendation logic.
//     Atlas Mind owns all interpretation downstream.
//   • Scan remains capture-only; Mind owns the generated scope.

// MARK: - QuotePlannerEvidenceV1

/// Container for all quote-planner evidence captured during a visit.
///
/// Nil when no quote-planner anchors were recorded.  Not required for session
/// validity — existing sessions without quote-planner evidence remain valid.
public struct QuotePlannerEvidenceV1: Codable, Sendable {

    /// Candidate install/service locations identified during the visit.
    public let candidateLocations: [CandidateLocationAnchorV1]

    /// Candidate pipe/service routes recorded during the visit.
    ///
    /// Empty when no routes were recorded.  Defaults to empty when decoding
    /// payloads produced before this field was introduced.
    public let candidateRoutes: [CandidateRouteV1]

    public init(
        candidateLocations: [CandidateLocationAnchorV1],
        candidateRoutes: [CandidateRouteV1] = []
    ) {
        self.candidateLocations = candidateLocations
        self.candidateRoutes = candidateRoutes
    }

    // MARK: - Custom Codable

    // `candidateRoutes` defaults to [] so that payloads produced before this
    // field was introduced continue to decode successfully.

    private enum CodingKeys: String, CodingKey {
        case candidateLocations
        case candidateRoutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidateLocations = try container.decode([CandidateLocationAnchorV1].self,
                                                  forKey: .candidateLocations)
        candidateRoutes = try container.decodeIfPresent([CandidateRouteV1].self,
                                                        forKey: .candidateRoutes) ?? []
    }
}

// MARK: - CandidateLocationAnchorV1

/// A candidate quote-planner location anchor recorded during the visit.
///
/// Evidence only — no pricing, no scope, no recommendation.
/// Atlas Mind derives those downstream.
public struct CandidateLocationAnchorV1: Codable, Sendable {

    /// Stable UUID for this anchor record.
    public let id: String

    /// Anchor kind raw value.  See known values in the comment below.
    ///
    /// Known values:
    ///   "existing_boiler" | "proposed_boiler" | "existing_cylinder" | "proposed_cylinder" |
    ///   "gas_meter" | "stop_tap" | "consumer_unit" |
    ///   "existing_flue_terminal" | "proposed_flue_terminal" |
    ///   "internal_waste" | "soil_stack" | "gully" | "soakaway_candidate" |
    ///   "airing_cupboard" | "loft_hatch" | "other"
    public let kind: String

    /// Optional free-text label set by the engineer.
    public let label: String?

    /// UUID of the room this anchor is associated with; nil when unlinked.
    public let roomId: String?

    /// Approximate 3-D position if captured from a spatial placement.
    /// Nil when position was not recorded.
    public let coordinates: ScanPoint3D?

    /// UUIDs of evidence photos linked to this anchor; may be empty.
    public let linkedPhotoIds: [String]

    /// UUIDs of object pins linked to this anchor; may be empty.
    public let linkedObjectPinIds: [String]

    /// Confidence level raw value.
    ///
    /// Known values: "confirmed" | "measured" | "estimated" | "needs_verification"
    public let confidence: String

    /// Provenance raw value — how the anchor was placed.
    ///
    /// Known values: "manual" | "ar_pin" | "room_scan_object" |
    ///               "photo_annotation" | "floor_plan_tap"
    public let provenance: String

    public init(
        id: String,
        kind: String,
        label: String?,
        roomId: String?,
        coordinates: ScanPoint3D?,
        linkedPhotoIds: [String],
        linkedObjectPinIds: [String],
        confidence: String,
        provenance: String
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.roomId = roomId
        self.coordinates = coordinates
        self.linkedPhotoIds = linkedPhotoIds
        self.linkedObjectPinIds = linkedObjectPinIds
        self.confidence = confidence
        self.provenance = provenance
    }
}

// MARK: - RouteWaypointV1

/// An intermediate waypoint along a candidate pipe or service route.
///
/// Carries optional 3-D spatial coordinates and/or a normalised plan-canvas
/// position.  Both may be nil when the route was described only in notes.
public struct RouteWaypointV1: Codable, Sendable {

    /// Stable UUID for this waypoint record.
    public let id: String

    /// 3-D position if captured from a spatial placement; nil when not recorded
    /// or when no reliable scale exists.
    public let coordinates: ScanPoint3D?

    /// Normalised plan/photo X position in the [0, 1] range; nil when not placed
    /// on a plan canvas.
    public let planX: Double?

    /// Normalised plan/photo Y position in the [0, 1] range; nil when not placed
    /// on a plan canvas.
    public let planY: Double?

    /// Optional free-text label for this waypoint (e.g. "behind radiator").
    public let label: String?

    public init(
        id: String,
        coordinates: ScanPoint3D?,
        planX: Double?,
        planY: Double?,
        label: String?
    ) {
        self.id = id
        self.coordinates = coordinates
        self.planX = planX
        self.planY = planY
        self.label = label
    }
}

// MARK: - CandidateRouteV1

/// A candidate pipe or service route recorded during the visit.
///
/// Evidence only — no lengths, no calculations.  Atlas Scan records geometry
/// and notes; Atlas Mind derives measured lengths once scale is confirmed.
public struct CandidateRouteV1: Codable, Sendable {

    /// Stable UUID for this route record.
    public let id: String

    /// Route type raw value.
    ///
    /// Known values:
    ///   "gas" | "condensate" | "heating_flow" | "heating_return" |
    ///   "hot_water" | "cold_main" | "discharge" | "controls"
    public let routeType: String

    /// Route status raw value.
    ///
    /// Known values: "existing" | "proposed" | "reused_existing" | "assumed"
    public let status: String

    /// Install method raw value; nil when not yet known.
    ///
    /// Known values:
    ///   "surface" | "boxed" | "concealed" | "underfloor" |
    ///   "loft" | "external" | "unknown"
    public let installMethod: String?

    /// UUID of the start ``CandidateLocationAnchorV1``; nil when not linked.
    public let startAnchorId: String?

    /// UUID of the end ``CandidateLocationAnchorV1``; nil when not linked.
    public let endAnchorId: String?

    /// Intermediate waypoints along the route.
    public let waypoints: [RouteWaypointV1]

    /// Free-text notes about the route (e.g. pipe sizing, routing constraints).
    public let notes: String?

    /// Confidence level raw value.
    ///
    /// Known values: "confirmed" | "measured" | "estimated" | "needs_verification"
    public let confidence: String

    /// Provenance raw value — how the route was recorded.
    ///
    /// Known values: "manual" | "ar_pin" | "room_scan_object" |
    ///               "photo_annotation" | "floor_plan_tap"
    public let provenance: String

    /// UUIDs of evidence photos linked to this route; may be empty.
    public let linkedPhotoIds: [String]

    /// Engineer review status raw value: "confirmed" | "pending" | "rejected"
    public let reviewStatus: String

    public init(
        id: String,
        routeType: String,
        status: String,
        installMethod: String?,
        startAnchorId: String?,
        endAnchorId: String?,
        waypoints: [RouteWaypointV1],
        notes: String?,
        confidence: String,
        provenance: String,
        linkedPhotoIds: [String],
        reviewStatus: String
    ) {
        self.id = id
        self.routeType = routeType
        self.status = status
        self.installMethod = installMethod
        self.startAnchorId = startAnchorId
        self.endAnchorId = endAnchorId
        self.waypoints = waypoints
        self.notes = notes
        self.confidence = confidence
        self.provenance = provenance
        self.linkedPhotoIds = linkedPhotoIds
        self.reviewStatus = reviewStatus
    }
}
