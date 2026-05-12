/// SurveyRoomState — Lifecycle status of a room within a continuous survey.
///
/// Distinct from `V2RoomCaptureStatusV1` (AtlasScanCore), which describes the
/// RoomPlan capture pipeline state. `SurveyRoomStatus` describes the *survey
/// shell* view of the room: whether the user has confirmed it, whether it is
/// currently being walked, whether it is captured / saved / discarded, and
/// whether it needs human review before handoff.
///
/// Used by `SurveyHomeView` to render the room list and by
/// `RoomSegmentationService` to track confirmed vs. suggested rooms.
public enum SurveyRoomStatus: String, Codable, Sendable, CaseIterable {
    /// The system has suggested a room break but the user has not confirmed it.
    case suggested
    /// The user is actively walking / capturing this room.
    case active
    /// Capture is complete for this room but it has not yet been saved.
    case captured
    /// Saved but flagged as requiring engineer review (geometry, missing
    /// evidence, low-confidence pins, etc.) before handoff.
    case needsReview = "needs_review"
    /// Fully saved and ready for handoff to Atlas Mind.
    case saved
    /// The user explicitly discarded this room candidate.
    case discarded
}

public extension SurveyRoomStatus {
    /// Whether this status counts as a real room in the visit summary.
    /// `suggested` and `discarded` rooms are excluded.
    var isVisibleInVisitSummary: Bool {
        switch self {
        case .active, .captured, .needsReview, .saved:
            return true
        case .suggested, .discarded:
            return false
        }
    }

    /// Whether this room blocks a "complete" handoff.
    var requiresReviewBeforeHandoff: Bool {
        self == .needsReview
    }
}
