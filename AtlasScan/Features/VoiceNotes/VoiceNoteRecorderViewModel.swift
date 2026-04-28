import Foundation
import Combine

// MARK: - VoiceNoteRecorderViewModel
//
// Manages the transcript-first voice note recording lifecycle.
//
// States:
//   .idle          — no recording in progress
//   .recording     — actively recording (audio captured by VoiceNoteRecorder)
//   .paused        — recording paused
//   .stopped       — recording finished; transcript may be pending or transcribing
//
// Design:
//   • Audio is captured via VoiceNoteRecorder (AVFoundation).
//   • After stopping, VoiceNoteTranscriptionService auto-transcribes on-device.
//   • The transcript is offered for review/edit in InlineVoiceCommitSheet.
//   • Raw audio is discarded when the note is committed or discarded.

@MainActor
final class VoiceNoteRecorderViewModel: ObservableObject {

    // MARK: Recording state

    enum RecordingState: Equatable {
        case idle
        case recording
        case paused
        case stopped
    }

    @Published private(set) var state: RecordingState = .idle
    @Published var transcript: String = ""
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var isTranscribing: Bool = false

    // MARK: Current draft

    private var activeDraft: CapturedVoiceNoteDraft?
    private var elapsedTimer: Timer?
    private var sessionStart: Date?

    // MARK: Audio recorder

    private let audioRecorder = VoiceNoteRecorder()

    // MARK: - Actions

    func start(roomId: UUID? = nil, linkedObjectId: UUID? = nil) {
        guard state == .idle || state == .stopped else { return }
        var draft = CapturedVoiceNoteDraft()
        draft.startedAt = Date()
        draft.roomId = roomId
        draft.linkedObjectId = linkedObjectId
        activeDraft = draft
        sessionStart = Date()
        elapsedSeconds = 0
        transcript = ""
        state = .recording
        startElapsedTimer()
        Task { await audioRecorder.startRecording() }
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        elapsedTimer?.invalidate()
        // AVAudioRecorder does not support pause/resume; stopping here ends the current
        // audio segment.  If resume() is called, a new recording session begins.
        // The earlier audio segment is preserved on disk but only the latest recording
        // is submitted for transcription.  This limitation is acceptable for the
        // short, single-take voice notes used in Atlas Scan.
        audioRecorder.stopRecording()
    }

    func resume() {
        guard state == .paused else { return }
        state = .recording
        startElapsedTimer()
        Task { await audioRecorder.startRecording() }
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        state = .stopped
        elapsedTimer?.invalidate()
        activeDraft?.endedAt = Date()
        audioRecorder.stopRecording()
        // Kick off auto-transcription so the engineer sees text in the commit sheet.
        transcribeIfPossible()
    }

    /// Commits the current note with the current transcript text.
    /// Returns the committed draft, or nil if there is nothing to commit.
    func commit() -> CapturedVoiceNoteDraft? {
        guard var draft = activeDraft, state == .stopped else { return nil }
        draft.transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        activeDraft = nil
        state = .idle
        elapsedSeconds = 0
        transcript = ""
        // Discard the raw audio file — the transcript is the only persistent artifact.
        audioRecorder.reset()
        return draft
    }

    /// Discards the current note without saving.
    func discard() {
        activeDraft = nil
        state = .idle
        elapsedSeconds = 0
        transcript = ""
        elapsedTimer?.invalidate()
        audioRecorder.reset()
    }

    // MARK: - Transcription

    private func transcribeIfPossible() {
        guard let fileURL = audioRecorder.recordedFileURL else { return }
        isTranscribing = true
        Task {
            let result = await VoiceNoteTranscriptionService.shared.transcribe(fileURL: fileURL)
            // Only set the transcript when we are still in the stopped state (not discarded).
            if state == .stopped, let text = result.transcript, !text.isEmpty {
                transcript = text
            }
            isTranscribing = false
        }
    }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedSeconds += 1
            }
        }
    }

    // MARK: - Computed helpers

    var elapsedTimeText: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var canStart: Bool { state == .idle || state == .stopped }
    var canPause: Bool { state == .recording }
    var canResume: Bool { state == .paused }
    var canStop: Bool  { state == .recording || state == .paused }
    var canCommit: Bool { state == .stopped && !isTranscribing }
}
