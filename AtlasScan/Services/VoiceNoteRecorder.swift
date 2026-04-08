import Foundation
import AVFoundation

// MARK: - VoiceNoteRecorder
//
// Manages a single record/play lifecycle for a voice note.
//
// Usage:
//   1. Call `startRecording()` — begins capturing audio.
//   2. Call `stopRecording()` — finalises the file; `recordedFileURL` is set.
//   3. Call `startPlayback()` / `stopPlayback()` to preview.
//   4. Build a VoiceNote from `recordedFileURL`, `recordingDuration`, and caller-supplied metadata.
//   5. Call `reset()` to clear state for a new recording session.
//
// The recorder writes to a temporary file in Documents/VoiceNotes/.
// The caller is responsible for persisting the VoiceNote metadata to the session.

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject {

    // MARK: - State

    enum RecorderState: Equatable {
        case idle
        case recording
        case recorded
        case playing
        case error(String)

        static func == (lhs: RecorderState, rhs: RecorderState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recording, .recording),
                 (.recorded, .recorded), (.playing, .playing):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var playbackProgress: TimeInterval = 0

    /// The URL of the completed recording. Set after `stopRecording()`.
    private(set) var recordedFileURL: URL?

    // MARK: - Private

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var durationTimer: Timer?
    private var playbackTimer: Timer?

    private let store = VoiceNoteStore.shared

    // MARK: - Recording

    /// Requests microphone permission and begins recording.
    func startRecording() async {
        let granted = await requestMicrophonePermission()
        guard granted else {
            state = .error("Microphone permission was denied. Please allow microphone access in Settings.")
            return
        }

        let noteID = UUID()
        let filename = store.filename(for: noteID)
        let fileURL = store.fileURL(for: filename)

        do {
            try configureAudioSession(forRecording: true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.record()
            audioRecorder = recorder
            recordedFileURL = fileURL
            recordingDuration = 0
            state = .recording
            startDurationTimer()
        } catch {
            state = .error("Could not start recording: \(error.localizedDescription)")
        }
    }

    /// Stops the active recording and finalises the file.
    func stopRecording() {
        guard state == .recording else { return }
        durationTimer?.invalidate()
        durationTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        try? configureAudioSession(forRecording: false)
        state = .recorded
    }

    // MARK: - Playback

    /// Plays back the recorded file from the beginning.
    func startPlayback() {
        guard state == .recorded || state == .playing,
              let url = recordedFileURL else { return }
        do {
            try configureAudioSession(forRecording: false)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            audioPlayer = player
            playbackProgress = 0
            state = .playing
            startPlaybackTimer()
        } catch {
            state = .error("Could not play recording: \(error.localizedDescription)")
        }
    }

    /// Stops playback.
    func stopPlayback() {
        guard state == .playing else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        state = .recorded
    }

    // MARK: - Reset

    /// Resets all state, deleting any draft recording that was not committed.
    /// Call this when the sheet is dismissed without saving.
    func reset() {
        audioRecorder?.stop()
        audioRecorder = nil
        audioPlayer?.stop()
        audioPlayer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        if let url = recordedFileURL {
            // Delete uncommitted draft
            try? FileManager.default.removeItem(at: url)
        }
        recordedFileURL = nil
        recordingDuration = 0
        playbackProgress = 0
        state = .idle
    }

    // MARK: - Private helpers

    private func configureAudioSession(forRecording: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if forRecording {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        } else {
            try session.setCategory(.playback, mode: .default)
        }
        try session.setActive(true)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.recordingDuration += 0.1
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.playbackProgress = self.audioPlayer?.currentTime ?? 0
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceNoteRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !flag {
                self.state = .error("Recording could not be saved.")
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceNoteRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.playbackTimer?.invalidate()
            self.playbackTimer = nil
            self.state = .recorded
            self.playbackProgress = 0
        }
    }
}
