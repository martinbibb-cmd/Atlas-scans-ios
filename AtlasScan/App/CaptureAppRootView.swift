import SwiftUI

// MARK: - CaptureAppRootView
//
// The new capture-only app root.
//
// Flow:
//   • If there is an active (non-exported) draft session → go to CaptureHubView
//   • Otherwise → show StartJobView to enter a visit reference
//
// "One visit, one session, one home screen."
//
// The existing PropertySessionListView remains accessible under a secondary tab
// for reading back completed sessions and legacy continuity.

struct CaptureAppRootView: View {

    @State private var activeStore: CaptureSessionStore?
    @State private var showingHub = false

    var body: some View {
        Group {
            if let store = activeStore, showingHub {
                CaptureHubView(store: store)
                    .transition(.opacity)
            } else {
                StartJobView { draft in
                    let store = CaptureSessionStore(
                        draft: draft,
                        persistence: .shared
                    )
                    store.saveNow()
                    activeStore = store
                    withAnimation { showingHub = true }
                }
                .overlay(alignment: .bottom) {
                    if let draft = CaptureSessionPersistence.shared.lastIncompleteDraft() {
                        resumeBanner(draft: draft)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear { checkForExistingDraft() }
    }

    // MARK: - Resume banner

    private func resumeBanner(draft: CaptureSessionDraft) -> some View {
        Button {
            let store = CaptureSessionStore(draft: draft, persistence: .shared)
            activeStore = store
            withAnimation { showingHub = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume last session")
                        .font(.caption.bold())
                    Text(draft.visitReference.isEmpty ? "No reference" : draft.visitReference)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    // MARK: - Check for existing draft on launch

    private func checkForExistingDraft() {
        guard activeStore == nil else { return }
        if let draft = CaptureSessionPersistence.shared.lastIncompleteDraft() {
            let store = CaptureSessionStore(draft: draft, persistence: .shared)
            activeStore = store
            showingHub = true
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Start Job") {
    CaptureAppRootView()
}
#endif
