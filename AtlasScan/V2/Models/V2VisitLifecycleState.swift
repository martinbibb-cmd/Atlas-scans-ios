/// VisitCaptureLifecycleState — Tracks the current phase of an active V2 capture visit.

public enum VisitCaptureLifecycleState: String, Codable {
    /// No active visit. App is at home screen.
    case noVisit
    /// User is setting up visit reference / label before scanning.
    case visitSetup
    /// A room scan is in progress (RoomPlan running).
    case scanningRoom
    /// Scan complete; user is reviewing + naming the captured room.
    case reviewingRoom
    /// Room has been saved to the session; user can scan another room or finish.
    case roomSaved
    /// User is deciding what to do next (next room, review, finish).
    case choosingNextStep
    /// User is reviewing all captured visit data.
    case visitReview
    /// Visit finished as draft before capture completeness checks pass.
    case draft
    /// Visit is actively being captured (high-level lifecycle state).
    case capturing
    /// Missing evidence exists; visit is finishable but requires review.
    case incompleteReadyForReview = "incomplete_ready_for_review"
    /// Visit is complete and ready to export.
    case readyToExport
    /// Visit data has been exported / handed off to Atlas Mind.
    case exported
}
