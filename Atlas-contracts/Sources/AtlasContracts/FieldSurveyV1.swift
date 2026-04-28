import Foundation

// MARK: - FieldSurveyV1
//
// Minimal field survey payload contract.
//
// Design rules:
//   • One FieldSurveyV1 represents the structured capture state of a single visit.
//   • It is derived from the in-app PropertyScanSession at read time; it is not
//     stored separately but rather re-derived as needed.
//   • atlas-scans-ios PRODUCES this shape from captured rooms, objects, and artefacts.
//   • atlas-contracts DEFINES the schema — this file is the single source of truth.
//   • deriveVisitReadinessFromFieldSurvey is a pure, side-effect-free function.
//   • Raw audio, scan assets, and spatial geometry are NOT part of this payload.

// MARK: - FieldSurveyRoomV1

/// Summary of a single room captured during the field survey.
public struct FieldSurveyRoomV1: Codable, Sendable, Equatable {

    /// Stable string identifier (UUID string) for the room.
    public let id: String

    /// Engineer-assigned name for the room.
    public let name: String

    /// Number of photos taken of or within this room.
    public let photoCount: Int

    /// Number of voice notes recorded in this room.
    public let voiceNoteCount: Int

    public init(id: String, name: String, photoCount: Int, voiceNoteCount: Int) {
        self.id = id
        self.name = name
        self.photoCount = photoCount
        self.voiceNoteCount = voiceNoteCount
    }
}

// MARK: - FieldSurveyV1

/// Structured summary of what was captured during the field visit.
///
/// This is the minimal field survey payload.  It carries counts and presence
/// flags rather than raw artefacts, so that the review surface can quickly
/// show what is present and what is missing without walking every child array.
public struct FieldSurveyV1: Codable, Sendable {

    // MARK: Rooms

    /// Rooms captured during the visit.
    public var rooms: [FieldSurveyRoomV1]

    // MARK: Artefact counts

    /// Total photos captured across all rooms and session level.
    public var totalPhotoCount: Int

    /// Total voice notes recorded across all rooms and session level.
    public var totalVoiceNoteCount: Int

    // MARK: Key object presence flags

    /// Whether a boiler or heat pump has been tagged.
    public var hasBoiler: Bool

    /// Whether a flue has been tagged.
    public var hasFlue: Bool

    /// Whether a hot water cylinder or thermal store has been tagged.
    public var hasHotWaterSystem: Bool

    /// Whether any heating system component (boiler or emitters) has been tagged.
    public var hasHeatingSystem: Bool

    // MARK: Derived helpers

    /// Shorthand count of rooms captured.
    public var roomCount: Int { rooms.count }

    /// Number of key objects that are present (boiler, flue, hot water, heating).
    public var keyObjectsPresentCount: Int {
        [hasBoiler, hasFlue, hasHotWaterSystem, hasHeatingSystem]
            .filter { $0 }.count
    }

    // MARK: Init

    public init(
        rooms: [FieldSurveyRoomV1] = [],
        totalPhotoCount: Int = 0,
        totalVoiceNoteCount: Int = 0,
        hasBoiler: Bool = false,
        hasFlue: Bool = false,
        hasHotWaterSystem: Bool = false,
        hasHeatingSystem: Bool = false
    ) {
        self.rooms = rooms
        self.totalPhotoCount = totalPhotoCount
        self.totalVoiceNoteCount = totalVoiceNoteCount
        self.hasBoiler = hasBoiler
        self.hasFlue = hasFlue
        self.hasHotWaterSystem = hasHotWaterSystem
        self.hasHeatingSystem = hasHeatingSystem
    }
}

// MARK: - VisitReadinessV1

/// Readiness flags derived from a FieldSurveyV1.
///
/// Each flag represents one dimension of survey completeness.
/// `isReady` is the summary: all critical flags must pass before a visit
/// can be marked as ready for completion.
public struct VisitReadinessV1: Codable, Sendable {

    /// At least one room has been added.
    public let hasRooms: Bool

    /// At least one evidence photo has been captured.
    public let hasPhotos: Bool

    /// A heating system component has been tagged.
    public let hasHeatingSystem: Bool

    /// A hot water system component has been tagged.
    public let hasHotWaterSystem: Bool

    /// A boiler or heat pump has been tagged.
    public let hasBoiler: Bool

    /// A flue has been tagged.
    public let hasFlue: Bool

    /// At least one voice note has been recorded.
    public let hasNotes: Bool

    // MARK: Summary

    /// True when all critical fields are present.
    ///
    /// Rooms, photos, boiler, and flue are the minimum required for a
    /// visit to be considered capture-complete.
    public var isReady: Bool {
        hasRooms && hasPhotos && hasBoiler && hasFlue
    }

    /// Human-readable descriptions of what is missing.
    public var missingItems: [String] {
        var missing: [String] = []
        if !hasRooms          { missing.append("No rooms captured") }
        if !hasPhotos         { missing.append("No photos captured") }
        if !hasBoiler         { missing.append("No boiler or heat source tagged") }
        if !hasFlue           { missing.append("No flue tagged") }
        if !hasHeatingSystem  { missing.append("No heating system tagged") }
        if !hasHotWaterSystem { missing.append("No hot water system tagged") }
        if !hasNotes          { missing.append("No voice notes recorded") }
        return missing
    }

    // MARK: Init

    public init(
        hasRooms: Bool,
        hasPhotos: Bool,
        hasHeatingSystem: Bool,
        hasHotWaterSystem: Bool,
        hasBoiler: Bool,
        hasFlue: Bool,
        hasNotes: Bool
    ) {
        self.hasRooms = hasRooms
        self.hasPhotos = hasPhotos
        self.hasHeatingSystem = hasHeatingSystem
        self.hasHotWaterSystem = hasHotWaterSystem
        self.hasBoiler = hasBoiler
        self.hasFlue = hasFlue
        self.hasNotes = hasNotes
    }
}

// MARK: - deriveVisitReadinessFromFieldSurvey

/// Derives `VisitReadinessV1` from the given `FieldSurveyV1`.
///
/// This is a pure, crash-safe function.  An empty or partially-populated
/// survey produces a readiness result with appropriate false flags rather
/// than crashing or returning nil.
public func deriveVisitReadinessFromFieldSurvey(_ survey: FieldSurveyV1) -> VisitReadinessV1 {
    VisitReadinessV1(
        hasRooms: !survey.rooms.isEmpty,
        hasPhotos: survey.totalPhotoCount > 0,
        hasHeatingSystem: survey.hasHeatingSystem,
        hasHotWaterSystem: survey.hasHotWaterSystem,
        hasBoiler: survey.hasBoiler,
        hasFlue: survey.hasFlue,
        hasNotes: survey.totalVoiceNoteCount > 0
    )
}
