import SwiftUI
import RoomPlan
#if canImport(ARKit)
import ARKit
#endif

// MARK: - BuildInfoView
//
// Displays build-level, device-level, and capability metadata for TestFlight testers.
//
// Rows:
//   App Version, Build Number, Bundle ID,
//   Device Model, iOS Version,
//   LiDAR available, RoomPlan available

struct BuildInfoView: View {

    var body: some View {
        List {
            appSection
            deviceSection
            capabilitySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Build Info")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - App section

    private var appSection: some View {
        Section {
            infoRow("App Version",  value: appVersion)
            infoRow("Build Number", value: buildNumber)
            infoRow("Bundle ID",    value: bundleID)
        } header: {
            Text("App")
        }
    }

    // MARK: - Device section

    private var deviceSection: some View {
        Section {
            infoRow("Device Model", value: deviceModel)
            infoRow("iOS Version",  value: iosVersion)
        } header: {
            Text("Device")
        }
    }

    // MARK: - Capability section

    private var capabilitySection: some View {
        Section {
            capabilityRow("LiDAR",     available: lidarAvailable)
            capabilityRow("RoomPlan",  available: roomPlanAvailable)
        } header: {
            Text("Capabilities")
        } footer: {
            Text("LiDAR requires iPhone 12 Pro or later. RoomPlan requires iOS 16+ and LiDAR.")
                .font(.caption2)
        }
    }

    // MARK: - Row helpers

    private func infoRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func capabilityRow(_ label: String, available: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            if available {
                Label("Available", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else {
                Label("Unavailable", systemImage: "xmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Data sources

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "–"
    }

    private var deviceModel: String {
        var sysInfo = utsname()
        uname(&sysInfo)
        let mirror = Mirror(reflecting: sysInfo.machine)
        let identifier = mirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { Character(UnicodeScalar(UInt8(bitPattern: $0))) }
        return String(identifier)
    }

    private var iosVersion: String {
        UIDevice.current.systemVersion
    }

    private var lidarAvailable: Bool {
        #if canImport(ARKit)
        return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        #else
        return false
        #endif
    }

    private var roomPlanAvailable: Bool {
        RoomCaptureSession.isSupported
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        BuildInfoView()
    }
}
#endif
