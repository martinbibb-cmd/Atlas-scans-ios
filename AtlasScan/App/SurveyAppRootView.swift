/// SurveyAppRootView — Root view of the new continuous-survey shell, gated
/// by `FeatureFlag.continuousSurveyShell`.
///
/// Routes through:
///   `SurveyHomeView`  ↔  Capture (PropertyMapView for now)
///                     ↔  `EvidenceReviewView`
///                     ↔  `FinishSurveyView`
///
/// The capture surface is currently the existing `PropertyMapView` (the
/// proven AR/RoomPlan path). A follow-up will swap this for the new
/// `ContinuousSurveyView` once camera + AR wiring is plumbed through the
/// new capture services.

import SwiftUI
import AtlasScanCore

@MainActor
struct SurveyAppRootView: View {

    let workspace: AtlasWorkspaceV1
    let visit: AtlasVisitIdentityV1
    let onSignOut: () -> Void
    let onChangeVisit: () -> Void

    @EnvironmentObject private var coordinator: ScanSessionCoordinator
    @StateObject private var homeViewModel = SurveyHomeViewModel()

    @State private var route: Route?
    @State private var presentFinish: Bool = false

    enum Route: Hashable {
        case capture
        case reviewEvidence
    }

    var body: some View {
        SurveyHomeView(
            viewModel: homeViewModel,
            onContinueSurvey: { route = .capture },
            onReviewEvidence: { route = .reviewEvidence },
            onFinishSurvey: { presentFinish = true },
            onSaveAndExit: handleSaveAndExit,
            onOpenVisitNotes: {},
            onOpenDebug: {}
        )
        .navigationDestination(item: $route) { route in
            switch route {
            case .capture:
                PropertyMapView()
            case .reviewEvidence:
                EvidenceReviewView(
                    session: coordinator.session,
                    onEditCapture: { self.route = .capture },
                    onClose: { self.route = nil }
                )
            }
        }
        .sheet(isPresented: $presentFinish) {
            NavigationStack {
                FinishSurveyView(
                    viewModel: FinishSurveyViewModel(session: coordinator.session),
                    onSendToMind: handleSendToMind,
                    onSaveAndContinueLater: handleSaveAndExit,
                    onDiscard: handleDiscard,
                    onBackToSurvey: { presentFinish = false }
                )
            }
        }
        .onAppear { hydrateHomeFromSession() }
        .onReceive(coordinator.$session) { _ in hydrateHomeFromSession() }
        .onReceive(coordinator.$lifecycleState) { _ in hydrateHomeFromSession() }
    }

    // MARK: - Sync

    private func hydrateHomeFromSession() {
        homeViewModel.rooms = coordinator.session.rooms
        homeViewModel.status = AtlasScanSessionStatus.from(lifecycle: coordinator.lifecycleState)
        homeViewModel.visit = visit
        homeViewModel.workspace = workspace

        // Persist the shell-level descriptor so resume works on next launch.
        SurveySessionStore.shared.saveActiveSession(
            AtlasScanSessionV1(
                visitId: coordinator.session.visitId,
                workspaceId: workspace.id,
                status: AtlasScanSessionStatus.from(lifecycle: coordinator.lifecycleState)
            )
        )
    }

    // MARK: - Actions

    private func handleSaveAndExit() {
        Task {
            await coordinator.saveSession()
            presentFinish = false
            onChangeVisit()
        }
    }

    private func handleSendToMind() {
        _ = MindDeepLinkService.openVisit(
            visitId: visit.id,
            workspaceId: workspace.id
        )
        presentFinish = false
    }

    private func handleDiscard() {
        coordinator.discardActiveSession()
        SurveySessionStore.shared.clearActiveSession()
        presentFinish = false
        onChangeVisit()
    }
}
