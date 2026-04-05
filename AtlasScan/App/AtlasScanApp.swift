import SwiftUI

@main
struct AtlasScanApp: App {

    @StateObject private var jobStore = ScanJobStore()

    var body: some Scene {
        WindowGroup {
            ScanSessionListView()
                .environmentObject(jobStore)
        }
    }
}
