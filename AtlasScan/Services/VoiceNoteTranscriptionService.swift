import Foundation

// MARK: - VoiceNoteTranscriptionService
//
// Seam for local voice-note transcription.
//
// Design rules:
//   • A note must always be saved regardless of whether transcription succeeds.
//   • The service returns `.failed` status (not a crash or error throw) when
//     transcription is unavailable so callers can handle gracefully.
//   • Wire SFSpeechRecognizer in the body of `transcribe(fileURL:)` when the
//     Speech framework is linked and NSSpeechRecognitionUsageDescription is
//     added to Info.plist.
//
// To enable Apple Speech transcription:
//   1. Link the Speech framework in the AtlasScan target.
//   2. Add NSSpeechRecognitionUsageDescription to Info.plist.
//   3. Replace the stub body of `transcribe(fileURL:)` with the
//      SFSpeechURLRecognitionRequest implementation shown in the comment below.

@MainActor
final class VoiceNoteTranscriptionService {

    static let shared = VoiceNoteTranscriptionService()

    // MARK: - Result

    struct TranscriptionResult {
        let transcript: String?
        let status: TranscriptStatus
    }

    // MARK: - Public API

    /// Attempts to transcribe the audio file at the given URL.
    ///
    /// Returns:
    ///   - `status: .completed`, non-empty `transcript` on success.
    ///   - `status: .failed`, `transcript: nil` when transcription is
    ///     unavailable or the recognition request fails.
    ///
    /// The caller must handle the `.failed` case: the voice note record
    /// must remain usable (via caption fallback) even without a transcript.
    func transcribe(fileURL: URL) async -> TranscriptionResult {
        // ── Seam ─────────────────────────────────────────────────────────────
        // Replace this stub with an SFSpeechRecognizer call to activate
        // on-device transcription.  Example implementation:
        //
        //   import Speech
        //
        //   guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
        //       let granted = await requestSpeechAuthorization()
        //       guard granted else { return .init(transcript: nil, status: .failed) }
        //   }
        //   guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
        //       return .init(transcript: nil, status: .failed)
        //   }
        //   let request = SFSpeechURLRecognitionRequest(url: fileURL)
        //   request.shouldReportPartialResults = false
        //   let result = try? await withCheckedThrowingContinuation { continuation in
        //       recognizer.recognitionTask(with: request) { result, error in
        //           if let result, result.isFinal {
        //               continuation.resume(returning: result.bestTranscription.formattedString)
        //           } else if let error {
        //               continuation.resume(throwing: error)
        //           }
        //       }
        //   }
        //   let text = result?.trimmingCharacters(in: .whitespacesAndNewlines)
        //   return text.map { .init(transcript: $0, status: .completed) }
        //          ?? .init(transcript: nil, status: .failed)
        // ─────────────────────────────────────────────────────────────────────

        return TranscriptionResult(transcript: nil, status: .failed)
    }
}
