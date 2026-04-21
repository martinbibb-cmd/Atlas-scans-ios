import Foundation

// MARK: - VisitConsolidatedNotes

/// The result of consolidating voice and text notes from a field visit.
///
/// `lines` are ordered chronologically.  Each line is the best available
/// text for one note — transcript when ready, caption fallback otherwise.
/// Empty and whitespace-only note content is excluded.
struct VisitConsolidatedNotes {

    /// Ordered, deduplicated note lines (transcript-first, then caption).
    let lines: [String]

    /// True when at least one note contributes usable text content.
    var hasUsableContent: Bool { !lines.isEmpty }

    /// All lines joined as a single block.
    var summary: String { lines.joined(separator: "\n") }

    /// A capped preview slice for display surfaces.
    func preview(maxLines: Int = 3) -> [String] {
        Array(lines.prefix(maxLines))
    }
}

// MARK: - consolidateVisitNotes

/// Derives a `VisitConsolidatedNotes` from the given voice and manual text notes.
///
/// Rules:
///   - Voice notes are sorted chronologically by `createdAt`.
///   - Transcript text is preferred when `transcriptStatus == .completed` and
///     the transcript is non-empty.
///   - Caption is used as fallback when transcript is absent or empty.
///   - A note contributes nothing when both transcript and caption are empty
///     (e.g. a newly-saved recording before transcription returns).
///   - Manual text notes are appended after the voice notes in the order supplied.
///   - Whitespace-only strings are ignored.
///
/// The function is pure and deterministic — it has no side effects.
func consolidateVisitNotes(
    voiceNotes: [VoiceNote],
    manualNotes: [String] = []
) -> VisitConsolidatedNotes {

    var lines: [String] = []

    let sorted = voiceNotes.sorted { $0.createdAt < $1.createdAt }

    for note in sorted {
        let text: String?

        if note.transcriptStatus == .completed,
           let t = note.transcript,
           !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = t.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let caption = note.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            text = caption.isEmpty ? nil : caption
        }

        if let t = text {
            lines.append(t)
        }
    }

    for rawNote in manualNotes {
        let trimmed = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append(trimmed)
        }
    }

    return VisitConsolidatedNotes(lines: lines)
}
