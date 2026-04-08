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

    /// Optional appliance profile identifier for model-specific clearance rules.
    /// When set, ClearanceEngine uses this profile's dimensions instead of category defaults.
    /// Must match an `ApplianceProfile.id` in `ApplianceProfileLibrary`.
    var applianceProfileID: String?

    /// Optional clearance profile identifier used by the clearance-check rendering layer.
    /// When set, overrides the appliance profile for clearance zone geometry only.
    /// Typically the same as `applianceProfileID`; split here for future extensibility.
    var clearanceProfileID: String?

    /// Spatial anchor set when the object is placed directly from the live camera view.
    /// Nil for objects added via the room-layout form flow.
    var worldAnchor: WorldAnchor3D?

    /// IDs of TaggedPhoto records linked to this object.
    /// Maintained as a convenience index; the authoritative link is TaggedPhoto.taggedObjectID.
    var linkedPhotoIDs: [UUID]

    /// IDs of VoiceNote records linked to this object.
    /// Maintained as a convenience index; the authoritative link is VoiceNote.linkedObjectID.
    var linkedVoiceNoteIDs: [UUID]

    /// IDs of ValidationIssue records associated with this object.
    var linkedIssueIDs: [UUID]

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
        applianceProfileID: String? = nil,
        clearanceProfileID: String? = nil,
        worldAnchor: WorldAnchor3D? = nil,
        linkedPhotoIDs: [UUID] = [],
        linkedVoiceNoteIDs: [UUID] = [],
        linkedIssueIDs: [UUID] = [],
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
        self.applianceProfileID = applianceProfileID
        self.clearanceProfileID = clearanceProfileID
        self.worldAnchor = worldAnchor
        self.linkedPhotoIDs = linkedPhotoIDs
        self.linkedVoiceNoteIDs = linkedVoiceNoteIDs
        self.linkedIssueIDs = linkedIssueIDs
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

    // MARK: Decodable — backward-compatible with pre-clearance-profile object records
    //
    // COMPATIBILITY GLUE: decodeIfPresent with explicit defaults ensures that
    // TaggedObject records saved before the following fields were introduced still
    // decode cleanly:
    //   clearanceProfileID  (added with layered clearance geometry)
    //   linkedPhotoIDs      (added for direct object → photo cross-linking)
    //   linkedIssueIDs      (added for object → validation issue cross-linking)

    private enum CodingKeys: String, CodingKey {
        case id, roomID, category, label
        case normalizedPosition, wallIndex, attachedWallID
        case placementMode, rotation, boundingSize
        case applianceProfileID, clearanceProfileID, worldAnchor
        case linkedPhotoIDs, linkedVoiceNoteIDs, linkedIssueIDs
        case quickFieldValues, notes, isConfirmed, confidence
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                  = try c.decode(UUID.self,                    forKey: .id)
        roomID              = try c.decode(UUID.self,                    forKey: .roomID)
        category            = try c.decode(ServiceObjectCategory.self,   forKey: .category)
        let rawLabel        = try c.decode(String.self,                  forKey: .label)
        label               = rawLabel
        normalizedPosition  = try c.decodeIfPresent(NormalizedPoint2D.self, forKey: .normalizedPosition)
        wallIndex           = try c.decodeIfPresent(Int.self,            forKey: .wallIndex)
        attachedWallID      = try c.decodeIfPresent(UUID.self,           forKey: .attachedWallID)
        placementMode       = try c.decode(PlacementMode.self,           forKey: .placementMode)
        rotation            = try c.decode(Double.self,                  forKey: .rotation)
        boundingSize        = try c.decodeIfPresent(PlacementSize.self,  forKey: .boundingSize)
        applianceProfileID  = try c.decodeIfPresent(String.self,         forKey: .applianceProfileID)
        // New fields — default to nil/empty for objects saved before these were introduced.
        clearanceProfileID  = try c.decodeIfPresent(String.self,         forKey: .clearanceProfileID)
        worldAnchor         = try c.decodeIfPresent(WorldAnchor3D.self,  forKey: .worldAnchor)
        linkedPhotoIDs      = try c.decodeIfPresent([UUID].self,         forKey: .linkedPhotoIDs)      ?? []
        linkedVoiceNoteIDs  = try c.decodeIfPresent([UUID].self,         forKey: .linkedVoiceNoteIDs) ?? []
        linkedIssueIDs      = try c.decodeIfPresent([UUID].self,         forKey: .linkedIssueIDs)      ?? []
        quickFieldValues    = try c.decode([String: String].self,        forKey: .quickFieldValues)
        notes               = try c.decode(String.self,                  forKey: .notes)
        isConfirmed         = try c.decode(Bool.self,                    forKey: .isConfirmed)
        confidence          = try c.decode(ConfidenceLevel.self,         forKey: .confidence)
        createdAt           = try c.decode(Date.self,                    forKey: .createdAt)
        updatedAt           = try c.decode(Date.self,                    forKey: .updatedAt)
    }
}

