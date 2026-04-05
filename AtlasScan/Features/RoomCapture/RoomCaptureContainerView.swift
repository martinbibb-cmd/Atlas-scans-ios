import SwiftUI
import Combine

// MARK: - RoomCaptureContainerView
//
// Scaffold for the room capture flow.
// Uses MockScannerAdapter for simulator / development.
// In PR 2, swap MockScannerAdapter for RoomPlanScannerAdapter.

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
                adapter: MockScannerAdapter(),
                jobID: jobID,
                roomName: roomName,
                floor: floor
            )
        )
    }

    var body: some View {
        ZStack {
            scannerPlaceholder
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

    // MARK: - Scanner placeholder

    private var scannerPlaceholder: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(.white.opacity(0.3))

                Text("Point the camera at the room\nand move slowly around the perimeter.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.subheadline)
            }
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

    private let adapter: any ScannerAdapterProtocol
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

    var statusMessage: String {
        switch state {
        case .idle:             return "Ready to scan"
        case .initialising:     return "Starting scanner…"
        case .scanning:         return "Scanning room…"
        case .processing:       return "Processing geometry…"
        case .completed:        return "Room captured!"
        case .failed(let msg):  return "Error: \(msg)"
        }
    }

    var statusSymbol: String {
        switch state {
        case .completed:   return "checkmark.circle.fill"
        case .failed:      return "xmark.circle.fill"
        default:           return "camera.viewfinder"
        }
    }

    var statusColor: Color {
        switch state {
        case .completed:   return .green
        case .failed:      return .red
        default:           return .white
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
