import SwiftUI

// MARK: - VoiceNoteRowView
//
// A reusable list row for a single VoiceNote.
//
// Shows:
//   • kind icon + display name
//   • duration (formatted mm:ss)
//   • created time (relative)
//   • optional caption
//   • play / pause action (via VoiceNotePlaybackManager.shared)
//   • delete action (via onDelete closure, when provided)
//   • edit caption (inline alert, when onUpdateCaption is provided)
//
// Designed to slot directly into a List / Section ForEach.

struct VoiceNoteRowView: View {

    // MARK: - Input

    let note: VoiceNote

    /// Called when the engineer deletes this note. Nil hides the delete action.
    var onDelete: (() -> Void)? = nil

    /// Called with the updated caption string. Nil hides the edit-caption action.
    var onUpdateCaption: ((String) -> Void)? = nil

    // MARK: - Private state

    @ObservedObject private var playback = VoiceNotePlaybackManager.shared

    @State private var showingEditCaption = false
    @State private var editedCaption = ""

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: kind + duration + created time + play button
            HStack(spacing: 8) {
                // Kind icon
                Image(systemName: note.kind.symbolName)
                    .foregroundStyle(kindColor)
                    .frame(width: 20)

                // Kind label
                Text(note.kind.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                // Duration
                Text(formatDuration(note.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                // Play / pause button
                playButton
            }

            // Playback progress bar — only visible while this note is playing
            if playback.isPlaying(note: note) {
                ProgressView(value: progressFraction)
                    .tint(.blue)
                    .transition(.opacity)
            }

            // Caption (if non-empty)
            if !note.caption.isEmpty {
                Text(note.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Created time
            Text(note.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            if let onUpdateCaption {
                Button {
                    editedCaption = note.caption
                    showingEditCaption = true
                } label: {
                    Label("Edit Caption", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .alert("Edit Caption", isPresented: $showingEditCaption) {
            TextField("Caption", text: $editedCaption)
            Button("Save") {
                onUpdateCaption?(editedCaption)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rename this voice note.")
        }
    }

    // MARK: - Play button

    private var playButton: some View {
        Button {
            playback.toggle(note: note)
        } label: {
            Image(systemName: playback.isPlaying(note: note) ? "pause.circle.fill" : "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var kindColor: Color {
        switch note.kind {
        case .observation:    return .blue
        case .customerNote:   return .teal
        case .constraint:     return .orange
        case .recommendation: return .green
        case .issue:          return .red
        case .other:          return .secondary
        }
    }

    private var progressFraction: Double {
        guard playback.playbackDuration > 0 else { return 0 }
        return min(playback.playbackProgress / playback.playbackDuration, 1.0)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    List {
        VoiceNoteRowView(
            note: VoiceNote(
                localFilename: "preview.m4a",
                duration: 62,
                caption: "Boiler flue clearance looks tight on the left side.",
                kind: .observation
            ),
            onDelete: {},
            onUpdateCaption: { _ in }
        )
        VoiceNoteRowView(
            note: VoiceNote(
                localFilename: "preview2.m4a",
                duration: 14,
                caption: "",
                kind: .issue
            ),
            onDelete: {},
            onUpdateCaption: { _ in }
        )
    }
}
#endif
