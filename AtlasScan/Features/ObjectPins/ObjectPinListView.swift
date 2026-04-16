import SwiftUI

// MARK: - ObjectPinListView
//
// Lists all object and pin placements for the visit.
// Provides quick placement of typed objects with optional room association.

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
                photos: store.draft.photos
            ) { pin in
                store.addObjectPin(pin)
                showingPlacement = false
            }
        }
        .sheet(item: $editingPin) { pin in
            ObjectPinEditView(pin: pin, roomScans: store.draft.roomScans, photos: store.draft.photos) { updated in
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
                HStack(spacing: 8) {
                    Text(pin.type.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let roomId = pin.roomId,
                       let scan = store.draft.roomScans.first(where: { $0.id == roomId }) {
                        Label(scan.roomLabel ?? "Room", systemImage: "square.split.2x1")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                .foregroundStyle(.accentColor)
        }
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
    let photos: [CapturedPhotoDraft]
    let onPlace: (CapturedObjectPinDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: ObjectPinType = .boiler
    @State private var label: String = ""
    @State private var selectedRoomId: UUID?
    @State private var selectedPhotoId: UUID?

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
        onPlace(pin)
    }
}

// MARK: - ObjectPinEditView

struct ObjectPinEditView: View {

    @State var pin: CapturedObjectPinDraft
    let roomScans: [CapturedRoomScanDraft]
    let photos: [CapturedPhotoDraft]
    let onSave: (CapturedObjectPinDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var label: String = ""

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
    draft.objectPins = [pin]
    let store = CaptureSessionStore(draft: draft)
    return NavigationStack {
        ObjectPinListView(store: store)
    }
}
#endif
