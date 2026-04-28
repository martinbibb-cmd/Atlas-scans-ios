import Foundation
import Speech

// MARK: - VoiceNoteTranscriptionService
//
// On-device voice-note transcription via SFSpeechRecognizer.
//
// Design rules:
//   • A note must always be saved regardless of whether transcription succeeds.
//   • The service returns `.failed` status (not a crash or error throw) when
//     transcription is unavailable so callers can handle gracefully.
//   • Requests microphone and speech-recognition permissions on demand.
//   • Info.plist keys required (already present):
//       NSMicrophoneUsageDescription
//       NSSpeechRecognitionUsageDescription

@MainActor
final class VoiceNoteTranscriptionService {

    static let shared = VoiceNoteTranscriptionService()

    // MARK: - Result

    struct TranscriptionResult {
        let transcript: String?
        let status: TranscriptStatus
    }

    // MARK: - Public API

    /// Attempts to transcribe the audio file at the given URL using on-device
    /// SFSpeechRecognizer.  Returns `.failed` gracefully when recognition is
    /// unavailable or the request fails so callers can still save the voice note.
    func transcribe(fileURL: URL) async -> TranscriptionResult {
        // Request authorisation if needed.
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            let granted = await requestSpeechAuthorization()
            guard granted else {
                return TranscriptionResult(transcript: nil, status: .failed)
            }
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            return TranscriptionResult(transcript: nil, status: .failed)
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false

        do {
            let text = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<String, Error>) in
                recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    } else if let error {
                        continuation.resume(throwing: error)
                    }
                }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return TranscriptionResult(transcript: nil, status: .failed)
            }
            return TranscriptionResult(transcript: trimmed, status: .completed)
        } catch {
            return TranscriptionResult(transcript: nil, status: .failed)
        }
    }

    // MARK: - Permission helper

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
