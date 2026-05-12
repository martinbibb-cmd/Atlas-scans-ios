/// RoomCandidateV1 — A possible room the system has detected during a
/// continuous survey, prior to the user confirming it as a real room.
///
/// The continuous-survey shell does *not* auto-create rooms. Instead, the
/// `RoomSegmentationService` emits `RoomCandidateV1` instances and surfaces
/// them via `RoomSuggestionSheet` for the user to confirm, rename, merge with
/// the current room, or ignore.
///
/// `suggestedName` is a hint only — derived from the listed `source` (a
/// quick-pick selection, a transcript keyword, an existing pin, etc.). The
/// shell must never invent random "Room 2" labels unless no better hint
/// exists.

import Foundation

/// Where a room name suggestion came from. Drives confidence and UI hints.
public enum RoomSuggestionSource: String, Codable, Sendable, CaseIterable {
    /// User chose from the manual quick picker.
    case userSelection = "user_selection"
    /// Derived from a speech transcript keyword (e.g. "this is the kitchen").
    case speechTranscript = "speech_transcript"
    /// Derived from an existing pin in the candidate (e.g. boiler → utility).
    case pinDerived = "pin_derived"
    /// Manually typed by the user.
    case manualEntry = "manual_entry"
    /// Future: semantic scene-understanding classifier.
    case semanticDetection = "semantic_detection"
    /// Fallback when no other source produced a label.
    case fallback
}

public struct RoomCandidateV1: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let visitId: UUID
    /// When the candidate was first detected.
    public let detectedAt: Date
    /// Human-readable suggested name (e.g. "Kitchen"). Suggestion only.
    public var suggestedName: String?
    /// Where `suggestedName` came from.
    public var source: RoomSuggestionSource
    /// `0.0 ... 1.0` — heuristic confidence in this being a *new* room break.
    public var breakConfidence: Double
    /// Optional id of the room this candidate is suggested to merge into,
    /// instead of creating a new room.
    public var mergeIntoRoomId: UUID?

    public init(
        id: UUID = UUID(),
        visitId: UUID,
        detectedAt: Date = Date(),
        suggestedName: String? = nil,
        source: RoomSuggestionSource = .fallback,
        breakConfidence: Double = 0.0,
        mergeIntoRoomId: UUID? = nil
    ) {
        self.id = id
        self.visitId = visitId
        self.detectedAt = detectedAt
        self.suggestedName = suggestedName
        self.source = source
        self.breakConfidence = max(0.0, min(1.0, breakConfidence))
        self.mergeIntoRoomId = mergeIntoRoomId
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case id, visitId, detectedAt, suggestedName, source, breakConfidence, mergeIntoRoomId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        visitId = try c.decode(UUID.self, forKey: .visitId)
        detectedAt = try c.decodeIfPresent(Date.self, forKey: .detectedAt) ?? Date()
        suggestedName = try c.decodeIfPresent(String.self, forKey: .suggestedName)
        source = try c.decodeIfPresent(RoomSuggestionSource.self, forKey: .source) ?? .fallback
        breakConfidence = try c.decodeIfPresent(Double.self, forKey: .breakConfidence) ?? 0.0
        mergeIntoRoomId = try c.decodeIfPresent(UUID.self, forKey: .mergeIntoRoomId)
    }
}
