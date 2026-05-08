import Foundation

// MARK: - SessionCaptureV2
//
// Capture-only handoff produced by Atlas Scan and consumed by Atlas Mind.
//
// Design goals:
//   • One SessionCaptureV2 = one complete single-visit capture session.
//   • Carries raw capture artefacts only — no derived outputs, no recommendations.
//   • Raw audio is excluded; transcript text is the only voice evidence exported.
//   • 3-D scan assets are referenced by path, not inlined.
//   • Atlas Mind owns all interpretation downstream of this boundary.
//
// Architecture rules:
//   • Scan exports observation.
//   • Mind owns editable semantic truth.
//   • Patches are the only edit path after export.
//   • 3D is demoted to projection — assets are references, not geometric truth.
//   • Engine outputs must not appear in this payload.

// MARK: - Version constants

/// Supported versions for SessionCaptureV2 payloads.
public let supportedSessionCaptureVersions: [String] = ["2.0"]

/// The schema version emitted by this client.
public let currentSessionCaptureVersion: String = "2.0"

// MARK: - Top-level envelope

/// Capture-only handoff from Atlas Scan to Atlas Mind.
///
/// Produced by `CaptureSessionExporter` and consumed by Atlas Mind when
/// importing a completed single-visit capture session.
public struct SessionCaptureV2: Codable, Sendable {

    // MARK: Schema identity

    /// Schema version; must be in `supportedSessionCaptureVersions`.
    public let schemaVersion: String

    /// UUID of the originating capture session.
    public let sessionId: String

    /// Engineer-assigned visit / job reference (e.g. "JOB-1712345678").
    public let visitReference: String

    /// Cross-system appointment key from Atlas Recommendations.
    ///
    /// Maps to ``AppointmentV1/appointmentId``.  Atlas Recommendations uses this
    /// field to associate the submitted capture with the appointment that triggered
    /// the visit.  May be nil for sessions started manually without an appointment.
    public let appointmentId: String?

    /// Optional property address for the visit.
    public let propertyAddress: String?

    /// Optional customer name for the visit.
    public let customerName: String?

    // MARK: Provenance

    /// ISO-8601 timestamp of when the session was first created.
    public let capturedAt: String

    /// ISO-8601 timestamp of when this payload was exported.
    public let exportedAt: String

    /// Device model string (e.g. "iPhone 15 Pro").
    public let deviceModel: String

    // MARK: Captured artefacts

    /// Indoor room scans captured during the visit. Evidence only.
    public let roomScans: [CapturedRoomScanV2]

    /// Evidence photos captured during the visit.
    public let photos: [CapturedPhotoV2]

    /// Voice note transcripts captured during the visit.
    /// Raw audio is NOT included; transcript text only.
    public let voiceNotes: [CapturedVoiceNoteV2]

    /// Typed object and pin placements made during the visit.
    public let objectPins: [CapturedObjectPinV2]

    /// Floor plan snapshots captured during the visit.
    public let floorPlanSnapshots: [CapturedFloorPlanSnapshotV2]

    // MARK: Fabric + hazard evidence (optional)

    /// Floor-plan fabric evidence (boundaries and openings) captured during the visit.
    ///
    /// Nil when no fabric data was recorded.  Not required for session validity —
    /// existing sessions without fabric evidence remain valid.
    public let floorPlanFabric: FloorPlanFabricCaptureV1?

    /// Site hazard observations recorded by the engineer during the visit.
    ///
    /// Nil or empty when no hazards were observed.  Not required for session validity.
    public let hazardObservations: [HazardObservationCaptureV1]?

    /// Candidate quote-planner location anchors recorded during the visit.
    ///
    /// Nil when no quote-planner anchors were captured.  Not required for session
    /// validity — existing sessions without this field remain valid.
    /// Atlas Mind consumes these anchors for quote planning; Scan is capture-only.
    public let quotePlannerEvidence: QuotePlannerEvidenceV1?

    /// Exterior area scans captured during the visit.
    ///
    /// Each record captures evidence around a specific exterior area (e.g. the
    /// flue terminal exit).  Nil or empty when no external scans were recorded.
    /// Not required for session validity — existing sessions remain valid.
    /// Atlas Mind evaluates flue clearance rules downstream; Scan is evidence-only.
    public let externalAreaScans: [ExternalAreaScanV1]?

    // MARK: Quality signals

    /// QA flags raised during capture. Capture-layer warnings only.
    public let qaFlags: [ScanQAFlag]

    // MARK: Init

