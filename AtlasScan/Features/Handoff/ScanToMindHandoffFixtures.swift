#if DEBUG
import Foundation
import AtlasContracts

enum ScanToMindHandoffFixtures {
    static let complete: ScanToMindHandoffV1 = makeComplete()
    static let incompleteDraft: ScanToMindHandoffV1 = makeIncompleteDraft()

    private static func makeComplete() -> ScanToMindHandoffV1 {
        let roomId = UUID().uuidString
        let capturePointId = UUID().uuidString
        let visitId = UUID().uuidString
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let readiness = VisitReadinessV1(
            hasRooms: true,
            hasPhotos: true,
            hasHeatingSystem: true,
            hasHotWaterSystem: true,
            hasBoiler: true,
            hasFlue: true,
            hasNotes: true
        )
        let visit = HandoffVisitSnapshotV1(
            visitId: visitId,
            visitNumber: "JOB-PREVIEW-COMPLETE",
            brandId: nil,
            status: VisitLifecycleStatus.complete.rawValue,
            readiness: readiness,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let capture = SessionCaptureV2(
            schemaVersion: currentSessionCaptureVersion,
            sessionId: visitId,
            visitReference: "JOB-PREVIEW-COMPLETE",
            capturedAt: timestamp,
            exportedAt: timestamp,
            deviceModel: "iPhone Preview",
            roomScans: [
                CapturedRoomScanV2(
                    id: roomId,
                    roomLabel: "Kitchen",
                    captureTimestamp: timestamp,
                    previewImageRef: "kitchen.jpg",
                    rawScanAssetRef: nil,
                    rawWidthM: 4.2,
                    rawDepthM: 3.6,
                    rawHeightM: 2.4,
                    localTransformOrigin: nil,
                    warnings: [],
                    confidence: .high
                )
            ],
            photos: [
                CapturedPhotoV2(
                    id: UUID().uuidString,
                    localFilename: "overview.jpg",
                    captureTimestamp: timestamp,
                    roomId: roomId,
                    capturePointId: capturePointId,
                    linkedObjectId: nil,
                    anchorConfidence: "high",
                    kind: "overview"
                )
            ],
            voiceNotes: [
                CapturedVoiceNoteV2(
                    id: UUID().uuidString,
                    transcript: "Boiler and flue confirmed.",
                    startedAt: timestamp,
                    endedAt: timestamp,
                    roomId: roomId,
                    capturePointId: capturePointId,
                    linkedObjectId: nil,
                    anchorConfidence: "high"
                )
            ],
            objectPins: [
                CapturedObjectPinV2(
                    id: UUID().uuidString,
                    type: "boiler",
                    label: "Main boiler",
                    roomId: roomId,
                    visitId: visitId,
                    capturePointId: capturePointId,
                    linkedPhotoId: nil,
                    approximatePositionRef: nil,
                    anchorConfidence: "high",
                    surfaceSemantic: "wall",
                    reviewStatus: "confirmed",
                    provenance: "manual_capture"
                ),
                CapturedObjectPinV2(
                    id: UUID().uuidString,
                    type: "flue",
                    label: "Rear flue",
                    roomId: roomId,
                    visitId: visitId,
                    capturePointId: capturePointId,
                    linkedPhotoId: nil,
                    approximatePositionRef: nil,
                    anchorConfidence: "high",
                    surfaceSemantic: "external_wall",
                    reviewStatus: "confirmed",
                    provenance: "manual_capture"
                )
            ],
            floorPlanSnapshots: [],
            qaFlags: []
        )

        return ScanToMindHandoffV1(
            visit: visit,
            capture: capture,
            reason: .completedCapture,
            exportedAt: timestamp
        )
    }

    private static func makeIncompleteDraft() -> ScanToMindHandoffV1 {
        let roomId = UUID().uuidString
        let capturePointId = UUID().uuidString
        let visitId = UUID().uuidString
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let readiness = VisitReadinessV1(
            hasRooms: true,
            hasPhotos: true,
            hasHeatingSystem: false,
            hasHotWaterSystem: false,
            hasBoiler: false,
            hasFlue: false,
            hasNotes: false
        )
        let visit = HandoffVisitSnapshotV1(
            visitId: visitId,
            visitNumber: "JOB-PREVIEW-INCOMPLETE",
            brandId: nil,
            status: VisitLifecycleStatus.capturing.rawValue,
            readiness: readiness,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let capture = SessionCaptureV2(
            schemaVersion: currentSessionCaptureVersion,
            sessionId: visitId,
            visitReference: "JOB-PREVIEW-INCOMPLETE",
            capturedAt: timestamp,
            exportedAt: timestamp,
            deviceModel: "iPhone Preview",
            roomScans: [
                CapturedRoomScanV2(
                    id: roomId,
                    roomLabel: "Utility",
                    captureTimestamp: timestamp,
                    previewImageRef: "utility.jpg",
                    rawScanAssetRef: nil,
                    rawWidthM: 1.2,
                    rawDepthM: nil,
                    rawHeightM: nil,
                    localTransformOrigin: nil,
                    warnings: [
                        ScanQAFlag(
                            code: "UNSTABLE_GEOMETRY",
                            message: "Room shape needs review.",
                            severity: "warning",
                            entityId: roomId
                        )
                    ],
                    confidence: .low
                )
            ],
            photos: [
                CapturedPhotoV2(
                    id: UUID().uuidString,
                    localFilename: "partial-overview.jpg",
                    captureTimestamp: timestamp,
                    roomId: roomId,
                    capturePointId: capturePointId,
                    linkedObjectId: nil,
                    anchorConfidence: "screen_only",
                    needsReview: true,
                    kind: "overview"
                )
            ],
            voiceNotes: [
                CapturedVoiceNoteV2(
                    id: UUID().uuidString,
                    transcript: "",
                    startedAt: timestamp,
                    endedAt: timestamp,
                    roomId: roomId,
                    capturePointId: capturePointId,
                    linkedObjectId: nil,
                    anchorConfidence: "screen_only",
                    needsReview: true
                )
            ],
            objectPins: [
                CapturedObjectPinV2(
                    id: UUID().uuidString,
                    type: "generic_note",
                    label: nil,
                    roomId: roomId,
                    visitId: visitId,
                    capturePointId: capturePointId,
                    linkedPhotoId: nil,
                    approximatePositionRef: nil,
                    anchorConfidence: "screen_only",
                    needsReview: true,
                    reviewStatus: "needs_review",
                    provenance: "room_scan_inference"
                )
            ],
            floorPlanSnapshots: [],
            qaFlags: [
                ScanQAFlag(
                    code: "UNSTABLE_GEOMETRY",
                    message: "Room shape needs review.",
                    severity: "warning",
                    entityId: roomId
                )
            ]
        )

        return ScanToMindHandoffV1(
            visit: visit,
            capture: capture,
            reason: .reviewInMind,
            exportedAt: timestamp,
            missingEvidence: readiness.missingItems
        )
    }
}
#endif
