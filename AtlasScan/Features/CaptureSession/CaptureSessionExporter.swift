import Foundation
import AtlasContracts
#if canImport(UIKit)
import UIKit
#endif

// MARK: - CaptureSessionExporter
//
// Maps a CaptureSessionDraft to the canonical SessionCaptureV2 handoff payload.
//
// Rules:
//   • Raw audio filenames must NOT appear in the exported payload.
//   • Transcript text is included; audio paths are excluded.
//   • Only artefacts present in the draft are exported.
//   • The exporter validates before export and returns useful errors.
//   • The exporter is pure (no side effects) and testable without a running app.

// MARK: - Export errors

enum CaptureExportError: LocalizedError, Equatable {
    case missingVisitReference
    case noRoomScans
    case emptyPayload

    var errorDescription: String? {
        switch self {
        case .missingVisitReference:
            return "A visit reference is required before exporting."
        case .noRoomScans:
            return "At least one room scan must be captured before exporting."
        case .emptyPayload:
            return "No capture data found. The session appears to be empty."
        }
    }
}

// MARK: - Export result

struct CaptureExportResult {
    /// The exported payload, ready for handoff to Atlas Mind.
    let payload: SessionCaptureV2
    /// The JSON-encoded representation of the payload.
    let jsonData: Data
}

// MARK: - CaptureSessionExporter

enum CaptureSessionExporter {

    // MARK: - Validate

