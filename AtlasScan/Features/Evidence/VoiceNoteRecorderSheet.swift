import SwiftUI

// MARK: - VoiceNoteRecorderSheet
//
// Records an audio voice note and lets the engineer add a caption and kind
// before attaching it to a session, room, or tagged object.
//
// The sheet drives a VoiceNoteRecorder (@StateObject).
// On "Save", it builds a VoiceNote and calls onAdd(_:).
// On "Cancel", the recorder's draft file is deleted.

struct VoiceNoteRecorderSheet: View {

    // MARK: Context

    /// Display label for where the note will attach (e.g. "Session", "Kitchen", "Boiler").
    let attachContext: String

    /// Called when the engineer confirms saving the voice note.
    let onAdd: (VoiceNote) -> Void

    // MARK: State

    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceNoteRecorder()

    @State private var caption: String = ""
    @State private var kind: VoiceNoteKind = .observation

    var body: some View {
        NavigationStack {
            Form {
                recordingSection
                if recorder.state == .recorded || recorder.state == .playing {
                    playbackSection
                    detailsSection
                }
            }
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.reset()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var recordingSection: some View {
        Section {
            VStack(spacing: 16) {
                // State icon
                Image(systemName: recorderStateSymbol)
                    .font(.system(size: 44))
                    .foregroundStyle(recorderStateColor)
                    .symbolEffect(.variableColor.iterative, isActive: recorder.state == .recording)

                // Duration / status label
                Text(durationLabel)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.primary)

                // Attach context badge
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text("Attaching to: \(attachContext)")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                // Record / Stop button
                Button {
                    handleRecordButton()
                } label: {
                    Label(recordButtonLabel, systemImage: recordButtonSymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.state == .recording ? .red : .blue)

                // Error display
                if case .error(let message) = recorder.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Recording")
        } footer: {
            Text("Tap record to capture observations, customer preferences, or constraints.")
                .font(.caption2)
        }
    }

    private var playbackSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    if recorder.state == .playing {
                        recorder.stopPlayback()
                    } else {
                        recorder.startPlayback()
                    }
                } label: {
                    Image(systemName: recorder.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: playbackFraction)
                        .tint(.blue)
                    HStack {
                        Text(formatDuration(recorder.playbackProgress))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(recorder.recordingDuration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Playback")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Picker("Kind", selection: $kind) {
                ForEach(VoiceNoteKind.allCases, id: \.self) { k in
                    Label(k.displayName, systemImage: k.symbolName).tag(k)
                }
            }

            TextField("Caption (optional)", text: $caption, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    // MARK: - Actions

    private func handleRecordButton() {
        switch recorder.state {
        case .idle, .error:
            Task { await recorder.startRecording() }
        case .recording:
            recorder.stopRecording()
        case .recorded, .playing:
            // Discard current recording and start fresh
            recorder.reset()
            Task { await recorder.startRecording() }
        }
    }

    private var canSave: Bool {
        recorder.state == .recorded && recorder.recordedFileURL != nil
    }

    private func saveNote() {
        guard let url = recorder.recordedFileURL else { return }
        let note = VoiceNote(
            localFilename: url.lastPathComponent,
            duration: recorder.recordingDuration,
            caption: caption,
            kind: kind
        )
        onAdd(note)
        dismiss()
    }

    // MARK: - Computed helpers

    private var recorderStateSymbol: String {
        switch recorder.state {
        case .idle:       return "mic.circle"
        case .recording:  return "waveform"
        case .recorded:   return "checkmark.circle.fill"
        case .playing:    return "speaker.wave.2.fill"
        case .error:      return "exclamationmark.circle"
        }
    }

    private var recorderStateColor: Color {
        switch recorder.state {
        case .idle:       return .secondary
        case .recording:  return .red
        case .recorded:   return .green
        case .playing:    return .blue
        case .error:      return .red
        }
    }

    private var durationLabel: String {
        switch recorder.state {
        case .idle:       return "Ready"
        case .recording:  return formatDuration(recorder.recordingDuration)
        case .recorded:   return formatDuration(recorder.recordingDuration)
        case .playing:    return formatDuration(recorder.playbackProgress)
        case .error:      return "Error"
        }
    }

    private var recordButtonLabel: String {
        switch recorder.state {
        case .idle:                return "Record"
        case .recording:           return "Stop"
        case .recorded, .playing:  return "Re-record"
        case .error:               return "Try Again"
        }
    }

    private var recordButtonSymbol: String {
        switch recorder.state {
        case .idle, .error:        return "mic.fill"
        case .recording:           return "stop.fill"
        case .recorded, .playing:  return "arrow.counterclockwise"
        }
    }

    private var playbackFraction: Double {
        guard recorder.recordingDuration > 0 else { return 0 }
        return min(recorder.playbackProgress / recorder.recordingDuration, 1.0)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    VoiceNoteRecorderSheet(attachContext: "Kitchen") { _ in }
}
#endif
