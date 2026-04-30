import SwiftUI
import AtlasContracts

// MARK: - AtlasScanApp
//
// Root entry point.
//
// Navigation:
//   HomeView
//     ├── Open Atlas Mind    → MindRootView (full-screen WebView)
//     ├── Start Local Visit  → StartVisitView sheet → VisitDetailView
//     └── Saved Visits       → SavedVisitsView → VisitDetailView
//
// URL scheme (atlasscan://):
//   atlasscan://?visitId=<ref>           – open / create visit by reference
//   atlasscan://?handoff=<base64-pack>   – receive VisitHandoffPackV1 from Mind

@main
struct AtlasScanApp: App {

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

// MARK: - MindRootView

/// Full-screen container for the Atlas Recommendations PWA.
///
/// Pass a `visitId` to deep-link directly to a specific visit on load.
struct MindRootView: View {

    /// Optional visit identifier to deep-link into Atlas Mind on open.
    /// Maps to the `visitId` query parameter of ``AtlasRecommendationsWebView``.
    let visitId: String?

    let onClose: () -> Void

    init(visitId: String? = nil, onClose: @escaping () -> Void) {
        self.visitId = visitId
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            AtlasRecommendationsWebView(visitId: visitId)
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

