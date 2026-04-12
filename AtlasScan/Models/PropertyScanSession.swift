import Foundation
import AtlasContracts

// MARK: - PropertyScanSession
//
// NEW CANONICAL CAPTURE STATE — replaces ScanJob as the in-app top-level entity.
//
// One PropertyScanSession = one property = one whole-house survey pass.
// Rooms, tagged objects, photos, and validation issues are all children of
// this single shared context and coordinate system.
//
// Room / session relationship:
//   • Rooms are subordinate capture units inside one property session.
//   • Objects and photos can exist at room level OR at session level (floating).
//   • allTaggedObjects and allPhotos aggregate across both levels.
//   • All rooms in a session share one spatial context (adjacencies + placements).
//
// COMPATIBILITY GLUE — what keeps the existing export pipeline intact:
//   • toScanJob() converts this session to a ScanJob for the export contract.
//   • The ScanJob export pipeline (ExportPackageBuilder etc.) is UNCHANGED.
//   • Backward-compatible init(from:) decoder handles session files written
//     before optional fields (syncState, roomPlacements, etc.) were introduced.

struct PropertyScanSession: Identifiable, Codable, Hashable {

    // MARK: - Hashable
    // Implemented explicitly to avoid requiring all child types to be Hashable.
    // Identity-based: two sessions with the same id are considered equal.
    static func == (lhs: PropertyScanSession, rhs: PropertyScanSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: UUID = UUID()

    // MARK: Job identity

    var jobReference: String

    var propertyAddress: String

    var engineerName: String

    /// Optional link to an Atlas job / recommendation ID.
    var atlasJobID: String?

    // MARK: Lifecycle state

    /// Capture / field state of the session.
    var scanState: ScanSessionState

    /// Review / sign-off state of the session.
    var reviewState: ReviewState

    /// Atlas sync state for the session as a whole.
    var syncState: SessionSyncState

    /// Handoff state — tracks whether the canonical payload has been sent to Atlas Mind.
    var handoffState: HandoffState

    // MARK: Children

    /// Rooms discovered or manually added during the session.
    /// Rooms are children of the session and can be refined after capture.
    var rooms: [ScannedRoom]

    /// Engineer-defined connections between rooms (doors, archways, etc.).
    var roomAdjacencies: [RoomAdjacency]

    /// Optional layout overrides for the property plan canvas.
    var roomPlacements: [RoomPlacementOverride]

    /// Objects tagged into the shared session model.
    /// An object is attached to a room when `roomID` is set, but room attachment is
    /// not required — objects can float at session level for unclassified items.
    var taggedObjects: [TaggedObject]

    /// Photos captured during the session.
    /// Each photo carries its own syncState for fine-grained upload control.
    var photos: [TaggedPhoto]

    /// Voice notes recorded during the session.
    /// Notes at session level are not assigned to a specific room.
    var voiceNotes: [VoiceNote]

    /// Structured facts extracted from voice notes during this session.
    /// Extraction is conservative — voice evidence is always preserved separately in `voiceNotes`.
    var extractedFacts: [ExtractedSessionFact]

    /// Validation issues collected during review or export validation.
    var issues: [ValidationIssue]

    // MARK: 3D evidence

    /// Indoor room-scan evidence records (RoomPlan / LiDAR captures).
    /// Each entry is evidence only — no maths may be derived from the asset.
    var roomScanEvidence: [RoomScanEvidence]

    /// Outdoor flue-clearance AR scene records.
    /// Compliance runs from `measurements` and `nearbyFeatures`, not raw geometry.
    var externalClearanceScenes: [ExternalClearanceScene]

    // MARK: Timestamps

    var createdAt: Date
    var updatedAt: Date

    // MARK: Init

    init(
        id: UUID = UUID(),
        jobReference: String = "",
        propertyAddress: String,
        engineerName: String = "",
        atlasJobID: String? = nil,
        scanState: ScanSessionState = .notStarted,
        reviewState: ReviewState = .pending,
        syncState: SessionSyncState = .localOnly,
        handoffState: HandoffState = .notSent,
        rooms: [ScannedRoom] = [],
        roomAdjacencies: [RoomAdjacency] = [],
        roomPlacements: [RoomPlacementOverride] = [],
        taggedObjects: [TaggedObject] = [],
        photos: [TaggedPhoto] = [],
        voiceNotes: [VoiceNote] = [],
        extractedFacts: [ExtractedSessionFact] = [],
        issues: [ValidationIssue] = [],
        roomScanEvidence: [RoomScanEvidence] = [],
        externalClearanceScenes: [ExternalClearanceScene] = []
    ) {
        self.id = id
        if jobReference.isEmpty {
            let stamp = Int(Date().timeIntervalSince1970)
            self.jobReference = "JOB-\(stamp)"
        } else {
            self.jobReference = jobReference
        }
        self.propertyAddress = propertyAddress
        self.engineerName = engineerName
        self.atlasJobID = atlasJobID
        self.scanState = scanState
        self.reviewState = reviewState
        self.syncState = syncState
        self.handoffState = handoffState
        self.rooms = rooms
        self.roomAdjacencies = roomAdjacencies
        self.roomPlacements = roomPlacements
        self.taggedObjects = taggedObjects
        self.photos = photos
        self.voiceNotes = voiceNotes
        self.extractedFacts = extractedFacts
        self.issues = issues
        self.roomScanEvidence = roomScanEvidence
        self.externalClearanceScenes = externalClearanceScenes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Decodable — backward-compatible with earlier session files

    private enum CodingKeys: String, CodingKey {
        case id, jobReference, propertyAddress, engineerName, atlasJobID
        case scanState, reviewState, syncState, handoffState
        case rooms, roomAdjacencies, roomPlacements
        case taggedObjects, photos, voiceNotes, extractedFacts, issues
        case roomScanEvidence, externalClearanceScenes
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,           forKey: .id)
        jobReference     = try c.decode(String.self,         forKey: .jobReference)
        propertyAddress  = try c.decode(String.self,         forKey: .propertyAddress)
        engineerName     = try c.decode(String.self,         forKey: .engineerName)
        atlasJobID       = try c.decodeIfPresent(String.self, forKey: .atlasJobID)
        scanState        = try c.decodeIfPresent(ScanSessionState.self,  forKey: .scanState)   ?? .notStarted
        reviewState      = try c.decodeIfPresent(ReviewState.self,       forKey: .reviewState)  ?? .pending
        syncState        = try c.decodeIfPresent(SessionSyncState.self,  forKey: .syncState)    ?? .localOnly
        handoffState     = try c.decodeIfPresent(HandoffState.self,      forKey: .handoffState) ?? .notSent
        rooms            = try c.decodeIfPresent([ScannedRoom].self,          forKey: .rooms)            ?? []
        roomAdjacencies  = try c.decodeIfPresent([RoomAdjacency].self,        forKey: .roomAdjacencies)  ?? []
        roomPlacements   = try c.decodeIfPresent([RoomPlacementOverride].self, forKey: .roomPlacements)  ?? []
        taggedObjects    = try c.decodeIfPresent([TaggedObject].self,          forKey: .taggedObjects)    ?? []
        photos           = try c.decodeIfPresent([TaggedPhoto].self,           forKey: .photos)           ?? []
        voiceNotes       = try c.decodeIfPresent([VoiceNote].self,             forKey: .voiceNotes)       ?? []
        extractedFacts   = try c.decodeIfPresent([ExtractedSessionFact].self,  forKey: .extractedFacts)   ?? []
        issues           = try c.decodeIfPresent([ValidationIssue].self,       forKey: .issues)           ?? []
        roomScanEvidence        = try c.decodeIfPresent([RoomScanEvidence].self,        forKey: .roomScanEvidence)        ?? []
        externalClearanceScenes = try c.decodeIfPresent([ExternalClearanceScene].self,  forKey: .externalClearanceScenes) ?? []
        createdAt        = try c.decode(Date.self,           forKey: .createdAt)
        updatedAt        = try c.decode(Date.self,           forKey: .updatedAt)
    }

    // MARK: Helpers

    mutating func touch() {
        updatedAt = Date()
    }

    /// All tagged objects across session-level list and all rooms.
    var allTaggedObjects: [TaggedObject] {
        taggedObjects + rooms.flatMap(\.taggedObjects)
    }

    /// All photos across session-level list and all rooms.
    var allPhotos: [TaggedPhoto] {
        photos + rooms.flatMap(\.photos)
    }

    /// All voice notes across session-level list and all rooms.
    var allVoiceNotes: [VoiceNote] {
        voiceNotes + rooms.flatMap(\.voiceNotes)
    }

    var totalTaggedObjects: Int { allTaggedObjects.count }

    var totalPhotos: Int { allPhotos.count }

    var totalVoiceNotes: Int { allVoiceNotes.count }

    var totalReviewedRooms: Int { rooms.filter(\.isReviewed).count }

    var isReadyToExport: Bool {
        !rooms.isEmpty && rooms.allSatisfy(\.isReviewed)
    }

    var hasBlockingIssues: Bool {
        issues.contains(where: { $0.severity == .blocking })
    }

    /// A filesystem-safe version of `jobReference`.
    var safeFileNameReference: String {
        jobReference
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }

    // MARK: Room helpers

    mutating func addRoom(_ room: ScannedRoom) {
        rooms.append(room)
        touch()
    }

    mutating func removeRoom(id: UUID) {
        rooms.removeAll { $0.id == id }
        roomAdjacencies.removeAll { $0.fromRoomID == id || $0.toRoomID == id }
        roomPlacements.removeAll { $0.id == id }
        // Remove photos explicitly linked to the deleted room.
        photos.removeAll { $0.roomID == id }
        // Remove session-level objects linked to the deleted room.
        taggedObjects.removeAll { $0.roomID == id }
        touch()
    }

    mutating func updateRoom(_ updated: ScannedRoom) {
        guard let index = rooms.firstIndex(where: { $0.id == updated.id }) else { return }
        rooms[index] = updated
        touch()
    }

    // MARK: Session-level tagged object helpers

    mutating func addTaggedObject(_ object: TaggedObject) {
        taggedObjects.append(object)
        touch()
    }

    mutating func removeTaggedObject(id: UUID) {
        taggedObjects.removeAll { $0.id == id }
        photos.removeAll { $0.taggedObjectID == id }
        touch()
    }

    mutating func updateTaggedObject(_ updated: TaggedObject) {
        guard let index = taggedObjects.firstIndex(where: { $0.id == updated.id }) else { return }
        taggedObjects[index] = updated
        touch()
    }

    // MARK: Session-level photo helpers

    mutating func addPhoto(_ photo: TaggedPhoto) {
        photos.append(photo)
        touch()
    }

    mutating func removePhoto(id: UUID) {
        photos.removeAll { $0.id == id }
        touch()
    }

    // MARK: Session-level voice note helpers

    mutating func addVoiceNote(_ note: VoiceNote) {
        voiceNotes.append(note)
        touch()
    }

    mutating func removeVoiceNote(id: UUID) {
        voiceNotes.removeAll { $0.id == id }
        touch()
    }

    mutating func updateVoiceNote(_ updated: VoiceNote) {
        guard let index = voiceNotes.firstIndex(where: { $0.id == updated.id }) else { return }
        voiceNotes[index] = updated
        touch()
    }

    // MARK: Extracted fact helpers

    mutating func addExtractedFact(_ fact: ExtractedSessionFact) {
        extractedFacts.append(fact)
        touch()
    }

    mutating func removeExtractedFact(id: UUID) {
        extractedFacts.removeAll { $0.id == id }
        touch()
    }

    mutating func replaceExtractedFacts(_ facts: [ExtractedSessionFact]) {
        extractedFacts = facts
        touch()
    }

    /// Computed knowledge coverage summary derived from `extractedFacts`.
    var knowledgeSummary: SessionKnowledgeSummary {
        SessionKnowledgeExtractor.knowledgeSummary(from: extractedFacts)
    }

    /// Re-runs extraction from all current voice notes and replaces existing extracted facts.
    ///
    /// Call this after adding or editing voice notes to keep the structured knowledge
    /// layer in sync with captured evidence.
    mutating func refreshExtractedFacts() {
        extractedFacts = SessionKnowledgeExtractor.extractFacts(from: allVoiceNotes)
        touch()
    }

    // MARK: Adjacency helpers

    mutating func addAdjacency(_ adjacency: RoomAdjacency) {
        roomAdjacencies.append(adjacency)
        touch()
    }

    mutating func removeAdjacency(id: UUID) {
        roomAdjacencies.removeAll { $0.id == id }
        touch()
    }

    mutating func updateAdjacency(_ updated: RoomAdjacency) {
        guard let index = roomAdjacencies.firstIndex(where: { $0.id == updated.id }) else { return }
        roomAdjacencies[index] = updated
        touch()
    }

    func adjacencies(for roomID: UUID) -> [RoomAdjacency] {
        roomAdjacencies.filter { $0.fromRoomID == roomID || $0.toRoomID == roomID }
    }

    // MARK: Room placement helpers

    mutating func setRoomPlacement(_ placement: RoomPlacementOverride) {
        if let index = roomPlacements.firstIndex(where: { $0.id == placement.id }) {
            roomPlacements[index] = placement
        } else {
            roomPlacements.append(placement)
        }
        touch()
    }

    func roomPlacement(for roomID: UUID) -> RoomPlacementOverride? {
        roomPlacements.first { $0.id == roomID }
    }

    // MARK: Issue helpers

    mutating func addIssue(_ issue: ValidationIssue) {
        issues.append(issue)
        touch()
    }

    mutating func clearIssues() {
        issues = []
        touch()
    }

    // MARK: Room scan evidence helpers

    mutating func addRoomScanEvidence(_ evidence: RoomScanEvidence) {
        roomScanEvidence.append(evidence)
        touch()
    }

    mutating func removeRoomScanEvidence(id: UUID) {
        roomScanEvidence.removeAll { $0.id == id }
        touch()
    }

    mutating func updateRoomScanEvidence(_ updated: RoomScanEvidence) {
        guard let index = roomScanEvidence.firstIndex(where: { $0.id == updated.id }) else { return }
        roomScanEvidence[index] = updated
        touch()
    }

    /// Returns all room scan evidence linked to a specific room.
    func roomScanEvidence(for roomID: UUID) -> [RoomScanEvidence] {
        roomScanEvidence.filter { $0.linkedRoomIDs.contains(roomID) }
    }

    // MARK: External clearance scene helpers

    mutating func addExternalClearanceScene(_ scene: ExternalClearanceScene) {
        externalClearanceScenes.append(scene)
        touch()
    }

    mutating func removeExternalClearanceScene(id: UUID) {
        externalClearanceScenes.removeAll { $0.id == id }
        touch()
    }

    mutating func updateExternalClearanceScene(_ updated: ExternalClearanceScene) {
        guard let index = externalClearanceScenes.firstIndex(where: { $0.id == updated.id }) else { return }
        externalClearanceScenes[index] = updated
        touch()
    }

    // MARK: Conversion — compatibility glue

    /// Converts this session to a legacy `ScanJob` for export and contract mapping.
    ///
    /// This is the compatibility bridge that keeps the existing export pipeline
    /// (ExportPackageBuilder → ScanBundleV1) unchanged. The export contract
    /// consumes `ScanJob`; callers do not need to know about `PropertyScanSession`.
    ///
    /// Session-level objects and photos are promoted to job-level equivalents.
    func toScanJob() -> ScanJob {
        var job = ScanJob(
            id: id,
            jobReference: jobReference,
            propertyAddress: propertyAddress,
            engineerName: engineerName,
            atlasJobID: atlasJobID,
            rooms: rooms,
            roomAdjacencies: roomAdjacencies,
            roomPlacements: roomPlacements,
            photos: photos
        )
        // Preserve the session's updatedAt timestamp for accurate sort ordering.
        job.updatedAt = updatedAt
        return job
    }
}

// MARK: - ScanSessionState

/// Capture / field lifecycle state of a PropertyScanSession.
enum ScanSessionState: String, Codable, CaseIterable {
    case notStarted  = "not_started"
    case inProgress  = "in_progress"
    case paused      = "paused"
    case completed   = "completed"
    case incomplete  = "incomplete"

