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
// Design rules:
//   • Embeds the full SessionCaptureV2 so Mind can preload the visit.
//   • VisitReadinessV1 tells Mind how complete the capture is on arrival.
//   • reason clarifies why the handoff was initiated.
//   • sourceApp and targetApp are fixed string identifiers, not the
//     HandoffSourceApp enum, to keep this type self-contained.

// MARK: - ScanToMindHandoffV1

/// URL-based handoff envelope from Atlas Scan (iOS) to Atlas Mind (PWA).
///
/// Carried as a percent-encoded JSON query parameter on Mind's
/// `/receive-scan` route.  Atlas Mind reads this payload to preload
/// the visit and display the appropriate capture summary.
public struct ScanToMindHandoffV1: Codable, Sendable {

    // MARK: Schema identity

    /// Contract version; always `"1.0"` for this generation.
    public let version: String

    /// Schema version; always `"1.0"` for this generation.
    public let schemaVersion: String

    // MARK: Routing

    /// Identifier of the producing app; always `"scan_ios"`.
    public let sourceApp: String

    /// Identifier of the consuming app; always `"mind_pwa"`.
    public let targetApp: String

    // MARK: Visit identity

    /// Stable visit UUID from ``AtlasScanVisit/visitId``.
    public let visitId: String

    /// Capture session UUID from ``SessionCaptureV2/sessionId``.
    ///
    /// Must equal `visitId` when the capture was produced by the same visit.
    public let sessionId: String

    // MARK: Readiness snapshot

    /// Readiness flags at the moment the handoff was built.
    public let readiness: VisitReadinessV1

    // MARK: Capture payload

    /// Full capture data for this visit.
    public let capture: SessionCaptureV2

    // MARK: Handoff reason

    /// Why this handoff was initiated.
    public let reason: ScanToMindHandoffReasonV1

    // MARK: Timestamp

    /// ISO-8601 timestamp of when this handoff was generated.
    public let exportedAt: String

    // MARK: Init

    public init(
        visitId: String,
        sessionId: String,
        readiness: VisitReadinessV1,
        capture: SessionCaptureV2,
        reason: ScanToMindHandoffReasonV1,
        exportedAt: String
    ) {
        self.version = "1.0"
        self.schemaVersion = "1.0"
        self.sourceApp = "scan_ios"
        self.targetApp = "mind_pwa"
        self.visitId = visitId
        self.sessionId = sessionId
        self.readiness = readiness
        self.capture = capture
        self.reason = reason
        self.exportedAt = exportedAt
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
