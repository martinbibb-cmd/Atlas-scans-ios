import Foundation

// MARK: - AtlasPropertyV1
//
// Canonical property truth produced by Atlas Scan and consumed by Atlas Mind.
//
// Design goals:
//   • One AtlasPropertyV1 = one complete property survey handoff.
//   • Carries provenance, spatial data, service assets, and evidence references
//     in a single self-describing envelope.
//   • Supersedes the ScanBundleV1 path as the primary handoff contract.
//   • ScanBundleV1 is retained as a fallback / compatibility export — see notes
//     on `AtlasPropertyV1.scanBundle`.
//
// Versioning:
//   • The `schemaVersion` field must match `currentAtlasPropertyVersion`.
//   • Atlas Mind should reject payloads whose version is not in
//     `supportedAtlasPropertyVersions`.

// MARK: - Version constants

/// The set of AtlasPropertyV1 schema versions Atlas can currently import.
public let supportedAtlasPropertyVersions: [String] = ["1.0"]

/// The schema version emitted by this client.
public let currentAtlasPropertyVersion: String = "1.0"

// MARK: - Top-level envelope

/// Canonical property handoff from Atlas Scan to Atlas Mind.
///
/// Produced by `PropertyScanSession.toAtlasPropertyV1()` and consumed by
/// Atlas Mind when importing a completed property survey.
public struct AtlasPropertyV1: Codable, Sendable {

    // MARK: Schema identity

    /// Schema version; must be in `supportedAtlasPropertyVersions`.
    public let schemaVersion: String

    // MARK: Property identity

    /// UUID of the originating `PropertyScanSession`.
    public let propertyID: String

    /// Engineer-assigned job reference (e.g. "JOB-1712345678").
    public let jobReference: String

    /// Property address as entered by the engineer on site.
    public let propertyAddress: String

    /// Engineer's name (may be empty).
    public let engineerName: String

    /// Optional Atlas job / recommendation ID linked to this property.
    public let atlasJobID: String?

    // MARK: Provenance timestamps

    /// ISO-8601 timestamp of when the session was first created.
    public let capturedAt: String

    /// ISO-8601 timestamp of when this handoff payload was generated.
    public let handoffAt: String

    // MARK: Capture state

    /// Capture lifecycle state at the time of handoff.
    /// One of: "not_started" | "in_progress" | "paused" | "completed" | "incomplete"
    public let scanState: String

    /// Review / sign-off state at the time of handoff.
    /// One of: "pending" | "in_review" | "reviewed" | "needs_attention" | "blocked"
    public let reviewState: String

    // MARK: Spatial content

    /// Rooms captured during the session.
    public let rooms: [AtlasPropertyRoomV1]

    /// Inter-room connections (doors, archways, etc.).
    public let adjacencies: [AtlasPropertyAdjacencyV1]

    /// Service objects that were not assigned to a specific room.
    public let sessionObjects: [AtlasPropertyObjectV1]

    // MARK: Evidence summary

    /// Aggregate counts of evidence captured during the session.
    public let evidenceSummary: AtlasEvidenceSummaryV1

    // MARK: Session knowledge (structured voice capture)

    /// Structured knowledge extracted from voice notes during the session.
    /// Nil when no facts were extracted (e.g. for older sessions without structured capture).
    public let sessionKnowledge: AtlasSessionKnowledgeV1?

    // MARK: 3D evidence (optional)

    /// Indoor room-scan evidence records (RoomPlan / LiDAR captures).
    /// Each entry references a heavy 3-D asset stored externally.
    /// nil / empty when no room scans have been captured or associated.
    ///
    /// Architecture rule: consumers must NOT derive heat-loss or engine inputs
    /// from these assets.  They are evidence records only.
    public let spatialEvidence3d: [SpatialEvidence3D]?

    /// Outdoor flue-clearance AR scene records.
    /// Each entry contains tagged features, measured distances, and a
    /// compliance summary derived from structured measurements.
    /// nil / empty when no external clearance scene has been captured.
    ///
    /// Architecture rule: compliance must be evaluated from
    /// `ExternalClearanceSceneV1.measurements` and `nearbyFeatures`,
    /// not from raw point-cloud geometry.
    public let externalClearanceScenes: [ExternalClearanceSceneV1]?

    // MARK: Install markup

    /// Structured install markup captured by the engineer on floor plans and wall photos.
    ///
    /// Carries both existing and proposed install objects and pipe routes, plus
    /// spatial annotations.  Nil when no install markup has been captured.
    ///
    /// Architecture rule: atlas-recommendation consumes this to derive routing
    /// complexity, material estimates, and install feasibility signals.
    /// It must NOT be derived from raw scan geometry; only from engineer-drawn markup.
    public let installLayer: InstallLayerModelV1?

    // MARK: Init

