import SwiftUI

// MARK: - PhotoCaptureView
//
// Sheet for capturing an evidence photo and assigning it to a room or object.
// In production this would launch the camera. Here it creates a draft record.

struct PhotoCaptureView: View {

    let roomScans: [CapturedRoomScanDraft]
    let objectPins: [CapturedObjectPinDraft]
    let onCapture: (CapturedPhotoDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: CapturePhotoKind = .other
    @State private var selectedRoomId: UUID?
    @State private var selectedObjectId: UUID?
    @State private var showingImagePicker = false

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
                        capturePhoto()
                    } label: {
                        Label("Use Camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("In the capture app, this opens the device camera. The photo is stored locally as a capture artefact.")
                        .font(.caption2)
                }
            }
            .navigationTitle("Capture Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Actions

    private func capturePhoto() {
        var photo = CapturedPhotoDraft(localFilename: "photo_\(UUID().uuidString).jpg")
        photo.kind = kind
        photo.roomId = selectedRoomId
        photo.linkedObjectId = selectedObjectId
        onCapture(photo)
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
