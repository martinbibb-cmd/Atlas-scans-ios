import Foundation

// MARK: - CaptureSessionDraft
//
// The single in-app capture state for one visit session.
//
// Design:
//   • One CaptureSessionDraft = one visit = one export.
//   • All captured artefacts live here as draft models.
//   • CaptureSessionExporter maps this to SessionCaptureV2 at export time.
//   • Raw audio is ephemeral and never stored in this model.
//   • No derived outputs — this is raw observation only.

struct CaptureSessionDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// Cross-system appointment key from Atlas Recommendations (AppointmentV1.appointmentId).
    /// Required for the SessionCaptureV1 contract; nil until the engineer selects or
    /// enters the appointment reference at session-start time.
    var appointmentId: String?

    /// Engineer-assigned visit / job reference (required before export).
    var visitReference: String = ""

    /// Optional property address for the visit.
    var propertyAddress: String = ""

    /// Optional customer name for the visit.
    var customerName: String = ""

    /// When the session was first created.
    var capturedAt: Date = Date()

    /// Indoor room scans captured during the visit.
    var roomScans: [CapturedRoomScanDraft] = []

    /// Evidence photos captured during the visit.
    var photos: [CapturedPhotoDraft] = []

    /// Voice note transcripts captured during the visit.
    /// Raw audio is ephemeral and must not be stored here.
    var voiceNotes: [CapturedVoiceNoteDraft] = []

    /// Typed object and pin placements made during the visit.
    var objectPins: [CapturedObjectPinDraft] = []

    /// Floor plan snapshots captured during the visit.
    var floorPlanSnapshots: [CapturedFloorPlanSnapshotDraft] = []

    /// Floor plan fabric records (boundaries and openings) captured during the visit.
    var fabricRecords: [CapturedFloorPlanFabricDraft] = []

    /// Site hazard observations recorded during the visit.
    var hazardObservations: [CapturedHazardObservationDraft] = []

    /// Export lifecycle state.
    var exportState: CaptureExportState = .draft

    /// Sync state with the Atlas Recommendations backend.
    var syncState: CaptureSyncState = .notSynced

    /// Remote visit ID assigned by Atlas Recommendations after a successful import.
    var remoteVisitId: String?

    /// When the session was last updated (set automatically on mutations).
    var updatedAt: Date = Date()
}

// MARK: - CaptureSyncState

/// Sync lifecycle state with the Atlas Recommendations backend.
enum CaptureSyncState: String, Codable, CaseIterable {
    /// Session has not been sent to Atlas Recommendations yet.
    case notSynced  = "not_synced"
    /// Upload in progress.
    case syncing    = "syncing"
    /// Successfully received by Atlas Recommendations.
    case synced     = "synced"
    /// Sync attempt failed — can be retried.
    case syncFailed = "sync_failed"

    var displayName: String {
        switch self {
        case .notSynced:  return "Not Synced"
        case .syncing:    return "Syncing…"
        case .synced:     return "Synced"
        case .syncFailed: return "Sync Failed"
        }
    }
}

// MARK: - EvidenceReviewStatus

/// Engineer review status for a single piece of captured evidence.
///
/// Rules:
///   - Manually created items default to `.confirmed`.
///   - LiDAR/inferred items default to `.pending`.
///   - Rejected items remain stored for audit but never count toward readiness.
///   - Pending items block final completion when they are required for readiness.
enum EvidenceReviewStatus: String, Codable, CaseIterable {
    /// Engineer has confirmed this evidence is correct and complete.
    case confirmed = "confirmed"
    /// Engineer has explicitly rejected this evidence (kept for audit; not counted).
    case rejected  = "rejected"
    /// Awaiting engineer review — may block completion if required.
    case pending   = "pending"

    var displayName: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .rejected:  return "Rejected"
        case .pending:   return "Pending"
        }
    }

    var symbolName: String {
        switch self {
        case .confirmed: return "checkmark.circle.fill"
        case .rejected:  return "xmark.circle.fill"
        case .pending:   return "clock.fill"
        }
    }
}

// MARK: - CaptureExportState

/// Lifecycle state for a capture session draft.
enum CaptureExportState: String, Codable, CaseIterable {
    /// Session is in progress — not yet ready for export.
    case draft = "draft"
    /// All required artefacts are present; session is ready to export.
    case readyForExport = "ready_for_export"
    /// Session has been successfully exported to SessionCaptureV2.
    case exported = "exported"
    /// Export was attempted but failed.
    case exportFailed = "export_failed"

