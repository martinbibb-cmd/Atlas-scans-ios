import Foundation

// MARK: - RoomAdjacency

/// Represents a manually confirmed connection between two rooms in a property.
/// One record is directional (from → to) but the connection is displayed
/// bidirectionally in the property plan overview.
///
/// Engineers add these links after capturing individual rooms to build a
/// whole-property picture before export.
struct RoomAdjacency: Identifiable, Codable {

    var id: UUID = UUID()

    /// The room this link originates from (typically the room whose opening was tagged).
    var fromRoomID: UUID

    /// The room this link connects to.
    var toRoomID: UUID

    /// Optional: the specific opening in fromRoom that creates this connection.
    var openingID: UUID?

    /// Nature of the connection.
    var kind: AdjacencyKind

    /// Whether the engineer has manually confirmed this link.
    /// Unconfirmed links are shown as dashed lines in the plan overview.
    var isConfirmed: Bool

    var notes: String

    var createdAt: Date

    // MARK: Init

    init(
        id: UUID = UUID(),
        fromRoomID: UUID,
        toRoomID: UUID,
        openingID: UUID? = nil,
        kind: AdjacencyKind = .door,
        isConfirmed: Bool = false,
        notes: String = ""
    ) {
        self.id = id
        self.fromRoomID = fromRoomID
        self.toRoomID = toRoomID
        self.openingID = openingID
        self.kind = kind
        self.isConfirmed = isConfirmed
        self.notes = notes
        self.createdAt = Date()
    }

    // MARK: Helpers

    /// Returns true if this adjacency connects the two given room IDs (in either direction).
    func connects(_ roomA: UUID, to roomB: UUID) -> Bool {
        (fromRoomID == roomA && toRoomID == roomB) ||
        (fromRoomID == roomB && toRoomID == roomA)
    }
}

// MARK: - AdjacencyKind

enum AdjacencyKind: String, Codable, CaseIterable {
    case door    = "door"
    case archway = "archway"
    case other   = "other"

    var displayName: String {
        switch self {
        case .door:    return "Door"
        case .archway: return "Archway"
        case .other:   return "Other Opening"
        }
    }

    var symbolName: String {
        switch self {
        case .door:    return "door.left.hand.open"
        case .archway: return "archivebox"
        case .other:   return "arrow.left.arrow.right"
        }
    }
}

// MARK: - RoomPlacementOverride

/// Records an engineer-adjusted position for a room in the property plan overview.
/// Coordinates are normalised (0…1) relative to the plan canvas.
/// Used only for review clarity — has no impact on geometry, clearance, or export.
struct RoomPlacementOverride: Identifiable, Codable {

    /// Matches the `ScannedRoom.id` this override applies to.
    var id: UUID

    /// Normalised x-offset in the plan canvas (0 = left edge, 1 = right edge).
    var x: Double

    /// Normalised y-offset in the plan canvas (0 = top edge, 1 = bottom edge).
    var y: Double

    init(id: UUID, x: Double = 0.5, y: Double = 0.5) {
        self.id = id
        self.x = max(0, min(1, x))
        self.y = max(0, min(1, y))
    }
}
