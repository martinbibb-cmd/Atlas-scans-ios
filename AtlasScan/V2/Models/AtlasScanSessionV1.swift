/// AtlasScanSessionV1 — Top-level descriptor of an in-progress or completed
/// continuous-survey session, as seen by the new survey shell.
///
/// This is *not* a replacement for `SessionCaptureV2` (the underlying capture
/// envelope persisted to disk by `AtomicSessionStore`). It is a thin
/// shell-level descriptor used by `SurveySessionStore`,
/// `SurveyAutosaveService`, and the new `AppRoot` to know *which* visit /
/// workspace is currently active and what high-level status it is in.
///
/// `AtlasScanSessionStatus` and `VisitCaptureLifecycleState` are kept as two
/// separate types intentionally:
///
/// - `VisitCaptureLifecycleState` describes the *capture pipeline* state
///   (scanning a room, reviewing a room, etc.) and is consumed by the
///   existing V2 capture views.
/// - `AtlasScanSessionStatus` describes the *survey shell* status (not
///   started / surveying / paused / review required / ready for Mind /
///   handed off) and is consumed by `SurveyHomeView`, `FinishSurveyView`,
///   and the handoff builder.
///
/// They are bridged by `AtlasScanSessionStatus.from(lifecycle:)` so we have a
/// single source of truth for the mapping rather than duplicating the enum.

import Foundation

// MARK: - Session status

public enum AtlasScanSessionStatus: String, Codable, Sendable, CaseIterable {
    case notStarted     = "not_started"
    case surveying
    case paused
    case reviewRequired = "review_required"
    case readyForMind   = "ready_for_mind"
    case handedOff      = "handed_off"
}

public extension AtlasScanSessionStatus {
    /// Whether the user can resume the session from where they left off.
    var isResumable: Bool {
        switch self {
        case .surveying, .paused, .reviewRequired:
            return true
        case .notStarted, .readyForMind, .handedOff:
            return false
        }
    }

    /// Whether the session has reached a terminal handoff state.
    var isTerminal: Bool {
        self == .handedOff
    }

    /// Map an existing capture-pipeline lifecycle state to a survey-shell
    /// status. Keeps both enums independent while ensuring a single canonical
    /// translation. Unknown / future cases default to `.surveying` to keep
    /// the shell from getting stuck.
    static func from(lifecycle: VisitCaptureLifecycleState) -> AtlasScanSessionStatus {
        switch lifecycle {
        case .noVisit:
            return .notStarted
        case .visitSetup:
            return .notStarted
        case .scanningRoom, .reviewingRoom, .roomSaved, .choosingNextStep, .capturing:
            return .surveying
        case .visitReview:
            return .reviewRequired
        case .draft, .incompleteReadyForReview:
            return .reviewRequired
        case .readyToExport:
            return .readyForMind
        case .exported:
            return .handedOff
        }
    }
}

// MARK: - Session shell descriptor

public struct AtlasScanSessionV1: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let visitId: UUID
    public let workspaceId: String?
    public var status: AtlasScanSessionStatus
    public let createdAt: Date
    public var updatedAt: Date
    /// When the user last interacted with this session (used to drive
    /// "Resume Survey" prompts on app launch).
    public var lastActiveAt: Date

    public init(
        id: UUID = UUID(),
        visitId: UUID,
        workspaceId: String? = nil,
        status: AtlasScanSessionStatus = .notStarted,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastActiveAt: Date? = nil
    ) {
        self.id = id
        self.visitId = visitId
        self.workspaceId = workspaceId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastActiveAt = lastActiveAt ?? createdAt
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case id, visitId, workspaceId, status, createdAt, updatedAt, lastActiveAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        visitId = try c.decode(UUID.self, forKey: .visitId)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        status = try c.decodeIfPresent(AtlasScanSessionStatus.self, forKey: .status) ?? .notStarted
        let created = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        createdAt = created
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
        lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt) ?? created
    }
}
