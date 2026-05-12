/// ContinuousSurveyViewModel — Drives `ContinuousSurveyView`. Holds the
/// active room context, sheet-presentation state, and dispatches capture
/// actions to the relevant capture services.
///
/// The view-model never *creates* a room itself — that is the job of
/// `RoomSegmentationService` after the user explicitly confirms a suggestion
/// in `RoomSuggestionSheet`.

import Foundation
import SwiftUI
import AtlasScanCore

@MainActor
public final class ContinuousSurveyViewModel: ObservableObject {

    public enum ActiveSheet: Identifiable {
        case tagObject
        case voiceNote
        case roomSuggestion(RoomCandidateV1)
        case finish

        public var id: String {
            switch self {
            case .tagObject:                 return "tag"
            case .voiceNote:                 return "note"
            case .roomSuggestion(let c):     return "room-\(c.id)"
            case .finish:                    return "finish"
            }
        }
    }

    @Published public var activeSheet: ActiveSheet?
    @Published public var cameraUnavailable: Bool = false
    @Published public var currentRoom: RoomCaptureV2?
    @Published public var lastError: String?

    public let visitId: UUID
    public let workspaceId: String?

    public init(
        visitId: UUID,
        workspaceId: String?,
        currentRoom: RoomCaptureV2? = nil
    ) {
        self.visitId = visitId
        self.workspaceId = workspaceId
        self.currentRoom = currentRoom
    }

    public var currentRoomLabel: String? {
        guard let room = currentRoom else { return nil }
        let label = room.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    // MARK: - Action stubs (wired to capture services by the parent)

    public func presentTag()         { activeSheet = .tagObject }
    public func presentVoiceNote()   { activeSheet = .voiceNote }
    public func presentFinish()      { activeSheet = .finish }
    public func presentRoom(suggested candidate: RoomCandidateV1) {
        activeSheet = .roomSuggestion(candidate)
    }
    public func dismissSheet()       { activeSheet = nil }

    public func reportError(_ error: Error) {
        lastError = error.localizedDescription
    }
}