    var displayName: String {
        switch self {
        case .draft:          return "Draft"
        case .readyForExport: return "Ready to Export"
        case .exported:       return "Exported"
        case .exportFailed:   return "Export Failed"
        }
    }

    var symbolName: String {
        switch self {
        case .draft:          return "pencil.circle"
        case .readyForExport: return "checkmark.circle"
        case .exported:       return "checkmark.seal.fill"
        case .exportFailed:   return "xmark.circle"
        }
    }
}

// MARK: - CapturedRoomScanDraft

/// In-app draft of a room scan artefact.
///
/// Stores raw observation data only. No heat loss, no thermal meaning,
/// no emitter adequacy — those belong in Mind.
struct CapturedRoomScanDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// Optional room label assigned by the engineer.
    var roomLabel: String?

    /// When the scan was captured.
    var captureTimestamp: Date = Date()

    /// Local path to the preview thumbnail image.
    var previewImageRef: String?

    /// Local path to the raw scan asset (USDZ / GLB).
    var rawScanAssetRef: String?

    /// Raw room width in metres from the platform scan API.
    var rawWidthM: Double?

    /// Raw room depth in metres from the platform scan API.
    var rawDepthM: Double?

    /// Raw ceiling height in metres from the platform scan API.
    var rawHeightM: Double?

    /// Optional capture-API warning codes.
    var warningCodes: [String] = []

    /// Scan confidence as reported by the capture API.
    var confidence: RoomScanConfidence = .medium

    /// How the room scan data was obtained (manual entry or LiDAR hardware scan).
    var captureSource: RoomScanCaptureSource = .manual

    /// Raw LiDAR metadata JSON from the RoomPlan capture API.
    /// Nil for manually entered scans. Stored for future use; not exported.
    var lidarMetadata: String?

    /// Floor plan annotations added by the engineer after the room scan.
    var floorPlan: FloorPlanDraft?

    /// Engineer review status for this room scan.
    /// Defaults to `.confirmed` for manually entered rooms; `.pending` for LiDAR scans.
    /// When creating a LiDAR room scan, set this to `.pending` explicitly.
    var reviewStatus: EvidenceReviewStatus = .confirmed
}

// MARK: - RoomScanConfidence

enum RoomScanConfidence: String, Codable, CaseIterable {
    case high   = "high"
    case medium = "medium"
    case low    = "low"

    var displayName: String {
        switch self {
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low"
        }
    }
}

// MARK: - RoomScanCaptureSource

/// How the room scan data was obtained.
enum RoomScanCaptureSource: String, Codable, CaseIterable {
    /// Engineer entered dimensions manually.
    case manual = "manual"
    /// Data derived from a LiDAR / RoomPlan hardware scan.
    case lidar  = "lidar"

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .lidar:  return "LiDAR"
        }
    }

    var symbolName: String {
        switch self {
        case .manual: return "pencil"
        case .lidar:  return "lidar.scanner"
        }
    }
}

// MARK: - CapturedPhotoDraft

/// In-app draft of an evidence photo.
struct CapturedPhotoDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// Local filename of the captured image.
    var localFilename: String

    /// When the photo was captured.
    var captureTimestamp: Date = Date()

    /// UUID of the room this photo is associated with; nil for session-level photos.
    var roomId: UUID?

    /// UUID of the object pin this photo is linked to; nil when not linked.
    var linkedObjectId: UUID?

    /// Evidence kind / category.
    var kind: CapturePhotoKind = .other

    /// Engineer review status for this photo.
    /// Photos are always manually captured, so they default to `.confirmed`.
    var reviewStatus: EvidenceReviewStatus = .confirmed
}

// MARK: - CapturePhotoKind

enum CapturePhotoKind: String, Codable, CaseIterable {
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

// MARK: - CapturedVoiceNoteDraft

/// In-app draft of a voice note.
///
/// Raw audio is ephemeral — it must not be stored in this model or exported.
/// Transcript text is the only voice evidence retained after recording ends.
struct CapturedVoiceNoteDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// Transcript text. Empty until transcription completes.
    var transcript: String = ""