    public init(
        schemaVersion: String,
        sessionId: String,
        visitReference: String,
        appointmentId: String? = nil,
        propertyAddress: String? = nil,
        customerName: String? = nil,
        capturedAt: String,
        exportedAt: String,
        deviceModel: String,
        roomScans: [CapturedRoomScanV2],
        photos: [CapturedPhotoV2],
        voiceNotes: [CapturedVoiceNoteV2],
        objectPins: [CapturedObjectPinV2],
        floorPlanSnapshots: [CapturedFloorPlanSnapshotV2],
        floorPlanFabric: FloorPlanFabricCaptureV1? = nil,
        hazardObservations: [HazardObservationCaptureV1]? = nil,
        quotePlannerEvidence: QuotePlannerEvidenceV1? = nil,
        externalAreaScans: [ExternalAreaScanV1]? = nil,
        qaFlags: [ScanQAFlag]
    ) {
        self.schemaVersion = schemaVersion
        self.sessionId = sessionId
        self.visitReference = visitReference
        self.appointmentId = appointmentId
        self.propertyAddress = propertyAddress
        self.customerName = customerName
        self.capturedAt = capturedAt
        self.exportedAt = exportedAt
        self.deviceModel = deviceModel
        self.roomScans = roomScans
        self.photos = photos
        self.voiceNotes = voiceNotes
        self.objectPins = objectPins
        self.floorPlanSnapshots = floorPlanSnapshots
        self.floorPlanFabric = floorPlanFabric
        self.hazardObservations = hazardObservations
        self.quotePlannerEvidence = quotePlannerEvidence
        self.externalAreaScans = externalAreaScans
        self.qaFlags = qaFlags
    }
}

// MARK: - CapturedRoomScanV2

/// A room scan artefact captured during the visit.
///
/// Stores raw observation data only. No heat loss, no thermal meaning,
/// no emitter adequacy — those belong in Mind.
public struct CapturedRoomScanV2: Codable, Sendable {

    /// Stable UUID for this room scan record.
    public let id: String

    /// Optional room label assigned by the engineer.
    public let roomLabel: String?

    /// ISO-8601 timestamp of when the scan was captured.
    public let captureTimestamp: String

    /// Local path reference to the preview thumbnail image.
    public let previewImageRef: String?

    /// Local path reference to the raw scan asset (USDZ / GLB).
    public let rawScanAssetRef: String?

    /// Raw room width in metres as supplied by the platform scan API.
    public let rawWidthM: Double?

    /// Raw room depth in metres as supplied by the platform scan API.
    public let rawDepthM: Double?

    /// Raw ceiling height in metres as supplied by the platform scan API.
    public let rawHeightM: Double?

    /// Optional local spatial origin/transform metadata from the capture API.
    public let localTransformOrigin: ScanPoint3D?

    /// Capture-layer warnings and confidence signals from the scan API.
    public let warnings: [ScanQAFlag]

    /// Overall scan confidence band as reported by the capture API.
    public let confidence: ScanConfidenceBand

    /// Engineer-annotated floor plan data (JSON-encoded `FloorPlanDraft`).
    /// Nil when no annotations were made.
    public let floorPlanData: String?

    public init(
        id: String,
        roomLabel: String?,
        captureTimestamp: String,
        previewImageRef: String?,
        rawScanAssetRef: String?,
        rawWidthM: Double?,
        rawDepthM: Double?,
        rawHeightM: Double?,
        localTransformOrigin: ScanPoint3D?,
        warnings: [ScanQAFlag],
        confidence: ScanConfidenceBand,
        floorPlanData: String? = nil
    ) {
        self.id = id
        self.roomLabel = roomLabel
        self.captureTimestamp = captureTimestamp
        self.previewImageRef = previewImageRef
        self.rawScanAssetRef = rawScanAssetRef
        self.rawWidthM = rawWidthM
        self.rawDepthM = rawDepthM
        self.rawHeightM = rawHeightM
        self.localTransformOrigin = localTransformOrigin
        self.warnings = warnings
        self.confidence = confidence
        self.floorPlanData = floorPlanData
    }
}

// MARK: - CapturedPhotoV2

/// An evidence photo captured during the visit.
public struct CapturedPhotoV2: Codable, Sendable {

    /// Stable UUID for this photo record.
    public let id: String

    /// Local filename of the captured image.
    public let localFilename: String

    /// ISO-8601 timestamp of when the photo was captured.
    public let captureTimestamp: String

    /// UUID of the room this photo is associated with; nil for session-level photos.
    public let roomId: String?

    /// UUID of the capture point this photo is associated with; nil when unanchored.
    public let capturePointId: String?

    /// UUID of the object/pin this photo is linked to; nil when not linked.
    public let linkedObjectId: String?

    /// Anchor confidence for this photo evidence when captured from a spatial point.
    public let anchorConfidence: String?

    /// True when this photo evidence requires engineer review.
    public let needsReview: Bool

    /// Evidence kind / category raw value (e.g. "overview", "plant", "flue").
    public let kind: String

