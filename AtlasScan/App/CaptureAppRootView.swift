import SwiftUI

// MARK: - CaptureAppRootView
//
// Atlas Scan V2 root: the single-session visit capture flow.
//
// Flow:
//   • Initialised with a pre-selected draft (from VisitPickerView).
//   • Live Capture → Review Visit → Export
//   • Export → onDone callback (returns to VisitPickerView)
//   • "Back to Capture" available from review screen.
//
// "One visit, one session, one home screen."

enum CaptureFlowState {
    case capturing
    case reviewing
}

struct CaptureAppRootView: View {

    let initialDraft: CaptureSessionDraft
    let onDone: () -> Void

    @State private var activeStore: CaptureSessionStore
    @State private var flowState: CaptureFlowState = .capturing

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
            case .capturing:
                capturingScreen
            case .reviewing:
                reviewingScreen
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flowState)
    }

    // MARK: - Capturing

    private var capturingScreen: some View {
        LiveCaptureView(store: activeStore) {
            flowState = .reviewing
        }
    }

    // MARK: - Reviewing

    private var reviewingScreen: some View {
        NavigationStack {
            ReviewVisitView(store: activeStore)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("← Capture") { flowState = .capturing }
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
#Preview("Capture") {
    CaptureAppRootView(
        initialDraft: CaptureSessionStore.newSession(visitReference: "JOB-PREVIEW-001"),
        onDone: {}
    )
}
#endif

