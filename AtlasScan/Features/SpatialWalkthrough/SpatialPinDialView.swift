import SwiftUI

// MARK: - SpatialPinDialView
//
// Floating contextual action dial shown when the engineer selects a placed
// object pin during Step B (Spatial Pinning) of the Room Loop.
//
// Three actions are presented:
//   1. Snap Photo    — opens the camera picker and auto-links the photo to this pin.
//   2. Dictate Note  — opens the voice note recorder linked to this pin.
//   3. Measure Clearance — launches the LiDAR Clearance Session for this appliance.
//
// Evidence linking hierarchy enforced here:
//   Room → ObjectPin → Photo / Transcript

struct SpatialPinDialView: View {

    // MARK: - Dependencies

    let pin: CapturedObjectPinDraft
    let roomId: UUID
    @ObservedObject var store: CaptureSessionStore
    let onDismiss: () -> Void

    // MARK: - State

    @State private var showingCamera      = false
    @State private var showingVoiceNote   = false
    @State private var showingClearance   = false

    @State private var photoLinked        = false
    @State private var noteLinked         = false
    @State private var clearanceMeasured  = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pinHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                Divider()

                actionList
                    .padding(.top, 8)

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pin Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        // Camera
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPickerView(
                onImage: { image in
                    let filename = (try? PhotoStore.shared.save(image))?.filename
                        ?? "photo_\(UUID().uuidString).jpg"
                    var photo = CapturedPhotoDraft(localFilename: filename)
                    photo.roomId = roomId
                    photo.linkedObjectId = pin.id
                    photo.captureTimestamp = Date()
                    store.addPhoto(photo)
                    photoLinked = true
                    showingCamera = false
                },
                onCancel: {
                    showingCamera = false
                }
            )
        }
        // Voice note recorder
        .sheet(isPresented: $showingVoiceNote) {
            CaptureVoiceNoteRecorderSheet(
                roomScans: store.draft.roomScans
            ) { note in
                var linkedNote = note
                linkedNote.linkedObjectId = pin.id
                linkedNote.roomId = roomId
                store.addVoiceNote(linkedNote)
                noteLinked = true
                showingVoiceNote = false
            }
        }
        // LiDAR clearance
        .fullScreenCover(isPresented: $showingClearance) {
            NavigationStack {
                LiDARClearanceView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingClearance = false
                                clearanceMeasured = true
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Pin header

    private var pinHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: pin.type.symbolName)
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(pin.displayLabel)
                    .font(.title3.bold())
                Text(pin.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            evidenceBadges
        }
    }

    private var evidenceBadges: some View {
        HStack(spacing: 6) {
            if photoLinked || linkedPhotoCount > 0 {
                evidenceBadge(symbol: "camera.fill", count: max(linkedPhotoCount, photoLinked ? 1 : 0), color: .blue)
            }
            if noteLinked || linkedNoteCount > 0 {
                evidenceBadge(symbol: "mic.fill", count: max(linkedNoteCount, noteLinked ? 1 : 0), color: .purple)
            }
            if clearanceMeasured {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    private func evidenceBadge(symbol: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.caption2)
            Text("\(count)").font(.caption2.bold())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - Action list

    private var actionList: some View {
        List {
            Section {
                // 1. Snap Photo
                Button {
                    showingCamera = true
                } label: {
                    dialRow(
                        symbol: "camera.fill",
                        color: .blue,
                        title: "Snap Photo",
                        subtitle: "Links photo to \(pin.displayLabel) and Room",
                        badge: linkedPhotoCount > 0 ? "\(linkedPhotoCount) photo(s)" : nil,
                        done: photoLinked || linkedPhotoCount > 0
                    )
                }

                // 2. Dictate Note
                Button {
                    showingVoiceNote = true
                } label: {
                    dialRow(
                        symbol: "waveform.badge.mic",
                        color: .purple,
                        title: "Dictate Note",
                        subtitle: "Voice note linked to this object — transcript exported to Atlas Mind",
                        badge: linkedNoteCount > 0 ? "\(linkedNoteCount) note(s)" : nil,
                        done: noteLinked || linkedNoteCount > 0
                    )
                }

                // 3. Measure Clearance
                if pin.type.supportsClearance {
                    Button {
                        showingClearance = true
                    } label: {
                        dialRow(
                            symbol: "ruler.fill",
                            color: .orange,
                            title: "Measure Clearance",
                            subtitle: "LiDAR-based clearance check for \(pin.type.displayName)",
                            badge: clearanceMeasured ? "Measured" : nil,
                            done: clearanceMeasured
                        )
                    }
                }
            } footer: {
                Text("All evidence captured here is automatically linked to \(pin.displayLabel) and the room.")
                    .font(.caption2)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func dialRow(
        symbol: String,
        color: Color,
        title: String,
        subtitle: String,
        badge: String?,
        done: Bool
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.body)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let badge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Evidence counts

    private var linkedPhotoCount: Int {
        store.draft.photos.filter { $0.linkedObjectId == pin.id }.count
    }

    private var linkedNoteCount: Int {
        store.draft.voiceNotes.filter { $0.linkedObjectId == pin.id }.count
    }
}

// MARK: - CapturedObjectPinDraft helpers

private extension CapturedObjectPinDraft {
    var displayLabel: String {
        if let l = label, !l.isEmpty { return l }
        return type.displayName
    }
}

// MARK: - ObjectPinType clearance support

private extension ObjectPinType {
    var supportsClearance: Bool {
        switch self {
        case .boiler, .heatPump, .cylinder, .pump, .radiator:
            return true
        default:
            return false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = CaptureSessionStore(
        draft: CaptureSessionStore.newSession(visitReference: "PREVIEW-DIAL"),
        persistence: .shared
    )
    var pin = CapturedObjectPinDraft(type: .boiler)
    pin.label = "Main Boiler"
    return SpatialPinDialView(pin: pin, roomId: UUID(), store: store, onDismiss: {})
}
#endif
