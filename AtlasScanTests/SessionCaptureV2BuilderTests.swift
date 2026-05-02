import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - SessionCaptureV2BuilderTests
//
// Tests for SessionCaptureV2Builder — the (visit, draft) → SessionCaptureV2 mapper.
//
// Covers:
//   - Empty draft builds valid SessionCaptureV2
//   - visitId / visitNumber / brandId are carried through
//   - Manual boiler pin produces MANUAL_PIN_CONFIRMED QA flag
//   - LiDAR / inferred pin produces LIDAR_PIN_PENDING_REVIEW QA flag
//   - Object-linked photo produces OBJECT_LINKED_PHOTO QA flag
//   - Transcript contains text only; no audio URI
//   - Floor plan snapshot maps separately from photos
//   - Room scan with LiDAR source produces ROOM_SCAN_LIDAR QA flag
//   - Readiness derives correctly from the built capture

final class SessionCaptureV2BuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeVisit(
        visitNumber: String? = "JOB-BUILDER-TEST",
        brandId: String? = nil
    ) -> AtlasScanVisit {
        AtlasScanVisit(visitNumber: visitNumber, brandId: brandId)
    }

    private func makeDraft(visitReference: String = "JOB-BUILDER-TEST") -> CaptureSessionDraft {
        CaptureSessionStore.newSession(visitReference: visitReference)
    }

    // MARK: - Empty draft

    func test_build_emptyDraft_producesValidCapture() {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        XCTAssertEqual(capture.schemaVersion, currentSessionCaptureVersion)
        XCTAssertTrue(capture.roomScans.isEmpty)
        XCTAssertTrue(capture.photos.isEmpty)
        XCTAssertTrue(capture.voiceNotes.isEmpty)
        XCTAssertTrue(capture.objectPins.isEmpty)
        XCTAssertTrue(capture.floorPlanSnapshots.isEmpty)
    }

    func test_build_emptyDraft_roundTripsAsValidJSON() throws {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let data = try JSONEncoder().encode(capture)
        let result = validateSessionCaptureV2(data)
        XCTAssertTrue(result.isSuccess, "Expected valid payload; errors: \(result.errors)")
    }

    // MARK: - Visit identity fields

    func test_build_sessionIdMatchesVisitId() {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        XCTAssertEqual(capture.sessionId, visit.visitId)
    }

    func test_build_visitReferenceMatchesVisitNumber() {
        let visit = makeVisit(visitNumber: "JOB-VISIT-NUMBER")
        let draft = makeDraft(visitReference: "DRAFT-REFERENCE")
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        // visitNumber takes precedence over draft.visitReference
        XCTAssertEqual(capture.visitReference, "JOB-VISIT-NUMBER")
    }

    func test_build_visitReferenceFromDraftWhenVisitNumberEmpty() {
        let visit = makeVisit(visitNumber: "")
        let draft = makeDraft(visitReference: "DRAFT-REFERENCE")
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        XCTAssertEqual(capture.visitReference, "DRAFT-REFERENCE")
    }

    func test_build_brandIdCarriedThroughAsQAFlag() {
        let visit = makeVisit(brandId: "BRAND-XYZ")
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let brandFlag = capture.qaFlags.first(where: { $0.code == "BRAND_ID" })
        XCTAssertNotNil(brandFlag, "BRAND_ID QA flag expected when brandId is set")
        XCTAssertTrue(brandFlag?.message.contains("BRAND-XYZ") == true)
    }

    func test_build_noBrandIdFlag_whenBrandIdNil() {
        let visit = makeVisit(brandId: nil)
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        XCTAssertFalse(capture.qaFlags.contains(where: { $0.code == "BRAND_ID" }))
    }

    // MARK: - Manual object pin → MANUAL_PIN_CONFIRMED

    func test_build_manualBoilerPin_producesConfirmedFlag() {
        let visit = makeVisit()
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.pinSource = .manual
        draft.objectPins.append(pin)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let flag = capture.qaFlags.first(where: {
            $0.code == "MANUAL_PIN_CONFIRMED" && $0.entityId == pin.id.uuidString
        })
        XCTAssertNotNil(flag, "Manual boiler pin must produce MANUAL_PIN_CONFIRMED flag")
    }

    func test_build_manualPin_withNilSource_producesConfirmedFlag() {
        // A pin with no explicit source defaults to manual/confirmed.
        let visit = makeVisit()
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .radiator)
        pin.pinSource = nil
        draft.objectPins.append(pin)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let flag = capture.qaFlags.first(where: {
            $0.code == "MANUAL_PIN_CONFIRMED" && $0.entityId == pin.id.uuidString
        })
        XCTAssertNotNil(flag, "Pin with nil source must default to MANUAL_PIN_CONFIRMED")
    }

    // MARK: - LiDAR / inferred pin → LIDAR_PIN_PENDING_REVIEW

    func test_build_lidarPin_producesPendingFlag() {
        let visit = makeVisit()
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .radiator)
        pin.pinSource = .lidar
        draft.objectPins.append(pin)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let flag = capture.qaFlags.first(where: {
            $0.code == "LIDAR_PIN_PENDING_REVIEW" && $0.entityId == pin.id.uuidString
        })
        XCTAssertNotNil(flag, "LiDAR pin must produce LIDAR_PIN_PENDING_REVIEW flag")
        XCTAssertEqual(flag?.severity, "warning")
    }

    func test_build_lidarPin_doesNotProduceConfirmedFlag() {
        let visit = makeVisit()
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .cylinder)
        pin.pinSource = .lidar
        draft.objectPins.append(pin)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertFalse(capture.qaFlags.contains(where: {
            $0.code == "MANUAL_PIN_CONFIRMED" && $0.entityId == pin.id.uuidString
        }), "LiDAR pin must not produce MANUAL_PIN_CONFIRMED flag")
    }

    // MARK: - Object-linked photo

    func test_build_objectLinkedPhoto_producesQAFlag() {
        let visit = makeVisit()
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "boiler.jpg")
        photo.linkedObjectId = UUID()
        draft.photos.append(photo)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let flag = capture.qaFlags.first(where: {
            $0.code == "OBJECT_LINKED_PHOTO" && $0.entityId == photo.id.uuidString
        })
        XCTAssertNotNil(flag, "Object-linked photo must produce OBJECT_LINKED_PHOTO flag")
    }

    func test_build_nonLinkedPhoto_noObjectLinkedPhotoFlag() {
        let visit = makeVisit()
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "overview.jpg")
        photo.linkedObjectId = nil
        draft.photos.append(photo)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertFalse(capture.qaFlags.contains(where: {
            $0.code == "OBJECT_LINKED_PHOTO" && $0.entityId == photo.id.uuidString
        }))
    }

    // MARK: - Transcript: text only, no audio URI

    func test_build_voiceNote_transcriptTextOnly() {
        let visit = makeVisit()
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "The boiler is located in the kitchen."
        draft.voiceNotes.append(note)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertEqual(capture.voiceNotes.count, 1)
        XCTAssertEqual(capture.voiceNotes.first?.transcript, "The boiler is located in the kitchen.")
    }

    func test_build_voiceNote_noAudioURIInJSON() throws {
        let visit = makeVisit()
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Test transcript"
        draft.voiceNotes.append(note)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let data = try JSONEncoder().encode(capture)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains(".m4a"), "m4a audio path must not appear in capture")
        XCTAssertFalse(json.contains(".mp3"), "mp3 audio path must not appear in capture")
        XCTAssertFalse(json.contains(".wav"), "wav audio path must not appear in capture")
        XCTAssertFalse(json.contains("rawAudio"), "rawAudio field must not appear in capture")
        XCTAssertFalse(json.contains("audioPath"), "audioPath field must not appear in capture")
    }

    // MARK: - Floor plan snapshots (point cloud / 3D assets)

    func test_build_floorPlanSnapshot_mapsToFloorPlanSnapshots_notPhotos() {
        let visit = makeVisit()
        var draft = makeDraft()
        let snapshot = CapturedFloorPlanSnapshotDraft(imageRef: "floorplan_scan.png")
        draft.floorPlanSnapshots.append(snapshot)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertEqual(capture.floorPlanSnapshots.count, 1)
        XCTAssertEqual(capture.floorPlanSnapshots.first?.imageRef, "floorplan_scan.png")
        // Snapshots must NOT appear in the photos array
        XCTAssertTrue(capture.photos.isEmpty)
    }

    func test_build_floorPlanSnapshot_idPreserved() {
        let visit = makeVisit()
        var draft = makeDraft()
        let snapshot = CapturedFloorPlanSnapshotDraft(imageRef: "fp.png")
        draft.floorPlanSnapshots.append(snapshot)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertEqual(capture.floorPlanSnapshots.first?.id, snapshot.id.uuidString)
    }

    // MARK: - Room scan mapping

    func test_build_lidarRoomScan_producesQAFlag() {
        let visit = makeVisit()
        var draft = makeDraft()
        var scan = CapturedRoomScanDraft()
        scan.captureSource = .lidar
        draft.roomScans.append(scan)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let flag = capture.qaFlags.first(where: {
            $0.code == "ROOM_SCAN_LIDAR" && $0.entityId == scan.id.uuidString
        })
        XCTAssertNotNil(flag, "LiDAR room scan must produce ROOM_SCAN_LIDAR QA flag")
    }

    func test_build_manualRoomScan_noLidarFlag() {
        let visit = makeVisit()
        var draft = makeDraft()
        var scan = CapturedRoomScanDraft()
        scan.captureSource = .manual
        draft.roomScans.append(scan)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertFalse(capture.qaFlags.contains(where: {
            $0.code == "ROOM_SCAN_LIDAR" && $0.entityId == scan.id.uuidString
        }))
    }

    // MARK: - Pipe route via floor plan data

    func test_build_roomScanWithFloorPlan_encodesFloorPlanData() throws {
        let visit = makeVisit()
        var draft = makeDraft()
        var scan = CapturedRoomScanDraft()
        var floorPlan = FloorPlanDraft()
        var segment = PipeSegmentDraft()
        segment.pipeType = .heating
        floorPlan.pipeSegments.append(segment)
        scan.floorPlan = floorPlan
        draft.roomScans.append(scan)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let exportedScan = try XCTUnwrap(capture.roomScans.first)
        XCTAssertNotNil(exportedScan.floorPlanData, "Floor plan data (incl. pipe segments) must be encoded")
    }

    func test_build_floorPlanData_decodesBackToFloorPlanDraft() throws {
        let visit = makeVisit()
        var draft = makeDraft()
        var scan = CapturedRoomScanDraft()
        var floorPlan = FloorPlanDraft()
        var segment = PipeSegmentDraft()
        segment.pipeType = .gas
        segment.start = NormalisedPoint(x: 0.1, y: 0.2)
        segment.end = NormalisedPoint(x: 0.8, y: 0.9)
        floorPlan.pipeSegments.append(segment)
        scan.floorPlan = floorPlan
        draft.roomScans.append(scan)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let exportedScan = try XCTUnwrap(capture.roomScans.first)
        let base64 = try XCTUnwrap(exportedScan.floorPlanData)
        let decoded = try XCTUnwrap(Data(base64Encoded: base64))
        let roundTripped = try JSONDecoder().decode(FloorPlanDraft.self, from: decoded)

        XCTAssertEqual(roundTripped.pipeSegments.count, 1)
        XCTAssertEqual(roundTripped.pipeSegments.first?.pipeType, .gas)
    }

    // MARK: - Schema version

    func test_build_schemaVersionIsCurrent() {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        XCTAssertEqual(capture.schemaVersion, currentSessionCaptureVersion)
        XCTAssertTrue(supportedSessionCaptureVersions.contains(capture.schemaVersion))
    }

    // MARK: - Readiness derives from built capture

    func test_readiness_derivesFromDraft_emptyIsFalse() {
        let draft = makeDraft()
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertFalse(readiness.hasRooms)
        XCTAssertFalse(readiness.hasPhotos)
        XCTAssertFalse(readiness.hasBoiler)
    }

    func test_readiness_boilerPinSetsTrueFlags() {
        var draft = makeDraft()
        draft.objectPins.append(CapturedObjectPinDraft(type: .boiler))
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertTrue(readiness.hasBoiler)
        XCTAssertTrue(readiness.hasHeatingSystem)
    }
}
