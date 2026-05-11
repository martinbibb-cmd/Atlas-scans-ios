/// ScanToMindHandoffV1 — Handover payload transmitted to the Atlas Mind app.

import Foundation

// MARK: - Hardware patch (custom appliance overrides dispatched from Mind)

public struct HardwarePatchV1: Codable, Sendable {
    public var targetModelId: UUID?
    public var customName: String
    public var widthM: Double
    public var heightM: Double
    public var depthM: Double
    public var clearanceTopOffsetM:    Double
    public var clearanceBottomOffsetM: Double
    public var clearanceFrontOffsetM:  Double
    public var clearanceBackOffsetM:   Double
    public var clearanceLeftOffsetM:   Double
    public var clearanceRightOffsetM:  Double

    public init(
        targetModelId: UUID? = nil,
        customName: String,
        widthM: Double,
        heightM: Double,
        depthM: Double,
        clearanceTopOffsetM: Double    = 0,
        clearanceBottomOffsetM: Double = 0,
        clearanceFrontOffsetM: Double  = 0,
        clearanceBackOffsetM: Double   = 0,
        clearanceLeftOffsetM: Double   = 0,
        clearanceRightOffsetM: Double  = 0
    ) {
        self.targetModelId = targetModelId
        self.customName = customName
        self.widthM = widthM
        self.heightM = heightM
        self.depthM = depthM
        self.clearanceTopOffsetM    = clearanceTopOffsetM
        self.clearanceBottomOffsetM = clearanceBottomOffsetM
        self.clearanceFrontOffsetM  = clearanceFrontOffsetM
        self.clearanceBackOffsetM   = clearanceBackOffsetM
        self.clearanceLeftOffsetM   = clearanceLeftOffsetM
        self.clearanceRightOffsetM  = clearanceRightOffsetM
    }
}

// MARK: - Visit handoff pack (Mind → Scan direction)

public struct VisitHandoffPackV1: Codable, Sendable {
    public let schemaVersion: String
    public let visitId: UUID
    public var propertyAddress: String?
    public var hardwarePatches: HardwarePatchV1?

    public init(
        visitId: UUID,
        propertyAddress: String? = nil,
        hardwarePatches: HardwarePatchV1? = nil
    ) {
        self.schemaVersion = "1.0"
        self.visitId = visitId
        self.propertyAddress = propertyAddress
        self.hardwarePatches = hardwarePatches
    }
}

// MARK: - Handoff payload

public struct ScanToMindHandoffV1: Codable, Sendable {
    public let schemaVersion: String
    public let session: SessionCaptureV2
    public let readiness: VisitReadinessV1
    public let missingEvidence: [String]
    public let engineerNotes: String?
    public let handedOffAt: String
    public let handoffId: UUID
    public let visitId: UUID

    /// Equipment evidence groups derived from the session's spatial pins.
    ///
    /// Groups all room pins by function (heat source, hot water storage,
    /// flue/external, emitters, heating components) and applies identity and
    /// anchor-confidence classification rules.
    ///
    /// Atlas Mind uses this to display structured equipment evidence cards
    /// instead of a flat generic object-pin list.
    public let equipmentEvidenceGroups: EquipmentEvidenceGroupsV1

    public init(
        session: SessionCaptureV2,
        readiness: VisitReadinessV1,
        missingEvidence: [String]? = nil,
        engineerNotes: String? = nil,
        handedOffAt: Date = Date(),
        handoffId: UUID = UUID()
    ) {
        self.schemaVersion = "1.0"
        self.session = session
        self.readiness = readiness
        self.missingEvidence = missingEvidence ?? readiness.unmetConditions
        self.engineerNotes = engineerNotes ?? session.engineerNotes
        self.handedOffAt = ISO8601DateFormatter().string(from: handedOffAt)
        self.handoffId = handoffId
        self.visitId = session.visitId
        self.equipmentEvidenceGroups = EquipmentEvidenceMapper.buildGroups(
            from: session.rooms,
            photos: session.photos,
            visitId: session.visitId.uuidString
        )
    }

    // MARK: - Custom Codable (backward compat)

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, session, readiness, missingEvidence, engineerNotes, handedOffAt, handoffId, visitId
        case equipmentEvidenceGroups
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        session = try c.decode(SessionCaptureV2.self, forKey: .session)
        readiness = try c.decode(VisitReadinessV1.self, forKey: .readiness)
        missingEvidence = try c.decodeIfPresent([String].self, forKey: .missingEvidence)
            ?? readiness.unmetConditions
        engineerNotes = try c.decodeIfPresent(String.self, forKey: .engineerNotes)
        handedOffAt = try c.decode(String.self, forKey: .handedOffAt)
        handoffId = try c.decode(UUID.self, forKey: .handoffId)
        visitId = try c.decode(UUID.self, forKey: .visitId)
        // Backward-compat: derive from session rooms when field absent in older payloads.
        equipmentEvidenceGroups = try c.decodeIfPresent(EquipmentEvidenceGroupsV1.self, forKey: .equipmentEvidenceGroups)
            ?? EquipmentEvidenceMapper.buildGroups(from: session.rooms, photos: session.photos, visitId: visitId.uuidString)
    }
}

// MARK: - Deep-link URL builder

public extension ScanToMindHandoffV1 {

    static let receiveScanURLString = "atlasmind:///receive-scan"

    func buildDeepLinkURL() throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(self)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw HandoffError.jsonStringConversionFailed
        }
        guard let encoded = jsonString.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else {
            throw HandoffError.percentEncodingFailed
        }
        let urlString = "\(Self.receiveScanURLString)?payload=\(encoded)"
        guard let url = URL(string: urlString) else {
            throw HandoffError.invalidURL(urlString)
        }
        return url
    }
}

// MARK: - Handoff errors

public enum HandoffError: Error, LocalizedError, Sendable {
    case jsonStringConversionFailed
    case percentEncodingFailed
    case invalidURL(String)
    case readinessNotSatisfied([String])

    public var errorDescription: String? {
        switch self {
        case .jsonStringConversionFailed:
            return "Failed to convert session JSON to a UTF-8 string."
        case .percentEncodingFailed:
            return "Failed to percent-encode the session payload."
        case .invalidURL(let raw):
            return "Could not construct a valid URL from: \(raw)"
        case .readinessNotSatisfied(let missing):
            return "Visit readiness not satisfied. Missing: \(missing.joined(separator: ", "))"
        }
    }
}
