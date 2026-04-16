import SwiftUI

// MARK: - RoomScanCaptureView
//
// Entry point for capturing a single room in the new SessionCaptureV2 flow.
//
// Flow:
//   1. Setup screen — engineer enters an optional room label and taps "Start Scan".
//   2. Live scan — RoomCaptureContainerView is presented full-screen. On LiDAR
//      hardware this uses RoomPlanScannerAdapter; on simulator / non-LiDAR devices
//      MockScannerAdapter is used automatically.
//   3. On scan completion, the ScannedRoom is mapped to CapturedRoomScanDraft and
//      returned via onComplete.
//
// The captured draft stores raw observation data only — no derived maths.

struct RoomScanCaptureView: View {

    let onComplete: (CapturedRoomScanDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var roomLabel: String = ""
    @State private var showingLiveScanner = false

    /// Disposable job UUID used only to satisfy RoomCaptureContainerView's API.
    /// It carries no semantic meaning in the SessionCaptureV2 flow.
    private let ephemeralJobID = UUID()

    var body: some View {
        NavigationStack {
            setupView
                .navigationTitle("Room Scan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .fullScreenCover(isPresented: $showingLiveScanner) {
            RoomCaptureContainerView(
                jobID: ephemeralJobID,
                roomName: roomLabel.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Room"
                    : roomLabel.trimmingCharacters(in: .whitespaces),
                floor: 0
            ) { scannedRoom in
                showingLiveScanner = false
                let draft = mapToDraft(from: scannedRoom)
                onComplete(draft)
            }
        }
    }

    // MARK: - Setup view

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lidar.scanner")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Ready to Scan")
                    .font(.title2.bold())
                Text("Enter an optional label for this room, then tap Start Scan.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Room label (e.g. Kitchen)", text: $roomLabel)
                .textInputAutocapitalization(.words)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()

            Button {
                showingLiveScanner = true
            } label: {
                Label("Start Scan", systemImage: "lidar.scanner")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
    }

    // MARK: - ScannedRoom → CapturedRoomScanDraft

    /// Maps the legacy ScannedRoom output from RoomCaptureContainerView into
    /// a CapturedRoomScanDraft for the SessionCaptureV2 capture flow.
    ///
    /// Dimension extraction:
    ///   • rawHeightM  — ceiling height from the scanner
    ///   • rawWidthM   — longest wall length (approximation of room width)
    ///   • rawDepthM   — shortest wall length (approximation of room depth)
    private func mapToDraft(from room: ScannedRoom) -> CapturedRoomScanDraft {
        var draft = CapturedRoomScanDraft()

        // Preserve any label the engineer set during setup.
        let label = room.name.trimmingCharacters(in: .whitespaces)
        draft.roomLabel = label.isEmpty ? nil : label

        // Map ceiling height directly.
        draft.rawHeightM = room.ceilingHeightMetres

        // Approximate width / depth from wall lengths when geometry was captured.
        // Note: using the longest and shortest measured walls is a best-effort
        // approximation for rectangular rooms. For irregular or L-shaped rooms the
        // values will be less accurate, but the ScannedRoom model does not provide a
        // floor polygon or bounding box to derive more precise measurements.
        if room.geometryCaptured {
            let sortedWallLengths = room.walls.compactMap(\.lengthMetres).sorted()
            // At least two distinct wall measurements are needed to differentiate
            // the two primary room dimensions (width and depth).
            if sortedWallLengths.count >= 2,
               let shortest = sortedWallLengths.first,
               let longest = sortedWallLengths.last {
                draft.rawDepthM = shortest
                draft.rawWidthM = longest
            }
        }

        // Map scan confidence.
        draft.confidence = room.geometryCaptured ? .high : .medium

        // Propagate any warning codes from the scanner state.
        // (ScannedRoom carries no explicit warning strings in the legacy model;
        // confidence downgrade above already signals low-quality captures.)

        return draft
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    RoomScanCaptureView { _ in }
}
#endif
