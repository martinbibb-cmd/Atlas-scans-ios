import SwiftUI

// MARK: - CaptureAppRootView
//
// Atlas Scan V2 root: the single-session visit capture flow.
//
// Flow:
//   • On launch: if a non-exported draft exists → go straight to LiveCaptureView
//   • Otherwise: show StartJobView to start a new visit
//   • "Finish Capture" → ReviewVisitView
//   • Export from review → session marked exported
//   • "New Visit" from review → resets to StartJobView
//
// "One visit, one session, one home screen."

enum CaptureFlowState {
    case start
    case capturing
    case reviewing
}

struct CaptureAppRootView: View {

    @State private var activeStore: CaptureSessionStore?
    @State private var flowState: CaptureFlowState = .start

    var body: some View {
        Group {
            switch flowState {
            case .start:
                startScreen
            case .capturing:
                capturingScreen
            case .reviewing:
                reviewingScreen
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flowState)
        .onAppear { checkForExistingDraft() }
    }

    // MARK: - Start

    private var startScreen: some View {
        StartJobView { draft in
            let store = CaptureSessionStore(draft: draft, persistence: .shared)
            store.saveNow()
            activeStore = store
            flowState = .capturing
        }
        .overlay(alignment: .bottom) {
            if let draft = CaptureSessionPersistence.shared.lastIncompleteDraft() {
                resumeBanner(draft: draft)
            }
        }
    }

    // MARK: - Capturing

    @ViewBuilder
    private var capturingScreen: some View {
        if let store = activeStore {
            LiveCaptureView(store: store) {
                flowState = .reviewing
            }
        } else {
            Color.black.onAppear { flowState = .start }
        }
    }

    // MARK: - Reviewing

    @ViewBuilder
    private var reviewingScreen: some View {
        if let store = activeStore {
            NavigationStack {
                ReviewVisitView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("← Capture") { flowState = .capturing }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            if store.draft.exportState == .exported {
                                Button("New Visit") { startNewVisit() }
                                    .fontWeight(.semibold)
                            }
                        }
                    }
            }
        } else {
            Color.black.onAppear { flowState = .start }
        }
    }

    // MARK: - Resume banner

    private func resumeBanner(draft: CaptureSessionDraft) -> some View {
        Button {
            let store = CaptureSessionStore(draft: draft, persistence: .shared)
            activeStore = store
            flowState = .capturing
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume last session")
                        .font(.caption.bold())
                    Text(draft.visitReference.isEmpty ? "No reference" : draft.visitReference)
                        .font(.caption2).foregroundStyle(.secondary)
                    if !draft.propertyAddress.isEmpty {
                        Text(draft.propertyAddress)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text("Resume →")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func checkForExistingDraft() {
        guard activeStore == nil else { return }
        if let draft = CaptureSessionPersistence.shared.lastIncompleteDraft() {
            activeStore = CaptureSessionStore(draft: draft, persistence: .shared)
            flowState = .capturing
        }
    }

    private func startNewVisit() {
        activeStore = nil
        flowState = .start
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Start Job") {
    CaptureAppRootView()
}
#endif

