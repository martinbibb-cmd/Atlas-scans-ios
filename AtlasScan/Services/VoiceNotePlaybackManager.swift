import Foundation
import AVFoundation

// MARK: - VoiceNotePlaybackManager
//
// Shared lightweight playback coordinator for voice note rows across
// SessionCaptureView surfaces (session, room, object).
//
// Only one note can be active at a time. Tapping play on a second note
// stops the first automatically.
//
// Usage:
//   @ObservedObject private var playback = VoiceNotePlaybackManager.shared
//   playback.toggle(note: note)
//   playback.isPlaying(note: note)   // true while this note is active

@MainActor
final class VoiceNotePlaybackManager: NSObject, ObservableObject {

    static let shared = VoiceNotePlaybackManager()

    // MARK: - Published state

    @Published private(set) var playingNoteID: UUID?
    @Published private(set) var playbackProgress: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0

    // MARK: - Private

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private let store = VoiceNoteStore.shared

    // MARK: - Public API

    /// Returns true if `note` is the currently playing note.
    func isPlaying(note: VoiceNote) -> Bool {
        playingNoteID == note.id
    }

    /// Toggles play/pause for the given note.
    /// If a different note is playing it is stopped first.
    func toggle(note: VoiceNote) {
        if playingNoteID == note.id {
            stop()
        } else {
            play(note: note)
        }
    }

    /// Stops whatever is currently playing.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopTimer()
        playingNoteID = nil
        playbackProgress = 0
        playbackDuration = 0
    }

    // MARK: - Private helpers

    private func play(note: VoiceNote) {
        // Stop any existing playback first.
        if audioPlayer != nil { stop() }

        let url = store.fileURL(for: note.localFilename)
        guard store.fileExists(filename: note.localFilename) else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            audioPlayer = player
            playingNoteID = note.id
            playbackProgress = 0
            playbackDuration = player.duration
            startTimer()
        } catch {
            stop()
        }
    }

    private func startTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.playbackProgress = self.audioPlayer?.currentTime ?? 0
            }
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceNotePlaybackManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }
}
