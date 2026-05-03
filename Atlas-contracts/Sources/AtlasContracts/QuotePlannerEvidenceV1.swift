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

    public init(candidateLocations: [CandidateLocationAnchorV1]) {
        self.candidateLocations = candidateLocations
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
