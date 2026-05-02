import SwiftUI
import AtlasContracts

// Atlas Scan is capture-only.
// Recommendation, simulation, scenario ranking, presentation,
// portal and PDF outputs are owned by Atlas Mind.

// MARK: - AtlasScanApp
//
// Root entry point.
//
// Navigation:
//   HomeView
//     ├── Open Atlas Mind    → MindRootView (full-screen Atlas Mind WebView shortcut)
//     ├── Start Local Visit  → StartVisitView sheet → VisitDetailView
//     └── Saved Visits       → SavedVisitsView → VisitDetailView
//
// URL scheme (atlasscan://):
//   atlasscan://?visitId=<ref>           – open / create visit by reference
//   atlasscan://?handoff=<base64-pack>   – receive VisitHandoffPackV1 from Mind

@main
struct AtlasScanApp: App {

    @StateObject private var visitStore = AtlasScanVisitStore.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(visitStore)
        }
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

