import SwiftUI
import UIKit
import Combine

// MARK: - ScannerViewRepresentable
//
// Wraps a UIView (e.g. RoomCaptureView) for embedding in SwiftUI.
// Used to show the live RoomPlan camera feed when a real adapter is active.

struct ScannerViewRepresentable: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - RoomCaptureContainerView
//
// Hosts the room capture flow.
// On LiDAR-capable devices the RoomPlanScannerAdapter provides a live camera view.
// On simulator / non-LiDAR hardware MockScannerAdapter is used automatically.
// Set the ATLAS_FORCE_MOCK_SCANNER=1 environment variable to force the mock adapter
// even on supported hardware (useful for UI development and demos).

struct RoomCaptureContainerView: View {

    let jobID: UUID
    let roomName: String
    let floor: Int
    let onRoomCaptured: (ScannedRoom) -> Void

    @StateObject private var viewModel: RoomCaptureViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        jobID: UUID,
        roomName: String,
        floor: Int,
        onRoomCaptured: @escaping (ScannedRoom) -> Void
    ) {
        self.jobID = jobID
        self.roomName = roomName
        self.floor = floor
        self.onRoomCaptured = onRoomCaptured
        _viewModel = StateObject(
            wrappedValue: RoomCaptureViewModel(
                adapter: RoomCaptureContainerView.makeAdapter(),
                jobID: jobID,
                roomName: roomName,
                floor: floor
            )
        )
    }

    var body: some View {
        ZStack {
            scannerBackground
            overlay
        }
        .navigationTitle("Scanning: \(roomName)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.state.isActive)
        .onAppear {
            viewModel.startCapture()
        }
        .onChange(of: viewModel.capturedRoom) { _, room in
            guard let room else { return }
            onRoomCaptured(room)
        }
    }

    // MARK: - Adapter factory

    /// Chooses the real RoomPlan adapter on LiDAR hardware, MockScannerAdapter elsewhere.
    private static func makeAdapter() -> any ScannerAdapterProtocol {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ATLAS_FORCE_MOCK_SCANNER"] == "1" {
            return MockScannerAdapter()
        }
        #endif
        if RoomPlanScannerAdapter.isSupported {
            return RoomPlanScannerAdapter()
        }
        return MockScannerAdapter()
    }

    // MARK: - Scanner background

    /// Shows the live RoomPlan camera feed while active; falls back to a placeholder.
    private var scannerBackground: some View {
        ZStack {
            if let liveView = viewModel.scannerView, viewModel.state.isActive {
                ScannerViewRepresentable(view: liveView)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: backgroundSymbol)
                        .font(.system(size: 80))
                        .foregroundStyle(.white.opacity(0.3))

                    Text(backgroundMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.subheadline)
                }
            }
        }
    }

    private var backgroundSymbol: String {
        switch viewModel.state {
        case .unsupported:      return "exclamationmark.triangle"
        case .permissionDenied: return "camera.fill"
        default:                return "camera.viewfinder"
        }
    }

    private var backgroundMessage: String {
        switch viewModel.state {
        case .unsupported:
            return "This device does not support LiDAR room scanning."
        case .permissionDenied:
            return "Camera access is required to scan a room.\nGrant permission in Settings."
        default:
            return "Point the camera at the room\nand move slowly around the perimeter."
        }
    }

    // MARK: - Overlay HUD

    private var overlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                statusCard

                if viewModel.state == .scanning {
                    Button {
                        viewModel.stopCapture()
                    } label: {
                        Label("Finish Scanning", systemImage: "stop.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }

                if case .permissionDenied = viewModel.state {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }

                if !viewModel.state.isActive {
                    Button {
                        viewModel.cancelCapture()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.bottom, 32)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            if viewModel.state.isActive {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: viewModel.statusSymbol)
                    .foregroundStyle(viewModel.statusColor)
            }

            Text(viewModel.statusMessage)
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - RoomCaptureViewModel

@MainActor
final class RoomCaptureViewModel: ObservableObject {

    @Published private(set) var state: ScannerState = .idle
    @Published private(set) var capturedRoom: ScannedRoom?

    let adapter: any ScannerAdapterProtocol
    let jobID: UUID
    let roomName: String
    let floor: Int

    private var cancellables = Set<AnyCancellable>()

    init(adapter: any ScannerAdapterProtocol, jobID: UUID, roomName: String, floor: Int) {
        self.adapter = adapter
        self.jobID = jobID
        self.roomName = roomName
        self.floor = floor

        adapter.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState
                if case .completed(let room) = newState {
                    var r = room
                    r.name = roomName
                    r.floor = floor
                    self?.capturedRoom = r
                }
            }
            .store(in: &cancellables)
    }

    func startCapture() {
        adapter.startCapture(jobID: jobID, roomName: roomName)
    }

    func stopCapture() {
        adapter.stopCapture()
    }

    func cancelCapture() {
        adapter.cancelCapture()
    }

    /// The live-camera UIView from the adapter, or nil when using a placeholder.
    var scannerView: UIView? { adapter.scannerView }

    var statusMessage: String {
        switch state {
        case .idle:             return "Ready to scan"
        case .initialising:     return "Starting scanner…"
        case .scanning:         return "Scanning room…"
        case .processing:       return "Processing geometry…"
        case .completed:        return "Room captured!"
        case .failed(let msg):  return "Error: \(msg)"
        case .unsupported:      return "LiDAR not available on this device"
        case .permissionDenied: return "Camera access required"
        }
    }

    var statusSymbol: String {
        switch state {
        case .completed:        return "checkmark.circle.fill"
        case .failed:           return "xmark.circle.fill"
        case .unsupported:      return "exclamationmark.triangle.fill"
        case .permissionDenied: return "camera.fill.badge.ellipsis"
        default:                return "camera.viewfinder"
        }
    }

    var statusColor: Color {
        switch state {
        case .completed:                    return .green
        case .failed:                       return .red
        case .unsupported, .permissionDenied: return .orange
        default:                            return .white
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NavigationStack {
        RoomCaptureContainerView(
            jobID: UUID(),
            roomName: "Living Room",
            floor: 0
        ) { _ in }
    }
}
#endif