    /// When recording started.
    var startedAt: Date = Date()

    /// When recording ended; nil if still recording.
    var endedAt: Date?

    /// UUID of the room this note is associated with; nil for session-level notes.
    var roomId: UUID?

    /// UUID of the object pin this note is linked to; nil when not linked.
    var linkedObjectId: UUID?

    /// Engineer review status for this voice note.
    /// Voice notes are always manually recorded, so they default to `.confirmed`.
    var reviewStatus: EvidenceReviewStatus = .confirmed
}

// MARK: - CapturedObjectPinDraft

/// In-app draft of a typed object or pin placement.
///
/// Captures "what is here" only. No engineering outputs, no
/// recommendations, no emitter adequacy signals.
struct CapturedObjectPinDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// The type of object placed.
    var type: ObjectPinType

    /// Optional free-text label set by the engineer.
    var label: String?

    /// UUID of the room this pin is associated with; nil for session-level pins.
    var roomId: UUID?

    /// UUID of a linked evidence photo.
    var linkedPhotoId: UUID?

    /// Source of the pin placement.
    var pinSource: ObjectPinSource?

    /// Confidence level for the pin (especially relevant for LiDAR-inferred pins).
    var pinConfidence: ObjectPinConfidence?

    /// Approximate position if captured from a placement interaction.
    var approximatePositionX: Double?
    var approximatePositionY: Double?
    var approximatePositionZ: Double?

    /// When the pin was placed.
    var placedAt: Date = Date()

    /// Engineer review status for this object pin.
    /// Manual pins default to `.confirmed`; LiDAR-inferred pins default to `.pending`.
    var reviewStatus: EvidenceReviewStatus = .confirmed

    /// Returns true when the pin has no meaningful user-assigned label.
    var hasNoLabel: Bool {
        (label ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - ObjectPinType

/// The types of objects that can be pinned during a visit capture.
///
/// Covers heating systems, controls, utilities, and structural items
/// relevant to a heat-system survey — without implying any engineering logic.
enum ObjectPinType: String, Codable, CaseIterable, Identifiable {

    // Heat source / plant
    case boiler             = "boiler"
    case heatPump           = "heat_pump"
    case cylinder           = "cylinder"
    case pump               = "pump"

    // Emitters
    case radiator           = "radiator"
    case towelRail          = "towel_rail"

    // Services / utilities
    case flue               = "flue"
    case gasMeter           = "gas_meter"
    case stopTap            = "stop_tap"

    // Controls
    case thermostat         = "thermostat"
    case control            = "control"
    case valve              = "valve"

    // Structural / siting
    case airingCupboard     = "airing_cupboard"

    // Evidence / notes
    case evidencePoint      = "evidence_point"
    case genericNote        = "generic_note"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .boiler:           return "Boiler"
        case .heatPump:         return "Heat Pump"
        case .cylinder:         return "Cylinder"
        case .pump:             return "Pump"
        case .radiator:         return "Radiator"
        case .towelRail:        return "Towel Rail"
        case .flue:             return "Flue"
        case .gasMeter:         return "Gas Meter"
        case .stopTap:          return "Stop Tap"
        case .thermostat:       return "Thermostat"
        case .control:          return "Control"
        case .valve:            return "Valve"
        case .airingCupboard:   return "Airing Cupboard"
        case .evidencePoint:    return "Evidence Point"
        case .genericNote:      return "Note"
        }
    }

    var symbolName: String {
        switch self {
        case .boiler:           return "flame"
        case .heatPump:         return "wind"
        case .cylinder:         return "cylinder"
        case .pump:             return "arrow.circlepath"
        case .radiator:         return "thermometer.medium"
        case .towelRail:        return "towel"
        case .flue:             return "arrow.up.to.line"
        case .gasMeter:         return "gauge"
        case .stopTap:          return "drop.circle"
        case .thermostat:       return "thermometer"
        case .control:          return "dial.medium"
        case .valve:            return "slider.horizontal.3"
        case .airingCupboard:   return "cabinet"
        case .evidencePoint:    return "mappin"
        case .genericNote:      return "note.text"
        }
    }
}

// MARK: - ObjectPinSource

/// How an object pin was placed.
enum ObjectPinSource: String, Codable {
    /// Placed manually by the engineer.
    case manual = "manual"
    /// Inferred from a LiDAR / RoomPlan scan.
    case lidar  = "lidar"

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .lidar:  return "LiDAR"
        }
    }
}

