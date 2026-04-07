import Foundation

// MARK: - EvidenceKind

/// The subject category of a captured evidence photo.
enum EvidenceKind: String, Codable, CaseIterable {
    case overview   = "overview"
    case plant      = "plant"
    case emitter    = "emitter"
    case flue       = "flue"
    case cupboard   = "cupboard"
    case control    = "control"
    case issue      = "issue"
    case other      = "other"

    var displayName: String {
        switch self {
        case .overview:  return "Overview"
        case .plant:     return "Plant"
        case .emitter:   return "Emitter"
        case .flue:      return "Flue"
        case .cupboard:  return "Cupboard"
        case .control:   return "Control"
        case .issue:     return "Issue"
        case .other:     return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .overview:  return "photo"
        case .plant:     return "flame"
        case .emitter:   return "thermometer.medium"
        case .flue:      return "arrow.up.to.line"
        case .cupboard:  return "cabinet"
        case .control:   return "dial.medium"
        case .issue:     return "exclamationmark.triangle"
        case .other:     return "camera"
        }
    }
}

// MARK: - TaggedPhoto

/// A photo taken as evidence for a service object, room, or job site.
struct TaggedPhoto: Identifiable, Codable {

    var id: UUID = UUID()

    /// Owning room identifier. Nil for job-level (site) photos.
    var roomID: UUID?

    /// Optional associated tagged object
    var taggedObjectID: UUID?

    /// Filename stored in local app Documents/Photos/ directory
    var filename: String

    /// Optional thumbnail filename stored in Documents/Thumbnails/
    var thumbnailPath: String?

    /// Free-form caption
    var caption: String

    /// Subject category of the photo
    var kind: EvidenceKind

    /// Whether this photo is marked as a key evidence item
    var isKeyEvidence: Bool

    var capturedAt: Date

    // MARK: Sync metadata (offline-first)

    /// Per-photo Atlas sync state.
    /// Default is `.localOnly` — photos are always saved locally first.
    var syncState: PhotoSyncState

    /// Remote asset identifier assigned by Atlas after a successful upload.
    /// Nil until the photo has been uploaded.
    var remoteAssetID: String?

    /// Approximate camera pose at capture time, when available (e.g. ARKit session).
    var cameraPose: CameraPose?

    // MARK: Optional issue tag

    /// Optional issue tag for photos capturing a specific defect or concern.
    var issueTag: String?

    // MARK: Init

    init(
        id: UUID = UUID(),
        roomID: UUID? = nil,
        taggedObjectID: UUID? = nil,
        filename: String,
        thumbnailPath: String? = nil,
        caption: String = "",
        kind: EvidenceKind = .other,
        isKeyEvidence: Bool = false,
        syncState: PhotoSyncState = .localOnly,
        remoteAssetID: String? = nil,
        cameraPose: CameraPose? = nil,
        issueTag: String? = nil
    ) {
        self.id = id
        self.roomID = roomID
        self.taggedObjectID = taggedObjectID
        self.filename = filename
        self.thumbnailPath = thumbnailPath
        self.caption = caption
        self.kind = kind
        self.isKeyEvidence = isKeyEvidence
        self.capturedAt = Date()
        self.syncState = syncState
        self.remoteAssetID = remoteAssetID
        self.cameraPose = cameraPose
        self.issueTag = issueTag
    }

    // MARK: Decodable — backward-compatible with pre-sync photo records
    //
    // COMPATIBILITY GLUE: decodeIfPresent with explicit defaults ensures that
    // TaggedPhoto records saved before the following fields were introduced still
    // decode cleanly:
    //   roomID        (was non-optional in the original model)
    //   kind          (added with EvidenceKind; defaults to .other)
    //   syncState     (added with offline-first sync; defaults to .localOnly)
    //   remoteAssetID (added with offline-first sync; defaults to nil)
    //   cameraPose    (added for spatial photo attachment; defaults to nil)
    //   issueTag      (added for issue-linked photos; defaults to nil)

    private enum CodingKeys: String, CodingKey {
        case id, roomID, taggedObjectID
        case filename, thumbnailPath
        case caption, kind, isKeyEvidence, capturedAt
        case syncState, remoteAssetID, cameraPose, issueTag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,     forKey: .id)
        // roomID was non-optional in the original model; decodeIfPresent keeps old files decodable.
        roomID        = try c.decodeIfPresent(UUID.self,    forKey: .roomID)
        taggedObjectID = try c.decodeIfPresent(UUID.self,   forKey: .taggedObjectID)
        filename      = try c.decode(String.self,           forKey: .filename)
        thumbnailPath = try c.decodeIfPresent(String.self,  forKey: .thumbnailPath)
        caption       = try c.decode(String.self,           forKey: .caption)
        // New field — default to .other for photos saved before EvidenceKind was introduced.
        kind          = try c.decodeIfPresent(EvidenceKind.self, forKey: .kind) ?? .other
        isKeyEvidence = try c.decode(Bool.self,             forKey: .isKeyEvidence)
        capturedAt    = try c.decode(Date.self,             forKey: .capturedAt)
        // Sync fields — default to .localOnly for photos saved before sync tracking was added.
        syncState     = try c.decodeIfPresent(PhotoSyncState.self, forKey: .syncState) ?? .localOnly
        remoteAssetID = try c.decodeIfPresent(String.self,         forKey: .remoteAssetID)
        cameraPose    = try c.decodeIfPresent(CameraPose.self,     forKey: .cameraPose)
        issueTag      = try c.decodeIfPresent(String.self,         forKey: .issueTag)
    }
}

// MARK: - PhotoSyncState

/// Sync state for an individual captured photo.
/// Photos default to `.localOnly` and transition through the upload pipeline.
enum PhotoSyncState: String, Codable, CaseIterable {
    case localOnly  = "local_only"
    case queued     = "queued"
    case uploading  = "uploading"
    case uploaded   = "uploaded"
    case failed     = "failed"
    case archived   = "archived"

    var displayName: String {
        switch self {
        case .localOnly:  return "Local Only"
        case .queued:     return "Queued for Atlas"
        case .uploading:  return "Uploading…"
        case .uploaded:   return "Uploaded"
        case .failed:     return "Upload Failed"
        case .archived:   return "Archived"
        }
    }

    var symbolName: String {
        switch self {
        case .localOnly:  return "iphone"
        case .queued:     return "clock.arrow.circlepath"
        case .uploading:  return "arrow.up.circle"
        case .uploaded:   return "checkmark.icloud.fill"
        case .failed:     return "exclamationmark.icloud.fill"
        case .archived:   return "archivebox"
        }
    }

    /// Whether this photo is eligible to be enqueued for upload.
    var canQueue: Bool {
        self == .localOnly || self == .failed
    }
}

// MARK: - CameraPose

/// Approximate camera position and orientation at photo capture time.
/// Expressed in ARKit world coordinates when available; nil otherwise.
struct CameraPose: Codable {

    /// Camera position in metres relative to session world origin.
    var positionX: Double
    var positionY: Double
    var positionZ: Double

    /// Camera facing direction as a unit vector (x, y, z).
    var directionX: Double
    var directionY: Double
    var directionZ: Double

    init(
        positionX: Double, positionY: Double, positionZ: Double,
        directionX: Double, directionY: Double, directionZ: Double
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.directionX = directionX
        self.directionY = directionY
        self.directionZ = directionZ
    }
}
