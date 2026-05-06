import SwiftUI

// Atlas Scan V2 — capture-only app.
// The root scene now uses ScanSessionCoordinator + MindRecallClient
// and launches into PropertyMapView.

@main
struct AtlasScanApp: App {

    @StateObject private var coordinator = ScanSessionCoordinator()
    @StateObject private var recallClient = MindRecallClient(store: .shared)

    var body: some Scene {
        WindowGroup {
            PropertyMapView()
                .environmentObject(coordinator)
                .environmentObject(recallClient)
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