    public init(
        schemaVersion: String,
        propertyID: String,
        jobReference: String,
        propertyAddress: String,
        engineerName: String,
        atlasJobID: String?,
        capturedAt: String,
        handoffAt: String,
        scanState: String,
        reviewState: String,
        rooms: [AtlasPropertyRoomV1],
        adjacencies: [AtlasPropertyAdjacencyV1],
        sessionObjects: [AtlasPropertyObjectV1],
        evidenceSummary: AtlasEvidenceSummaryV1,
        sessionKnowledge: AtlasSessionKnowledgeV1? = nil,
        spatialEvidence3d: [SpatialEvidence3D]? = nil,
        externalClearanceScenes: [ExternalClearanceSceneV1]? = nil,
        installLayer: InstallLayerModelV1? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.propertyID = propertyID
        self.jobReference = jobReference
        self.propertyAddress = propertyAddress
        self.engineerName = engineerName
        self.atlasJobID = atlasJobID
        self.capturedAt = capturedAt
        self.handoffAt = handoffAt
        self.scanState = scanState
        self.reviewState = reviewState
        self.rooms = rooms
        self.adjacencies = adjacencies
        self.sessionObjects = sessionObjects
        self.evidenceSummary = evidenceSummary
        self.sessionKnowledge = sessionKnowledge
        self.spatialEvidence3d = spatialEvidence3d
        self.externalClearanceScenes = externalClearanceScenes
        self.installLayer = installLayer
    }
}

// MARK: - Room

/// A room within a property survey.
public struct AtlasPropertyRoomV1: Codable, Sendable {

    /// UUID of the originating `ScannedRoom`.
    public let id: String

    /// Engineer-assigned room name (e.g. "Kitchen", "Living Room").
    public let name: String

    /// Storey index: 0 = ground floor, 1 = first floor, -1 = basement.
    public let floorIndex: Int

    /// `true` when LiDAR scan geometry was captured for this room.
    public let geometryCaptured: Bool

    /// Floor area in square metres; nil when not captured.
    public let areaM2: Double?

    /// Ceiling height in metres; nil when not captured.
    public let heightM: Double?

    /// `true` when the engineer marked this room as reviewed before handoff.
    public let isReviewed: Bool

    /// Service objects tagged in this room.
    public let objects: [AtlasPropertyObjectV1]

    /// Number of evidence photos attached to this room (includes object photos).
    public let photoCount: Int

    /// Number of voice notes recorded in this room (includes object notes).
    public let voiceNoteCount: Int

    public init(
        id: String,
        name: String,
        floorIndex: Int,
        geometryCaptured: Bool,
        areaM2: Double?,
        heightM: Double?,
        isReviewed: Bool,
        objects: [AtlasPropertyObjectV1],
        photoCount: Int,
        voiceNoteCount: Int
    ) {
        self.id = id
        self.name = name
        self.floorIndex = floorIndex
        self.geometryCaptured = geometryCaptured
        self.areaM2 = areaM2
        self.heightM = heightM
        self.isReviewed = isReviewed
        self.objects = objects
        self.photoCount = photoCount
        self.voiceNoteCount = voiceNoteCount
    }
}

// MARK: - Object

/// A service object tagged during the survey.
public struct AtlasPropertyObjectV1: Codable, Sendable {

    /// UUID of the originating `TaggedObject`.
    public let id: String

    /// Service category raw value (e.g. "boiler", "radiator", "cylinder").
    public let category: String

    /// Best-guess display label (e.g. "Worcester Bosch Combi").
    public let label: String

    /// UUID of the room this object belongs to; nil for session-level objects.
    public let roomID: String?

    /// Placement mode: "unplaced" | "manual" | "lidar" | "ar_estimated".
    public let placementMode: String

    /// Placement confidence: "high" | "medium" | "low" | "unknown".
    public let confidence: String

    /// Number of evidence photos attached to this object.
    public let photoCount: Int

    /// Number of voice notes linked to this object.
    public let voiceNoteCount: Int

    /// Engineer-entered quick-field values (keyed by field name).
    public let quickFields: [String: String]

    /// World-space position captured during the survey; nil if not placed.
    public let worldAnchor: AtlasWorldAnchorV1?

    public init(
        id: String,
        category: String,
        label: String,
        roomID: String?,
        placementMode: String,
        confidence: String,
        photoCount: Int,
        voiceNoteCount: Int,
        quickFields: [String: String],
        worldAnchor: AtlasWorldAnchorV1?
    ) {
        self.id = id
        self.category = category
        self.label = label
        self.roomID = roomID
        self.placementMode = placementMode
        self.confidence = confidence
        self.photoCount = photoCount
        self.voiceNoteCount = voiceNoteCount
        self.quickFields = quickFields
        self.worldAnchor = worldAnchor
    }
}

// MARK: - World anchor

