import SwiftUI

// MARK: - RoomContextList
//
// Displays capture and planning content grouped by room, giving surveyors
// a spatially coherent view of each room's objects, proposed emitters,
// access notes, and room plan notes.
//
// Features:
//   - Per-room cards with coverage indicators (photos, notes, objects, planning).
//   - Room reassignment for key objects, proposed emitters, and planning notes.
//   - An explicit Unassigned section for content not linked to any room.
//   - Read-only when the visit is completed.

// MARK: - RoomContextList

/// Room-grouped context view showing capture and planning content anchored to rooms.
///
/// Intended for use inside `FieldPlanView` (and optionally `FieldReviewView`)
/// so the surveyor can review the full room-level picture and clean up any
/// room/object/planning relationships quickly.
struct RoomContextList: View {

    @ObservedObject var store: FieldVisitStore

    private let emitterCategoryRawValues: Set<String> = [
        "radiator", "radiator_drop", "towel_rail", "ufh_zone", "fan_convector"
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            ForEach(store.session.rooms) { room in
                RoomContextCard(
                    room: room,
                    store: store,
                    emitterCategoryRawValues: emitterCategoryRawValues
                )
            }
            unassignedSection
        }
    }

    // MARK: - Unassigned section

    @ViewBuilder
    private var unassignedSection: some View {
        let unassignedObjects   = unassignedKeyObjects
        let unassignedEmitters  = unassignedProposedEmitters
        let unassignedAccess    = unassignedAccessNotes
        let unassignedPlanNotes = unassignedRoomPlanNotes

        let hasAny = !unassignedObjects.isEmpty
            || !unassignedEmitters.isEmpty
            || !unassignedAccess.isEmpty
            || !unassignedPlanNotes.isEmpty

        if hasAny {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Unassigned Items")
                            .font(.subheadline.bold())
                        Text("These items are not linked to a room yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider().padding(.horizontal, 16)

                // Unassigned key objects
                ForEach(unassignedObjects) { obj in
                    RoomAssignmentRow(
                        icon: "tag",
                        tint: .blue,
                        title: obj.displayLabel,
                        subtitle: "Key object — no room",
                        currentRoomName: nil,
                        rooms: store.session.rooms,
                        isCompleted: store.isCompleted,
                        onAssign: { roomID in
                            store.assignKeyObject(obj.id, toRoom: roomID)
                        }
                    )
                }

                // Unassigned proposed emitters
                ForEach(unassignedEmitters) { emitter in
                    RoomAssignmentRow(
                        icon: "thermometer.medium",
                        tint: .orange,
                        title: emitter.displayLabel,
                        subtitle: "Proposed emitter — no room",
                        currentRoomName: nil,
                        rooms: store.session.rooms,
                        isCompleted: store.isCompleted,
                        onAssign: { roomID in
                            store.assignProposedEmitter(emitter.id, toRoom: roomID)
                        }
                    )
                }

                // Unassigned access notes
                ForEach(unassignedAccess) { note in
                    RoomAssignmentRow(
                        icon: "door.left.hand.open",
                        tint: .purple,
                        title: note.text,
                        subtitle: "Access note — no room",
                        currentRoomName: nil,
                        rooms: store.session.rooms,
                        isCompleted: store.isCompleted,
                        onAssign: { roomID in
                            store.assignAccessNote(note.id, toRoom: roomID)
                        }
                    )
                }

                // Unassigned room plan notes
                ForEach(unassignedPlanNotes) { note in
                    RoomAssignmentRow(
                        icon: "rectangle.portrait",
                        tint: .green,
                        title: note.text,
                        subtitle: "Room plan note — no room",
                        currentRoomName: nil,
                        rooms: store.session.rooms,
                        isCompleted: store.isCompleted,
                        onAssign: { roomID in
                            store.assignRoomPlanNote(note.id, toRoom: roomID)
                        }
                    )
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Computed: unassigned items

    /// Key objects stored at session level (roomID == session.id).
    private var unassignedKeyObjects: [TaggedObject] {
        store.session.taggedObjects.filter { $0.roomID == store.session.id }
    }

    /// Proposed emitters with no room association.
    private var unassignedProposedEmitters: [InstallMarkupObject] {
        store.session.installMarkupObjects.filter {
            $0.layer == .proposed
            && emitterCategoryRawValues.contains($0.categoryRawValue)
            && $0.roomID == nil
        }
    }

    /// Access notes with no room association.
    private var unassignedAccessNotes: [PlanningAnnotation] {
        store.session.planningAnnotations.filter {
            $0.kind == .accessNote && $0.roomID == nil
        }
    }

    /// Room plan notes with no room association.
    private var unassignedRoomPlanNotes: [PlanningAnnotation] {
        store.session.planningAnnotations.filter {
            $0.kind == .roomPlanNote && $0.roomID == nil
        }
    }
}

// MARK: - RoomContextCard

/// A card showing the capture and planning content for a single room.
private struct RoomContextCard: View {

    let room: ScannedRoom
    @ObservedObject var store: FieldVisitStore
    let emitterCategoryRawValues: Set<String>

    // MARK: Derived content

    private var keyObjects: [TaggedObject] {
        store.session.taggedObjects.filter { $0.roomID == room.id }
        + room.taggedObjects
    }

    private var proposedEmitters: [InstallMarkupObject] {
        store.session.installMarkupObjects.filter {
            $0.layer == .proposed
            && emitterCategoryRawValues.contains($0.categoryRawValue)
            && $0.roomID == room.id
        }
    }

    private var accessNotes: [PlanningAnnotation] {
        store.session.planningAnnotations.filter {
            $0.kind == .accessNote && $0.roomID == room.id
        }
    }

    private var roomPlanNotes: [PlanningAnnotation] {
        store.session.planningAnnotations.filter {
            $0.kind == .roomPlanNote && $0.roomID == room.id
        }
    }

    // Coverage flags
    private var hasPhotos: Bool   { !room.photos.isEmpty }
    private var hasNotes: Bool    { !room.voiceNotes.isEmpty || !room.notes.isEmpty }
    private var hasObjects: Bool  { !keyObjects.isEmpty }
    private var hasPlanning: Bool { !proposedEmitters.isEmpty || !accessNotes.isEmpty || !roomPlanNotes.isEmpty }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            roomHeader
            Divider()
            coverageRow
            if hasObjects || hasPlanning {
                Divider()
                contentRows
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Room header

    private var roomHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.split.2x1")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(room.name)
                .font(.subheadline.bold())
            Spacer()
            Text(room.displayFloor)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Coverage row

    private var coverageRow: some View {
        HStack(spacing: 16) {
            CoverageChip(label: "Photos",   present: hasPhotos,   symbol: "camera")
            CoverageChip(label: "Notes",    present: hasNotes,    symbol: "mic")
            CoverageChip(label: "Objects",  present: hasObjects,  symbol: "tag")
            CoverageChip(label: "Planning", present: hasPlanning, symbol: "pencil.and.ruler")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Content rows

    @ViewBuilder
    private var contentRows: some View {
        // Key objects
        ForEach(keyObjects) { obj in
            RoomAssignmentRow(
                icon: "tag",
                tint: .blue,
                title: obj.displayLabel,
                subtitle: "Key object",
                currentRoomName: room.name,
                rooms: store.session.rooms,
                isCompleted: store.isCompleted,
                onAssign: { roomID in
                    store.assignKeyObject(obj.id, toRoom: roomID)
                }
            )
        }

        // Proposed emitters
        ForEach(proposedEmitters) { emitter in
            RoomAssignmentRow(
                icon: "thermometer.medium",
                tint: .orange,
                title: emitter.displayLabel,
                subtitle: "Proposed emitter",
                currentRoomName: room.name,
                rooms: store.session.rooms,
                isCompleted: store.isCompleted,
                onAssign: { roomID in
                    store.assignProposedEmitter(emitter.id, toRoom: roomID)
                }
            )
        }

        // Access notes
        ForEach(accessNotes) { note in
            RoomAssignmentRow(
                icon: "door.left.hand.open",
                tint: .purple,
                title: note.text,
                subtitle: "Access note",
                currentRoomName: room.name,
                rooms: store.session.rooms,
                isCompleted: store.isCompleted,
                onAssign: { roomID in
                    store.assignAccessNote(note.id, toRoom: roomID)
                }
            )
        }

        // Room plan notes
        ForEach(roomPlanNotes) { note in
            RoomAssignmentRow(
                icon: "rectangle.portrait",
                tint: .green,
                title: note.text,
                subtitle: "Plan note",
                currentRoomName: room.name,
                rooms: store.session.rooms,
                isCompleted: store.isCompleted,
                onAssign: { roomID in
                    store.assignRoomPlanNote(note.id, toRoom: roomID)
                }
            )
        }
    }
}

// MARK: - CoverageChip

/// A compact indicator showing whether a coverage type is present for a room.
private struct CoverageChip: View {
    let label: String
    let present: Bool
    let symbol: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: present ? "\(symbol)" : "\(symbol)")
                .font(.caption2)
                .foregroundStyle(present ? Color.green : Color.secondary.opacity(0.4))
            Text(label)
                .font(.caption2)
                .foregroundStyle(present ? .primary : .secondary)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: present ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 8))
                .foregroundStyle(present ? Color.green : Color.secondary.opacity(0.4))
                .offset(x: 4, y: -2)
        }
    }
}

// MARK: - RoomAssignmentRow

/// A row for a single item (object, emitter, note) that supports room reassignment.
///
/// Shows the item's title, a subtitle, the current room, and (when not completed)
/// a "Change room" button that opens a picker.
struct RoomAssignmentRow: View {

    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let currentRoomName: String?
    let rooms: [ScannedRoom]
    let isCompleted: Bool
    let onAssign: (UUID?) -> Void

    @State private var showingPicker = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint.opacity(0.8))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isCompleted {
                Button {
                    showingPicker = true
                } label: {
                    Text(currentRoomName == nil ? "Assign room" : "Change room")
                        .font(.caption)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingPicker) {
                    RoomPickerSheet(
                        currentRoomName: currentRoomName,
                        rooms: rooms,
                        isPresented: $showingPicker,
                        onSelect: onAssign
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

        Divider().padding(.leading, 42)
    }
}

// MARK: - RoomPickerSheet

/// A sheet presenting a list of rooms plus "Unassigned" so the engineer can
/// reassign an item quickly.
private struct RoomPickerSheet: View {

    let currentRoomName: String?
    let rooms: [ScannedRoom]
    @Binding var isPresented: Bool
    let onSelect: (UUID?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                        isPresented = false
                    } label: {
                        HStack {
                            Text("Unassigned")
                                .foregroundStyle(.primary)
                            Spacer()
                            if currentRoomName == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Rooms") {
                    ForEach(rooms) { room in
                        Button {
                            onSelect(room.id)
                            isPresented = false
                        } label: {
                            HStack {
                                Text(room.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if currentRoomName == room.name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Assign Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    var session = PropertyScanSession(propertyAddress: "47 Baker Street")
    let kitchenID = UUID()
    let loungeID = UUID()
    session.addRoom(ScannedRoom(id: kitchenID, propertyID: session.id, name: "Kitchen"))
    session.addRoom(ScannedRoom(id: loungeID,  propertyID: session.id, name: "Lounge"))
    session.addTaggedObject(TaggedObject(roomID: kitchenID, category: .boiler))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))
    session.installMarkupObjects.append(
        InstallMarkupObject(categoryRawValue: "radiator", label: "Hall rad",
                            position: NormalizedPoint2D(x: 0.5, y: 0.5), layer: .proposed,
                            roomID: loungeID)
    )
    session.addPlanningAnnotation(
        PlanningAnnotation(text: "Pipe drop via cupboard", kind: .roomPlanNote, roomID: kitchenID)
    )
    session.addPlanningAnnotation(
        PlanningAnnotation(text: "Check loft hatch", kind: .accessNote)
    )
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return ScrollView {
        VStack(spacing: 16) {
            RoomContextList(store: visitStore)
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
