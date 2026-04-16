import SwiftUI

@main
struct AtlasScanApp: App {

    @StateObject private var jobStore = ScanJobStore()
    @StateObject private var sessionStore = ScanSessionStore()
    @StateObject private var atlasSync = AtlasSync()

    var body: some Scene {
        WindowGroup {
            TabView {
                // MARK: Primary — capture-only visit flow
                // Start Job → Capture Hub → capture sections → Review & Export
                CaptureAppRootView()
                    .tabItem {
                        Label("Capture", systemImage: "camera.viewfinder")
                    }

                // MARK: Secondary — completed session history (legacy + AtlasPropertyV1 export)
                // Quarantined from the default journey; visible but not the primary path.
                PropertySessionListView()
                    .environmentObject(sessionStore)
                    .environmentObject(atlasSync)
                    .tabItem {
                        Label("Sessions", systemImage: "clock.arrow.circlepath")
                    }

                #if DEBUG
                ScanSessionListView()
                    .environmentObject(jobStore)
                    .tabItem {
                        Label("Jobs (Legacy)", systemImage: "folder")
                    }
                #endif
            }
        }
    }
}
