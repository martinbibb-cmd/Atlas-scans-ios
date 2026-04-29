import SwiftUI
import PhotosUI

// MARK: - PhotoCaptureSheet
//
// Sheet that lets the engineer pick a photo (from library or camera)
// and attach it to the active capture session.
//
// The selected image is written to Documents/CapturePhotos/<uuid>.jpg
// and a CapturedPhotoDraft is appended to the session store.

struct PhotoCaptureSheet: View {

    @ObservedObject var store: CaptureSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var kind: CapturePhotoKind = .other
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Choose Photo", systemImage: "photo.badge.plus")
                                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $kind) {
                        ForEach(CapturePhotoKind.allCases, id: \.self) { k in
                            Label(k.displayName, systemImage: k.symbolName).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { savePhoto() }
                        .disabled(selectedImage == nil || isSaving)
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                loadImage(from: newItem)
            }
        }
    }

    // MARK: - Load image from picker

    private func loadImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run { selectedImage = image }
            }
        }
    }

    // MARK: - Save photo

    private func savePhoto() {
        guard let image = selectedImage else { return }
        isSaving = true
        Task {
            let filename = await writeImageToDisk(image)
            await MainActor.run {
                isSaving = false
                if let filename {
                    let photo = CapturedPhotoDraft(
                        localFilename: filename,
                        kind: kind
                    )
                    store.addPhoto(photo)
                    dismiss()
                } else {
                    saveError = "Failed to save image. Please try again."
                }
            }
        }
    }

    // MARK: - Write image to disk

    private func writeImageToDisk(_ image: UIImage) async -> String? {
        let filename = "\(UUID().uuidString).jpg"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CapturePhotos", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(filename)
            guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }
}
