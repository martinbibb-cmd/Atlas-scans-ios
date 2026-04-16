import SwiftUI

// MARK: - VisitPhotosScreenView

/// Evidence photo capture screen within the visit session.
///
/// Shows all photos (session, room, and object scope) and provides
/// a button to capture new evidence with category selection.
struct VisitPhotosScreenView: View {

    @ObservedObject var viewModel: VisitCaptureViewModel
    @State private var showingAddPhoto = false
    @State private var photoScope: PhotoScope = .all

    // MARK: - Photo scope filter

    enum PhotoScope: String, CaseIterable {
        case all     = "All"
        case session = "Session"
        case room    = "Room"
        case object  = "Object"
    }

    var body: some View {
        List {
            scopePickerSection
            if filteredPhotos.isEmpty {
                emptyState
            } else {
                photoListSection
            }
            captureSection
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingAddPhoto) {
            addPhotoSheet
        }
    }

    // MARK: - Scope picker

    private var scopePickerSection: some View {
        Section {
            Picker("Scope", selection: $photoScope) {
                ForEach(PhotoScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Photos list

    private var filteredPhotos: [TaggedPhoto] {
        switch photoScope {
        case .all:
            return viewModel.session.allPhotos
        case .session:
            return viewModel.session.photos
        case .room:
            return viewModel.session.rooms.flatMap(\.photos).filter { $0.taggedObjectID == nil }
        case .object:
            return viewModel.session.allPhotos.filter { $0.taggedObjectID != nil }
        }
    }

    private var photoListSection: some View {
        Section("Photos (\(filteredPhotos.count))") {
            ForEach(filteredPhotos) { photo in
                photoRow(photo)
            }
        }
    }

    private func photoRow(_ photo: TaggedPhoto) -> some View {
        HStack(spacing: 12) {
            photoThumbnail(photo)
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.kind.displayName)
                    .font(.body)
                HStack(spacing: 8) {
                    if let roomID = photo.roomID,
                       let room = viewModel.session.rooms.first(where: { $0.id == roomID }) {
                        Label(room.name, systemImage: "square.split.2x1")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(photo.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func photoThumbnail(_ photo: TaggedPhoto) -> some View {
        if let path = photo.thumbnailPath,
           let data = try? Data(contentsOf: PhotoStore.shared.thumbnailsDirectory.appendingPathComponent(path)),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "camera.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No photos captured")
                    .foregroundStyle(.secondary)
                Text("Capture evidence photos to document the visit.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Capture section

    private var captureSection: some View {
        Section {
            Button {
                showingAddPhoto = true
            } label: {
                Label("Capture Evidence Photo", systemImage: "camera.badge.plus")
                    .font(.body.bold())
            }
        } header: {
            Text("Capture")
        } footer: {
            if let room = viewModel.selectedRoom {
                Text("Photos will be attached to \(room.name).")
                    .font(.caption)
            } else {
                Text("Photos will be attached at session level. Select a room to scope them.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Add photo sheet

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
    let session = PropertyScanSession(propertyAddress: "12 Test Lane")
    let vm = VisitCaptureViewModel(session: session, sessionStore: store, atlasSync: AtlasSync())
    return VisitPhotosScreenView(viewModel: vm)
}
#endif