    var displayName: String {
        switch self {
        case .notStarted:  return "Not Started"
        case .inProgress:  return "In Progress"
        case .paused:      return "Paused"
        case .completed:   return "Completed"
        case .incomplete:  return "Incomplete"
        }
    }

    var symbolName: String {
        switch self {
        case .notStarted:  return "doc"
        case .inProgress:  return "camera.viewfinder"
        case .paused:      return "pause.circle"
        case .completed:   return "checkmark.circle"
        case .incomplete:  return "exclamationmark.triangle"
        }
    }
}

// MARK: - ReviewState

/// Engineer review / sign-off state.
enum ReviewState: String, Codable, CaseIterable {
    case pending        = "pending"
    case inReview       = "in_review"
    case reviewed       = "reviewed"
    case needsAttention = "needs_attention"
    case blocked        = "blocked"

    var displayName: String {
        switch self {
        case .pending:        return "Pending"
        case .inReview:       return "In Review"
        case .reviewed:       return "Reviewed"
        case .needsAttention: return "Needs Attention"
        case .blocked:        return "Blocked / Incomplete"
        }
    }

    var symbolName: String {
        switch self {
        case .pending:        return "clock"
        case .inReview:       return "magnifyingglass"
        case .reviewed:       return "checkmark.seal.fill"
        case .needsAttention: return "exclamationmark.circle.fill"
        case .blocked:        return "xmark.circle.fill"
        }
    }
}

// MARK: - SessionSyncState

/// Atlas sync state for a session or individual artifact.
enum SessionSyncState: String, Codable, CaseIterable {
    case localOnly      = "local_only"
    case queued         = "queued"
    case uploading      = "uploading"
    case uploaded       = "uploaded"
    case failed         = "failed"
    case archived       = "archived"

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
}

// MARK: - HandoffState

/// Tracks whether the canonical AtlasPropertyV1 payload has been sent to Atlas Mind.
enum HandoffState: String, Codable, CaseIterable {
    case notSent   = "not_sent"
    case sent      = "sent"
    case exported  = "exported"

