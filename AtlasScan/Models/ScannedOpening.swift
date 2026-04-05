import Foundation

// MARK: - ScannedOpening

/// Represents a door, window, archway or other opening between spaces.
struct ScannedOpening: Identifiable, Codable {

    var id: UUID = UUID()

    var kind: OpeningKind

    /// Wall index in the parent room where this opening sits
    var wallIndex: Int

    /// Approximate width in metres
    var widthMetres: Double?

    /// Approximate height in metres
    var heightMetres: Double?

    /// Room this opening connects to, if known
    var connectsToRoomID: UUID?

    init(
        id: UUID = UUID(),
        kind: OpeningKind,
        wallIndex: Int,
        widthMetres: Double? = nil,
        heightMetres: Double? = nil,
        connectsToRoomID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.wallIndex = wallIndex
        self.widthMetres = widthMetres
        self.heightMetres = heightMetres
        self.connectsToRoomID = connectsToRoomID
    }
}

// MARK: - OpeningKind

enum OpeningKind: String, Codable, CaseIterable {
    case door       = "door"
    case window     = "window"
    case archway    = "archway"
    case hatch      = "hatch"
    case other      = "other"

    var displayName: String {
        switch self {
        case .door:     return "Door"
        case .window:   return "Window"
        case .archway:  return "Archway"
        case .hatch:    return "Hatch"
        case .other:    return "Other"
        }
    }
}
