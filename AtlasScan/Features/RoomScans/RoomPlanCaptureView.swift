import SwiftUI
import RoomPlan

// MARK: - RoomPlanCaptureView
//
// Fullscreen modal for LiDAR room scanning using Apple RoomPlan.
//
// Flow:
//   1. Present fullscreen — "Start Scan" shown on a dark background.
//   2. User taps "Start" — live AR scanning begins via RoomCaptureView.
//   3. User taps "Stop"  — RoomPlan processes the captured geometry.
//   4. "Accept" and "Rescan" buttons appear when processing is complete.
//   5. "Accept" — maps the result via RoomPlanMapper and calls onAccept.
//   6. "Cancel" at any point — stops the session and calls onCancel.
//
// On devices without LiDAR, an unavailable state is shown immediately.

struct RoomPlanCaptureView: View {

    // MARK: - Dependencies

    @StateObject private var service = RoomPlanCaptureService()

    /// 1-based index used to generate the default room label (e.g. "Room 2").
    let roomIndex: Int

    /// Called when the engineer accepts the scan. Receives the mapped room scan,
    /// LiDAR-inferred object pins, and the auto-generated floor plan snapshot.
    let onAccept: (CapturedRoomScanDraft, [CapturedObjectPinDraft], CapturedFloorPlanSnapshotDraft) -> Void

    /// Called when the engineer cancels without saving.
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ZStack {
            if RoomPlanCaptureService.isSupported {
                supportedBody
            } else {
                unavailableBody
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Supported (LiDAR device) body

    private var supportedBody: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureRepresentable(captureView: service.roomCaptureView)
                .ignoresSafeArea()
            overlayControls
        }
    }

    // MARK: - Overlay controls

    private var overlayControls: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 60)
            Spacer()
            bottomActions
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            statusBadge
            Spacer()
            cancelButton
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(statusColor.opacity(0.85))
            .clipShape(Capsule())
    }

    private var cancelButton: some View {
        Button("Cancel") {
            service.cancelScan()
            onCancel()
            dismiss()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: - Status text / colour helpers

    private var statusText: String {
        switch service.sessionState {
        case .ready:       return "Ready"
        case .scanning:    return "Scanning…"
        case .processing:  return "Processing…"
        case .completed:   return "Scan Complete"
        case .cancelled:   return "Cancelled"
        case .unavailable: return "LiDAR Unavailable"
        case .failed:      return "Scan Failed"
        }
    }

    private var statusColor: Color {
        switch service.sessionState {
        case .ready:       return .blue
        case .scanning:    return .green
        case .processing:  return .orange
        case .completed:   return .green
        case .cancelled:   return .gray
        case .unavailable, .failed: return .red
        }
    }

    // MARK: - Bottom action buttons

    @ViewBuilder
    private var bottomActions: some View {
        switch service.sessionState {
        case .ready:
            startButton
        case .scanning:
            stopButton
        case .processing:
            processingIndicator
        case .completed:
            HStack(spacing: 16) {
                rescanButton
                acceptButton
            }
        case .cancelled, .unavailable, .failed:
            EmptyView()
        }
    }

    private var startButton: some View {
        Button {
            service.startScan()
        } label: {
            Label("Start Scan", systemImage: "lidar.scanner")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
    }

    private var stopButton: some View {
        Button {
            service.stopScan()
        } label: {
            Label("Stop Scan", systemImage: "stop.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    private var processingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Processing scan…")
                .foregroundStyle(.white)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var rescanButton: some View {
        Button {
            service.startScan()
        } label: {
            Label("Rescan", systemImage: "arrow.clockwise")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
    }

    private var acceptButton: some View {
        Button {
            acceptScan()
        } label: {
            Label("Accept", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(service.capturedResult == nil)
    }

    // MARK: - Accept

    private func acceptScan() {
        guard let result = service.capturedResult else { return }
        let (scan, pins) = RoomPlanMapper.map(result, roomIndex: roomIndex)
        let snapshot = RoomPlanMapper.autoSnapshot(for: scan)
        onAccept(scan, pins, snapshot)
        dismiss()
    }

    // MARK: - Unavailable body (non-LiDAR devices)

    private var unavailableBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lidar.scanner")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("LiDAR Not Available")
                .font(.title2.bold())
            Text("This device does not support LiDAR room scanning.\nUse manual entry to record room dimensions.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Dismiss") {
                onCancel()
                dismiss()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }
}

// MARK: - RoomCaptureRepresentable
//
// Bridges RoomCaptureView (UIKit) into SwiftUI.

private struct RoomCaptureRepresentable: UIViewRepresentable {

    let captureView: RoomCaptureView

    func makeUIView(context: Context) -> RoomCaptureView {
        captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

// MARK: - Preview

#if DEBUG
#Preview {
    RoomPlanCaptureView(roomIndex: 1, onAccept: { _, _, _ in }, onCancel: {})
}
#endif