// MARK: - ObjectPinConfidence

/// Confidence level for an object pin placement.
enum ObjectPinConfidence: String, Codable {
    /// Manually verified by the engineer.
    case manual      = "manual"
    /// Inferred from scan data; may require review.
    case inferred    = "inferred"
    /// Requires engineer review before export.
    case needsReview = "needs_review"
    /// Linked to photographic evidence.
    case photoLinked = "photo_linked"

    var displayName: String {
        switch self {
        case .manual:      return "Manual"
        case .inferred:    return "Inferred"
        case .needsReview: return "Needs Review"
        case .photoLinked: return "Photo Linked"
        }
    }
}

// MARK: - CapturedFloorPlanSnapshotDraft

/// In-app draft of a floor plan snapshot.
struct CapturedFloorPlanSnapshotDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// Local path to the snapshot image.
    var imageRef: String

    /// When the snapshot was captured.
    var captureTimestamp: Date = Date()

    /// UUID of the room associated with this snapshot; nil for whole-property snapshots.
    var roomId: UUID?

    /// Engineer review status for this floor plan snapshot.
    /// Snapshots are always manually created, so they default to `.confirmed`.
    var reviewStatus: EvidenceReviewStatus = .confirmed
}

// MARK: - CaptureSessionDraft helpers

extension CaptureSessionDraft {

    /// Returns the total count of all captured artefacts.
    var totalArtefactCount: Int {
        roomScans.count + photos.count + voiceNotes.count + objectPins.count + floorPlanSnapshots.count
    }

    // MARK: Review counts

    /// Number of artefacts across all categories with a pending review status.
    var pendingReviewCount: Int {
        roomScans.filter       { $0.reviewStatus == .pending }.count
        + photos.filter        { $0.reviewStatus == .pending }.count
        + voiceNotes.filter    { $0.reviewStatus == .pending }.count
        + objectPins.filter    { $0.reviewStatus == .pending }.count
        + floorPlanSnapshots.filter { $0.reviewStatus == .pending }.count
        + fabricRecords.flatMap { $0.boundaries }.filter { $0.reviewStatus == .pending }.count
        + fabricRecords.flatMap { $0.openings   }.filter { $0.reviewStatus == .pending }.count
        + hazardObservations.filter { $0.reviewStatus == .pending }.count
    }

    /// Number of artefacts across all categories that have been rejected.
    var rejectedReviewCount: Int {
        roomScans.filter       { $0.reviewStatus == .rejected }.count
        + photos.filter        { $0.reviewStatus == .rejected }.count
        + voiceNotes.filter    { $0.reviewStatus == .rejected }.count
        + objectPins.filter    { $0.reviewStatus == .rejected }.count
        + floorPlanSnapshots.filter { $0.reviewStatus == .rejected }.count
        + fabricRecords.flatMap { $0.boundaries }.filter { $0.reviewStatus == .rejected }.count
        + fabricRecords.flatMap { $0.openings   }.filter { $0.reviewStatus == .rejected }.count
        + hazardObservations.filter { $0.reviewStatus == .rejected }.count
    }

    /// Number of artefacts across all categories that have been confirmed.
    var confirmedReviewCount: Int {
        roomScans.filter       { $0.reviewStatus == .confirmed }.count
        + photos.filter        { $0.reviewStatus == .confirmed }.count
        + voiceNotes.filter    { $0.reviewStatus == .confirmed }.count
        + objectPins.filter    { $0.reviewStatus == .confirmed }.count
        + floorPlanSnapshots.filter { $0.reviewStatus == .confirmed }.count
        + fabricRecords.flatMap { $0.boundaries }.filter { $0.reviewStatus == .confirmed }.count
        + fabricRecords.flatMap { $0.openings   }.filter { $0.reviewStatus == .confirmed }.count
        + hazardObservations.filter { $0.reviewStatus == .confirmed }.count
    }

    // MARK: Optional readiness indicators

    /// Returns true when at least one confirmed boundary or opening has been recorded.
    ///
    /// Informational only — does not gate the seven completion flags.
    var hasFabricMeasurements: Bool {
        fabricRecords.contains { record in
            record.boundaries.contains { $0.reviewStatus == .confirmed }
            || record.openings.contains { $0.reviewStatus == .confirmed }
        }
    }