    var displayName: String {
        switch self {
        case .notSent:   return "Not Sent"
        case .sent:      return "Sent to Atlas Mind"
        case .exported:  return "Exported"
        }
    }

    var symbolName: String {
        switch self {
        case .notSent:   return "paperplane"
        case .sent:      return "paperplane.fill"
        case .exported:  return "checkmark.circle.fill"
        }
    }
}

// MARK: - HandoffReadiness

/// Computed readiness of a session for Atlas Mind handoff.
///
/// A session is ready when the minimum set of essentials is present:
/// at least one room, at least one tagged object, and at least one photo.
/// Any missing essentials are surfaced as human-readable reasons.
struct HandoffReadiness {
    /// True when all essentials are present and the session can be sent cleanly.
    let isReady: Bool
    /// Human-readable descriptions of missing essentials (empty when `isReady` is true).
    let missingEssentials: [String]
}

extension PropertyScanSession {

    // MARK: - Handoff readiness

    /// Computes the current handoff readiness of this session.
    var handoffReadiness: HandoffReadiness {
        var missing: [String] = []
        if rooms.isEmpty {
            missing.append("No rooms captured")
        }
        if totalTaggedObjects == 0 {
            missing.append("No objects tagged")
        }
        if totalPhotos == 0 {
            missing.append("No photos taken")
        }
        return HandoffReadiness(isReady: missing.isEmpty, missingEssentials: missing)
    }
}

/// Unified survey session composed from multiple concurrent capture streams.
///
/// Design goal:
/// Keep observational, spatial, asset, and services data logically separate,
/// but in one shared session envelope and timeline.
struct AtlasSurveySessionV2: Codable, Identifiable, Equatable {
    var id: UUID
    var spatial: AtlasSpatialStreamV1?
    var observations: [ObservationCaptureEvent]
    var assets: [AssetCaptureEvent]
    var services: ServiceInputsStreamV1
    var startedAt: Date
    var updatedAt: Date
}

// MARK: - Stream payloads

struct AtlasSpatialStreamV1: Codable, Equatable {
    /// Number of rooms currently in the progressively refined spatial model.
    var roomCount: Int

