import SwiftUI

// MARK: - ObjectPinListView
//
// Lists all object and pin placements for the visit.
// Provides quick placement of typed objects with optional room and wall association.
//
// Wall-mounted objects (radiator, towel rail, fan convector) show wall context.
// If no wall is assigned to a wall-mounted object, a "Needs wall placement"
// badge is shown to prompt the engineer.

struct ObjectPinListView: View {

    @ObservedObject var store: CaptureSessionStore
    @State private var showingPlacement = false
    @State private var editingPin: CapturedObjectPinDraft?

    var sortedPins: [CapturedObjectPinDraft] {
        store.draft.objectPins.sorted { $0.placedAt > $1.placedAt }
    }

    var body: some View {
        List {
            if sortedPins.isEmpty {
                emptyState
            } else {
                pinsSection
            }
            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Objects & Pins")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPlacement) {
            ObjectPinPlacementView(
                roomScans: store.draft.roomScans,
                fabricRecords: store.draft.fabricRecords,
                photos: store.draft.photos
            ) { pin in
                store.addObjectPin(pin)
                showingPlacement = false
            }
        }
        .sheet(item: $editingPin) { pin in
            ObjectPinEditView(
                pin: pin,
                roomScans: store.draft.roomScans,
                fabricRecords: store.draft.fabricRecords,
                photos: store.draft.photos
            ) { updated in
                store.updateObjectPin(updated)
                editingPin = nil
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No objects placed")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Quickly tag boilers, radiators, and other items to record their location.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Pins list

    private var pinsSection: some View {
        Section("Objects (\(sortedPins.count))") {
            ForEach(sortedPins) { pin in
                pinRow(pin)
                    .contentShape(Rectangle())
                    .onTapGesture { editingPin = pin }
            }
            .onDelete { indexSet in
                let sorted = sortedPins
                indexSet.forEach { i in
                    store.removeObjectPin(id: sorted[i].id)
                }
            }
        }
    }

    private func pinRow(_ pin: CapturedObjectPinDraft) -> some View {
        HStack(spacing: 12) {
            pinIcon(pin.type)
            VStack(alignment: .leading, spacing: 4) {
                Text(pin.label ?? pin.type.displayName)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(pin.type.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let roomId = pin.roomId,
                       let scan = store.draft.roomScans.first(where: { $0.id == roomId }) {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(scan.roomLabel ?? "Room")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Wall context for wall-mounted objects
                    if pin.type.isWallMounted {
                        if let wallId = pin.attachedWallId,
                           let wallLabel = wallContextLabel(for: wallId) {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Label(wallLabel, systemImage: "square.grid.2x2")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Needs wall placement", systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            Spacer()
            if pin.linkedPhotoId != nil {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pinIcon(_ type: ObjectPinType) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: type.symbolName)
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
        }
    }

    /// Returns a short wall label (e.g. "Wall 2") for the given wall UUID by
    /// searching all fabric records in the session.
    private func wallContextLabel(for wallId: UUID) -> String? {
        for record in store.draft.fabricRecords {
            if let wall = record.boundaries.first(where: { $0.id == wallId }) {
                return wall.wallIndex.map { "Wall \($0)" } ?? "Wall"
            }
        }
        return nil
    }

    // MARK: - Actions section

    private var actionsSection: some View {
        Section {
            Button {
                showingPlacement = true
            } label: {
                Label("Add Object / Pin", systemImage: "plus.circle")
                    .font(.body.bold())
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("Place objects to record what's in each room. No engineering calculations are run on placements.")
                .font(.caption2)
        }
    }
}

// MARK: - ObjectPinPlacementView

struct ObjectPinPlacementView: View {

    let roomScans: [CapturedRoomScanDraft]
    let fabricRecords: [CapturedFloorPlanFabricDraft]
    let photos: [CapturedPhotoDraft]
    let onPlace: (CapturedObjectPinDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: ObjectPinType = .boiler
    @State private var label: String = ""
    @State private var selectedRoomId: UUID?
    @State private var selectedWallId: UUID?
    @State private var selectedPhotoId: UUID?

    /// Walls available in the selected room's fabric record.
    private var availableWalls: [CapturedBoundaryDraft] {
        guard let roomId = selectedRoomId else { return [] }
        return fabricRecords.first(where: { $0.roomId == roomId })?.boundaries ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Object Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(ObjectPinType.allCases) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: selectedType) { _, _ in
                        // Clear wall selection when type changes to non-wall-mounted.
                        if !selectedType.isWallMounted { selectedWallId = nil }
                    }
                }

                Section("Label (optional)") {
                    TextField("e.g. Worcester Bosch 30i", text: $label)
                }

                if !roomScans.isEmpty {
                    Section("Room") {
                        Picker("Room", selection: $selectedRoomId) {
                            Text("Session level").tag(UUID?.none)
                            ForEach(roomScans) { scan in
                                Text(scan.roomLabel ?? "Unnamed Room").tag(Optional(scan.id))
                            }
                        }
                        .onChange(of: selectedRoomId) { _, _ in
                            // Reset wall when room changes.
                            selectedWallId = nil
                        }
                    }
                }

                if selectedType.isWallMounted && !availableWalls.isEmpty {
                    Section("Wall") {
                        Picker("Wall", selection: $selectedWallId) {
                            Text("Not assigned").tag(UUID?.none)
                            ForEach(availableWalls) { wall in
                                Text(wall.wallIndex.map { "Wall \($0)" } ?? wall.boundaryType.displayName)
                                    .tag(Optional(wall.id))
                            }
                        }
                    }
                }

                if !photos.isEmpty {
                    Section("Linked Photo (optional)") {
                        Picker("Photo", selection: $selectedPhotoId) {
                            Text("None").tag(UUID?.none)
                            ForEach(photos) { photo in
                                Text(photo.kind.displayName + " · " + photo.captureTimestamp.formatted(date: .omitted, time: .shortened))
                                    .tag(Optional(photo.id))
                            }
                        }
                    }
                }

                Section {
                    Button {
                        placePin()
                    } label: {
                        Label("Place Object", systemImage: "mappin.circle.fill")
                            .frame(maxWidth: .infinity)
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Add Object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func placePin() {
        var pin = CapturedObjectPinDraft(type: selectedType)
        pin.label = label.trimmingCharacters(in: .whitespaces).isEmpty ? nil : label.trimmingCharacters(in: .whitespaces)
        pin.roomId = selectedRoomId
        pin.linkedPhotoId = selectedPhotoId
        if selectedType.isWallMounted {
            pin.attachedWallId = selectedWallId
        }
        onPlace(pin)
    }
}

// MARK: - ObjectPinEditView

struct ObjectPinEditView: View {

    @State var pin: CapturedObjectPinDraft
    let roomScans: [CapturedRoomScanDraft]
    let fabricRecords: [CapturedFloorPlanFabricDraft]
    let photos: [CapturedPhotoDraft]
    let onSave: (CapturedObjectPinDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var label: String = ""

    /// Walls for the pin's currently selected room.
    private var availableWalls: [CapturedBoundaryDraft] {
        guard let roomId = pin.roomId else { return [] }
        return fabricRecords.first(where: { $0.roomId == roomId })?.boundaries ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    LabeledContent("Object Type", value: pin.type.displayName)
                }
                Section("Label") {
                    TextField("Optional label", text: $label)
                }
                if !roomScans.isEmpty {
                    Section("Room") {
                        Picker("Room", selection: $pin.roomId) {
                            Text("Session level").tag(UUID?.none)
                            ForEach(roomScans) { scan in
                                Text(scan.roomLabel ?? "Unnamed Room").tag(Optional(scan.id))
                            }
                        }
                        .onChange(of: pin.roomId) { _, _ in
                            // Clear wall when room changes.
                            if pin.type.isWallMounted { pin.attachedWallId = nil }
                        }
                    }
                }

                if pin.type.isWallMounted {
                    Section("Wall") {
                        if availableWalls.isEmpty {
                            Text("No walls recorded for this room. Add a fabric review record first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Wall", selection: $pin.attachedWallId) {
                                Text("Not assigned").tag(UUID?.none)
                                ForEach(availableWalls) { wall in
                                    Text(wall.wallIndex.map { "Wall \($0)" } ?? wall.boundaryType.displayName)
                                        .tag(Optional(wall.id))
                                }
                            }
                        }
                    }
                }

                Section("Details") {
                    Text(pin.placedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .navigationTitle("Edit Object")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { label = pin.label ?? "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        pin.label = label.trimmingCharacters(in: .whitespaces).isEmpty ? nil : label
                        onSave(pin)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var draft = CaptureSessionDraft()
    draft.visitReference = "JOB-001"
    var pin = CapturedObjectPinDraft(type: .boiler)
    pin.label = "Worcester Bosch 30i"
    var rad = CapturedObjectPinDraft(type: .radiator)
    rad.label = "Lounge radiator"
    draft.objectPins = [pin, rad]
    let store = CaptureSessionStore(draft: draft)
    return NavigationStack {
        ObjectPinListView(store: store)
    }
}
#endif
