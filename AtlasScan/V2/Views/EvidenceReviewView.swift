/// EvidenceReviewView — Read-only summary of the captured evidence in the
/// active visit. From here the user can dive back into Continuous Survey to
/// edit, or close back to `SurveyHomeView`.

import SwiftUI
import AtlasScanCore

public struct EvidenceReviewView: View {

    public let session: SessionCaptureV2

    /// Triggered when the user taps a row that should reopen the capture
    /// surface for editing. The parent decides exactly which screen to open.
    public let onEditCapture: () -> Void
    public let onClose: () -> Void

    public init(
        session: SessionCaptureV2,
        onEditCapture: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.onEditCapture = onEditCapture
        self.onClose = onClose
    }

    public var body: some View {
        List {
            roomsSection
            photosSection
            voiceNotesSection
            qaFlagsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review Evidence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Edit") { onEditCapture() }
            }
        }
    }

    private var roomsSection: some View {
        Section("Rooms (\(session.rooms.count))") {
            if session.rooms.isEmpty {
                Text("No rooms captured.").foregroundStyle(.secondary)
            } else {
                ForEach(session.rooms, id: \.id) { room in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.displayName.isEmpty ? "Untitled room" : room.displayName)
                            .font(.body)
                        Text(room.captureStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var photosSection: some View {
        Section("Photos (\(session.photos.count))") {
            if session.photos.isEmpty {
                Text("No photos.").foregroundStyle(.secondary)
            } else {
                Text("\(session.photos.count) photos captured")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var voiceNotesSection: some View {
        Section("Voice notes (\(session.voiceNotes.count))") {
            if session.voiceNotes.isEmpty {
                Text("No voice notes.").foregroundStyle(.secondary)
            } else {
                Text("\(session.voiceNotes.count) voice notes recorded")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var qaFlagsSection: some View {
        Section("QA flags (\(session.qaFlags.count))") {
            if session.qaFlags.isEmpty {
                Text("No QA flags raised.").foregroundStyle(.secondary)
            } else {
                ForEach(session.qaFlags, id: \.id) { flag in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(describing: flag.type))
                                .font(.subheadline)
                            if !flag.detail.isEmpty {
                                Text(flag.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
