/// ScanToMindPayloadEncoder (AtlasScanCore v2) — Encodes a SessionCaptureV2
/// session into a transmissible payload for the Atlas Mind handoff.

import Foundation

public enum ScanToMindPayloadEncoder {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// Encodes `session` into a `ScanToMindHandoffV1` payload and returns it.
    ///
    public static func encode(session: SessionCaptureV2) throws -> ScanToMindHandoffV1 {
        let readiness = VisitReadinessV1.derive(from: session)
        return ScanToMindHandoffV1(
            session: session,
            readiness: readiness,
            missingEvidence: readiness.unmetConditions,
            engineerNotes: session.engineerNotes
        )
    }

    /// Returns the raw JSON `Data` for the payload (for diagnostics / clipboard).
    public static func encodeToData(session: SessionCaptureV2) throws -> Data {
        let payload = try encode(session: session)
        return try encoder.encode(payload)
    }
}
