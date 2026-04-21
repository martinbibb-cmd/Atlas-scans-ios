import SwiftUI
import AtlasContracts

// MARK: - FieldPlanView

/// Plan tab for the field visit shell.
///
/// Shows live planning cards for proposed emitters, access notes, room plan notes,
/// and spec notes.  Each card shows a count badge, up to three recent entries with
/// delete actions, and an "Add …" button.
///
/// All mutations go through `FieldVisitStore` so planning readiness in the Review
/// tab updates immediately after every save.  The tab is read-only when the visit
/// is completed.
struct FieldPlanView: View {

    @ObservedObject var store: FieldVisitStore

    // MARK: Sheet state

    @State private var showingAddEmitter    = false
    @State private var showingAddAccessNote = false
    @State private var showingAddRoomNote   = false
    @State private var showingAddSpecNote   = false
    @State private var showRoomContext      = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isCompleted {
                    completedNotice
                }
                if !store.session.rooms.isEmpty {
                    roomContextToggle
                    if showRoomContext {
                        RoomContextList(store: store)
                    }
                }
                proposedEmittersCard
                accessNotesCard
                roomPlanNotesCard
                specNotesCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { store.enterPlanningPhase() }
        .sheet(isPresented: $showingAddEmitter) {
            AddProposedEmitterSheet(store: store, isPresented: $showingAddEmitter)
        }
        .sheet(isPresented: $showingAddAccessNote) {
            AddAccessNoteSheet(store: store, isPresented: $showingAddAccessNote)
        }
        .sheet(isPresented: $showingAddRoomNote) {
            AddRoomPlanNoteSheet(store: store, isPresented: $showingAddRoomNote)
        }
        .sheet(isPresented: $showingAddSpecNote) {
            AddSpecNoteSheet(store: store, isPresented: $showingAddSpecNote)
        }
    }

    // MARK: - Room context toggle

    private var roomContextToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showRoomContext.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.split.2x1")
                    .foregroundStyle(.blue)
                Text("Room Context")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: showRoomContext ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Completed notice

    private var completedNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text("This visit has been completed and is now read-only.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Proposed emitters card

    private var proposedEmittersCard: some View {
        let emitters = store.session.installMarkupObjects
            .filter { $0.layer == .proposed && emitterCategoryRawValues.contains($0.categoryRawValue) }
        return PlanningCard(
            title: "Proposed Emitters",
            count: emitters.count,
            symbol: "thermometer.medium",
            tint: .orange,
            emptyText: "No proposed emitters added yet",
            addButtonLabel: store.isCompleted ? nil : "Add Radiator",
            onAdd: { showingAddEmitter = true }
        ) {
            ForEach(emitters.prefix(3)) { emitter in
                PlanningItemRow(
                    icon: "thermometer.medium",
                    tint: .orange,
                    title: emitterDisplayName(emitter),
                    subtitle: emitter.note.isEmpty ? nil : emitter.note,
                    isCompleted: store.isCompleted,
                    onDelete: { store.removeProposedEmitter(id: emitter.id) }
                )
            }
            if emitters.count > 3 {
                Text("+ \(emitters.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Access notes card

    private var accessNotesCard: some View {
        let notes = store.session.planningAnnotations(ofKind: .accessNote)
        return PlanningCard(
            title: "Access Notes",
            count: notes.count,
            symbol: "door.left.hand.open",
            tint: .purple,
            emptyText: "No access notes added yet",
            addButtonLabel: store.isCompleted ? nil : "Add Access Note",
            onAdd: { showingAddAccessNote = true }
        ) {
            ForEach(notes.prefix(3)) { note in
                PlanningItemRow(
                    icon: "door.left.hand.open",
                    tint: .purple,
                    title: note.text,
                    subtitle: note.category.map { categoryDisplayName($0) },
                    isCompleted: store.isCompleted,
                    onDelete: { store.removeAccessNote(id: note.id) }
                )
            }
            if notes.count > 3 {
                Text("+ \(notes.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Room plan notes card

    private var roomPlanNotesCard: some View {
        let notes = store.session.planningAnnotations(ofKind: .roomPlanNote)
        return PlanningCard(
            title: "Room Plan Notes",
            count: notes.count,
            symbol: "rectangle.portrait",
            tint: .green,
            emptyText: "No room plan notes added yet",
            addButtonLabel: store.isCompleted ? nil : "Add Room Plan Note",
            onAdd: { showingAddRoomNote = true }
        ) {
            ForEach(notes.prefix(3)) { note in
                PlanningItemRow(
                    icon: "rectangle.portrait",
                    tint: .green,
                    title: note.text,
                    subtitle: roomName(for: note.roomID),
                    isCompleted: store.isCompleted,
                    onDelete: { store.removeRoomPlanNote(id: note.id) }
                )
            }
            if notes.count > 3 {
                Text("+ \(notes.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Spec notes card

    private var specNotesCard: some View {
        let notes = store.session.planningAnnotations(ofKind: .specNote)
        return PlanningCard(
            title: "Spec Notes",
            count: notes.count,
            symbol: "list.bullet.clipboard",
            tint: .gray,
            emptyText: "No spec notes added yet",
            addButtonLabel: store.isCompleted ? nil : "Add Spec Note",
            onAdd: { showingAddSpecNote = true }
        ) {
            ForEach(notes.prefix(3)) { note in
                PlanningItemRow(
                    icon: "list.bullet.clipboard",
                    tint: .gray,
                    title: note.text,
                    subtitle: nil,
                    isCompleted: store.isCompleted,
                    onDelete: { store.removeSpecNote(id: note.id) }
                )
            }
            if notes.count > 3 {
                Text("+ \(notes.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Helpers

    private let emitterCategoryRawValues: Set<String> = [
        "radiator", "radiator_drop", "towel_rail", "ufh_zone", "fan_convector"
    ]

    private func emitterDisplayName(_ obj: InstallMarkupObject) -> String {
        let type = ServiceObjectCategory(rawValue: obj.categoryRawValue)?.displayName ?? obj.categoryRawValue
        let label = obj.label.isEmpty ? type : "\(type) — \(obj.label)"
        return obj.replacesExisting ? "\(label) (replaces existing)" : label
    }

    private func roomName(for roomID: UUID?) -> String? {
        guard let roomID else { return nil }
        return store.session.rooms.first(where: { $0.id == roomID })?.name
    }

    private func categoryDisplayName(_ raw: String) -> String {
        switch raw {
        case "ladder":       return "Ladder"
        case "clearance":    return "Clearance"
        case "obstruction":  return "Obstruction"
        case "loft_access":  return "Loft Access"
        case "emitter":      return "Emitter"
        case "pipework":     return "Pipework"
        case "access":       return "Access"
        case "controls":     return "Controls"
        case "general":      return "General"
        default:             return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - PlanningCard

/// A card showing a planning category (emitters, access notes, etc.)
/// with a count badge, item list, and optional add button.
private struct PlanningCard<Content: View>: View {
    let title: String
    let count: Int
    let symbol: String
    let tint: Color
    let emptyText: String
    let addButtonLabel: String?
    let onAdd: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(count > 0 ? tint : .secondary)
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.15))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if count == 0 {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            if let addButtonLabel, let onAdd {
                Divider()
                Button(action: onAdd) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(tint)
                        Text(addButtonLabel)
                            .font(.subheadline)
                            .foregroundStyle(tint)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - PlanningItemRow

/// A single item row inside a PlanningCard showing title, optional subtitle,
/// and a delete button.
private struct PlanningItemRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    let isCompleted: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint.opacity(0.8))
                .frame(width: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !isCompleted {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        Divider()
    }
}

// MARK: - AddProposedEmitterSheet

/// Sheet for adding a proposed emitter to the planning overlay.
private struct AddProposedEmitterSheet: View {
    @ObservedObject var store: FieldVisitStore
    @Binding var isPresented: Bool

    private let emitterTypes: [(ServiceObjectCategory, String)] = [
        (.radiator,     "Radiator"),
        (.radiatorDrop, "Vertical Radiator"),
        (.towelRail,    "Towel Rail"),
        (.ufhZone,      "UFH Zone"),
        (.fanConvector, "Fan Convector"),
        (.other,        "Other"),
    ]

    @State private var selectedType: ServiceObjectCategory = .radiator
    @State private var selectedRoomID: UUID?               = nil
    @State private var label                               = ""
    @State private var note                                = ""
    @State private var replacesExisting                    = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Emitter Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(emitterTypes, id: \.0) { type, name in
                            Text(name).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if !store.session.rooms.isEmpty {
                    Section("Room (optional)") {
                        Picker("Room", selection: $selectedRoomID) {
                            Text("No room").tag(UUID?.none)
                            ForEach(store.session.rooms) { room in
                                Text(room.name).tag(UUID?.some(room.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Label (optional)") {
                    TextField("e.g. Hall radiator, Guest bath towel rail", text: $label)
                }

                Section("Note (optional)") {
                    TextField("e.g. Double panel, under window", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Toggle("Replaces existing emitter", isOn: $replacesExisting)
                }
            }
            .navigationTitle("Add Radiator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addProposedEmitter(
                            roomID: selectedRoomID,
                            type: selectedType,
                            label: label,
                            note: note,
                            replacesExisting: replacesExisting
                        )
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - AddAccessNoteSheet

/// Sheet for adding an access constraint note to the planning overlay.
private struct AddAccessNoteSheet: View {
    @ObservedObject var store: FieldVisitStore
    @Binding var isPresented: Bool

    private let categories: [(String, String)] = [
        ("general",      "General"),
        ("ladder",       "Ladder"),
        ("clearance",    "Clearance"),
        ("obstruction",  "Obstruction"),
        ("loft_access",  "Loft Access"),
    ]

    @State private var selectedRoomID: UUID?  = nil
    @State private var selectedCategory       = "general"
    @State private var noteText               = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.0) { raw, display in
                            Text(display).tag(raw)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if !store.session.rooms.isEmpty {
                    Section("Room (optional)") {
                        Picker("Room", selection: $selectedRoomID) {
                            Text("No room").tag(UUID?.none)
                            ForEach(store.session.rooms) { room in
                                Text(room.name).tag(UUID?.some(room.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Note") {
                    TextField("Describe the access constraint…", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Access Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addAccessNote(
                            roomID: selectedRoomID,
                            category: selectedCategory,
                            note: noteText
                        )
                        isPresented = false
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - AddRoomPlanNoteSheet

/// Sheet for adding a per-room planning note to the planning overlay.
private struct AddRoomPlanNoteSheet: View {
    @ObservedObject var store: FieldVisitStore
    @Binding var isPresented: Bool

    private let categories: [(String, String)] = [
        ("general",   "General"),
        ("emitter",   "Emitter"),
        ("pipework",  "Pipework"),
        ("access",    "Access"),
        ("controls",  "Controls"),
    ]

    @State private var selectedRoomID: UUID?  = nil
    @State private var selectedCategory       = "general"
    @State private var noteText               = ""

    var body: some View {
        NavigationStack {
            Form {
                if !store.session.rooms.isEmpty {
                    Section("Room (optional)") {
                        Picker("Room", selection: $selectedRoomID) {
                            Text("No room").tag(UUID?.none)
                            ForEach(store.session.rooms) { room in
                                Text(room.name).tag(UUID?.some(room.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.0) { raw, display in
                            Text(display).tag(raw)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Note") {
                    TextField("Describe the room planning intent…", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Room Plan Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addRoomPlanNote(
                            roomID: selectedRoomID,
                            category: selectedCategory,
                            note: noteText
                        )
                        isPresented = false
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - AddSpecNoteSheet

/// Sheet for adding a quick spec / material note to the planning overlay.
private struct AddSpecNoteSheet: View {
    @ObservedObject var store: FieldVisitStore
    @Binding var isPresented: Bool

    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("e.g. Filter required on return, 22mm flow pipe", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Spec Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addSpecNote(noteText)
                        isPresented = false
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    let session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldPlanView(store: visitStore)
}
#endif

