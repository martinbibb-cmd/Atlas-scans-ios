/// RoomSegmentationService — Owns the live `currentRoomCandidate`,
/// `confirmedRooms`, and `suggestedRoomBreaks` state for a continuous
/// survey.
///
/// Critically: this service **never** auto-creates a confirmed room. It only
/// surfaces suggestions; the user must explicitly Confirm / Rename / Merge /
/// Ignore via `RoomSuggestionSheet` for a candidate to become a real room.

import Foundation
import Combine
import AtlasScanCore

@MainActor
public final class RoomSegmentationService: ObservableObject {

    @Published public private(set) var currentRoomCandidate: RoomCandidateV1?
    @Published public private(set) var confirmedRooms: [RoomCaptureV2] = []
    @Published public private(set) var suggestedRoomBreaks: [RoomCandidateV1] = []

    public let visitId: UUID

    public init(visitId: UUID, confirmedRooms: [RoomCaptureV2] = []) {
        self.visitId = visitId
        self.confirmedRooms = confirmedRooms
    }

    // MARK: - Suggestion intake

    /// Records a new candidate without confirming it.
    public func suggestRoom(
        suggestedName: String? = nil,
        source: RoomSuggestionSource = .fallback,
        breakConfidence: Double = 0.0,
        mergeIntoRoomId: UUID? = nil
    ) -> RoomCandidateV1 {
        let candidate = RoomCandidateV1(
            visitId: visitId,
            suggestedName: suggestedName,
            source: source,
            breakConfidence: breakConfidence,
            mergeIntoRoomId: mergeIntoRoomId
        )
        currentRoomCandidate = candidate
        suggestedRoomBreaks.append(candidate)
        return candidate
    }

    // MARK: - User decisions

    /// Confirm the candidate as a brand-new room. Returns the `RoomCaptureV2`
    /// that should be appended to the session.
    public func confirm(_ candidate: RoomCandidateV1, name: String? = nil) -> RoomCaptureV2 {
        let label = (name ?? candidate.suggestedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = label.isEmpty ? "Untitled Room" : label
        let room = RoomCaptureV2(
            displayName: displayName,
            captureStatus: .captured
        )
        confirmedRooms.append(room)
        clear(candidate)
        return room
    }

    /// Merge the candidate into an existing room — no new room is created.
    public func merge(_ candidate: RoomCandidateV1, into roomId: UUID) {
        clear(candidate)
        // Caller is responsible for re-pointing any in-flight evidence at
        // `roomId`; this service just clears the suggestion.
    }

    /// User explicitly ignores this suggestion.
    public func ignore(_ candidate: RoomCandidateV1) {
        clear(candidate)
    }

    private func clear(_ candidate: RoomCandidateV1) {
        suggestedRoomBreaks.removeAll(where: { $0.id == candidate.id })
        if currentRoomCandidate?.id == candidate.id {
            currentRoomCandidate = nil
        }
    }
}
