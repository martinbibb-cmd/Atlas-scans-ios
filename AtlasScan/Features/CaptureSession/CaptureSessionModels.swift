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

    /// Floor plan annotations added by the engineer after the room scan.
    var floorPlan: FloorPlanDraft?
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

    /// Approximate position if captured from a placement interaction.
    var approximatePositionX: Double?
    var approximatePositionY: Double?
    var approximatePositionZ: Double?

    /// When the pin was placed.
    var placedAt: Date = Date()

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
}

// MARK: - CaptureSessionDraft helpers

extension CaptureSessionDraft {

    /// Returns the total count of all captured artefacts.
    var totalArtefactCount: Int {
        roomScans.count + photos.count + voiceNotes.count + objectPins.count + floorPlanSnapshots.count
    }

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
