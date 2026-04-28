import SwiftUI

// MARK: - AtlasScanApp
//
// Root entry point.
//
// Navigation stack:
//   WelcomeView
//     ├── Scan → VisitPickerView → CaptureAppRootView (visit-owned)
//     └── Mind → AtlasRecommendationsWebView

@main
struct AtlasScanApp: App {

    var body: some Scene {
        WindowGroup {
            AtlasRootView()
        }
    }
}

// MARK: - AtlasRootView

/// Manages top-level navigation between Welcome, Scan, and Mind modes.
struct AtlasRootView: View {

    @State private var activeMode: AtlasMode?

    var body: some View {
        Group {
            if let mode = activeMode {
                switch mode {
                case .scan:
                    ScanRootView {
                        // "Back to Welcome" from within the scan flow
                        activeMode = nil
                    }
                    .transition(.move(edge: .trailing))
                case .mind:
                    MindRootView {
                        activeMode = nil
                    }
                    .transition(.move(edge: .trailing))
                }
            } else {
                WelcomeView { selected in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        activeMode = selected
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: activeMode != nil)
    }
}

// MARK: - ScanRootView

/// Top-level container for the Scan mode.
///
/// Stack: VisitPickerView → CaptureAppRootView (per visit)
struct ScanRootView: View {

    let onBackToWelcome: () -> Void

    @State private var activeDraft: CaptureSessionDraft?

    var body: some View {
        Group {
            if activeDraft != nil {
                CaptureAppRootView(initialDraft: activeDraft!) {
                    // Returned from capture flow (e.g. after export)
                    activeDraft = nil
                }
            } else {
                NavigationStack {
                    VisitPickerView { draft in
                        activeDraft = draft
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                onBackToWelcome()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Atlas")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - MindRootView

/// Top-level container for the Mind mode (Atlas Recommendations PWA).
struct MindRootView: View {

    let onBackToWelcome: () -> Void

    var body: some View {
        NavigationStack {
            AtlasRecommendationsWebView(visitId: nil)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onBackToWelcome()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Atlas")
                            }
                        }
                    }
                }
        }
    }
}

