import SwiftUI

@main
struct AtlasScanApp: App {

    @StateObject private var jobStore = ScanJobStore()
    @StateObject private var sessionStore = ScanSessionStore()
    @StateObject private var atlasSync = AtlasSync()

    var body: some Scene {
        WindowGroup {
            TabView {
                PropertySessionListView()
                    .environmentObject(sessionStore)
                    .environmentObject(atlasSync)
                    .tabItem {
                        Label("Sessions", systemImage: "camera.viewfinder")
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
