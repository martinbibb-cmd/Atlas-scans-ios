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
            appointmentId: draft.appointmentId,
            propertyAddress: draft.propertyAddress.isEmpty ? nil : draft.propertyAddress,
            customerName: draft.customerName.isEmpty ? nil : draft.customerName,
            capturedAt: iso8601.string(from: draft.capturedAt),
            exportedAt: now,
            deviceModel: deviceModel(),
            roomScans: draft.roomScans.map(mapRoomScan),
            photos: draft.photos.map(mapPhoto),
            voiceNotes: draft.voiceNotes.map(mapVoiceNote),
            objectPins: draft.objectPins.map(mapObjectPin),
            floorPlanSnapshots: draft.floorPlanSnapshots.map(mapFloorPlanSnapshot),
            floorPlanFabric: mapFloorPlanFabric(from: draft),
            hazardObservations: mapHazardObservations(from: draft),
            quotePlannerEvidence: mapQuotePlannerEvidence(from: draft),
            qaFlags: buildQAFlags(from: draft)
        )
    }

    // MARK: - Floor plan fabric mapping

    /// Maps fabric draft records to ``FloorPlanFabricCaptureV1``.
    /// Returns nil when no fabric records exist (backward-compatible).
    private static func mapFloorPlanFabric(from draft: CaptureSessionDraft) -> FloorPlanFabricCaptureV1? {
        guard !draft.fabricRecords.isEmpty else { return nil }

        let roomLookup: [UUID: String] = Dictionary(
            uniqueKeysWithValues: draft.roomScans.compactMap { scan in
                guard let label = scan.roomLabel else { return nil }
                return (scan.id, label)
            }
        )

        let rooms: [RoomFabricCaptureV1] = draft.fabricRecords.map { record in
            let boundaries = record.boundaries.map { b in
                BoundaryCaptureV1(
                    id: b.id.uuidString,
                    boundaryType: b.boundaryType.rawValue,
                    lengthM: b.lengthM,
                    heightM: b.heightM,
                    material: b.material,
                    reviewStatus: b.reviewStatus.rawValue
                )
            }
            let openings = record.openings.map { o in
                OpeningCaptureV1(
                    id: o.id.uuidString,
                    openingType: o.openingType.rawValue,
                    widthM: o.widthM,
                    heightM: o.heightM,
                    material: o.material,
                    linkedBoundaryId: o.linkedBoundaryId?.uuidString,
                    reviewStatus: o.reviewStatus.rawValue
                )
            }

            let perimeterM: Double? = {
                let confirmedLengths = record.boundaries
                    .filter { $0.reviewStatus == .confirmed }
                    .compactMap(\.lengthM)
                return confirmedLengths.isEmpty ? nil : confirmedLengths.reduce(0, +)
            }()

            let linkedScan = record.roomId.flatMap { id in
                draft.roomScans.first(where: { $0.id == id })
            }

            return RoomFabricCaptureV1(
                roomId: record.roomId?.uuidString,
                roomLabel: record.roomId.flatMap { roomLookup[$0] },
                perimeterM: perimeterM,
                areaM2: linkedScan?.rawWidthM.flatMap { w in linkedScan?.rawDepthM.map { d in w * d } },
                heightM: linkedScan?.rawHeightM,
                boundaries: boundaries,
                openings: openings
            )
        }

        return FloorPlanFabricCaptureV1(rooms: rooms)
    }

    // MARK: - Hazard observation mapping

    /// Maps hazard observation drafts to ``HazardObservationCaptureV1`` records.
    /// Returns nil when no observations exist.
    private static func mapHazardObservations(from draft: CaptureSessionDraft) -> [HazardObservationCaptureV1]? {
        guard !draft.hazardObservations.isEmpty else { return nil }

        return draft.hazardObservations.map { h in
            HazardObservationCaptureV1(
                id: h.id.uuidString,
                category: h.category.rawValue,
                severity: h.severity.rawValue,
                title: h.title,
                description: h.descriptionText.isEmpty ? nil : h.descriptionText,
                linkedPhotoIds: h.linkedPhotoIds.map(\.uuidString),
                linkedObjectPinIds: h.linkedObjectPinIds.map(\.uuidString),
                actionRequired: h.actionRequired,
                reviewStatus: h.reviewStatus.rawValue
            )
        }
    }

    // MARK: - Quote planner evidence mapping

    /// Maps quote-planner anchor and route drafts to ``QuotePlannerEvidenceV1``.
    /// Returns nil when no anchors or routes exist (backward-compatible).
    private static func mapQuotePlannerEvidence(from draft: CaptureSessionDraft) -> QuotePlannerEvidenceV1? {
        guard !draft.quotePlannerAnchors.isEmpty || !draft.candidateRoutes.isEmpty else { return nil }

        let locations = draft.quotePlannerAnchors.map { anchor -> CandidateLocationAnchorV1 in
            var coordinates: ScanPoint3D?
            if let x = anchor.coordinateX,
               let y = anchor.coordinateY,
               let z = anchor.coordinateZ {
                coordinates = ScanPoint3D(x: x, y: y, z: z)
            }

            return CandidateLocationAnchorV1(
                id: anchor.id.uuidString,
                kind: anchor.kind.rawValue,
                label: anchor.label,
                roomId: anchor.roomId?.uuidString,
                coordinates: coordinates,
                linkedPhotoIds: anchor.linkedPhotoIds.map(\.uuidString),
                linkedObjectPinIds: anchor.linkedObjectPinIds.map(\.uuidString),
                confidence: anchor.provenance.defaultConfidence,
                provenance: anchor.provenance.rawValue
            )
        }

        let routes = draft.candidateRoutes.map { route -> CandidateRouteV1 in
            let waypoints = route.waypoints.map { wp -> RouteWaypointV1 in
                var coordinates: ScanPoint3D?
                if let x = wp.coordinateX, let y = wp.coordinateY, let z = wp.coordinateZ {
                    coordinates = ScanPoint3D(x: x, y: y, z: z)
                }
                return RouteWaypointV1(
                    id: wp.id.uuidString,
                    coordinates: coordinates,
                    planX: wp.planX,
                    planY: wp.planY,
                    label: wp.label
                )
            }
            return CandidateRouteV1(
                id: route.id.uuidString,
                routeType: route.routeType.rawValue,
                status: route.status.rawValue,
                installMethod: route.installMethod?.rawValue,
                startAnchorId: route.startAnchorId?.uuidString,
                endAnchorId: route.endAnchorId?.uuidString,
                waypoints: waypoints,
                notes: route.notes.isEmpty ? nil : route.notes,
                confidence: route.provenance.defaultConfidence,
                provenance: route.provenance.rawValue,
                linkedPhotoIds: route.linkedPhotoIds.map(\.uuidString),
                reviewStatus: route.reviewStatus.rawValue
            )
        }

        return QuotePlannerEvidenceV1(candidateLocations: locations, candidateRoutes: routes)
    }

    // MARK: - Room scan mapping

    private static func mapRoomScan(_ scan: CapturedRoomScanDraft) -> CapturedRoomScanV2 {
        let warnings: [ScanQAFlag] = scan.warningCodes.map { code in
            ScanQAFlag(code: code, message: code, severity: "warning", entityId: scan.id.uuidString)
        }

        let floorPlanData: String? = scan.floorPlan.flatMap { plan in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try? encoder.encode(plan).base64EncodedString()
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
            confidence: mapConfidence(scan.confidence),
            floorPlanData: floorPlanData
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

        if draft.objectPins.contains(where: { $0.hasNoLabel && $0.type == .genericNote }) {
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