// MARK: - AnchorConfidence

/// Describes the quality and source of a WorldAnchor3D's spatial placement.
///
/// This drives both rendering decisions (e.g. pin opacity / styling) and
/// honest UX communication about how precisely a tag is locked to the real scene.
enum AnchorConfidence: String, Codable, CaseIterable {
    /// Position derived from screen-tap only; x/y/z are approximate placeholders
    /// (x = screenX, y = 0, z = screenY projected onto a unit floor plane).
    case screenOnly       = "screenOnly"

    /// Position obtained from an ARKit `estimatedPlane` raycast; spatially grounded
    /// and will stay approximately attached to the real scene as the camera moves.
    /// May shift slightly as the AR session refines its world model.
    case raycastEstimated = "raycastEstimated"

    /// Reserved for future: position locked to a persistent AR anchor or
    /// resolved plane geometry with high confidence.
    case worldLocked      = "worldLocked"

    var displayName: String {
        switch self {
        case .screenOnly:        return "Screen only"
        case .raycastEstimated:  return "AR estimated"
        case .worldLocked:       return "World locked"
        }
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
struct NormalizedPoint2D: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = max(0, min(1, x))
        self.y = max(0, min(1, y))
    }
}

// MARK: - WorldAnchor3D

/// A spatial anchor recording where a tagged object was placed in the live camera view.
///
/// `screenX` and `screenY` store the normalised view position (0...1) at the moment
/// the engineer tapped, preserved as a render fallback when ARKit reprojection is
/// unavailable (e.g. older devices, simulator, or screen-only placement mode).
///
/// `x`, `y`, `z` store the world-space position in metres relative to the ARKit
/// session origin.  For the screen-only path these are approximate placeholders
/// (x = screenX, y = 0, z = screenY).  When `anchorConfidence` is
/// `.raycastEstimated` or higher, these contain the real world coordinates from an
/// ARKit `estimatedPlane` raycast and can be reprojected each frame to keep the
/// pin visually locked to the physical scene.
struct WorldAnchor3D: Codable, Equatable {

    /// World-space x position in metres (ARKit session origin).
    var x: Double

    /// World-space y position in metres (0 = ARKit session floor plane).
    var y: Double

    /// World-space z position in metres (ARKit session origin).
    var z: Double

    /// Normalised horizontal screen position at placement time (0 = left, 1 = right).
    /// Preserved as a fallback render position independent of AR tracking quality.
    var screenX: Double

    /// Normalised vertical screen position at placement time (0 = top, 1 = bottom).
    /// Preserved as a fallback render position independent of AR tracking quality.
    var screenY: Double

    /// How the world-space coordinates were obtained.
    /// Used by the live-view rendering layer to decide whether to reproject
    /// the pin from world-space each frame or to use the stored screen position.
    var anchorConfidence: AnchorConfidence

    init(
        x: Double = 0,
        y: Double = 0,
        z: Double = 0,
        screenX: Double,
        screenY: Double,
        anchorConfidence: AnchorConfidence = .screenOnly
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.screenX = max(0, min(1, screenX))
        self.screenY = max(0, min(1, screenY))
        self.anchorConfidence = anchorConfidence
    }

    // MARK: Codable — backward-compatible with pre-anchorConfidence records

    private enum CodingKeys: String, CodingKey {
        case x, y, z, screenX, screenY, anchorConfidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x                = try c.decode(Double.self, forKey: .x)
        y                = try c.decode(Double.self, forKey: .y)
        z                = try c.decode(Double.self, forKey: .z)
        screenX          = try c.decode(Double.self, forKey: .screenX)
        screenY          = try c.decode(Double.self, forKey: .screenY)
        // New field — older records default to .screenOnly.
        anchorConfidence = try c.decodeIfPresent(AnchorConfidence.self,
                                                  forKey: .anchorConfidence) ?? .screenOnly
    }
}
