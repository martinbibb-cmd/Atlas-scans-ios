import SwiftUI

// MARK: - CaptureFlowState

enum CaptureFlowState {
    case spatial    // Spatial-first walkthrough (PropertyNavigatorView) — default
    case classic    // Legacy card-based LiveCaptureView
    case reviewing
}

// MARK: - CaptureAppRootView
//
// Atlas Scan V2 root: the single-session visit capture flow.
//
// Modes:
//   • Spatial (default) — spatial-first walkthrough via PropertyNavigatorView.
//   • Classic           — legacy card-based LiveCaptureView.
//   • Reviewing         — ReviewVisitView with export actions.
//
// "One visit, one session, one home screen."

struct CaptureAppRootView: View {

    let initialDraft: CaptureSessionDraft
    let onDone: () -> Void

    @State private var activeStore: CaptureSessionStore
    @State private var flowState: CaptureFlowState = .spatial

    // MARK: Init

    init(initialDraft: CaptureSessionDraft, onDone: @escaping () -> Void) {
        self.initialDraft = initialDraft
        self.onDone = onDone
        _activeStore = State(
            wrappedValue: CaptureSessionStore(draft: initialDraft, persistence: .shared)
        )
    }

    var body: some View {
        Group {
            switch flowState {
            case .spatial:
                spatialScreen
            case .classic:
                capturingScreen
            case .reviewing:
                reviewingScreen
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flowState)
    }

    // MARK: - Spatial walkthrough (primary)

    private var spatialScreen: some View {
        NavigationStack {
            PropertyNavigatorView(store: activeStore)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Classic Capture Mode") {
                                flowState = .classic
                            }
                            Button("Review & Export") {
                                flowState = .reviewing
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        }
    }

    // MARK: - Classic capture (legacy)

    private var capturingScreen: some View {
        NavigationStack {
            LiveCaptureView(store: activeStore) {
                flowState = .reviewing
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        flowState = .spatial
                    } label: {
                        Label("Walkthrough", systemImage: "map")
                    }
                }
            }
        }
    }

    // MARK: - Reviewing

    private var reviewingScreen: some View {
        NavigationStack {
            ReviewVisitView(store: activeStore)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("← Walkthrough") { flowState = .spatial }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if activeStore.draft.exportState == .exported {
                            Button("Done") { onDone() }
                                .fontWeight(.semibold)
                        }
                    }
                }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Spatial Walkthrough") {
    CaptureAppRootView(
        initialDraft: CaptureSessionStore.newSession(visitReference: "JOB-PREVIEW-001"),
        onDone: {}
    )
}

#Preview("Classic Capture") {
    let root = CaptureAppRootView(
        initialDraft: CaptureSessionStore.newSession(visitReference: "JOB-PREVIEW-002"),
        onDone: {}
    )
    return root
}
#endif