    /// Whether at least one room has captured scan geometry.
    var hasCapturedGeometry: Bool

    /// Number of rooms still operating in manual/no-scan mode.
    var manualRoomCount: Int
}

struct ObservationCaptureEvent: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case voiceNote
        case photo
    }

    var id: UUID
    var kind: Kind
    var roomID: UUID?
    var taggedObjectID: UUID?
    var position: WorldAnchor3D?
    var timestamp: Date
}

struct AssetCaptureEvent: Codable, Equatable, Identifiable {
    var id: UUID
    var taggedObjectID: UUID
    var category: ServiceObjectCategory
    var roomID: UUID?
    var position: WorldAnchor3D?
    var timestamp: Date
}

struct ServiceInputsStreamV1: Codable, Equatable {
    var pressureBar: Double?
    var flowTemperatureC: Double?
    var returnTemperatureC: Double?
    var primaryPipeDescription: String?
    var notes: [String]

    static let empty = ServiceInputsStreamV1(
        pressureBar: nil,
        flowTemperatureC: nil,
        returnTemperatureC: nil,
        primaryPipeDescription: nil,
        notes: []
    )
}

// MARK: - AtlasPropertyV1 projection

extension PropertyScanSession {

    /// Projects this session into a canonical `AtlasPropertyV1` for Atlas Mind handoff.
    ///
    /// This is the primary export path introduced in PR 5.  The legacy
    /// `toScanJob()` / `ExportPackageBuilder` path is preserved as a fallback.
    ///
    /// - Parameter handoffDate: Timestamp to record as `handoffAt`. Defaults to now.
    /// - Returns: A fully populated `AtlasPropertyV1` ready for sharing or upload.
    func toAtlasPropertyV1(handoffDate: Date = Date()) -> AtlasPropertyV1 {
        let iso: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        // Build room projections
        let roomPayloads: [AtlasPropertyRoomV1] = rooms.map { room in
            let objectPayloads = room.taggedObjects.map { obj in
                atlasObject(from: obj, roomID: room.id)
            }
            let photoCount = room.photos.count +
                room.taggedObjects.reduce(0) { $0 + $1.linkedPhotoIDs.count }
            let voiceNoteCount = room.voiceNotes.count +
                room.taggedObjects.reduce(0) { $0 + $1.linkedVoiceNoteIDs.count }

            return AtlasPropertyRoomV1(
                id: room.id.uuidString,
                name: room.name,
                floorIndex: room.floor,
                geometryCaptured: room.geometryCaptured,
                areaM2: room.areaSquareMetres,
                heightM: room.ceilingHeightMetres,
                isReviewed: room.isReviewed,
                objects: objectPayloads,
                photoCount: photoCount,
                voiceNoteCount: voiceNoteCount
            )
        }

        // Session-level (floating) objects — not assigned to any room
        let sessionObjectPayloads = taggedObjects.map { atlasObject(from: $0, roomID: nil) }

        // Adjacencies
        let adjacencyPayloads: [AtlasPropertyAdjacencyV1] = roomAdjacencies.map { adj in
            AtlasPropertyAdjacencyV1(
                id: adj.id.uuidString,
                fromRoomID: adj.fromRoomID.uuidString,
                toRoomID: adj.toRoomID.uuidString,
                kind: adj.kind.rawValue,
                isConfirmed: adj.isConfirmed,
                openingID: adj.openingID?.uuidString,
                notes: adj.notes
            )
        }

        // Evidence summary
        let evidenceSummary = AtlasEvidenceSummaryV1(
            totalPhotos: totalPhotos,
            totalVoiceNotes: totalVoiceNotes,
            sessionPhotoCount: photos.count,
            sessionVoiceNoteCount: voiceNotes.count
        )

        // Session knowledge — project medium/high-confidence extracted facts only.
        let projectedFacts: [AtlasExtractedFactV1] = extractedFacts
            .filter { $0.confidence >= .medium }
            .map { fact in
                AtlasExtractedFactV1(
                    id: fact.id.uuidString,
                    category: fact.category.rawValue,
                    value: fact.value,
                    confidence: fact.confidence.rawValue,
                    sourceNoteID: fact.sourceNoteID?.uuidString,
                    roomID: fact.roomID?.uuidString,
                    objectID: fact.objectID?.uuidString,
                    createdAt: iso.string(from: fact.createdAt)
                )
            }
        let sessionKnowledge: AtlasSessionKnowledgeV1? = projectedFacts.isEmpty
            ? nil
            : AtlasSessionKnowledgeV1(extractedFacts: projectedFacts)

        return AtlasPropertyV1(
            schemaVersion: currentAtlasPropertyVersion,
            propertyID: id.uuidString,
            jobReference: jobReference,
            propertyAddress: propertyAddress,
            engineerName: engineerName,
            atlasJobID: atlasJobID,
            capturedAt: iso.string(from: createdAt),
            handoffAt: iso.string(from: handoffDate),
            scanState: scanState.rawValue,
            reviewState: reviewState.rawValue,
            rooms: roomPayloads,
            adjacencies: adjacencyPayloads,
            sessionObjects: sessionObjectPayloads,
            evidenceSummary: evidenceSummary,
            sessionKnowledge: sessionKnowledge,
            spatialEvidence3d: roomScanEvidence.isEmpty
                ? nil
                : roomScanEvidence.map { $0.toSpatialEvidence3D() },
            externalClearanceScenes: externalClearanceScenes.isEmpty
                ? nil
                : externalClearanceScenes.map { $0.toExternalClearanceSceneV1() }
        )
    }

