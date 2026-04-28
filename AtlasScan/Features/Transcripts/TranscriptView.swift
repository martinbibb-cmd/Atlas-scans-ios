import SwiftUI

// MARK: - TranscriptView
//
// Displays all voice note transcripts captured during a visit session.
//
// Transcripts are grouped by room (where available), then session-level.
// Each entry shows the transcript text, recording timestamp, and duration.
//
// The view is read-only — engineers review the captured voice evidence and
// can copy individual transcripts to the clipboard.

struct TranscriptView: View {

    let draft: CaptureSessionDraft

    @State private var searchText = ""
    @State private var copiedId: UUID?

    // MARK: - Computed

    private var sessionNotes: [CapturedVoiceNoteDraft] {
        draft.voiceNotes.filter { $0.roomId == nil }
    }

    private var roomGroups: [(room: CapturedRoomScanDraft, notes: [CapturedVoiceNoteDraft])] {
        draft.roomScans.compactMap { scan in
            let notes = draft.voiceNotes.filter { $0.roomId == scan.id }
            guard !notes.isEmpty else { return nil }
            return (room: scan, notes: notes)
        }
    }

    private var filteredSessionNotes: [CapturedVoiceNoteDraft] {
        filterNotes(sessionNotes)
    }

    private func filteredRoomNotes(_ notes: [CapturedVoiceNoteDraft]) -> [CapturedVoiceNoteDraft] {
        filterNotes(notes)
    }

    private func filterNotes(_ notes: [CapturedVoiceNoteDraft]) -> [CapturedVoiceNoteDraft] {
        guard !searchText.isEmpty else { return notes }
        return notes.filter { $0.transcript.localizedCaseInsensitiveContains(searchText) }
    }

    private var hasAnyTranscripts: Bool {
        draft.voiceNotes.contains { !$0.transcript.isEmpty }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if draft.voiceNotes.isEmpty {
                emptyState(message: "No voice notes recorded for this visit.")
            } else if !hasAnyTranscripts {
                emptyState(message: "Transcription is pending for this session.")
            } else {
                transcriptList
            }
        }
        .searchable(text: $searchText, prompt: "Search transcripts")
        .navigationTitle("Transcripts")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Transcript list

    private var transcriptList: some View {
        List {
            // Session-level notes (not tied to a room)
            if !filteredSessionNotes.isEmpty {
                Section("Session Notes") {
                    ForEach(filteredSessionNotes) { note in
                        TranscriptRow(note: note, copiedId: $copiedId)
                    }
                }
            }

            // Room-grouped notes
            ForEach(roomGroups, id: \.room.id) { group in
                let filtered = filteredRoomNotes(group.notes)
                if !filtered.isEmpty {
                    Section(group.room.roomLabel ?? "Unnamed Room") {
                        ForEach(filtered) { note in
                            TranscriptRow(note: note, copiedId: $copiedId)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty state

    private func emptyState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.microphone")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TranscriptRow

private struct TranscriptRow: View {

    let note: CapturedVoiceNoteDraft
    @Binding var copiedId: UUID?

    @State private var expanded = false

    private var isCopied: Bool { copiedId == note.id }

    private var durationText: String? {
        guard let ended = note.endedAt else { return nil }
        let secs = Int(ended.timeIntervalSince(note.startedAt))
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m \(secs % 60)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Timestamp + duration row
            HStack {
                Label(note.startedAt.formatted(date: .omitted, time: .shortened), systemImage: "mic.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if let dur = durationText {
                    Text("· \(dur)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = note.transcript
                    withAnimation { copiedId = note.id }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedId == note.id {
                            withAnimation { copiedId = nil }
                        }
                    }
                } label: {
                    Label(
                        isCopied ? "Copied" : "Copy",
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption)
                    .foregroundStyle(isCopied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
            }

            // Transcript text
            if note.transcript.isEmpty {
                Text("Transcription pending…")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                Text(note.transcript)
                    .font(.subheadline)
                    .lineLimit(expanded ? nil : 4)
                    .onTapGesture { withAnimation { expanded.toggle() } }

                if !expanded && note.transcript.count > 200 {
                    Button("Show more") {
                        withAnimation { expanded = true }
                    }
                    .font(.caption)
                    .foregroundStyle(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("With transcripts") {
    let draft: CaptureSessionDraft = {
        var d = CaptureSessionDraft()
        d.visitReference = "JOB-2025-0001"
        var n1 = CapturedVoiceNoteDraft()
        n1.transcript = "The boiler is located in the kitchen cupboard under the stairs. Serial number looks to be on the right-hand side, partially obscured by insulation."
        n1.endedAt = Date().addingTimeInterval(45)
        var n2 = CapturedVoiceNoteDraft()
        n2.transcript = "Customer mentioned the radiator in the front bedroom has been cold for several weeks."
        n2.endedAt = Date().addingTimeInterval(12)
        d.voiceNotes = [n1, n2]
        return d
    }()

    NavigationStack {
        TranscriptView(draft: draft)
    }
}

#Preview("Empty") {
    NavigationStack {
        TranscriptView(draft: CaptureSessionDraft())
    }
}
#endif
