import SwiftUI

// MARK: - VoiceNotesView
//
// Lists all voice note transcripts captured during the visit.
// Provides the recorder sheet for starting a new note.

struct VoiceNotesView: View {

    @ObservedObject var store: CaptureSessionStore
    @State private var showingRecorder = false

    var sortedNotes: [CapturedVoiceNoteDraft] {
        store.draft.voiceNotes.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        List {
            if sortedNotes.isEmpty {
                emptyState
            } else {
                transcriptSummarySection
                notesSection
            }
            recordSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Voice Notes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRecorder) {
            CaptureVoiceNoteRecorderSheet(
                roomScans: store.draft.roomScans
            ) { note in
                store.addVoiceNote(note)
                showingRecorder = false
            }
        }
    }

    // MARK: - Transcript summary

    private var transcriptSummarySection: some View {
        let withTranscript = sortedNotes.filter { !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return Section {
            HStack {
                Label("\(withTranscript) of \(sortedNotes.count) notes have a transcript", systemImage: "text.bubble")
                    .font(.body)
                Spacer()
                if withTranscript == sortedNotes.count && !sortedNotes.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text("Transcripts")
        }
    }

    // MARK: - Notes list

    private var notesSection: some View {
        Section("Notes (\(sortedNotes.count))") {
            ForEach(sortedNotes) { note in
                noteRow(note)
            }
            .onDelete { indexSet in
                let sorted = sortedNotes
                indexSet.forEach { i in
                    store.removeVoiceNote(id: sorted[i].id)
                }
            }
        }
    }

    private func noteRow(_ note: CapturedVoiceNoteDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                transcriptStatusBadge(note)
                Spacer()
                Text(note.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !note.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note.transcript)
                    .font(.body)
                    .lineLimit(3)
            } else {
                Text("No transcript yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            if let roomId = note.roomId,
               let scan = store.draft.roomScans.first(where: { $0.id == roomId }) {
                Label(scan.roomLabel ?? "Unnamed Room", systemImage: "square.split.2x1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func transcriptStatusBadge(_ note: CapturedVoiceNoteDraft) -> some View {
        if note.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label("No transcript", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else {
            Label("Transcribed", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No voice notes recorded")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Record voice notes to capture observations and context during the visit.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Record section

    private var recordSection: some View {
        Section {
            Button {
                showingRecorder = true
            } label: {
                Label("Record Voice Note", systemImage: "mic.badge.plus")
                    .font(.body.bold())
            }
        } header: {
            Text("Record")
        } footer: {
            Text("Transcript text is retained. Raw audio is not included in the exported session.")
                .font(.caption2)
        }
    }
}

// MARK: - CaptureVoiceNoteRecorderSheet (capture-flow version)
//
// A lightweight recording sheet used within the new capture flow.
// Wraps VoiceNoteRecorderViewModel to manage the recording lifecycle.

struct CaptureVoiceNoteRecorderSheet: View {

    let roomScans: [CapturedRoomScanDraft]
    let onSave: (CapturedVoiceNoteDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceNoteRecorderViewModel()
    @State private var selectedRoomId: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                stateDisplay
                transcriptEditor
                if !roomScans.isEmpty {
                    roomPicker
                }
                controlBar
                Spacer()
            }
            .padding()
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.discard()
                        dismiss()
                    }
                }
                if recorder.canCommit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveNote() }
                    }
                }
            }
        }
    }

    // MARK: - State display

    private var stateDisplay: some View {
        VStack(spacing: 8) {
            Image(systemName: recorderIcon)
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(recorderColor)
                .animation(.easeInOut, value: recorder.state)

            Text(recorder.elapsedTimeText)
                .font(.system(.title, design: .monospaced).bold())
                .foregroundStyle(.primary)

            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var recorderIcon: String {
        switch recorder.state {
        case .idle:      return "mic.circle"
        case .recording: return "mic.fill"
        case .paused:    return "pause.circle.fill"
        case .stopped:   return "checkmark.circle.fill"
        }
    }

    private var recorderColor: Color {
        switch recorder.state {
        case .idle:      return .secondary
        case .recording: return .red
        case .paused:    return .orange
        case .stopped:   return .green
        }
    }

    private var stateLabel: String {
        switch recorder.state {
        case .idle:      return "Ready to record"
        case .recording: return "Recording…"
        case .paused:    return "Paused"
        case .stopped:   return "Recording complete — add transcript below"
        }
    }

    // MARK: - Transcript editor

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextEditor(text: $recorder.transcript)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Room picker

    private var roomPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Room")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Picker("Room", selection: $selectedRoomId) {
                Text("Session level").tag(UUID?.none)
                ForEach(roomScans) { scan in
                    Text(scan.roomLabel ?? "Unnamed Room").tag(Optional(scan.id))
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 16) {
            if recorder.canStart {
                controlButton(label: "Start", symbol: "record.circle.fill", color: .red) {
                    recorder.start(roomId: selectedRoomId)
                }
            }
            if recorder.canPause {
                controlButton(label: "Pause", symbol: "pause.circle.fill", color: .orange) {
                    recorder.pause()
                }
            }
            if recorder.canResume {
                controlButton(label: "Resume", symbol: "play.circle.fill", color: .blue) {
                    recorder.resume()
                }
            }
            if recorder.canStop {
                controlButton(label: "Stop", symbol: "stop.circle.fill", color: .primary) {
                    recorder.stop()
                }
            }
        }
    }

    private func controlButton(
        label: String,
        symbol: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save

    private func saveNote() {
        guard var note = recorder.commit() else { return }
        note.roomId = selectedRoomId
        onSave(note)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var draft = CaptureSessionDraft()
    draft.visitReference = "JOB-001"
    var note = CapturedVoiceNoteDraft()
    note.transcript = "The boiler is in the kitchen, near the back wall."
    draft.voiceNotes = [note]
    let store = CaptureSessionStore(draft: draft)
    return NavigationStack {
        VoiceNotesView(store: store)
    }
}
#endif