    /// Returns true when at least one confirmed hazard observation has been recorded.
    ///
    /// Informational only — does not gate the seven completion flags.
    var hasHazardObservations: Bool {
        hazardObservations.contains { $0.reviewStatus == .confirmed }
    }

    // MARK: Room-scoped helpers

    /// Returns voice notes associated with a specific room.
    func voiceNotes(for roomId: UUID) -> [CapturedVoiceNoteDraft] {
        voiceNotes.filter { $0.roomId == roomId }
    }

    /// Returns object pins associated with a specific room.
    func objectPins(for roomId: UUID) -> [CapturedObjectPinDraft] {
        objectPins.filter { $0.roomId == roomId }
    }

    /// Returns photos associated with a specific room.
    func photos(for roomId: UUID) -> [CapturedPhotoDraft] {
        photos.filter { $0.roomId == roomId }
    }

    /// Marks the session as updated now.
    mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - FloorPlanDraft

/// Engineer-annotated floor plan for one room.
///
/// Stores:
///   - the room outline as a normalised polygon (0…1 coordinate space)
///   - service-object placements on the plan
///   - pipework segments drawn by the engineer
///
/// Coordinates are normalised (0…1) relative to the bounding box of the
/// scan, so the model is resolution-independent.
struct FloorPlanDraft: Codable {

    /// Normalised polygon vertices describing the room outline.
    var outlinePoints: [NormalisedPoint] = []

    /// Service objects placed by the engineer on the plan.
    var objectPlacements: [FloorPlanObjectPlacement] = []

    /// Pipework segments drawn by the engineer.
    var pipeSegments: [PipeSegmentDraft] = []
}

// MARK: - NormalisedPoint

/// A 2-D point with coordinates normalised to [0, 1].
struct NormalisedPoint: Codable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

// MARK: - FloorPlanObjectPlacement

/// An object pin placed on the floor plan canvas.
struct FloorPlanObjectPlacement: Identifiable, Codable {
    var id: UUID = UUID()
    /// Type of service object.
    var type: ObjectPinType
    /// Optional free-text label.
    var label: String?
    /// Normalised canvas position.
    var position: NormalisedPoint
}

// MARK: - PipeSegmentDraft

/// A pipework segment drawn on the floor plan by the engineer.
struct PipeSegmentDraft: Identifiable, Codable {
    var id: UUID = UUID()
    /// Normalised start point.
    var start: NormalisedPoint
    /// Normalised end point.
    var end: NormalisedPoint
    /// Type of pipe service.
    var pipeType: PipeType = .heating
}

// MARK: - PipeType

enum PipeType: String, Codable, CaseIterable, Identifiable {
    case heating = "heating"
    case water   = "water"
    case gas     = "gas"
    case other   = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heating: return "Heating"
        case .water:   return "Water"
        case .gas:     return "Gas"
        case .other:   return "Other"
        }
    }
}

// MARK: - CapturedFloorPlanFabricDraft

/// In-app draft of per-room floor-plan fabric evidence.
///
/// Stores raw boundary and opening observations for one room.
/// No U-values, no thermal calculation — those belong in Mind.
struct CapturedFloorPlanFabricDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// UUID of the room scan this fabric record relates to; nil when unlinked.
    var roomId: UUID?

    /// Boundary observations recorded for this room.
    var boundaries: [CapturedBoundaryDraft] = []

    /// Opening observations recorded for this room.
    var openings: [CapturedOpeningDraft] = []
}

// MARK: - CapturedBoundaryDraft

/// In-app draft of a single boundary (wall segment) observation.
struct CapturedBoundaryDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// Classification of this boundary.
    var boundaryType: BoundaryType = .unknown

    /// Measured length in metres; nil if not recorded.
    var lengthM: Double?

    /// Measured height in metres; nil if not recorded.
    var heightM: Double?

    /// Free-text material description (e.g. "solid brick", "cavity wall").
    var material: String?

    /// Engineer review status.
    /// Manually entered boundaries default to `.confirmed`.
    var reviewStatus: EvidenceReviewStatus = .confirmed
}

// MARK: - BoundaryType

