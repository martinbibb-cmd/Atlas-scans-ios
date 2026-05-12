import SwiftUI

// Atlas Scan V2 — capture-only app.
// The root scene now uses ScanSessionCoordinator + MindRecallClient
// and launches into PropertyMapView.

@main
struct AtlasScanApp: App {

    @StateObject private var coordinator = ScanSessionCoordinator()
    @StateObject private var recallClient = MindRecallClient(store: .shared)
    @StateObject private var authState = AtlasAuthState()

    var body: some Scene {
        WindowGroup {
            AtlasAuthRootView()
                .environmentObject(authState)
                .environmentObject(coordinator)
                .environmentObject(recallClient)
        }
    }
}

@MainActor
private struct AtlasAuthRootView: View {
    @EnvironmentObject private var authState: AtlasAuthState
    @EnvironmentObject private var coordinator: ScanSessionCoordinator
    @State private var didBootstrap = false

    var body: some View {
        NavigationStack {
            Group {
                if !authState.isAuthenticated {
                    LoginView(
                        isLoading: authState.isLoading,
                        errorMessage: authState.errorMessage
                    ) {
                        Task { await authState.signInWithGoogle() }
                    }
                } else if let workspace = authState.selectedWorkspace {
                    if let visit = authState.selectedVisit {
                        Group {
                            if FeatureFlags.isEnabled(.continuousSurveyShell) {
                                SurveyAppRootView(
                                    workspace: workspace,
                                    visit: visit,
                                    onSignOut: {
                                        Task {
                                            coordinator.discardActiveSession()
                                            await authState.signOut()
                                        }
                                    },
                                    onChangeVisit: {
                                        authState.selectedVisit = nil
                                    }
                                )
                            } else {
                                PropertyMapView()
                            }
                        }
                            .onAppear {
                                applyVisitContextIfNeeded(visit: visit)
                            }
                    } else {
                        AtlasVisitPickerView(
                            workspace: workspace,
                            visits: authState.visits,
                            isLoading: authState.isLoading,
                            errorMessage: authState.errorMessage,
                            onRefresh: { Task { await authState.refreshVisits() } },
                            onCreateMindVisit: { Task { await authState.createMindVisit() } },
                            onSelectVisit: { visit in
                                authState.chooseVisit(visit)
                                applyVisitContextIfNeeded(visit: visit)
                            },
                            onBack: {
                                authState.clearWorkspaceSelection()
                            },
                            onSignOut: {
                                Task {
                                    coordinator.discardActiveSession()
                                    await authState.signOut()
                                }
                            }
                        )
                    }
                } else {
                    WorkspacePickerView(
                        profile: authState.profile,
                        workspaces: authState.workspaces,
                        selectedWorkspace: authState.selectedWorkspace,
                        onSelectWorkspace: { workspace in
                            authState.chooseWorkspace(workspace)
                            Task { await authState.refreshVisits() }
                        },
                        onSignOut: {
                            Task {
                                coordinator.discardActiveSession()
                                await authState.signOut()
                            }
                        }
                    )
                }
            }
            .task {
                guard !didBootstrap else { return }
                didBootstrap = true
                await authState.bootstrap()
                if authState.selectedWorkspace != nil && authState.visits.isEmpty {
                    await authState.refreshVisits()
                }
            }
        }
    }

    private func applyVisitContextIfNeeded(visit: AtlasVisitIdentityV1) {
        let currentReference = coordinator.session.visitReference?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard currentReference != visit.visitReference else { return }
        coordinator.discardActiveSession()
        coordinator.session.visitReference = visit.visitReference
        coordinator.session.visitLabel = visit.propertyAddress
        Task { await coordinator.saveSession() }
    }
}

// MARK: - MindRootView

/// Full-screen "Open Atlas Mind" shortcut — wraps the Atlas Mind PWA.
///
/// Pass a `visitId` to deep-link directly to a specific visit on load.
/// This view is not a simulator or recommendation surface; it is a
/// shortcut to the Atlas Mind PWA only.
struct MindRootView: View {

    /// Optional visit identifier to deep-link into Atlas Mind on open.
    /// Maps to the `visitId` query parameter of ``AtlasMindWebView``.
    let visitId: String?

    let onClose: () -> Void

    init(visitId: String? = nil, onClose: @escaping () -> Void) {
        self.visitId = visitId
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            AtlasMindWebView(visitId: visitId)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onClose()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Home")
                            }
                        }
                    }
                }
        }
    }
}
