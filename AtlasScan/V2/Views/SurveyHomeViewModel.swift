/// SurveyHomeViewModel — Drives `SurveyHomeView`. Holds the room list,
/// active visit context, and the actions surfaced by the three primary
/// buttons (Continue Survey / Review Evidence / Finish Survey).
///
/// The view-model deliberately exposes the *survey-shell* status
/// (`AtlasScanSessionStatus`) rather than the lower-level
/// `VisitCaptureLifecycleState`. Bridging happens via
/// `AtlasScanSessionStatus.from(lifecycle:)`.

import Foundation
import SwiftUI
import AtlasScanCore

@MainActor
final class SurveyHomeViewModel: ObservableObject {

    @Published public var rooms: [RoomCaptureV2] = []
    @Published public var status: AtlasScanSessionStatus = .notStarted
    @Published public var visit: AtlasVisitIdentityV1?
    @Published public var workspace: AtlasWorkspaceV1?

    init(
        rooms: [RoomCaptureV2] = [],
        status: AtlasScanSessionStatus = .notStarted,
        visit: AtlasVisitIdentityV1? = nil,
        workspace: AtlasWorkspaceV1? = nil
    ) {
        self.rooms = rooms
        self.status = status
        self.visit = visit
        self.workspace = workspace
    }

    /// Rooms to surface in the visit summary list. Filters out
    /// suggested/discarded rooms — only confirmed rooms appear.
    var visibleRooms: [RoomCaptureV2] {
        rooms.filter { room in
            switch room.captureStatus {
            case .saved, .needsReview, .captured:
                return true
            case .scanning, .draft, .discarded:
                return false
            }
        }
    }

    /// Whether the user can finish the survey from the home screen.
    /// Per the brief, Finish must always be available — even with zero
    /// rooms, since draft / incomplete handoffs are valid.
    var canFinish: Bool { true }

    /// Whether at least one room needs engineer review before handoff.
    var hasNeedsReviewRooms: Bool {
        rooms.contains { $0.captureStatus == .needsReview }
    }
}
