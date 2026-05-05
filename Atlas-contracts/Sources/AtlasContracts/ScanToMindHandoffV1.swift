import Foundation

// MARK: - ScanToMindHandoffV1
//
// URL-based handoff payload from Atlas Scan to Atlas Mind.
//
// Produced by ScanToMindHandoffBuilder and carried to Mind via a
// percent-encoded JSON query parameter on the /receive-scan route:
//
//   https://next.atlas-phm.uk/receive-scan?payload=<percent-encoded JSON>
//
// Canonical shape (v1):
//   {
//     "kind": "scan-to-mind-handoff",
//     "schemaVersion": 1,
//     "exportedAt": "...",
//     "sourceApp": "scan_ios",
//     "targetApp": "mind_pwa",
//     "reason": "complete_capture" | "save_progress" | "review_in_mind" | "quote_planner",
//     "visit": { "version": "1.0", "visitId": "...", ... },
//     "capture": { ... }
//   }
//
// Design rules:
//   • Embeds the full SessionCaptureV2 so Mind can preload the visit.
//   • visit carries lifecycle state and readiness at the moment of handoff.
//   • reason clarifies why the handoff was initiated.
//   • sourceApp and targetApp are fixed string identifiers, not the
//     HandoffSourceApp enum, to keep this type self-contained.
//   • schemaVersion is a numeric Int (1), not a string.
//   • kind must be "scan-to-mind-handoff" for consumer-side validation.

// MARK: - ScanToMindHandoffV1

/// URL-based handoff envelope from Atlas Scan (iOS) to Atlas Mind (PWA).
///
/// Carried as a percent-encoded JSON query parameter on Mind's
/// `/receive-scan` route.  Atlas Mind reads this payload to preload
/// the visit and display the appropriate capture summary.
public struct ScanToMindHandoffV1: Codable, Sendable {

    // MARK: Schema identity

    /// Discriminator; always `"scan-to-mind-handoff"`.
    ///
    /// Mind uses this to route the payload to the correct handler.
    public let kind: String

    /// Numeric schema version; always `1` for this generation.
    ///
    /// Intentionally an `Int` (not `String`) so consumers can use `>=` guards.
    public let schemaVersion: Int

    // MARK: Routing

    /// Identifier of the producing app; always `"scan_ios"`.
    public let sourceApp: String

    /// Identifier of the consuming app; always `"mind_pwa"`.
    public let targetApp: String

    // MARK: Timestamp

    /// ISO-8601 timestamp of when this handoff was generated.
    public let exportedAt: String

    // MARK: Handoff reason

    /// Why this handoff was initiated.
    public let reason: ScanToMindHandoffReasonV1

    // MARK: Visit snapshot

    /// Lifecycle and readiness state of the visit at the moment of handoff.
    public let visit: HandoffVisitSnapshotV1

    // MARK: Capture payload

    /// Full capture data for this visit.
    public let capture: SessionCaptureV2

    // MARK: Init

    public init(
        visit: HandoffVisitSnapshotV1,
        capture: SessionCaptureV2,
        reason: ScanToMindHandoffReasonV1,
        exportedAt: String
    ) {
        self.kind = "scan-to-mind-handoff"
        self.schemaVersion = 1
        self.sourceApp = "scan_ios"
        self.targetApp = "mind_pwa"
        self.exportedAt = exportedAt
        self.reason = reason
        self.visit = visit
        self.capture = capture
    }
}

// MARK: - HandoffVisitSnapshotV1

/// Lifecycle and readiness snapshot for the visit being handed off.
///
/// Carries the minimum visit context that Mind needs to display
/// the capture summary without re-fetching from the server.
public struct HandoffVisitSnapshotV1: Codable, Sendable {

    // MARK: Schema identity

    /// Visit snapshot version; always `"1.0"`.
    public let version: String

    // MARK: Visit identity

    /// Stable visit UUID.
    public let visitId: String

    /// Engineer-assigned visit/job reference (e.g. "JOB-1712345678").
    public let visitNumber: String?

    /// Optional brand or client identifier.
    public let brandId: String?

    // MARK: Lifecycle state

    /// Visit lifecycle status raw value (e.g. `"complete"`).
    public let status: String

    // MARK: Readiness snapshot

    /// Readiness flags at the moment the handoff was built.
    public let readiness: VisitReadinessV1

    // MARK: Timestamps

    /// ISO-8601 timestamp of when the visit was first created.
    public let createdAt: String

    /// ISO-8601 timestamp of when the visit was last updated.
    public let updatedAt: String

    // MARK: Init

    public init(
        visitId: String,
        visitNumber: String?,
        brandId: String?,
        status: String,
        readiness: VisitReadinessV1,
        createdAt: String,
        updatedAt: String
    ) {
        self.version = "1.0"
        self.visitId = visitId
        self.visitNumber = visitNumber
        self.brandId = brandId
        self.status = status
        self.readiness = readiness
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ScanToMindHandoffReasonV1

/// The reason a Scan → Mind handoff was initiated.
public enum ScanToMindHandoffReasonV1: String, Codable, Sendable, CaseIterable {

    /// Engineer completed the full capture and is handing off to Mind for review.
    case completedCapture = "complete_capture"

    /// Engineer is saving progress mid-capture; visit is not yet fully complete.
    case saveProgress = "save_progress"

    /// Engineer (or developer) is triggering the handoff to review the visit in Mind.
    case reviewInMind = "review_in_mind"

    /// Engineer is opening the Quote Planner in Atlas Mind with visit evidence preloaded.
    case quotePlanner = "quote_planner"
}
