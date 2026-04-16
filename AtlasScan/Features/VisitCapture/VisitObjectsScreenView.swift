import SwiftUI

// MARK: - VisitObjectsScreenView

/// Object placement and tagging screen within the visit session.
///
/// Shows all placed objects (session-level and room-level) and provides
/// the ability to add new objects and attach photos to them.
struct VisitObjectsScreenView: View {

    @ObservedObject var viewModel: VisitCaptureViewModel
    @State private var showingAddObject = false
    @State private var showingAddPhoto = false

    var body: some View {
        List {
            roomFilterSection
            if viewModel.session.allTaggedObjects.isEmpty {
                emptyState
            } else {
                objectsSection
            }
            actionsSection
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingAddObject) {
            addObjectSheet
        }
        .sheet(isPresented: $showingAddPhoto) {
            addPhotoSheet
        }
    }

    // MARK: - Room filter

    private var roomFilterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    roomPill(id: nil, name: "All")
                    ForEach(viewModel.session.rooms) { room in
                        roomPill(id: room.id, name: room.name.isEmpty ? "Room" : room.name)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private func roomPill(id: UUID?, name: String) -> some View {
        let isSelected = viewModel.selectedRoomID == id
        return Button {
            viewModel.selectRoom(id)
        } label: {
            Text(name)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Objects list

    private var filteredObjects: [TaggedObject] {
        if let roomID = viewModel.selectedRoomID {
            return viewModel.session.rooms
                .first(where: { $0.id == roomID })?.taggedObjects ?? []
        }
        return viewModel.session.allTaggedObjects
    }

    private var objectsSection: some View {
        Section("Objects (\(filteredObjects.count))") {
            ForEach(filteredObjects) { object in
                objectRow(object)
            }
        }
    }

    private func objectRow(_ object: TaggedObject) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(object.displayLabel)
                    .font(.body)
                HStack(spacing: 8) {
                    Label(object.category.displayName, systemImage: object.category.symbolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Label(object.placementMode.displayName, systemImage: object.placementMode.symbolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                confidenceBadge(object.confidence)
                if !object.linkedPhotoIDs.isEmpty {
                    Label("\(object.linkedPhotoIDs.count)", systemImage: "camera.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectObject(object.id)
        }
        .background(
            viewModel.selectedObjectID == object.id
                ? Color.accentColor.opacity(0.1)
                : Color.clear
        )
    }

    private func confidenceBadge(_ level: TaggedObjectConfidenceLevel) -> some View {
        let color: Color
        switch level {
        case .high:    color = .green
        case .medium:  color = .orange
        case .low, .unknown: color = .red
        }
        return Text(level.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No objects tagged")
                    .foregroundStyle(.secondary)
                Text("Add objects to track service equipment locations.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                showingAddObject = true
            } label: {
                Label("Add Object", systemImage: "plus.circle")
                    .font(.body.bold())
            }

            if viewModel.selectedObjectID != nil {
                Button {
                    showingAddPhoto = true
                } label: {
                    Label("Add Photo to Selected Object", systemImage: "camera.badge.plus")
                }
            }
        } header: {
            Text("Actions")
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private var addObjectSheet: some View {
        let room = viewModel.selectedRoom ?? viewModel.makePlaceholderRoom()
        AddObjectSheet(room: room) { object in
            viewModel.addObject(object)
            showingAddObject = false
        }
    }

    private var addPhotoSheet: some View {
        AddPhotoSheet(
            roomID: viewModel.selectedRoomID,
            taggedObjectID: viewModel.selectedObjectID
        ) { photo in
            viewModel.addPhoto(photo)
            showingAddPhoto = false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    var session = PropertyScanSession(propertyAddress: "12 Test Lane")
    var room = ScannedRoom(jobID: session.id, name: "Boiler Room")
    room.addTaggedObject(TaggedObject(roomID: room.id, category: .boiler))
    session.addRoom(room)
    let vm = VisitCaptureViewModel(session: session, sessionStore: store, atlasSync: AtlasSync())
    return VisitObjectsScreenView(viewModel: vm)
}
#endif
