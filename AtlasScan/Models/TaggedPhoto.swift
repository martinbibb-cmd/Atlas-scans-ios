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

    // MARK: Init

    init(
        id: UUID = UUID(),
        roomID: UUID? = nil,
        taggedObjectID: UUID? = nil,
        filename: String,
        thumbnailPath: String? = nil,
        caption: String = "",
        kind: EvidenceKind = .other,
        isKeyEvidence: Bool = false
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
    }

    // MARK: Decodable — backward-compatible with pre-evidence-kind photo records

    private enum CodingKeys: String, CodingKey {
        case id, roomID, taggedObjectID
        case filename, thumbnailPath
        case caption, kind, isKeyEvidence, capturedAt
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
    }
}
