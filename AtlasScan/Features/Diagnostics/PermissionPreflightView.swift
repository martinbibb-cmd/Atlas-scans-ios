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
//   Camera, Microphone, Speech Recognition, Photo Library,
//   Motion/AR (CMMotionActivityManager),
//   Local Network — listed as "future / optional" (no runtime API to query)

struct PermissionPreflightView: View {

    @State private var cameraStatus:  PermissionStatus = .unknown
    @State private var micStatus:     PermissionStatus = .unknown
    @State private var speechStatus:  PermissionStatus = .unknown
    @State private var photosStatus:  PermissionStatus = .unknown
    @State private var motionStatus:  PermissionStatus = .unknown

    var body: some View {
        List {
            Section {
                permissionRow("Camera",             symbol: "camera",              status: cameraStatus)
                permissionRow("Microphone",         symbol: "mic",                 status: micStatus)
                permissionRow("Speech Recognition", symbol: "waveform",            status: speechStatus)
                permissionRow("Photo Library",      symbol: "photo.on.rectangle",  status: photosStatus)
                permissionRow("Motion / AR",        symbol: "gyroscope",           status: motionStatus)
            } header: {
                Text("Required Permissions")
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

    // MARK: - Row

    private func permissionRow(_ label: String, symbol: String, status: PermissionStatus) -> some View {
        HStack {
            Label(label, systemImage: symbol)
            Spacer()
            statusBadge(status)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionStatus) -> some View {
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

    // MARK: - Refresh

    @MainActor
    private func refreshAll() async {
        cameraStatus  = await checkCamera()
        micStatus     = await checkMicrophone()
        speechStatus  = await checkSpeech()
        photosStatus  = await checkPhotos()
        motionStatus  = checkMotion()
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

    private func checkMotion() -> PermissionStatus {
        if CMMotionActivityManager.isActivityAvailable() {
            return .granted
        }
        return .denied
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
