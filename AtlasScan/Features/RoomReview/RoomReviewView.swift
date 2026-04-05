import SwiftUI

// MARK: - RoomReviewView
//
// Shows the captured/manual room geometry, lets the engineer:
//   • rename the room
//   • review/edit walls and openings
//   • add/edit/delete tagged service objects
//   • place objects on the room layout
//   • mark the room as reviewed

struct RoomReviewView: View {

    @State private var room: ScannedRoom
    @Binding var job: ScanJob
    @EnvironmentObject private var jobStore: ScanJobStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddObject = false
    @State private var selectedObject: TaggedObject?
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var selectedObjectIDOnLayout: UUID?

    init(room: ScannedRoom, job: Binding<ScanJob>) {
        _room = State(initialValue: room)
        _job = job
    }

    var body: some View {
        List {
            layoutSection
            geometrySection
            serviceObjectsSection
            notesSection
            reviewSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddObject = true
                } label: {
                    Label("Add Object", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Rename") {
                    editedName = room.name
                    isEditingName = true
                }
            }
        }
        .sheet(isPresented: $showingAddObject) {
            AddObjectSheet(room: room) { newObject in
                room.addTaggedObject(newObject)
                persistRoom()
            }
        }
        .sheet(item: $selectedObject) { object in
            EditObjectSheet(object: object) { updated in
                room.updateTaggedObject(updated)
                persistRoom()
                selectedObject = nil
            }
        }
        .alert("Rename Room", isPresented: $isEditingName) {
            TextField("Room name", text: $editedName)
            Button("Save") {
                room.name = editedName
                persistRoom()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var layoutSection: some View {
        Section {
            RoomLayoutView(
                room: room,
                selectedObjectID: selectedObjectIDOnLayout,
                onTapRoom: nil,
                onTapObject: { id in
                    selectedObjectIDOnLayout = id
                    selectedObject = room.taggedObjects.first { $0.id == id }
                },
                onMoveObject: { id, newPos in
                    guard var obj = room.taggedObjects.first(where: { $0.id == id }) else { return }
                    PlacementService.place(object: &obj, at: newPos, in: room)
                    room.updateTaggedObject(obj)
                    persistRoom()
                }
            )
            .listRowInsets(EdgeInsets())
            .frame(minHeight: 220)
        } header: {
            Text("Room Layout")
        } footer: {
            Text("Drag objects to reposition. Tap an object to edit.")
                .font(.caption2)
        }
    }

    private var geometrySection: some View {
        Section {
            if room.geometryCaptured {
                Label("Geometry captured by scanner", systemImage: "camera.viewfinder")
                    .foregroundStyle(.green)
            } else {
                Label("Manual entry — no scan geometry", systemImage: "pencil.and.ruler")
                    .foregroundStyle(.orange)
            }

            if let area = room.areaSquareMetres {
                LabeledContent("Floor area", value: String(format: "%.1f m²", area))
            }

            if let height = room.ceilingHeightMetres {
                LabeledContent("Ceiling height", value: String(format: "%.2f m", height))
            }

            LabeledContent("Floor", value: room.displayFloor)
            LabeledContent("Walls", value: "\(room.walls.count)")
            LabeledContent("Openings", value: "\(room.openings.count)")
        } header: {
            Text("Geometry")
        }
    }

    private var serviceObjectsSection: some View {
        Section {
            if room.taggedObjects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No service objects tagged yet.")
                        .foregroundStyle(.secondary)
                    Button("Add Object") { showingAddObject = true }
                        .font(.subheadline)
                }
            } else {
                ForEach(room.taggedObjects) { object in
                    Button {
                        selectedObject = object
                    } label: {
                        TaggedObjectRowView(object: object)
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    for index in offsets {
                        room.removeTaggedObject(id: room.taggedObjects[index].id)
                    }
                    persistRoom()
                }
            }
        } header: {
            HStack {
                Text("Service Objects")
                Spacer()
                Button {
                    showingAddObject = true
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Engineer notes (optional)", text: $room.notes, axis: .vertical)
                .lineLimit(3...6)
                .onChange(of: room.notes) { _, _ in persistRoom() }
        }
    }

    private var reviewSection: some View {
        Section {
            Toggle("Mark Room as Reviewed", isOn: $room.isReviewed)
                .onChange(of: room.isReviewed) { _, _ in persistRoom() }

            if room.isReviewed {
                Label("Room signed off", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Persistence

    private func persistRoom() {
        room.touch()
        job.updateRoom(room)
        jobStore.save(job)
        NotificationCenter.default.post(name: .roomUpdated, object: room)
    }
}

// MARK: - TaggedObjectRowView

struct TaggedObjectRowView: View {
    let object: TaggedObject

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: object.category.symbolName)
                .frame(width: 28, height: 28)
                .foregroundStyle(.white)
                .background(categoryColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(object.displayLabel)
                    .font(.subheadline.bold())

                HStack(spacing: 6) {
                    Text(object.category.groupName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !object.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                ConfidenceDot(confidence: object.confidence)
                if object.isConfirmed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var categoryColor: Color {
        switch object.category.groupName {
        case "Heat Source / Plant":     return .orange
        case "Emitters":                return .red
        case "Services / Utilities":    return .blue
        case "Controls":                return .purple
        case "Structural / Siting":     return .gray
        default:                        return .secondary
        }
    }
}

// MARK: - ConfidenceDot

struct ConfidenceDot: View {
    let confidence: ConfidenceLevel

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch confidence {
        case .high:    return .green
        case .medium:  return .orange
        case .low:     return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NavigationStack {
        RoomReviewView(
            room: MockData.utilityRoom,
            job: .constant(MockData.sampleJob)
        )
        .environmentObject(ScanJobStore())
    }
}
#endif
