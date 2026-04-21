import SwiftUI
import PhotosUI

// MARK: - FieldCaptureView

/// Capture tab for the field visit shell.
///
/// Provides functional capture actions for all minimum required completion items:
/// rooms, photos, boiler, flue, and notes.  Each action writes through
/// `FieldVisitStore` so readiness updates immediately after every save.
///
/// Layout:
///   - Read-only notice when the visit is completed.
///   - Rooms section: count + latest room names + add/delete.
///   - Photos section: count + thumbnails + add/delete.
///   - Key Objects section: boiler and flue counts + add/delete.
///   - Notes section: count + note previews + add/delete.
struct FieldCaptureView: View {

    @ObservedObject var store: FieldVisitStore

    // MARK: Sheet state

    @State private var showingAddRoom    = false
    @State private var showingAddBoiler  = false
    @State private var showingAddFlue    = false
    @State private var showingAddNote    = false
    @State private var showingCamera     = false

    // Photo picker state (PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isCompleted {
                    completedNotice
                }
                roomsSection
                photosSection
                keyObjectsSection
                notesSection
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { store.enterCapturePhase() }
        // MARK: Sheets
        .sheet(isPresented: $showingAddRoom) {
            AddRoomSheet(store: store, isPresented: $showingAddRoom)
        }
        .sheet(isPresented: $showingAddBoiler) {
            AddKeyObjectSheet(store: store, category: .boiler, isPresented: $showingAddBoiler)
        }
        .sheet(isPresented: $showingAddFlue) {
            AddKeyObjectSheet(store: store, category: .flue, isPresented: $showingAddFlue)
        }
        .sheet(isPresented: $showingAddNote) {
            AddNoteSheet(store: store, isPresented: $showingAddNote)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPickerView(
                onImage: { image in
                    savePhoto(image)
                    showingCamera = false
                },
                onDismiss: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    savePhoto(image)
                }
                selectedPhotoItem = nil
            }
        }
    }

    // MARK: - Photo helper

    private func savePhoto(_ image: UIImage) {
        let photoID = UUID()
        guard let saved = try? PhotoStore.shared.save(image, id: photoID) else { return }
        let photo = TaggedPhoto(
            id: photoID,
            filename: saved.filename,
            thumbnailPath: saved.thumbnailPath,
            kind: .overview
        )
        store.addPhoto(photo)
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

    // MARK: - Rooms section

    private var roomsSection: some View {
        let rooms = store.session.rooms
        return CaptureCategoryCard(
            title: "Rooms",
            count: rooms.count,
            symbol: "square.split.2x1",
            tint: .blue,
            isEmpty: rooms.isEmpty,
            emptyText: "No rooms added yet",
            addButtonLabel: store.isCompleted ? nil : "Add Room",
            onAdd: { showingAddRoom = true }
        ) {
            ForEach(rooms.prefix(3)) { room in
                HStack {
                    Image(systemName: "square.split.2x1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(room.name)
                        .font(.subheadline)
                    Spacer()
                    if !store.isCompleted {
                        Button(role: .destructive) {
                            store.removeRoom(id: room.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
            if rooms.count > 3 {
                Text("+ \(rooms.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Photos section

    private var photosSection: some View {
        let allPhotos = store.session.allPhotos
        return CaptureCategoryCard(
            title: "Photos",
            count: allPhotos.count,
            symbol: "camera",
            tint: .orange,
            isEmpty: allPhotos.isEmpty,
            emptyText: "No photos added yet",
            addButtonLabel: nil,
            onAdd: nil
        ) {
            // Thumbnail row
            if !allPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allPhotos.prefix(10)) { photo in
                            ZStack(alignment: .topTrailing) {
                                PhotoThumbnailCell(photo: photo)
                                if !store.isCompleted {
                                    Button(role: .destructive) {
                                        PhotoStore.shared.deleteFiles(for: photo)
                                        store.removePhoto(id: photo.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            // Add photo buttons (library + camera)
            if !store.isCompleted {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: - Key objects section

    private var keyObjectsSection: some View {
        let allObjects = store.session.allTaggedObjects
        let boilers = allObjects.filter { $0.category == .boiler || $0.category == .heatPump }
        let flues   = allObjects.filter { $0.category == .flue }

        return CaptureCategoryCard(
            title: "Key Objects",
            count: boilers.count + flues.count,
            symbol: "mappin.and.ellipse",
            tint: .purple,
            isEmpty: boilers.isEmpty && flues.isEmpty,
            emptyText: "No boiler or flue tagged yet",
            addButtonLabel: nil,
            onAdd: nil
        ) {
            // Boiler row
            KeyObjectRow(
                label: "Boiler",
                symbol: "flame",
                tint: .red,
                count: boilers.count,
                items: boilers,
                isCompleted: store.isCompleted,
                onAddLabel: "Add Boiler",
                onAdd: { showingAddBoiler = true },
                onRemove: { id in store.removeKeyObject(id: id) }
            )
            Divider()
            // Flue row
            KeyObjectRow(
                label: "Flue",
                symbol: "arrow.up.to.line",
                tint: .gray,
                count: flues.count,
                items: flues,
                isCompleted: store.isCompleted,
                onAddLabel: "Add Flue",
                onAdd: { showingAddFlue = true },
                onRemove: { id in store.removeKeyObject(id: id) }
            )
        }
    }

    // MARK: - Notes section

    private var notesSection: some View {
        let notes = store.session.allVoiceNotes
        return CaptureCategoryCard(
            title: "Notes",
            count: notes.count,
            symbol: "mic",
            tint: .green,
            isEmpty: notes.isEmpty,
            emptyText: "No notes added yet",
            addButtonLabel: store.isCompleted ? nil : "Add Note",
            onAdd: { showingAddNote = true }
        ) {
            ForEach(notes.prefix(3)) { note in
                HStack(alignment: .top) {
                    Image(systemName: "text.alignleft")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .padding(.top, 2)
                    Text(note.caption.isEmpty ? (note.transcript ?? "Note") : note.caption)
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer()
                    if !store.isCompleted {
                        Button(role: .destructive) {
                            store.removeTextNote(id: note.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
            if notes.count > 3 {
                Text("+ \(notes.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - CaptureCategoryCard

/// A card showing a summary for one capture category (rooms, photos, objects, notes).
///
/// Contains a header row, optional list content via `@ViewBuilder`, and an
/// optional "Add …" action button.  Used by `FieldCaptureView` to give each
/// capture category a consistent look.
private struct CaptureCategoryCard<Content: View>: View {

    let title: String
    let count: Int
    let symbol: String
    let tint: Color
    let isEmpty: Bool
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

            if isEmpty {
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

// MARK: - KeyObjectRow

/// A row inside the Key Objects card showing the count for one category
/// (boiler or flue) with individual delete buttons and an add action.
private struct KeyObjectRow: View {
    let label: String
    let symbol: String
    let tint: Color
    let count: Int
    let items: [TaggedObject]
    let isCompleted: Bool
    let onAddLabel: String
    let onAdd: () -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(count == 0 ? "None" : "\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(count > 0 ? tint : .tertiary)
                if !isCompleted {
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
            }
            .padding(.vertical, 6)

            ForEach(items) { item in
                HStack {
                    Text(item.displayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                    Spacer()
                    if !isCompleted {
                        Button(role: .destructive) {
                            onRemove(item.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - PhotoThumbnailCell

/// Displays a thumbnail for a single `TaggedPhoto`, loading the image lazily
/// from `PhotoStore` on first appearance.
private struct PhotoThumbnailCell: View {
    let photo: TaggedPhoto
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemFill)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if let thumbPath = photo.thumbnailPath {
                image = PhotoStore.shared.thumbnail(path: thumbPath)
            } else if image == nil {
                image = PhotoStore.shared.image(filename: photo.filename)
            }
        }
    }
}

// MARK: - AddRoomSheet

/// Sheet for adding a new room to the session.
private struct AddRoomSheet: View {
    @ObservedObject var store: FieldVisitStore
    @Binding var isPresented: Bool

    @State private var label = ""
    @State private var floor = 0

    private let floorOptions = [("Ground Floor", 0), ("First Floor", 1), ("Second Floor", 2), ("Basement", -1)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Room Label") {
                    TextField("e.g. Kitchen, Lounge", text: $label)
                }
                Section("Floor") {
                    Picker("Floor", selection: $floor) {
                        ForEach(floorOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Add Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addRoom(label: label.isEmpty ? "Room" : label, floor: floor)
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - AddKeyObjectSheet

/// Sheet for tagging a key object (boiler or flue) into the session.
private struct AddKeyObjectSheet: View {
    @ObservedObject var store: FieldVisitStore
    let category: ServiceObjectCategory
    @Binding var isPresented: Bool

    @State private var label = ""
    @State private var note  = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Label (optional)") {
                    TextField(category.displayName, text: $label)
                }
                Section("Note (optional)") {
                    TextField("Any relevant note…", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Add \(category.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addKeyObject(
                            category: category,
                            label: label,
                            note: note
                        )
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - AddNoteSheet

/// Sheet for adding a quick text note to the session.
private struct AddNoteSheet: View {
    @ObservedObject var store: FieldVisitStore
    @Binding var isPresented: Bool

    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Enter note…", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addTextNote(text)
                        isPresented = false
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - CameraPickerView

/// A `UIViewControllerRepresentable` wrapper around `UIImagePickerController`
/// for camera capture.
private struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let onDismiss: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
            self.onImage = onImage
            self.onDismiss = onDismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onDismiss()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDismiss()
        }
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Empty") {
    let store = ScanSessionStore()
    let session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldCaptureView(store: visitStore)
}

#Preview("Populated") {
    let store = ScanSessionStore()
    var session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
    session.addRoom(ScannedRoom(jobID: session.id, name: "Boiler Room"))
    session.addPhoto(TaggedPhoto(filename: "p1.jpg"))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .boiler))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))
    session.addVoiceNote(VoiceNote(localFilename: "", caption: "Boiler is in utility room", kind: .observation))
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldCaptureView(store: visitStore)
}

#Preview("Completed") {
    let store = ScanSessionStore()
    var session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    session.visitLifecycle = .complete
    session.completedAt = Date()
    session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldCaptureView(store: visitStore)
}
#endif