/// Classification of a building boundary (wall segment).
enum BoundaryType: String, Codable, CaseIterable, Identifiable {
    case external = "external"
    case `internal` = "internal"
    case party    = "party"
    case unknown  = "unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .external:  return "External"
        case .internal:  return "Internal"
        case .party:     return "Party"
        case .unknown:   return "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .external:  return "building.2"
        case .internal:  return "square.split.2x1"
        case .party:     return "person.2.square.stack"
        case .unknown:   return "questionmark.square"
        }
    }
}

// MARK: - CapturedOpeningDraft

/// In-app draft of a single opening (door, window, etc.) observation.
struct CapturedOpeningDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// Classification of this opening.
    var openingType: OpeningType = .window

    /// Measured or estimated width in metres; nil if not recorded.
    var widthM: Double?

    /// Measured or estimated height in metres; nil if not recorded.
    var heightM: Double?

    /// Free-text material / glazing description.
    var material: String?

    /// UUID of the boundary this opening belongs to; nil when unlinked.
    var linkedBoundaryId: UUID?

    /// Engineer review status.
    /// Manually entered openings default to `.confirmed`.
    var reviewStatus: EvidenceReviewStatus = .confirmed
}

// MARK: - OpeningType

/// Classification of a building opening.
enum OpeningType: String, Codable, CaseIterable, Identifiable {
    case door      = "door"
    case window    = "window"
    case patio     = "patio"
    case rooflight = "rooflight"
    case openArch  = "open_arch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .door:      return "Door"
        case .window:    return "Window"
        case .patio:     return "Patio Door"
        case .rooflight: return "Rooflight"
        case .openArch:  return "Open Arch"
        }
    }

    var symbolName: String {
        switch self {
        case .door:      return "door.right.hand.open"
        case .window:    return "window.casement"
        case .patio:     return "door.sliding.right.hand.open"
        case .rooflight: return "sun.roof"
        case .openArch:  return "archivebox"
        }
    }
}

// MARK: - CapturedHazardObservationDraft

/// In-app draft of a site hazard observation.
///
/// Raw observation only — no risk score, no remediation recommendation.
/// Those belong in Mind.
struct CapturedHazardObservationDraft: Identifiable, Codable {

    var id: UUID = UUID()

    /// Hazard category.
    var category: HazardCategory = .other

    /// Hazard severity.
    var severity: HazardSeverity = .low

    /// Short title describing the hazard.
    var title: String = ""

    /// Longer description of the hazard observation.
    var descriptionText: String = ""

    /// UUIDs of evidence photos linked to this hazard.
    var linkedPhotoIds: [UUID] = []

    /// UUIDs of object pins linked to this hazard.
    var linkedObjectPinIds: [UUID] = []

    /// Whether the engineer considers immediate action required.
    var actionRequired: Bool = false

    /// Engineer review status.
    /// Manually entered hazards default to `.confirmed`.
    var reviewStatus: EvidenceReviewStatus = .confirmed
}

// MARK: - HazardCategory

/// Category of a site hazard observation.
enum HazardCategory: String, Codable, CaseIterable, Identifiable {
    case asbestos   = "asbestos"
    case structural = "structural"
    case electrical = "electrical"
    case gas        = "gas"
    case water      = "water"
    case slipTrip   = "slip_trip"
    case other      = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asbestos:   return "Asbestos / ACM"
        case .structural: return "Structural"
        case .electrical: return "Electrical"
        case .gas:        return "Gas"
        case .water:      return "Water / Damp"
        case .slipTrip:   return "Slip / Trip"
        case .other:      return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .asbestos:   return "exclamationmark.triangle.fill"
        case .structural: return "building.columns"
        case .electrical: return "bolt.fill"
        case .gas:        return "flame.fill"
        case .water:      return "drop.fill"
        case .slipTrip:   return "figure.walk.motion"
        case .other:      return "exclamationmark.circle"
        }
    }
}

// MARK: - HazardSeverity

/// Severity level for a site hazard observation.
enum HazardSeverity: String, Codable, CaseIterable, Identifiable {
    case low      = "low"
    case medium   = "medium"
    case high     = "high"
    case critical = "critical"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .critical: return "Critical"
        }
    }

    var color: String {
        switch self {
        case .low:      return "green"
        case .medium:   return "yellow"
        case .high:     return "orange"
        case .critical: return "red"
        }
    }
}
