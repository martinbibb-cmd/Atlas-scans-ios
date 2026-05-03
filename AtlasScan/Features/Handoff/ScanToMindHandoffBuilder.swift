import Foundation
import AtlasContracts

// MARK: - ScanToMindHandoffBuilder
//
// Builds a ScanToMindHandoffV1 from an AtlasScanVisit + SessionCaptureV2 pair.
//
// Rules:
//   • visit.visitId must match capture.sessionId — throws otherwise.
//   • version = "1.0", schemaVersion = "1.0".
//   • sourceApp = "scan_ios", targetApp = "mind_pwa".
//   • readiness is copied directly from the visit at build time.
//   • reason is supplied by the caller:
//       complete_capture  — completed visit
//       save_progress     — draft / incomplete visit
//       review_in_mind    — engineer review flow
//       quote_planner     — open quote planner in Atlas Mind
//   • Pure function: no side effects, no I/O.

enum ScanToMindHandoffBuilder {

    // MARK: - Errors

    /// Errors that can occur when building a handoff.
    enum HandoffBuildError: LocalizedError, Equatable {

        /// The visit ID and capture session ID do not match.
        case visitSessionMismatch(visitId: String, captureSessionId: String)

        public var errorDescription: String? {
            switch self {
            case .visitSessionMismatch(let v, let c):
                return "Visit ID '\(v)' does not match capture session ID '\(c)'."
            }
        }
    }

    // MARK: - Build

    /// Builds a ``ScanToMindHandoffV1`` from a visit envelope and its linked capture.
    ///
    /// - Parameters:
    ///   - visit: The lifecycle visit that owns this capture session.
    ///   - capture: The ``SessionCaptureV2`` produced for this visit.
    ///   - reason: The reason this handoff is being initiated.
    /// - Returns: A fully-populated ``ScanToMindHandoffV1`` ready for encoding.
    /// - Throws: ``HandoffBuildError/visitSessionMismatch`` when
    ///   `visit.visitId` does not equal `capture.sessionId`.
    static func buildHandoff(
        visit: AtlasScanVisit,
        capture: SessionCaptureV2,
        reason: ScanToMindHandoffReasonV1
    ) throws -> ScanToMindHandoffV1 {
        guard visit.visitId == capture.sessionId else {
            throw HandoffBuildError.visitSessionMismatch(
                visitId: visit.visitId,
                captureSessionId: capture.sessionId
            )
        }

        return ScanToMindHandoffV1(
            visitId: visit.visitId,
            sessionId: capture.sessionId,
            readiness: visit.readiness,
            capture: capture,
            reason: reason,
            exportedAt: iso8601.string(from: Date())
        )
    }

    /// Builds a ``ScanToMindHandoffV1`` directly from a ``CaptureSessionDraft``.
    ///
    /// Uses `draft.id.uuidString` as both `visitId` and `sessionId` (they are
    /// always equal when produced this way, satisfying the contract).  Readiness
    /// is derived from the draft at build time.
    ///
    /// Use this overload when no ``AtlasScanVisit`` lifecycle object is available
    /// (e.g. the review/export screen accessed outside the main visit flow).
    ///
    /// - Parameters:
    ///   - draft: The capture session draft to build the handoff from.
    ///   - capture: The ``SessionCaptureV2`` produced from the same draft.
    ///   - reason: The reason this handoff is being initiated.
    /// - Returns: A fully-populated ``ScanToMindHandoffV1`` ready for encoding.
    static func buildHandoffFromDraft(
        _ draft: CaptureSessionDraft,
        capture: SessionCaptureV2,
        reason: ScanToMindHandoffReasonV1
    ) -> ScanToMindHandoffV1 {
        let sessionId = draft.id.uuidString
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        return ScanToMindHandoffV1(
            visitId: sessionId,
            sessionId: sessionId,
            readiness: readiness,
            capture: capture,
            reason: reason,
            exportedAt: iso8601.string(from: Date())
        )
    }

    // MARK: - Private

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
