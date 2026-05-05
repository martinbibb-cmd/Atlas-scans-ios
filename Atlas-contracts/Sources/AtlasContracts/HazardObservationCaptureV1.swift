import Foundation

// MARK: - HazardObservationCaptureV1
//
// Hazard capture contract — carries site hazard observations recorded by the
// engineer during a visit.  Produced by Atlas Scan and consumed by Atlas Mind.
//
// Design:
//   • One HazardObservationCaptureV1 = one hazard observation record.
//   • Carried as an optional array in ``SessionCaptureV2``.
//   • Raw observation only — no risk-assessment score, no action plan,
//     no recommendation logic.  Atlas Mind owns all interpretation downstream.

/// A single site-hazard observation recorded by the engineer.
///
/// Raw observation only — no risk score, no remediation recommendation.
/// Atlas Mind derives those downstream.
public struct HazardObservationCaptureV1: Codable, Sendable {

    /// Stable UUID for this hazard record.
    public let id: String

    /// Hazard category raw value.
    ///
    /// Known values: "asbestos" | "electrical" | "flue" | "gas" | "water" |
    ///               "access" | "working_at_height" | "structural" |
    ///               "slip_trip" | "customer_property" | "other"
    public let category: String

    /// Hazard severity raw value.
    ///
    /// Valid values: "low" | "medium" | "high" | "critical"
    public let severity: String

    /// Short engineer-supplied title for the hazard.
    public let title: String

    /// Optional longer description of the hazard observation.
    public let description: String?

    /// UUIDs of evidence photos linked to this hazard; may be empty.
    public let linkedPhotoIds: [String]

    /// UUIDs of object pins linked to this hazard; may be empty.
    public let linkedObjectPinIds: [String]

    /// Whether the engineer considers immediate action required.
    public let actionRequired: Bool

    /// Engineer review status raw value: "confirmed" | "pending" | "rejected".
    public let reviewStatus: String

    public init(
        id: String,
        category: String,
        severity: String,
        title: String,
        description: String?,
        linkedPhotoIds: [String],
        linkedObjectPinIds: [String],
        actionRequired: Bool,
        reviewStatus: String
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.description = description
        self.linkedPhotoIds = linkedPhotoIds
        self.linkedObjectPinIds = linkedObjectPinIds
        self.actionRequired = actionRequired
        self.reviewStatus = reviewStatus
    }
}
