import SwiftUI

// MARK: - AtlasScanApp
//
// Root entry point.
//
// Navigation:
//   HomeView
//     ├── Open Atlas Mind    → MindRootView (full-screen WebView)
//     ├── Start Local Visit  → StartVisitView sheet → VisitDetailView
//     └── Saved Visits       → SavedVisitsView → VisitDetailView

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
struct MindRootView: View {

    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            AtlasRecommendationsWebView(visitId: nil)
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