    /// Maps a `TaggedObject` to `AtlasPropertyObjectV1`.
    ///
    /// - Parameters:
    ///   - obj: The tagged object to map.
    ///   - roomID: The UUID of the room this object belongs to, or `nil` for
    ///             session-level objects that are not assigned to any room.
    private func atlasObject(from obj: TaggedObject, roomID: UUID?) -> AtlasPropertyObjectV1 {
        let anchor: AtlasWorldAnchorV1? = obj.worldAnchor.map { wa in
            AtlasWorldAnchorV1(
                x: wa.x,
                y: wa.y,
                z: wa.z,
                screenX: wa.screenX,
                screenY: wa.screenY,
                anchorConfidence: wa.anchorConfidence.rawValue
            )
        }
        return AtlasPropertyObjectV1(
            id: obj.id.uuidString,
            category: obj.category.rawValue,
            label: obj.displayLabel,
            roomID: roomID?.uuidString,
            placementMode: obj.placementMode.rawValue,
            confidence: obj.confidence.rawValue,
            photoCount: obj.linkedPhotoIDs.count,
            voiceNoteCount: obj.linkedVoiceNoteIDs.count,
            quickFields: obj.quickFieldValues,
            worldAnchor: anchor
        )
    }
}

// MARK: - PropertyScanSession projection

