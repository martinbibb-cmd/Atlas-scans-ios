import Foundation

// MARK: - TaggedObject

/// A service-engineering object manually tagged by the engineer inside a scanned room.
/// Geometry is approximate; the emphasis is on presence, category, and quick attributes.
struct TaggedObject: Identifiable, Codable {

    var id: UUID = UUID()

    /// Owning room identifier (denormalised for convenience)
    var roomID: UUID

    var category: ServiceObjectCategory

    /// Human-readable label override; defaults to category.displayName if empty
    var label: String

    /// Rough position within the room (normalised 0…1 relative to room bounding box)
    var normalizedPosition: NormalizedPoint2D?

    /// Wall index the object is associated with (if applicable)
    var wallIndex: Int?

    /// UUID of the ScannedWall the object is attached to, for wall-mounted objects
    var attachedWallID: UUID?

    /// How the object is placed in the room
    var placementMode: PlacementMode

    /// Rotation of the object about the vertical axis, in radians (0 = facing room centre)
    var rotation: Double

    /// Approximate physical footprint of the object
    var boundingSize: PlacementSize?

    /// Quick-entry field values keyed by QuickField.key
    var quickFieldValues: [String: String]

    /// Free-form engineer note
    var notes: String

    /// Whether the object has been confirmed / reviewed
    var isConfirmed: Bool

    /// Confidence level for the tag placement
    var confidence: ConfidenceLevel

    var createdAt: Date
    var updatedAt: Date

    // MARK: Init

    init(
        id: UUID = UUID(),
        roomID: UUID,
        category: ServiceObjectCategory,
        label: String = "",
        normalizedPosition: NormalizedPoint2D? = nil,
        wallIndex: Int? = nil,
        attachedWallID: UUID? = nil,
        placementMode: PlacementMode? = nil,
        rotation: Double = 0.0,
        boundingSize: PlacementSize? = nil,
        quickFieldValues: [String: String] = [:],
        notes: String = "",
        isConfirmed: Bool = false,
        confidence: ConfidenceLevel = .medium
    ) {
        self.id = id
        self.roomID = roomID
        self.category = category
        self.label = label.isEmpty ? category.displayName : label
        self.normalizedPosition = normalizedPosition
        self.wallIndex = wallIndex
        self.attachedWallID = attachedWallID
        self.placementMode = placementMode ?? category.defaultPlacementMode
        self.rotation = rotation
        self.boundingSize = boundingSize
        self.quickFieldValues = quickFieldValues
        self.notes = notes
        self.isConfirmed = isConfirmed
        self.confidence = confidence
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Helpers

    var displayLabel: String {
        label.isEmpty ? category.displayName : label
    }

    mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - ConfidenceLevel

enum ConfidenceLevel: String, Codable, CaseIterable {
    case high    = "high"
    case medium  = "medium"
    case low     = "low"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .high:    return "High"
        case .medium:  return "Medium"
        case .low:     return "Low"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - NormalizedPoint2D

/// A 2D point normalised to 0…1 within a room's bounding rectangle.
struct NormalizedPoint2D: Codable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = max(0, min(1, x))
        self.y = max(0, min(1, y))
    }
}
