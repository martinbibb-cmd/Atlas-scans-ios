import Foundation

// MARK: - ScannedWall

/// Represents a single wall surface within a scanned room.
struct ScannedWall: Identifiable, Codable {

    var id: UUID = UUID()

    /// Index within the parent room's wall array (for display labelling)
    var index: Int

    /// Approximate wall length in metres
    var lengthMetres: Double?

    /// Approximate wall height in metres
    var heightMetres: Double?

    /// Whether this wall is believed to be an external wall
    var isExternalWall: Bool

    /// Whether this wall has a window
    var hasWindow: Bool

    /// Whether this wall has a door or opening
    var hasDoor: Bool

    /// Compass bearing of the wall normal (degrees, 0 = North), if known
    var bearingDegrees: Double?

    init(
        id: UUID = UUID(),
        index: Int,
        lengthMetres: Double? = nil,
        heightMetres: Double? = nil,
        isExternalWall: Bool = false,
        hasWindow: Bool = false,
        hasDoor: Bool = false,
        bearingDegrees: Double? = nil
    ) {
        self.id = id
        self.index = index
        self.lengthMetres = lengthMetres
        self.heightMetres = heightMetres
        self.isExternalWall = isExternalWall
        self.hasWindow = hasWindow
        self.hasDoor = hasDoor
        self.bearingDegrees = bearingDegrees
    }

    var displayName: String { "Wall \(index + 1)" }

    /// Formats a wall index (0-based) as a display name without a ScannedWall instance.
    static func displayName(forIndex index: Int) -> String { "Wall \(index + 1)" }
}
