import SwiftUI

// MARK: - VisitLiDARScreenView

/// LiDAR / RoomPlan capture screen within the visit session.
///
/// Shows the list of rooms already captured and provides a button to
/// start a new room scan.  Each completed scan updates the shared session
/// without creating a separate session fragment.
struct VisitLiDARScreenView: View {

    @ObservedObject var viewModel: VisitCaptureViewModel
    @State private var showingRoomCapture = false
    @State private var showingAddRoomManually = false
    @State private var newRoomName = ""
    @State private var newRoomFloor = 0

    var body: some View {
        List {
            if viewModel.session.rooms.isEmpty {
                emptyState
            } else {
                roomsSection
            }
            actionsSection
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingRoomCapture) {
            roomCaptureSheet
        }
        .sheet(isPresented: $showingAddRoomManually) {
            addRoomManuallySheet
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "lidar.scanner")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No rooms captured yet")
                    .foregroundStyle(.secondary)
                Text("Start a LiDAR room scan or add a room manually.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Rooms list

    private var roomsSection: some View {
        Section("Rooms (\(viewModel.session.rooms.count))") {
            ForEach(viewModel.session.rooms) { room in
                roomRow(room)
            }
        }
    }

    private func roomRow(_ room: ScannedRoom) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name.isEmpty ? "Unnamed Room" : room.name)
                    .font(.body)
                HStack(spacing: 8) {
                    if room.geometryCaptured {
                        Label("LiDAR", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Label("Manual", systemImage: "pencil.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let area = room.areaSquareMetres {
                        Text(String(format: "%.1f m²", area))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Floor \(room.floor)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if room.isReviewed {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectRoom(room.id)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                showingRoomCapture = true
            } label: {
                Label("Start LiDAR Room Scan", systemImage: "lidar.scanner")
                    .font(.body.bold())
            }

            Button {
                newRoomName = ""
                newRoomFloor = 0
                showingAddRoomManually = true
            } label: {
                Label("Add Room Manually", systemImage: "plus.rectangle.on.rectangle")
            }
        } header: {
            Text("Actions")
        }
    }

    // MARK: - Room capture sheet

    @ViewBuilder
    private var roomCaptureSheet: some View {
        NavigationStack {
            RoomCaptureContainerView(
                jobID: viewModel.session.id,
                roomName: "New Room",
                floor: 0
            ) { scannedRoom in
                viewModel.addRoom(scannedRoom)
                showingRoomCapture = false
            }
            .navigationTitle("Room Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRoomCapture = false }
                }
            }
        }
    }

    // MARK: - Add room manually sheet

    private var addRoomManuallySheet: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room name", text: $newRoomName)
                    Stepper("Floor \(newRoomFloor)", value: $newRoomFloor, in: -2...10)
                }
            }
            .navigationTitle("Add Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddRoomManually = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let room = ScannedRoom(
                            jobID: viewModel.session.id,
                            name: newRoomName.trimmingCharacters(in: .whitespaces),
                            floor: newRoomFloor
                        )
                        viewModel.addRoom(room)
                        showingAddRoomManually = false
                    }
                    .disabled(newRoomName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    var session = PropertyScanSession(propertyAddress: "12 Test Lane")
    session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen", geometryCaptured: true))
    session.addRoom(ScannedRoom(jobID: session.id, name: "Living Room"))
    let vm = VisitCaptureViewModel(session: session, sessionStore: store, atlasSync: AtlasSync())
    return VisitLiDARScreenView(viewModel: vm)
}
#endif
