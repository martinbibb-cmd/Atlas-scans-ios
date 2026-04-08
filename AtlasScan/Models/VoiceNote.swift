import Foundation

// MARK: - VoiceNoteKind

/// The context category of a captured voice note.
enum VoiceNoteKind: String, Codable, CaseIterable {
    case observation    = "observation"
    case customerNote   = "customer_note"
    case constraint     = "constraint"
    case recommendation = "recommendation"
    case issue          = "issue"
    case other          = "other"

    var displayName: String {
        switch self {
        case .observation:    return "Observation"
        case .customerNote:   return "Customer Note"
        case .constraint:     return "Constraint"
        case .recommendation: return "Recommendation"
        case .issue:          return "Issue"
        case .other:          return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .observation:    return "eye"
        case .customerNote:   return "person.bubble"
        case .constraint:     return "exclamationmark.triangle"
        case .recommendation: return "lightbulb"
        case .issue:          return "xmark.circle"
        case .other:          return "mic"
        }
    }
}

// MARK: - TranscriptStatus

/// Whether a voice note has been transcribed.
enum TranscriptStatus: String, Codable, CaseIterable {
    case none       = "none"
    case pending    = "pending"
    case completed  = "completed"
    case failed     = "failed"

    var displayName: String {
        switch self {
        case .none:      return "No Transcript"
        case .pending:   return "Transcription Pending"
        case .completed: return "Transcribed"
        case .failed:    return "Transcription Failed"
        }
    }
}

// MARK: - VoiceNoteSyncState

/// Sync state for an individual captured voice note.
/// Voice notes default to `.localOnly` and transition through the upload pipeline.
enum VoiceNoteSyncState: String, Codable, CaseIterable {
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

    /// Whether this voice note is eligible to be enqueued for upload.
    var canQueue: Bool {
        self == .localOnly || self == .failed
    }
}

// MARK: - VoiceNote

/// An audio voice note recorded by an engineer and attached to a session, room, or object.
struct VoiceNote: Identifiable, Codable {

    var id: UUID = UUID()

    /// Owning room identifier. Nil for session-level notes.
    var linkedRoomID: UUID?

    /// Optional associated tagged object.
    var linkedObjectID: UUID?

    /// Filename stored in local app Documents/VoiceNotes/ directory.
    var localFilename: String

    /// Duration of the recording in seconds.
    var duration: TimeInterval

    /// Optional free-form caption added by the engineer.
    var caption: String

    /// Context category of the note.
    var kind: VoiceNoteKind

    /// Whether transcription has been requested or completed.
    var transcriptStatus: TranscriptStatus

    /// Optional transcript text, populated after server-side transcription.
    var transcript: String?

    /// Per-note Atlas sync state.
    var syncState: VoiceNoteSyncState

    /// Remote asset identifier assigned by Atlas after a successful upload.
    var remoteAssetID: String?

    var createdAt: Date

    // MARK: Init

    init(
        id: UUID = UUID(),
        linkedRoomID: UUID? = nil,
        linkedObjectID: UUID? = nil,
        localFilename: String,
        duration: TimeInterval = 0,
        caption: String = "",
        kind: VoiceNoteKind = .other,
        transcriptStatus: TranscriptStatus = .none,
        transcript: String? = nil,
        syncState: VoiceNoteSyncState = .localOnly,
        remoteAssetID: String? = nil
    ) {
        self.id = id
        self.linkedRoomID = linkedRoomID
        self.linkedObjectID = linkedObjectID
        self.localFilename = localFilename
        self.duration = duration
        self.caption = caption
        self.kind = kind
        self.transcriptStatus = transcriptStatus
        self.transcript = transcript
        self.syncState = syncState
        self.remoteAssetID = remoteAssetID
        self.createdAt = Date()
    }

    // MARK: Decodable — backward-compatible

    private enum CodingKeys: String, CodingKey {
        case id, linkedRoomID, linkedObjectID
        case localFilename, duration
        case caption, kind
        case transcriptStatus, transcript
        case syncState, remoteAssetID
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,          forKey: .id)
        linkedRoomID     = try c.decodeIfPresent(UUID.self, forKey: .linkedRoomID)
        linkedObjectID   = try c.decodeIfPresent(UUID.self, forKey: .linkedObjectID)
        localFilename    = try c.decode(String.self,        forKey: .localFilename)
        duration         = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        caption          = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        kind             = try c.decodeIfPresent(VoiceNoteKind.self, forKey: .kind) ?? .other
        transcriptStatus = try c.decodeIfPresent(TranscriptStatus.self, forKey: .transcriptStatus) ?? .none
        transcript       = try c.decodeIfPresent(String.self, forKey: .transcript)
        syncState        = try c.decodeIfPresent(VoiceNoteSyncState.self, forKey: .syncState) ?? .localOnly
        remoteAssetID    = try c.decodeIfPresent(String.self, forKey: .remoteAssetID)
        createdAt        = try c.decode(Date.self,          forKey: .createdAt)
    }
}
