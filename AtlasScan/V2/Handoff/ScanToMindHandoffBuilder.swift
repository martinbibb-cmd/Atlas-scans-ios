/// ScanToMindHandoffBuilder — Pure builder around the existing
/// `ScanToMindPayloadEncoder` (AtlasScanCore).
///
/// The encoder accepts a `SessionCaptureV2` and returns a `ScanToMindHandoffV1`
/// (with backward-compatible `completionStatus` and `missingEvidence`). This
/// builder is the sole construction site that the new continuous-survey shell
/// uses, so the shell never builds handoff payloads ad-hoc.
///
/// Behavioural rules (matching the brief):
///   - Incomplete sessions are *allowed*; they produce a handoff with
///     `completionStatus == .incompleteDraft`.
///   - The caller-supplied `engineerNotes` overrides the session's stored
///     `engineerNotes` when non-nil.
///   - The builder never mutates the session.

import Foundation
import AtlasScanCore

public enum ScanToMindHandoffBuilder {

    /// Builds a handoff payload from the given session. Engineer notes
    /// supplied here override anything stored on the session.
    public static func build(
        session: SessionCaptureV2,
        engineerNotesOverride: String? = nil
    ) throws -> ScanToMindHandoffV1 {
        let baseHandoff = try ScanToMindPayloadEncoder.encode(session: session)

        guard let override = engineerNotesOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
              !override.isEmpty,
              override != session.engineerNotes
        else {
            return baseHandoff
        }

        // Re-build with the override note. The encoder always derives
        // readiness/missingEvidence from the session, so we replicate the
        // same construction with the override applied.
        var sessionWithNote = session
        sessionWithNote.engineerNotes = override
        return try ScanToMindPayloadEncoder.encode(session: sessionWithNote)
    }

    /// Convenience: returns the JSON `Data` for the built payload.
    public static func buildData(
        session: SessionCaptureV2,
        engineerNotesOverride: String? = nil
    ) throws -> Data {
        let handoff = try build(session: session, engineerNotesOverride: engineerNotesOverride)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(handoff)
    }
}
