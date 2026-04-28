import Foundation

// MARK: - VisitLifecycleV1
//
// Contract types for the field-visit lifecycle phase.
//
// Design rules:
//   • VisitLifecycleStatus is the single source of truth for where a visit
//     currently sits in the field workflow.
//   • The status is persisted alongside the visit draft; it is never inferred
//     purely from local UI navigation state.
//   • atlas-scans-ios WRITES this status as the engineer moves through phases.
//   • atlas-contracts DEFINES the valid states and their raw values.
//   • Consumers downstream (atlas-recommendation, reports) can use this to
//     understand whether a visit is ready for processing.

// MARK: - VisitLifecycleStatus

/// The phase a field visit is currently in.
///
/// Transitions:
///   draft → capturing (when engineer begins capture work)
///   capturing → planning (when engineer moves to planning)
///   any → readyToComplete (derived from readiness; may be shown dynamically)
///   readyToComplete → complete (explicit engineer action; PR 5)
///
/// The `complete` case is defined here but must not be set by the app
/// until the explicit completion flow is implemented in PR 5.
public enum VisitLifecycleStatus: String, Codable, Sendable, CaseIterable {

    /// Visit created but no capture or planning work has started.
    case draft = "draft"

    /// Engineer is actively capturing rooms, photos, and objects.
    case capturing = "capturing"

    /// Engineer is planning the installation on top of the captured survey.
    case planning = "planning"

    /// All readiness checks pass; visit is ready for completion.
    case readyToComplete = "ready_to_complete"

    /// Visit has been explicitly completed. Set only in PR 5.
    case complete = "complete"

    // MARK: Display

    public var displayName: String {
        switch self {
        case .draft:           return "Draft"
        case .capturing:       return "Capturing"
        case .planning:        return "Planning"
        case .readyToComplete: return "Ready to Complete"
        case .complete:        return "Complete"
        }
    }

    public var symbolName: String {
        switch self {
        case .draft:           return "doc"
        case .capturing:       return "camera.viewfinder"
        case .planning:        return "pencil.and.ruler"
        case .readyToComplete: return "checkmark.circle"
        case .complete:        return "checkmark.seal.fill"
        }
    }
}
