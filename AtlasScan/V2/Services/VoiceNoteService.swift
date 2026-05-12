/// VoiceNoteService — Thin wrapper that produces `VoiceNoteV1` records from
/// a processed transcript (raw audio is intentionally never stored — the
/// underlying schema only persists the transcript).
///
/// The capture surface uses `VoiceNoteRecorder` + transcription separately,
/// then hands the final transcript text into `record(transcript:...)` to
/// produce the schema record that the shell appends to `SessionCaptureV2`.

import Foundation
import AtlasScanCore

@MainActor
public final class VoiceNoteService {

    public init() {}

    public enum CaptureError: Error, LocalizedError {
        case emptyTranscript
        public var errorDescription: String? {
            switch self {
            case .emptyTranscript: return "Voice note transcript is empty."
            }
        }
    }

    /// Builds a `VoiceNoteV1` from the supplied transcript and metadata.
    public func record(
        transcript: String,
        visitId: UUID,
        roomId: UUID,
        capturePointId: UUID? = nil,
        linkedObjectId: UUID? = nil,
        extractionHint: ExtractionHint = .general
    ) throws -> VoiceNoteV1 {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CaptureError.emptyTranscript
        }
        return VoiceNoteV1(
            visitId: visitId,
            roomId: roomId,
            capturePointId: capturePointId,
            linkedObjectId: linkedObjectId,
            processedTranscript: trimmed,
            extractionHint: extractionHint
        )
    }
}
