import SwiftUI

// MARK: - VisitVoiceScreenView

/// Voice notes capture screen within the visit session.
///
/// Shows all voice notes (session-level and room-level) and provides
/// controls to record new notes.  Transcript status is visible at a glance.
struct VisitVoiceScreenView: View {

    @ObservedObject var viewModel: VisitCaptureViewModel
    @State private var showingRecorder = false

    var allNotes: [VoiceNote] {
        viewModel.session.allVoiceNotes
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if allNotes.isEmpty {
                emptyState
            } else {
                transcriptSummarySection
                notesSection
            }
            recordSection
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingRecorder) {
            recorderSheet
        }
    }

    // MARK: - Transcript summary

    private var transcriptSummarySection: some View {
        let withTranscript = allNotes.filter { $0.transcript != nil }.count
        return Section("Transcripts") {
            HStack {
                Text("\(withTranscript) of \(allNotes.count) notes transcribed")
                    .font(.body)
                Spacer()
                if withTranscript == allNotes.count {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "clock.circle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Notes list

    private var notesSection: some View {
        Section("Notes (\(allNotes.count))") {
            ForEach(allNotes) { note in
                noteRow(note)
            }
        }
    }

    private func noteRow(_ note: VoiceNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(note.kind.displayName, systemImage: note.kind.symbolName)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(durationText(note.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                transcriptBadge(note)
            }
            if !note.caption.isEmpty {
                Text(note.caption)
                    .font(.body)
                    .lineLimit(2)
            }
            if let transcript = note.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let roomID = note.linkedRoomID,
               let room = viewModel.session.rooms.first(where: { $0.id == roomID }) {
                Label(room.name, systemImage: "square.split.2x1")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func transcriptBadge(_ note: VoiceNote) -> some View {
        switch note.transcriptStatus {
        case .none:
            EmptyView()
        case .pending:
            Label("Pending", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .completed:
            Label("Transcribed", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "xmark.circle")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No voice notes recorded")
                    .foregroundStyle(.secondary)
                Text("Record voice notes to capture observations and context.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
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
            if let room = viewModel.selectedRoom {
                Text("Note will be attached to \(room.name).")
                    .font(.caption)
            } else {
                Text("Note will be attached at session level.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Recorder sheet

    private var recorderSheet: some View {
        let context = viewModel.selectedRoom?.name ?? "Session"
        return VoiceNoteRecorderSheet(attachContext: context) { note in
            viewModel.addVoiceNote(note)
            showingRecorder = false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    let session = PropertyScanSession(propertyAddress: "12 Test Lane")
    let vm = VisitCaptureViewModel(session: session, sessionStore: store, atlasSync: AtlasSync())
    return VisitVoiceScreenView(viewModel: vm)
}
#endif