extension PropertyScanSession {
    /// Projects legacy `PropertyScanSession` data into a unified multi-stream model.
    ///
    /// This keeps data-layer separation while presenting capture as one composed session.
    var surveySessionV2: AtlasSurveySessionV2 {
        let roomObjects = rooms.flatMap(\.taggedObjects)
        let allObjects = taggedObjects + roomObjects

        let roomVoiceNotes = rooms.flatMap(\.voiceNotes)
        let allVoiceNotes = voiceNotes + roomVoiceNotes

        let roomPhotos = rooms.flatMap(\.photos)
        let allPhotos = photos + roomPhotos

        let observationEventsFromVoice: [ObservationCaptureEvent] = allVoiceNotes.map { note in
            ObservationCaptureEvent(
                id: note.id,
                kind: .voiceNote,
                roomID: note.linkedRoomID,
                taggedObjectID: note.linkedObjectID,
                position: allObjects.first(where: { $0.id == note.linkedObjectID })?.worldAnchor,
                timestamp: note.createdAt
            )
        }

        let observationEventsFromPhotos: [ObservationCaptureEvent] = allPhotos.map { photo in
            ObservationCaptureEvent(
                id: photo.id,
                kind: .photo,
                roomID: photo.roomID,
                taggedObjectID: photo.taggedObjectID,
                position: allObjects.first(where: { $0.id == photo.taggedObjectID })?.worldAnchor,
                timestamp: photo.createdAt
            )
        }

        let assetEvents: [AssetCaptureEvent] = allObjects.map { obj in
            AssetCaptureEvent(
                id: obj.id,
                taggedObjectID: obj.id,
                category: obj.category,
                roomID: obj.roomID,
                position: obj.worldAnchor,
                timestamp: obj.createdAt
            )
        }

        let spatialStream = AtlasSpatialStreamV1(
            roomCount: rooms.count,
            hasCapturedGeometry: rooms.contains(where: \.geometryCaptured),
            manualRoomCount: rooms.filter { !$0.geometryCaptured }.count
        )

        return AtlasSurveySessionV2(
            id: id,
            spatial: rooms.isEmpty ? nil : spatialStream,
            observations: (observationEventsFromVoice + observationEventsFromPhotos)
                .sorted(by: { $0.timestamp < $1.timestamp }),
            assets: assetEvents.sorted(by: { $0.timestamp < $1.timestamp }),
            services: .empty,
            startedAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
