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
        let results = clearanceResults
        return List {
            layoutSection(with: results)
            geometrySection
            serviceObjectsSection(with: results)
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

    private func layoutSection(with results: [UUID: ClearanceResult]) -> some View {
        Section {
            RoomLayoutView(
                room: room,
                selectedObjectID: selectedObjectIDOnLayout,
                clearanceResults: results,
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

            if let selectedID = selectedObjectIDOnLayout,
               let result = results[selectedID] {
                ClearanceSummaryView(result: result)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }
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

    private func serviceObjectsSection(with results: [UUID: ClearanceResult]) -> some View {
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
                        TaggedObjectRowView(
                            object: object,
                            clearanceStatus: results[object.id]?.status
                        )
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

    // MARK: - Clearance

    private var clearanceResults: [UUID: ClearanceResult] {
        room.taggedObjects.reduce(into: [:]) { dict, obj in
            if let result = ClearanceEngine.evaluate(object: obj, in: room) {
                dict[obj.id] = result
            }
        }
    }
}

// MARK: - TaggedObjectRowView

struct TaggedObjectRowView: View {
    let object: TaggedObject
    var clearanceStatus: ClearanceStatus? = nil

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
                if let status = clearanceStatus {
                    ClearanceDot(status: status)
                }
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

// MARK: - ClearanceDot

/// A small icon indicating the clearance status of a service object.
struct ClearanceDot: View {
    let status: ClearanceStatus

    var body: some View {
        Image(systemName: status.symbolName)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .clear:    return .green
        case .warning:  return .orange
        case .conflict: return .red
        }
    }
}

// MARK: - ClearanceSummaryView

/// Compact panel showing the clearance evaluation result for a selected object.
/// Displayed in the Room Layout section when an object with clearance data is tapped.
struct ClearanceSummaryView: View {
    let result: ClearanceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: result.status.symbolName)
                    .foregroundStyle(statusColor)
                Text(result.status.displayMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text("Clearance Check")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: issueSFSymbol(for: issue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let note = result.confidenceNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(12)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch result.status {
        case .clear:    return .green
        case .warning:  return .orange
        case .conflict: return .red
        }
    }

    private func issueSFSymbol(for issue: ClearanceIssue) -> String {
        switch issue.kind {
        case .frontAccessRestricted:     return "arrow.forward.circle"
        case .tooCloseToSideWall:        return "arrow.left.arrow.right"
        case .rearClearanceInsufficient: return "arrow.backward.circle"
        case .openingWithinAccessZone:   return "door.left.hand.open"
        case .ceilingHeightLimiting:     return "arrow.up.to.line"
        case .enclosedInstallation:      return "cabinet.fill"
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
