import SwiftUI
import UIKit

// MARK: - PhotoCaptureView
//
// Sheet for capturing an evidence photo and assigning it to a room or object.
// Opens the device camera (or photo library on simulator) to take a real photo,
// saves it to PhotoStore, then creates a CapturedPhotoDraft.

struct PhotoCaptureView: View {

    let roomScans: [CapturedRoomScanDraft]
    let objectPins: [CapturedObjectPinDraft]
    let onCapture: (CapturedPhotoDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: CapturePhotoKind = .other
    @State private var selectedRoomId: UUID?
    @State private var selectedObjectId: UUID?
    @State private var showingImagePicker = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo Category") {
                    Picker("Category", selection: $kind) {
                        ForEach(CapturePhotoKind.allCases, id: \.self) { k in
                            Label(k.displayName, systemImage: k.symbolName).tag(k)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if !roomScans.isEmpty {
                    Section("Associate with Room") {
                        Picker("Room", selection: $selectedRoomId) {
                            Text("Session (no room)").tag(UUID?.none)
                            ForEach(roomScans) { scan in
                                Text(scan.roomLabel ?? "Unnamed Room").tag(Optional(scan.id))
                            }
                        }
                    }
                }

                if !objectPins.isEmpty {
                    Section("Associate with Object") {
                        Picker("Object", selection: $selectedObjectId) {
                            Text("None").tag(UUID?.none)
                            ForEach(objectPins) { pin in
                                Text(pin.label ?? pin.type.displayName).tag(Optional(pin.id))
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingImagePicker = true
                    } label: {
                        Label("Use Camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                } footer: {
                    if let error = saveError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else {
                        Text("Opens the device camera to capture an evidence photo. The photo is stored locally.")
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle("Capture Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingImagePicker) {
                CameraPickerView { image in
                    savePhoto(image)
                } onCancel: {
                    showingImagePicker = false
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Actions

    private func savePhoto(_ image: UIImage) {
        showingImagePicker = false
        saveError = nil
        do {
            let (filename, _) = try PhotoStore.shared.save(image)
            var photo = CapturedPhotoDraft(localFilename: filename)
            photo.kind = kind
            photo.roomId = selectedRoomId
            photo.linkedObjectId = selectedObjectId
            onCapture(photo)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Kitchen"
    return PhotoCaptureView(
        roomScans: [scan],
        objectPins: []
    ) { _ in }
}
#endif