    /// Validates the draft before export.
    ///
    /// Returns a list of blocking errors. An empty array means export is safe.
    static func validate(_ draft: CaptureSessionDraft) -> [CaptureExportError] {
        var errors: [CaptureExportError] = []

        if draft.visitReference.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.missingVisitReference)
        }

        if draft.roomScans.isEmpty && draft.photos.isEmpty && draft.voiceNotes.isEmpty && draft.objectPins.isEmpty {
            errors.append(.emptyPayload)
        }

        return errors
    }

    // MARK: - Export

    /// Exports the draft to a `SessionCaptureV2` payload.
    ///
    /// Returns a `CaptureExportResult` on success, or throws a `CaptureExportError`
    /// if blocking validation issues exist.
    static func export(_ draft: CaptureSessionDraft) throws -> CaptureExportResult {
        let errors = validate(draft)
        if let first = errors.first {
            throw first
        }

        let payload = buildPayload(from: draft)
        let jsonData = try encode(payload)

        return CaptureExportResult(payload: payload, jsonData: jsonData)
    }

    // MARK: - Build payload

    private static func buildPayload(from draft: CaptureSessionDraft) -> SessionCaptureV2 {
        let now = iso8601.string(from: Date())

        return SessionCaptureV2(
            schemaVersion: currentSessionCaptureVersion,
            sessionId: draft.id.uuidString,
            visitReference: draft.visitReference,
            capturedAt: iso8601.string(from: draft.capturedAt),
            exportedAt: now,
            deviceModel: deviceModel(),
            roomScans: draft.roomScans.map(mapRoomScan),
            photos: draft.photos.map(mapPhoto),
            voiceNotes: draft.voiceNotes.map(mapVoiceNote),
            objectPins: draft.objectPins.map(mapObjectPin),
            floorPlanSnapshots: draft.floorPlanSnapshots.map(mapFloorPlanSnapshot),
            qaFlags: buildQAFlags(from: draft)
        )
    }

    // MARK: - Room scan mapping

    private static func mapRoomScan(_ scan: CapturedRoomScanDraft) -> CapturedRoomScanV2 {
        let warnings: [ScanQAFlag] = scan.warningCodes.map { code in
            ScanQAFlag(code: code, message: code, severity: "warning", entityId: scan.id.uuidString)
        }

        return CapturedRoomScanV2(
            id: scan.id.uuidString,
            roomLabel: scan.roomLabel,
            captureTimestamp: iso8601.string(from: scan.captureTimestamp),
            previewImageRef: scan.previewImageRef,
            rawScanAssetRef: scan.rawScanAssetRef,
            rawWidthM: scan.rawWidthM,
            rawDepthM: scan.rawDepthM,
            rawHeightM: scan.rawHeightM,
            localTransformOrigin: nil,
            warnings: warnings,
            confidence: mapConfidence(scan.confidence)
        )
    }

    private static func mapConfidence(_ confidence: RoomScanConfidence) -> ScanConfidenceBand {
        switch confidence {
        case .high:   return .high
        case .medium: return .medium
        case .low:    return .low
        }
    }

    // MARK: - Photo mapping

    private static func mapPhoto(_ photo: CapturedPhotoDraft) -> CapturedPhotoV2 {
        CapturedPhotoV2(
            id: photo.id.uuidString,
            localFilename: photo.localFilename,
            captureTimestamp: iso8601.string(from: photo.captureTimestamp),
            roomId: photo.roomId?.uuidString,
            linkedObjectId: photo.linkedObjectId?.uuidString,
            kind: photo.kind.rawValue
        )
    }

    // MARK: - Voice note mapping

    // IMPORTANT: Raw audio filenames are intentionally excluded.
    // Only transcript text crosses the Scan → Mind boundary.
    private static func mapVoiceNote(_ note: CapturedVoiceNoteDraft) -> CapturedVoiceNoteV2 {
        CapturedVoiceNoteV2(
            id: note.id.uuidString,
            transcript: note.transcript,
            startedAt: iso8601.string(from: note.startedAt),
            endedAt: note.endedAt.map { iso8601.string(from: $0) },
            roomId: note.roomId?.uuidString,
            linkedObjectId: note.linkedObjectId?.uuidString
        )
    }

    // MARK: - Object pin mapping

    private static func mapObjectPin(_ pin: CapturedObjectPinDraft) -> CapturedObjectPinV2 {
        var position: ScanPoint3D?
        if let x = pin.approximatePositionX,
           let y = pin.approximatePositionY,
           let z = pin.approximatePositionZ {
            position = ScanPoint3D(x: x, y: y, z: z)
        }

        return CapturedObjectPinV2(
            id: pin.id.uuidString,
            type: pin.type.rawValue,
            label: pin.label,
            roomId: pin.roomId?.uuidString,
            linkedPhotoId: pin.linkedPhotoId?.uuidString,
            approximatePositionRef: position
        )
    }

    // MARK: - Floor plan snapshot mapping

    private static func mapFloorPlanSnapshot(_ snapshot: CapturedFloorPlanSnapshotDraft) -> CapturedFloorPlanSnapshotV2 {
        CapturedFloorPlanSnapshotV2(
            id: snapshot.id.uuidString,
            imageRef: snapshot.imageRef,
            captureTimestamp: iso8601.string(from: snapshot.captureTimestamp),
            roomId: snapshot.roomId?.uuidString
        )
    }

    // MARK: - QA flags

    private static func buildQAFlags(from draft: CaptureSessionDraft) -> [ScanQAFlag] {
        var flags: [ScanQAFlag] = []

        if draft.voiceNotes.contains(where: { $0.transcript.trimmingCharacters(in: .whitespaces).isEmpty }) {
            flags.append(ScanQAFlag(
                code: "VOICE_NOTE_NO_TRANSCRIPT",
                message: "One or more voice notes have no transcript.",
                severity: "warning"
            ))
        }

        if draft.objectPins.contains(where: { ($0.label ?? "").trimmingCharacters(in: .whitespaces).isEmpty && $0.type == .genericNote }) {
            flags.append(ScanQAFlag(
                code: "GENERIC_PIN_NO_LABEL",
                message: "One or more generic note pins have no label.",
                severity: "info"
            ))
        }

        return flags
    }

    // MARK: - Encode

    /// Encodes a `SessionCaptureV2` to JSON data.
    static func encode(_ payload: SessionCaptureV2) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    // MARK: - Device model

    private static func deviceModel() -> String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "Unknown"
        #endif
    }

    // MARK: - ISO-8601 formatter (cached)

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
