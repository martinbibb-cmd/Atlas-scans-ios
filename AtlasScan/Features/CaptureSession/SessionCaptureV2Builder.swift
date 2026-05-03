import Foundation
import AtlasContracts
#if canImport(UIKit)
import UIKit
#endif

// MARK: - SessionCaptureV2Builder
//
// Maps a (AtlasScanVisit, CaptureSessionDraft) pair to the canonical
// SessionCaptureV2 handoff payload.
//
// Rules:
//   • Visit identity (visitId, visitNumber) takes precedence over draft fields.
//   • Raw audio filenames must NOT appear in the exported payload.
//   • Manual object pins are flagged as confirmed; LiDAR/inferred pins are
//     flagged as pending review.
//   • Object-linked photos receive a QA annotation.
//   • Floor plan snapshots are kept separate from evidence photos.
//   • This builder is pure (no side effects) and testable without a running app.

enum SessionCaptureV2Builder {

    // MARK: - Build

    /// Builds a ``SessionCaptureV2`` from a visit lifecycle envelope and its
    /// linked capture draft.
    ///
    /// - Parameters:
    ///   - visit: The lifecycle visit that owns this capture session.
    ///   - draft:  The draft artefacts collected during the visit.
    /// - Returns: A fully-populated ``SessionCaptureV2`` ready for persistence.
    static func buildSessionCaptureV2(
        visit: AtlasScanVisit,
        draft: CaptureSessionDraft
    ) -> SessionCaptureV2 {
        let now = iso8601.string(from: Date())

        // Visit-level identity takes precedence over the draft's own reference,
        // which may be stale or empty if the visit was created externally.
        let visitReference = visit.visitNumber?.trimmingCharacters(in: .whitespaces)
            .isEmpty == false
            ? visit.visitNumber!
            : draft.visitReference

        return SessionCaptureV2(
            schemaVersion: currentSessionCaptureVersion,
            sessionId: visit.visitId,
            visitReference: visitReference,
            appointmentId: draft.appointmentId,
            propertyAddress: draft.propertyAddress.isEmpty ? nil : draft.propertyAddress,
            customerName: draft.customerName.isEmpty ? nil : draft.customerName,
            capturedAt: iso8601.string(from: visit.createdAt),
            exportedAt: now,
            deviceModel: deviceModel(),
            roomScans: draft.roomScans.map(mapRoomScan),
            photos: draft.photos.map(mapPhoto),
            voiceNotes: draft.voiceNotes.map(mapVoiceNote),
            objectPins: draft.objectPins.map(mapObjectPin),
            floorPlanSnapshots: draft.floorPlanSnapshots.map(mapFloorPlanSnapshot),
            floorPlanFabric: mapFloorPlanFabric(draft),
            hazardObservations: mapHazardObservations(draft),
            quotePlannerEvidence: mapQuotePlannerEvidence(draft),
            qaFlags: buildQAFlags(visit: visit, draft: draft)
        )
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

    // MARK: - Floor plan fabric mapping

    /// Maps fabric draft records to the ``FloorPlanFabricCaptureV1`` contract.
    ///
    /// Returns nil when no fabric records exist (keeping the payload backward-compatible).
    private static func mapFloorPlanFabric(_ draft: CaptureSessionDraft) -> FloorPlanFabricCaptureV1? {
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

            // Derive perimeter from confirmed boundary lengths.
            let perimeterM: Double? = {
                let confirmedLengths = record.boundaries
                    .filter { $0.reviewStatus == .confirmed }
                    .compactMap(\.lengthM)
                return confirmedLengths.isEmpty ? nil : confirmedLengths.reduce(0, +)
            }()

            // Carry known room dimensions from the linked room scan.
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
    ///
    /// Returns nil when no hazard observations exist.
    private static func mapHazardObservations(
        _ draft: CaptureSessionDraft
    ) -> [HazardObservationCaptureV1]? {
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

    /// Maps quote-planner anchor drafts to ``QuotePlannerEvidenceV1``.
    ///
    /// Returns nil when no anchors exist (keeping the payload backward-compatible).
    private static func mapQuotePlannerEvidence(
        _ draft: CaptureSessionDraft
    ) -> QuotePlannerEvidenceV1? {
        guard !draft.quotePlannerAnchors.isEmpty else { return nil }

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

        return QuotePlannerEvidenceV1(candidateLocations: locations)
    }

    // MARK: - QA flags

    private static func buildQAFlags(visit: AtlasScanVisit, draft: CaptureSessionDraft) -> [ScanQAFlag] {
        var flags: [ScanQAFlag] = []

        // Carry brandId as an info annotation (not a first-class SessionCaptureV2 field).
        if let brandId = visit.brandId, !brandId.isEmpty {
            flags.append(ScanQAFlag(
                code: "BRAND_ID",
                message: "brandId: \(brandId)",
                severity: "info"
            ))
        }

        // LiDAR room scans: mark scan provenance.
        for scan in draft.roomScans where scan.captureSource == .lidar {
            flags.append(ScanQAFlag(
                code: "ROOM_SCAN_LIDAR",
                message: "Room scan captured via LiDAR; provenance: scan.",
                severity: "info",
                entityId: scan.id.uuidString
            ))
        }

        // Single pass over objectPins for provenance and label flags.
        var hasUnlabelledGenericPin = false
        for pin in draft.objectPins {
            switch pin.pinSource {
            case .manual, .none:
                if pin.pinConfidence == .needsReview {
                    flags.append(ScanQAFlag(
                        code: "PIN_NEEDS_REVIEW",
                        message: "Object pin '\(pin.type.rawValue)' is flagged as needing review.",
                        severity: "warning",
                        entityId: pin.id.uuidString
                    ))
                } else {
                    flags.append(ScanQAFlag(
                        code: "MANUAL_PIN_CONFIRMED",
                        message: "Object pin '\(pin.type.rawValue)' placed manually; provenance: confirmed.",
                        severity: "info",
                        entityId: pin.id.uuidString
                    ))
                }
            case .lidar:
                flags.append(ScanQAFlag(
                    code: "LIDAR_PIN_PENDING_REVIEW",
                    message: "Object pin '\(pin.type.rawValue)' inferred from LiDAR scan; review required before handoff.",
                    severity: "warning",
                    entityId: pin.id.uuidString
                ))
            }
            if pin.type == .genericNote && pin.hasNoLabel {
                hasUnlabelledGenericPin = true
            }
        }
        if hasUnlabelledGenericPin {
            flags.append(ScanQAFlag(
                code: "GENERIC_PIN_NO_LABEL",
                message: "One or more generic note pins have no label.",
                severity: "info"
            ))
        }

        // Single pass over photos for object-link annotations.
        for photo in draft.photos where photo.linkedObjectId != nil {
            flags.append(ScanQAFlag(
                code: "OBJECT_LINKED_PHOTO",
                message: "Photo '\(photo.localFilename)' is linked to an object pin; exclude from customer report.",
                severity: "info",
                entityId: photo.id.uuidString
            ))
        }

        // Single pass over voice notes for missing-transcript flags.
        var hasUntranscribedNote = false
        for note in draft.voiceNotes where note.transcript.trimmingCharacters(in: .whitespaces).isEmpty {
            hasUntranscribedNote = true
            break
        }
        if hasUntranscribedNote {
            flags.append(ScanQAFlag(
                code: "VOICE_NOTE_NO_TRANSCRIPT",
                message: "One or more voice notes have no transcript.",
                severity: "warning"
            ))
        }

        return flags
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
