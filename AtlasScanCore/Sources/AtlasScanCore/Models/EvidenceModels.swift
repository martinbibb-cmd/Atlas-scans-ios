/// EvidenceModels — Photo, voice note, QA flag, and transcript evidence types.

import Foundation

// MARK: - Photo evidence

public struct PhotoEvidenceV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let visitId: UUID
    public let roomId: UUID

    /// UUID of the pinned object this photo documents (if any).
    public var linkedObjectId: UUID?

    /// Relative file path under `Documents/captures/{visitId}/photos/`.
    public let relativeFilePath: String

    /// ISO-8601 timestamp.
    public let capturedAt: String

    /// World-space camera position at capture time (Y-up, metres).
    public var cameraPositionX: Double?
    public var cameraPositionY: Double?
    public var cameraPositionZ: Double?

    public init(
        id: UUID = UUID(),
        visitId: UUID,
        roomId: UUID,
        linkedObjectId: UUID? = nil,
        relativeFilePath: String,
        capturedAt: Date = Date(),
        cameraPositionX: Double? = nil,
        cameraPositionY: Double? = nil,
        cameraPositionZ: Double? = nil
    ) {
        self.id = id
        self.visitId = visitId
        self.roomId = roomId
        self.linkedObjectId = linkedObjectId
        self.relativeFilePath = relativeFilePath
        self.capturedAt = ISO8601DateFormatter().string(from: capturedAt)
        self.cameraPositionX = cameraPositionX
        self.cameraPositionY = cameraPositionY
        self.cameraPositionZ = cameraPositionZ
    }
}

// MARK: - Voice note (processed transcript only — NO raw audio)

/// Hint that tells Atlas Mind which engineering field to populate automatically.
public enum ExtractionHint: String, Codable, CaseIterable, Sendable {
    case householdComposition     = "household_composition"
    case boilerServiceHistory     = "boiler_service_history"
    case heatingIssueDescription  = "heating_issue_description"
    case flueMaterial             = "flue_material"
    case pipeworkCondition        = "pipework_condition"
    case pressureReading          = "pressure_reading"
    case general                  = "general"
}

public struct VoiceNoteV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let visitId: UUID
    public let roomId: UUID

    /// UUID of the pinned object this note is anchored to (if any).
    public var linkedObjectId: UUID?

    // Raw audio is EXCLUDED — only the processed transcript is stored.
    public let processedTranscript: String

    public var extractionHint: ExtractionHint

    public let recordedAt: String

    public init(
        id: UUID = UUID(),
        visitId: UUID,
        roomId: UUID,
        linkedObjectId: UUID? = nil,
        processedTranscript: String,
        extractionHint: ExtractionHint = .general,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.visitId = visitId
        self.roomId = roomId
        self.linkedObjectId = linkedObjectId
        self.processedTranscript = processedTranscript
        self.extractionHint = extractionHint
        self.recordedAt = ISO8601DateFormatter().string(from: recordedAt)
    }
}

// MARK: - Processed transcript

public struct ProcessedTranscriptV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let visitId: UUID
    public let roomId: UUID
    public var linkedObjectId: UUID?
    public let transcript: String
    public var extractionHint: ExtractionHint
    public let processedAt: String

    public init(
        id: UUID = UUID(),
        visitId: UUID,
        roomId: UUID,
        linkedObjectId: UUID? = nil,
        transcript: String,
        extractionHint: ExtractionHint = .general,
        processedAt: Date = Date()
    ) {
        self.id = id
        self.visitId = visitId
        self.roomId = roomId
        self.linkedObjectId = linkedObjectId
        self.transcript = transcript
        self.extractionHint = extractionHint
        self.processedAt = ISO8601DateFormatter().string(from: processedAt)
    }
}

// MARK: - QA flags

public enum QAFlagType: String, Codable, CaseIterable, Sendable {
    case clearanceConflict  = "CLEARANCE_CONFLICT"
    case clearancePass      = "CLEARANCE_PASS"
    case missingFabric      = "MISSING_FABRIC"
    case lowPhotoCount      = "LOW_PHOTO_COUNT"
    case incompleteTranscript = "INCOMPLETE_TRANSCRIPT"
    case flueConflict       = "FLUE_CONFLICT"
}

public struct QAFlagV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let type: QAFlagType
    public let roomId: UUID?
    public var detail: String

    public init(
        id: UUID = UUID(),
        type: QAFlagType,
        roomId: UUID? = nil,
        detail: String = ""
    ) {
        self.id = id
        self.type = type
        self.roomId = roomId
        self.detail = detail
    }
}

// MARK: - Outdoor flue clearance report

public struct OutdoorFlueClearanceReportV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let visitId: UUID

    /// World-space position of the flue terminal exit.
    public let flueTerminalPositionX: Double
    public let flueTerminalPositionY: Double
    public let flueTerminalPositionZ: Double

    /// Measured distances to nearby openings (windows / doors).
    public var openingDistances: [OpeningDistanceMeasurement]

    public init(
        id: UUID = UUID(),
        visitId: UUID,
        flueTerminalPositionX: Double,
        flueTerminalPositionY: Double,
        flueTerminalPositionZ: Double,
        openingDistances: [OpeningDistanceMeasurement] = []
    ) {
        self.id = id
        self.visitId = visitId
        self.flueTerminalPositionX = flueTerminalPositionX
        self.flueTerminalPositionY = flueTerminalPositionY
        self.flueTerminalPositionZ = flueTerminalPositionZ
        self.openingDistances = openingDistances
    }
}

public struct OpeningDistanceMeasurement: Codable, Identifiable, Sendable {
    public let id: UUID
    public let openingType: OpeningType
    public let distanceM: Double
    public let passesBuildingRegs: Bool   // ≥ 300 mm for most opening types

    public init(
        id: UUID = UUID(),
        openingType: OpeningType,
        distanceM: Double,
        minimumRequiredM: Double = 0.300
    ) {
        self.id = id
        self.openingType = openingType
        self.distanceM = distanceM
        self.passesBuildingRegs = distanceM >= minimumRequiredM
    }
}

public enum OpeningType: String, Codable, CaseIterable, Sendable {
    case window
    case door
    case airBrick
    case ventilationGrille
    case other
}
