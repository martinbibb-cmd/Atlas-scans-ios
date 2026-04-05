import SwiftUI

// MARK: - ScanJobDetailView
//
// Shows the rooms within a job and provides navigation to capture / review / export.

struct ScanJobDetailView: View {

    @EnvironmentObject private var jobStore: ScanJobStore
    @State private var job: ScanJob
    @State private var showingAddRoom = false
    @State private var showingExport = false
    @State private var newRoomName = ""
    @State private var newRoomFloor = 0

    init(job: ScanJob) {
        _job = State(initialValue: job)
    }

    var body: some View {
        List {
            jobHeaderSection
            roomsSection
            if !job.rooms.isEmpty {
                propertyPlanSection
                exportSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(job.propertyAddress)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddRoom = true
                } label: {
                    Label("Add Room", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRoom) {
            addRoomSheet
        }
        .sheet(isPresented: $showingExport) {
            ExportPreviewView(job: $job)
        }
        .onReceive(NotificationCenter.default.publisher(for: .roomUpdated)) { note in
            if let updated = note.object as? ScannedRoom, updated.jobID == job.id {
                job.updateRoom(updated)
                jobStore.save(job)
            }
        }
    }

    // MARK: - Sections

    private var jobHeaderSection: some View {
        Section("Job Details") {
            LabeledContent("Reference", value: job.jobReference)
            LabeledContent("Engineer", value: job.engineerName.isEmpty ? "–" : job.engineerName)
            LabeledContent("Status", value: job.status.displayName)
            LabeledContent("Rooms", value: "\(job.rooms.count)")
            LabeledContent("Tagged objects", value: "\(job.totalTaggedObjects)")
        }
    }

    private var roomsSection: some View {
        Section {
            if job.rooms.isEmpty {
                Text("No rooms yet. Tap + to add a room.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(job.rooms) { room in
                    NavigationLink {
                        RoomReviewView(room: room, job: $job)
                    } label: {
                        RoomRowView(room: room)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        job.removeRoom(id: job.rooms[index].id)
                    }
                    jobStore.save(job)
                }
            }
        } header: {
            Text("Rooms")
        }
    }

    private var propertyPlanSection: some View {
        Section {
            NavigationLink {
                PropertyPlanView(job: $job)
            } label: {
                Label("Property Plan", systemImage: "map")
            }
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                showingExport = true
            } label: {
                Label("Export to Atlas", systemImage: "arrow.up.doc.fill")
                    .foregroundStyle(job.isReadyToExport ? .blue : .orange)
            }

            if !job.isReadyToExport {
                Text("Mark all rooms as reviewed before exporting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Add room sheet

    private var addRoomSheet: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room name", text: $newRoomName)
                        .autocorrectionDisabled()

                    Picker("Floor", selection: $newRoomFloor) {
                        Text("Basement").tag(-1)
                        Text("Ground Floor").tag(0)
                        Text("First Floor").tag(1)
                        Text("Second Floor").tag(2)
                    }
                }

                Section {
                    NavigationLink("Scan Room") {
                        RoomCaptureContainerView(
                            jobID: job.id,
                            roomName: newRoomName.isEmpty ? "New Room" : newRoomName,
                            floor: newRoomFloor
                        ) { capturedRoom in
                            job.addRoom(capturedRoom)
                            jobStore.save(job)
                            showingAddRoom = false
                        }
                    }
                    .disabled(newRoomName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Add Room (Manual / No Scan)") {
                        let room = ScannedRoom(
                            jobID: job.id,
                            name: newRoomName.isEmpty ? "New Room" : newRoomName,
                            floor: newRoomFloor
                        )
                        job.addRoom(room)
                        jobStore.save(job)
                        newRoomName = ""
                        newRoomFloor = 0
                        showingAddRoom = false
                    }
                    .disabled(newRoomName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Add Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddRoom = false
                        newRoomName = ""
                        newRoomFloor = 0
                    }
                }
            }
        }
    }
}

// MARK: - RoomRowView

struct RoomRowView: View {
    let room: ScannedRoom

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(room.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(room.displayFloor)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let area = room.areaSquareMetres {
                        Text(String(format: "%.1f m²", area))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !room.taggedObjects.isEmpty {
                        Label("\(room.taggedObjects.count)", systemImage: "tag.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            if room.isReviewed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if room.geometryCaptured {
                Image(systemName: "camera.viewfinder")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Notification extension

extension Notification.Name {
    static let roomUpdated = Notification.Name("AtlasScan.roomUpdated")
}

// MARK: - Previews

#if DEBUG
#Preview {
    NavigationStack {
        ScanJobDetailView(job: MockData.sampleJob)
            .environmentObject(ScanJobStore())
    }
}
#endif