    public init(
        id: String,
        localFilename: String,
        captureTimestamp: String,
        roomId: String?,
        capturePointId: String? = nil,
        linkedObjectId: String?,
        anchorConfidence: String? = nil,
        needsReview: Bool = false,
        kind: String
    ) {
        self.id = id
        self.localFilename = localFilename
        self.captureTimestamp = captureTimestamp
        self.roomId = roomId
        self.capturePointId = capturePointId
        self.linkedObjectId = linkedObjectId
        self.anchorConfidence = anchorConfidence
        self.needsReview = needsReview
        self.kind = kind
    }
}

// MARK: - CapturedVoiceNoteV2

/// A voice note transcript captured during the visit.
///
/// Raw audio is deliberately excluded. Transcript text is the only
/// voice evidence that crosses the Scan → Mind boundary.
public struct CapturedVoiceNoteV2: Codable, Sendable {

    /// Stable UUID for this voice note record.
    public let id: String

    /// Transcript text of the recording. Empty string if not yet transcribed.
    public let transcript: String

    /// ISO-8601 timestamp of when recording started.
    public let startedAt: String

    /// ISO-8601 timestamp of when recording ended; nil if still in progress.
    public let endedAt: String?

    /// UUID of the room this note is associated with; nil for session-level notes.
    public let roomId: String?

    /// UUID of the capture point this note is associated with; nil when unanchored.
    public let capturePointId: String?

    /// UUID of the object/pin this note is linked to; nil when not linked.
    public let linkedObjectId: String?

    /// Anchor confidence for this note evidence when captured from a spatial point.
    public let anchorConfidence: String?

    /// True when this voice note requires engineer review.
    public let needsReview: Bool

    public init(
        id: String,
        transcript: String,
        startedAt: String,
        endedAt: String?,
        roomId: String?,
        capturePointId: String? = nil,
        linkedObjectId: String?,
        anchorConfidence: String? = nil,
        needsReview: Bool = false
    ) {
        self.id = id
        self.transcript = transcript
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.roomId = roomId
        self.capturePointId = capturePointId
        self.linkedObjectId = linkedObjectId
        self.anchorConfidence = anchorConfidence
        self.needsReview = needsReview
    }
}

// MARK: - CapturedObjectPinV2

/// A typed object or pin placement made during the visit.
///
/// Captures "what is here" only — no engineering outputs, no
/// recommendations, no emitter adequacy signals.
public struct CapturedObjectPinV2: Codable, Sendable {

    /// Stable UUID for this pin record.
    public let id: String

    /// Object type raw value (e.g. "boiler", "radiator", "cylinder").
    public let type: String

    /// Optional free-text label set by the engineer.
    public let label: String?

    /// UUID of the room this pin is associated with; nil for session-level pins.
    public let roomId: String?

    /// UUID of the capture point this pin is associated with; nil when unanchored.
    public let capturePointId: String?

    /// UUID of a linked evidence photo; nil when no photo is attached.
    public let linkedPhotoId: String?

    /// Approximate 3-D position if captured from a placement interaction.
    /// Nil when position was not captured.
    public let approximatePositionRef: ScanPoint3D?

    /// Anchor confidence for this pin placement.
    public let anchorConfidence: String?

    /// Surface semantic this pin is attached to.
    public let surfaceSemantic: String?

    /// True when this pin requires engineer review.
    public let needsReview: Bool

    public init(
        id: String,
        type: String,
        label: String?,
        roomId: String?,
        capturePointId: String? = nil,
        linkedPhotoId: String?,
        approximatePositionRef: ScanPoint3D?,
        anchorConfidence: String? = nil,
        surfaceSemantic: String? = nil,
        needsReview: Bool = false
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.roomId = roomId
        self.capturePointId = capturePointId
        self.linkedPhotoId = linkedPhotoId
        self.approximatePositionRef = approximatePositionRef
        self.anchorConfidence = anchorConfidence
        self.surfaceSemantic = surfaceSemantic
        self.needsReview = needsReview
    }
}

// MARK: - CapturedFloorPlanSnapshotV2

/// A floor plan snapshot captured during the visit.
public struct CapturedFloorPlanSnapshotV2: Codable, Sendable {

    /// Stable UUID for this snapshot record.
    public let id: String

    /// Local path reference to the snapshot image.
    public let imageRef: String

    /// ISO-8601 timestamp of when the snapshot was captured.
    public let captureTimestamp: String

    /// UUID of the room this snapshot is associated with; nil for whole-property snapshots.
    public let roomId: String?

    public init(
        id: String,
        imageRef: String,
        captureTimestamp: String,
        roomId: String?
    ) {
        self.id = id
        self.imageRef = imageRef
        self.captureTimestamp = captureTimestamp
        self.roomId = roomId
    }
}
