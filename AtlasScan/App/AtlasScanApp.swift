import SwiftUI

@main
struct AtlasScanApp: App {

    var body: some Scene {
        WindowGroup {
            TabView {
                // MARK: Tab 1 — Atlas Scan V2 visit capture flow
                // Start Visit → Live Capture → Review Visit → Export
                CaptureAppRootView()
                    .tabItem {
                        Label("Capture", systemImage: "camera.viewfinder")
                    }

                // MARK: Tab 2 — Atlas Recommendations web app
                // Wrapped WebView of next.atlas-phm.uk; deep-links to imported visits.
                NavigationStack {
                    AtlasRecommendationsWebView(visitId: nil)
                }
                .tabItem {
                    Label("Atlas", systemImage: "globe")
                }
            }
        }
    }
}
