import SwiftUI
import AVFoundation
import Speech
import Photos
import CoreMotion

// MARK: - PermissionPreflightView
//
// Shows the current authorisation status for every permission the app needs.
// Designed for TestFlight testers to verify that all permissions are granted
// before beginning a capture session.
//
// Permissions checked:
//   Camera, Microphone, Speech Recognition, Photo Library — OS authorization status.
//   Motion Activity — hardware availability (no authorization prompt required).
//   Local Network   — listed as "future / optional" (no runtime API to query).

struct PermissionPreflightView: View {

    @State private var cameraStatus:  PermissionStatus = .unknown
    @State private var micStatus:     PermissionStatus = .unknown
    @State private var speechStatus:  PermissionStatus = .unknown
    @State private var photosStatus:  PermissionStatus = .unknown
    @State private var motionAvailable: Bool? = nil

    var body: some View {
        List {
            Section {
                permissionRow("Camera",             symbol: "camera",              status: cameraStatus)
                permissionRow("Microphone",         symbol: "mic",                 status: micStatus)
                permissionRow("Speech Recognition", symbol: "waveform",            status: speechStatus)
                permissionRow("Photo Library",      symbol: "photo.on.rectangle",  status: photosStatus)
                hardwareAvailabilityRow(
                    "Motion Activity",
                    symbol: "gyroscope",
                    available: motionAvailable
                )
            } header: {
                Text("Required Permissions")
            } footer: {
                Text("Motion Activity shows hardware availability — the device prompts for authorization only when the app first accesses step/activity data.")
                    .font(.caption2)
            }

            Section {
                HStack {
                    Label("Local Network", systemImage: "network")
                    Spacer()
                    Text("Future / Optional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Future Permissions")
            } footer: {
                Text("Local network access is not used in this build. It will be required in a future release for collaborative capture.")
                    .font(.caption2)
            }

            Section {
                Button {
                    Task { await refreshAll() }
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAll() }
    }

    // MARK: - Permission row

    private func permissionRow(_ label: String, symbol: String, status: PermissionStatus) -> some View {
        HStack {
            Label(label, systemImage: symbol)
            Spacer()
            permissionStatusBadge(status)
        }
    }

    @ViewBuilder
    private func permissionStatusBadge(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
                .font(.caption.bold())
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.red)
                .font(.caption.bold())
        case .restricted:
            Label("Restricted", systemImage: "minus.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.orange)
                .font(.caption.bold())
        case .notDetermined:
            Label("Not Asked", systemImage: "questionmark.circle")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .font(.caption.bold())
        case .unknown:
            ProgressView()
        }
    }

    // MARK: - Hardware availability row

    private func hardwareAvailabilityRow(
        _ label: String,
        symbol: String,
        available: Bool?
    ) -> some View {
        HStack {
            Label(label, systemImage: symbol)
            Spacer()
            hardwareAvailabilityBadge(available)
        }
    }

    @ViewBuilder
    private func hardwareAvailabilityBadge(_ available: Bool?) -> some View {
        switch available {
        case .none:
            ProgressView()
        case .some(true):
            Label("Available", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
                .font(.caption.bold())
        case .some(false):
            Label("Not Available", systemImage: "xmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.red)
                .font(.caption.bold())
        }
    }

    // MARK: - Refresh

    @MainActor
    private func refreshAll() async {
        cameraStatus    = await checkCamera()
        micStatus       = await checkMicrophone()
        speechStatus    = await checkSpeech()
        photosStatus    = await checkPhotos()
        motionAvailable = CMMotionActivityManager.isActivityAvailable()
    }

    private func checkCamera() async -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:                 return .granted
        case .denied:                     return .denied
        case .restricted:                 return .restricted
        case .notDetermined:              return .notDetermined
        @unknown default:                 return .unknown
        }
    }

    private func checkMicrophone() async -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:                 return .granted
        case .denied:                     return .denied
        case .restricted:                 return .restricted
        case .notDetermined:              return .notDetermined
        @unknown default:                 return .unknown
        }
    }

    private func checkSpeech() async -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:                 return .granted
        case .denied:                     return .denied
        case .restricted:                 return .restricted
        case .notDetermined:              return .notDetermined
        @unknown default:                 return .unknown
        }
    }

    private func checkPhotos() async -> PermissionStatus {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:       return .granted
        case .denied:                     return .denied
        case .restricted:                 return .restricted
        case .notDetermined:              return .notDetermined
        @unknown default:                 return .unknown
        }
    }
}

// MARK: - PermissionStatus

private enum PermissionStatus {
    case granted, denied, restricted, notDetermined, unknown
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        PermissionPreflightView()
    }
}
#endif
