import SwiftUI

// MARK: - TestFlightDiagnosticsView
//
// Entry-point sheet for TestFlight smoke-test diagnostics.
// Accessible to all testers from the Atlas Scan home screen.
//
// Sections:
//   Build Info  — app version, build number, bundle ID, device model,
//                 iOS version, LiDAR/RoomPlan availability
//   Permissions — camera, microphone, speech, photos, motion/AR status

struct TestFlightDiagnosticsView: View {

    let onClose: () -> Void

    @State private var showingFeedback = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        BuildInfoView()
                    } label: {
                        Label("Build & Device Info", systemImage: "info.circle")
                    }

                    NavigationLink {
                        PermissionPreflightView()
                    } label: {
                        Label("Permissions", systemImage: "lock.shield")
                    }
                } header: {
                    Text("TestFlight Diagnostics")
                } footer: {
                    Text("Use these screens to verify device capabilities and permission status before testing. Share screenshots with your feedback report.")
                        .font(.caption2)
                }

                Section {
                    Button {
                        showingFeedback = true
                    } label: {
                        Label("Report TestFlight Issue", systemImage: "exclamationmark.bubble")
                    }
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Opens a pre-filled report with your build number, device model, and iOS version. Share it via email, Notes, or any other app.")
                        .font(.caption2)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
            }
            .sheet(isPresented: $showingFeedback) {
                ShareSheet(items: TestFlightFeedbackReporter.makeShareItems())
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    TestFlightDiagnosticsView(onClose: {})
}
#endif
