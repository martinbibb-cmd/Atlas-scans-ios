import Foundation
import Combine

// MARK: - VoiceNoteRecorderViewModel
//
// Manages the transcript-first voice note recording lifecycle.
//
// States:
//   .idle          — no recording in progress
//   .recording     — actively recording
//   .paused        — recording paused
//   .stopped       — recording finished; transcript may be pending
//
// Design:
//   • Raw audio is ephemeral — it is used only to produce a transcript.
//   • The draft model (CapturedVoiceNoteDraft) never contains audio paths.
//   • Transcript text is the only evidence that persists.

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

    // MARK: Current draft

    private var activeDraft: CapturedVoiceNoteDraft?
    private var elapsedTimer: Timer?
    private var sessionStart: Date?

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
        state = .recording
        startElapsedTimer()
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        elapsedTimer?.invalidate()
    }

    func resume() {
        guard state == .paused else { return }
        state = .recording
        startElapsedTimer()
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        state = .stopped
        elapsedTimer?.invalidate()
        activeDraft?.endedAt = Date()
        // In production, raw audio file path is resolved here and then discarded
        // after transcription is complete. It must NOT be stored in the draft.
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
        return draft
    }

    /// Discards the current note without saving.
    func discard() {
        activeDraft = nil
        state = .idle
        elapsedSeconds = 0
        transcript = ""
        elapsedTimer?.invalidate()
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
    var canCommit: Bool { state == .stopped }
}
