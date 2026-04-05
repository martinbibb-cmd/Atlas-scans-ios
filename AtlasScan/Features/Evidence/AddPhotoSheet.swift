import SwiftUI

// MARK: - AddPhotoSheet
//
// Presents a two-step flow: source picker → optional caption/kind → confirm.
// The caller provides the pre-filled roomID / taggedObjectID context so the
// engineer can add a photo in one tap from any room or object screen.

struct AddPhotoSheet: View {

    // MARK: Context provided by caller

    /// Room the photo belongs to. Nil for job-level (site) photos.
    let roomID: UUID?

    /// Optional pre-filled object link.
    let taggedObjectID: UUID?

    /// Called when the engineer confirms saving the new photo.
    let onAdd: (TaggedPhoto) -> Void

    // MARK: State

    @Environment(\.dismiss) private var dismiss

    @State private var pickedImage: UIImage? = nil
    @State private var caption: String = ""
    @State private var kind: EvidenceKind = .other
    @State private var isKeyEvidence: Bool = false
    @State private var showingSourcePicker = false
    @State private var selectedSource: ImagePickerView.Source = .camera
    @State private var showingImagePicker = false
    @State private var isSaving = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                detailsSection
                if pickedImage != nil {
                    keyEvidenceSection
                }
            }
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePhoto() }
                        .disabled(pickedImage == nil || isSaving)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePickerView(source: selectedSource) { image in
                    pickedImage = image
                }
            }
            .confirmationDialog("Add Photo", isPresented: $showingSourcePicker, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        selectedSource = .camera
                        showingImagePicker = true
                    }
                }
                Button("Choose from Library") {
                    selectedSource = .photoLibrary
                    showingImagePicker = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Could Not Save Photo", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The photo could not be saved. Please check that you have enough storage space and try again.")
            }
        }
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section {
            if let image = pickedImage {
                HStack {
                    Spacer()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Button("Retake Photo", role: .destructive) {
                    showingSourcePicker = true
                }
            } else {
                Button {
                    showingSourcePicker = true
                } label: {
                    Label("Add Photo", systemImage: "camera.fill")
                }
            }
        } header: {
            Text("Photo")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Picker("Kind", selection: $kind) {
                ForEach(EvidenceKind.allCases, id: \.self) { k in
                    Label(k.displayName, systemImage: k.symbolName).tag(k)
                }
            }

            TextField("Caption (optional)", text: $caption, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    private var keyEvidenceSection: some View {
        Section {
            Toggle("Mark as Key Evidence", isOn: $isKeyEvidence)
        } footer: {
            Text("Key evidence photos are highlighted in the room and export summary.")
        }
    }

    // MARK: - Save

    private func savePhoto() {
        guard let image = pickedImage else { return }
        isSaving = true

        let photoID = UUID()
        let filename: String
        let thumbnailPath: String?

        do {
            let saved = try PhotoStore.shared.save(image, id: photoID)
            filename = saved.filename
            thumbnailPath = saved.thumbnailPath
        } catch {
            isSaving = false
            saveFailed = true
            return
        }

        let photo = TaggedPhoto(
            id: photoID,
            roomID: roomID,
            taggedObjectID: taggedObjectID,
            filename: filename,
            thumbnailPath: thumbnailPath,
            caption: caption,
            kind: kind,
            isKeyEvidence: isKeyEvidence
        )

        isSaving = false
        onAdd(photo)
        dismiss()
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    AddPhotoSheet(roomID: UUID(), taggedObjectID: nil) { _ in }
}
#endif
