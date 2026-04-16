import SwiftUI

// MARK: - PhotoListView
//
// Lists all evidence photos captured during the visit.
// Shows room and object associations at a glance.

struct PhotoListView: View {

    @ObservedObject var store: CaptureSessionStore
    @State private var showingCapture = false

    var body: some View {
        List {
            if store.draft.photos.isEmpty {
                emptyState
            } else {
                photosSection
            }
            captureSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCapture) {
            PhotoCaptureView(
                roomScans: store.draft.roomScans,
                objectPins: store.draft.objectPins
            ) { photo in
                store.addPhoto(photo)
                showingCapture = false
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
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Capture evidence photos to document the visit.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Photos list

    private var photosSection: some View {
        Section("Photos (\(store.draft.photos.count))") {
            ForEach(store.draft.photos) { photo in
                photoRow(photo)
            }
            .onDelete { indexSet in
                indexSet.forEach { i in
                    store.removePhoto(id: store.draft.photos[i].id)
                }
            }
        }
    }

    private func photoRow(_ photo: CapturedPhotoDraft) -> some View {
        HStack(spacing: 12) {
            photoThumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.kind.displayName)
                    .font(.body)
                HStack(spacing: 8) {
                    if let roomId = photo.roomId,
                       let scan = store.draft.roomScans.first(where: { $0.id == roomId }) {
                        Label(scan.roomLabel ?? "Room", systemImage: "square.split.2x1")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Session", systemImage: "doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if photo.linkedObjectId != nil {
                        Label("Linked to object", systemImage: "link")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(photo.captureTimestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var photoThumbnail: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Capture section

    private var captureSection: some View {
        Section {
            Button {
                showingCapture = true
            } label: {
                Label("Capture Evidence Photo", systemImage: "camera.badge.plus")
                    .font(.body.bold())
            }
        } header: {
            Text("Capture")
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var draft = CaptureSessionDraft()
    draft.visitReference = "JOB-001"
    draft.photos = [
        CapturedPhotoDraft(localFilename: "p1.jpg"),
        {
            var p = CapturedPhotoDraft(localFilename: "p2.jpg")
            p.kind = .plant
            return p
        }()
    ]
    let store = CaptureSessionStore(draft: draft)
    return NavigationStack {
        PhotoListView(store: store)
    }
}
#endif
