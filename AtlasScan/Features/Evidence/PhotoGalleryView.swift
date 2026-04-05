import SwiftUI

// MARK: - PhotoGalleryView
//
// A reusable thumbnail grid for a list of TaggedPhoto records.
// Tapping a thumbnail opens FullPhotoView for full-screen viewing,
// caption editing, and deletion.

struct PhotoGalleryView: View {

    let photos: [TaggedPhoto]
    let onDelete: (UUID) -> Void
    let onUpdateCaption: ((UUID, String) -> Void)?

    @State private var selectedPhoto: TaggedPhoto? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 4)
    ]

    var body: some View {
        if photos.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos) { photo in
                    PhotoThumbnailView(photo: photo)
                        .onTapGesture { selectedPhoto = photo }
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(photo.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .sheet(item: $selectedPhoto) { photo in
                FullPhotoView(
                    photo: photo,
                    onDelete: {
                        onDelete(photo.id)
                        selectedPhoto = nil
                    },
                    onUpdateCaption: onUpdateCaption.map { fn in
                        { newCaption in fn(photo.id, newCaption) }
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.tertiary)
            Text("No photos yet")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - PhotoThumbnailView

struct PhotoThumbnailView: View {

    let photo: TaggedPhoto

    @State private var thumbnailImage: UIImage? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let img = thumbnailImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if photo.isKeyEvidence {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .padding(4)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
                    .padding(3)
            }
        }
        .task { await loadThumbnail() }
    }

    @MainActor
    private func loadThumbnail() async {
        if let path = photo.thumbnailPath {
            thumbnailImage = await Task.detached(priority: .utility) {
                PhotoStore.shared.thumbnail(path: path)
            }.value
        } else {
            thumbnailImage = await Task.detached(priority: .utility) {
                PhotoStore.shared.image(filename: photo.filename)
            }.value
        }
    }
}

// MARK: - FullPhotoView

struct FullPhotoView: View {

    let photo: TaggedPhoto
    let onDelete: () -> Void
    let onUpdateCaption: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: UIImage? = nil
    @State private var editedCaption: String
    @State private var isEditingCaption = false
    @State private var showingDeleteConfirm = false

    init(
        photo: TaggedPhoto,
        onDelete: @escaping () -> Void,
        onUpdateCaption: ((String) -> Void)?
    ) {
        self.photo = photo
        self.onDelete = onDelete
        self.onUpdateCaption = onUpdateCaption
        _editedCaption = State(initialValue: photo.caption)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Group {
                        if let img = fullImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 280)
                                .overlay(ProgressView())
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    photoMetadata
                }
                .padding(.bottom, 32)
            }
            .navigationTitle(photo.kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Photo", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            }
            .task { await loadImage() }
        }
    }

    private var photoMetadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(photo.kind.displayName, systemImage: photo.kind.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if photo.isKeyEvidence {
                    Label("Key Evidence", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            if let fn = onUpdateCaption {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Caption")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Add caption…", text: $editedCaption, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: editedCaption) { _, newValue in
                            fn(newValue)
                        }
                }
            } else if !photo.caption.isEmpty {
                Text(photo.caption)
                    .font(.body)
            }

            Text(photo.capturedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
    }

    @MainActor
    private func loadImage() async {
        fullImage = await Task.detached(priority: .utility) {
            PhotoStore.shared.image(filename: photo.filename)
        }.value
    }
}