/// Approximate world-space position of a tagged object.
public struct AtlasWorldAnchorV1: Codable, Sendable {

    /// World-space x coordinate (metres, right-handed Y-up).
    public let x: Double

    /// World-space y coordinate (metres).
    public let y: Double

    /// World-space z coordinate (metres).
    public let z: Double

    /// Normalised screen-space x position at the time of tagging (0…1).
    public let screenX: Double

    /// Normalised screen-space y position at the time of tagging (0…1).
    public let screenY: Double

    /// Anchor confidence: "screen_only" | "raycast_estimated" | "world_locked".
    public let anchorConfidence: String

    public init(
        x: Double,
        y: Double,
        z: Double,
        screenX: Double,
        screenY: Double,
        anchorConfidence: String
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.screenX = screenX
        self.screenY = screenY
        self.anchorConfidence = anchorConfidence
    }
}

// MARK: - Adjacency

/// A directional connection between two rooms (door, archway, etc.).
public struct AtlasPropertyAdjacencyV1: Codable, Sendable {

    /// UUID of the originating `RoomAdjacency`.
    public let id: String

    /// UUID of the originating room.
    public let fromRoomID: String

    /// UUID of the connected room.
    public let toRoomID: String

    /// Connection kind: "door" | "archway" | "opening" | "wall_shared" | "unknown".
    public let kind: String

    /// `true` when the engineer confirmed this connection.
    public let isConfirmed: Bool

    /// Optional UUID of the opening (door/window) on the shared wall.
    public let openingID: String?

    /// Free-text notes about this connection.
    public let notes: String

    public init(
        id: String,
        fromRoomID: String,
        toRoomID: String,
        kind: String,
        isConfirmed: Bool,
        openingID: String?,
        notes: String
    ) {
        self.id = id
        self.fromRoomID = fromRoomID
        self.toRoomID = toRoomID
        self.kind = kind
        self.isConfirmed = isConfirmed
        self.openingID = openingID
        self.notes = notes
    }
}

// MARK: - Evidence summary

/// Aggregate evidence counts for a property handoff.
public struct AtlasEvidenceSummaryV1: Codable, Sendable {

    /// Total photos across the whole session (session-level + all rooms).
    public let totalPhotos: Int

    /// Total voice notes across the whole session (session-level + all rooms).
    public let totalVoiceNotes: Int

    /// Photos attached at session level (not assigned to a specific room).
    public let sessionPhotoCount: Int

    /// Voice notes recorded at session level (not assigned to a specific room).
    public let sessionVoiceNoteCount: Int

    public init(
        totalPhotos: Int,
        totalVoiceNotes: Int,
        sessionPhotoCount: Int,
        sessionVoiceNoteCount: Int
    ) {
        self.totalPhotos = totalPhotos
        self.totalVoiceNotes = totalVoiceNotes
        self.sessionPhotoCount = sessionPhotoCount
        self.sessionVoiceNoteCount = sessionVoiceNoteCount
    }
}

// MARK: - Session knowledge (structured voice capture)

/// Structured knowledge extracted from engineer voice notes during a session.
///
/// Produced by the Scan app's `SessionKnowledgeExtractor` and projected
/// alongside the spatial content into the canonical handoff payload.
/// Only medium/high-confidence facts are included in the handoff.
public struct AtlasSessionKnowledgeV1: Codable, Sendable {

    /// Structured facts projected from voice notes into canonical knowledge.
    /// Only facts with sufficient confidence are included.
    public let extractedFacts: [AtlasExtractedFactV1]

    public init(extractedFacts: [AtlasExtractedFactV1]) {
        self.extractedFacts = extractedFacts
    }
}

/// A single structured knowledge fact carried in the canonical handoff.
public struct AtlasExtractedFactV1: Codable, Sendable {

    /// UUID of the originating `ExtractedSessionFact`.
    public let id: String

    /// Raw value of `SessionFactCategory` (e.g. "household_composition").
    public let category: String

    /// Human-readable extracted value.
    public let value: String

    /// Confidence: "low" | "medium" | "high".
    public let confidence: String

    /// UUID of the originating voice note; nil when manually entered.
    public let sourceNoteID: String?

    /// UUID of the room scope; nil for session-level facts.
    public let roomID: String?

    /// UUID of the object scope; nil when not tied to a specific object.
    public let objectID: String?

    /// ISO-8601 timestamp when the fact was extracted.
    public let createdAt: String

    public init(
        id: String,
        category: String,
        value: String,
        confidence: String,
        sourceNoteID: String?,
        roomID: String?,
        objectID: String?,
        createdAt: String
    ) {
        self.id = id
        self.category = category
        self.value = value
        self.confidence = confidence
        self.sourceNoteID = sourceNoteID
        self.roomID = roomID
        self.objectID = objectID
        self.createdAt = createdAt
    }
}
