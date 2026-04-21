import Foundation

// MARK: - PlanningAnnotationKind

/// The kind of a planning annotation added during the Plan phase.
enum PlanningAnnotationKind: String, Codable, CaseIterable {

    /// A note about access constraints for installation routes.
    case accessNote = "access_note"

    /// A per-room note about the proposed floor plan or layout.
    case roomPlanNote = "room_plan_note"

    /// A specification or material note for the proposed installation.
    case specNote = "spec_note"

    var displayName: String {
        switch self {
        case .accessNote:   return "Access Note"
        case .roomPlanNote: return "Room Plan Note"
        case .specNote:     return "Spec Note"
        }
    }

    var symbolName: String {
        switch self {
        case .accessNote:   return "door.left.hand.open"
        case .roomPlanNote: return "rectangle.portrait"
        case .specNote:     return "list.bullet.clipboard"
        }
    }
}

// MARK: - PlanningAnnotation

/// A free-text planning annotation added by the engineer during the Plan phase.
///
/// Planning annotations complement install markup objects and routes by capturing
/// qualitative notes that do not have a spatial component or are not tied to
/// a specific drawn element.
///
/// They map to `PlanningNoteV1` in the planning overlay contract at handoff time.
struct PlanningAnnotation: Identifiable, Codable {

    var id: UUID = UUID()

    /// The annotation text.
    var text: String

    /// The kind of planning note.
    var kind: PlanningAnnotationKind

    /// Optional room association.  Nil for property-level notes.
    var roomID: UUID?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        kind: PlanningAnnotationKind,
        roomID: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.roomID = roomID
        self.createdAt = Date()
    }

    // MARK: Decodable — backward-compatible

    private enum CodingKeys: String, CodingKey {
        case id, text, kind, roomID, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,                  forKey: .id)
        text      = try c.decode(String.self,                forKey: .text)
        kind      = try c.decodeIfPresent(PlanningAnnotationKind.self, forKey: .kind) ?? .specNote
        roomID    = try c.decodeIfPresent(UUID.self,         forKey: .roomID)
        createdAt = try c.decode(Date.self,                  forKey: .createdAt)
    }
}
