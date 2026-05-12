/// FinishSurveyViewModel — Drives `FinishSurveyView`. Provides the captured /
/// needs-review summary and exposes the four end-of-survey actions described
/// in the brief:
///
///   1. Send to Mind          — happy path; complete or incomplete-draft handoff
///   2. Save & Continue Later — autosave + return to visit picker
///   3. Discard Survey        — destructive; clears the active session
///   4. Back to Survey        — cancel the finish flow

import Foundation
import SwiftUI
import AtlasScanCore

@MainActor
public final class FinishSurveyViewModel: ObservableObject {

    @Published public var session: SessionCaptureV2
    @Published public var engineerNotes: String
    @Published public var sendError: String?

    public init(session: SessionCaptureV2) {
        self.session = session
        self.engineerNotes = session.engineerNotes ?? ""
    }

    public var capturedRooms: [RoomCaptureV2] {
        session.rooms.filter { $0.captureStatus == .saved || $0.captureStatus == .captured }
    }

    public var needsReviewRooms: [RoomCaptureV2] {
        session.rooms.filter { $0.captureStatus == .needsReview }
    }

    /// Returns the readiness derived from the underlying session.
    public var readiness: VisitReadinessV1 {
        VisitReadinessV1.derive(from: session)
    }

    /// Whether sending now would yield an incomplete-draft handoff.
    public var willBeIncompleteDraft: Bool {
        !readiness.isReady
    }

    /// Builds the handoff payload using `ScanToMindHandoffBuilder`. The
    /// caller is responsible for transmitting the payload (e.g. via
    /// `MindDeepLinkService`).
    public func buildHandoff() throws -> ScanToMindHandoffV1 {
        try ScanToMindHandoffBuilder.build(
            session: session,
            engineerNotesOverride: engineerNotes
        )
    }
}
