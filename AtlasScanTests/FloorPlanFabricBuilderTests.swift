import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - FloorPlanFabricBuilderTests
//
// Tests for the floor-plan fabric and hazard capture shell wired into
// SessionCaptureV2Builder.
//
// Covers:
//   - Builder maps fabric capture into floorPlanFabric
//   - Builder maps hazard observations into hazardObservations
//   - Nil fabric / nil hazards when no records exist
//   - Rejected / pending / confirmed states persist through the builder
//   - Suspected asbestos category maps correctly
//   - Unknown material maps correctly (nil)
//   - No heat-loss output generated
//   - No risk score generated
//   - hasFabricMeasurements / hasHazardObservations optional indicators
//   - Completion still works without fabric / hazard data

final class FloorPlanFabricBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeVisit() -> AtlasScanVisit {
        AtlasScanVisit(visitNumber: "JOB-FAB-TEST")
    }

    private func makeDraft() -> CaptureSessionDraft {
        CaptureSessionStore.newSession(visitReference: "JOB-FAB-TEST")
    }

    // MARK: - Nil when no fabric records

    func test_build_noFabricRecords_floorPlanFabricIsNil() {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        XCTAssertNil(capture.floorPlanFabric, "floorPlanFabric must be nil when no fabric records exist")
    }

    // MARK: - Nil when no hazard observations

    func test_build_noHazards_hazardObservationsIsNil() {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        XCTAssertNil(capture.hazardObservations, "hazardObservations must be nil when no hazards exist")
    }

    // MARK: - Fabric capture is mapped

    func test_build_fabricRecord_mapsToFloorPlanFabric() {
        let visit = makeVisit()
        var draft = makeDraft()

        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.boundaryType = .external
        boundary.lengthM = 4.5
        boundary.heightM = 2.4
        boundary.material = "solid brick"
        record.boundaries.append(boundary)

        var opening = CapturedOpeningDraft()
        opening.openingType = .window
        opening.widthM = 1.2
        opening.heightM = 1.0
        opening.material = "double glazed uPVC"
        record.openings.append(opening)

        draft.fabricRecords.append(record)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertNotNil(capture.floorPlanFabric, "floorPlanFabric must be populated")
        XCTAssertEqual(capture.floorPlanFabric?.rooms.count, 1)

        let room = capture.floorPlanFabric?.rooms.first
        XCTAssertEqual(room?.boundaries.count, 1)
        XCTAssertEqual(room?.openings.count, 1)

        let exportedBoundary = room?.boundaries.first
        XCTAssertEqual(exportedBoundary?.id, boundary.id.uuidString)
        XCTAssertEqual(exportedBoundary?.boundaryType, "external")
        XCTAssertEqual(exportedBoundary?.lengthM, 4.5)
        XCTAssertEqual(exportedBoundary?.heightM, 2.4)
        XCTAssertEqual(exportedBoundary?.material, "solid brick")
        XCTAssertEqual(exportedBoundary?.reviewStatus, "confirmed")

        let exportedOpening = room?.openings.first
        XCTAssertEqual(exportedOpening?.id, opening.id.uuidString)
        XCTAssertEqual(exportedOpening?.openingType, "window")
        XCTAssertEqual(exportedOpening?.widthM, 1.2)
        XCTAssertEqual(exportedOpening?.heightM, 1.0)
        XCTAssertEqual(exportedOpening?.material, "double glazed uPVC")
    }

    // MARK: - Hazard observations are mapped

    func test_build_hazardObservation_mapsCorrectly() {
        let visit = makeVisit()
        var draft = makeDraft()

        var hazard = CapturedHazardObservationDraft()
        hazard.category = .structural
        hazard.severity = .high
        hazard.title = "Cracked lintel"
        hazard.descriptionText = "Large crack above rear door lintel."
        hazard.actionRequired = true

        draft.hazardObservations.append(hazard)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertEqual(capture.hazardObservations?.count, 1)
        let exported = capture.hazardObservations?.first
        XCTAssertEqual(exported?.id, hazard.id.uuidString)
        XCTAssertEqual(exported?.category, "structural")
        XCTAssertEqual(exported?.severity, "high")
        XCTAssertEqual(exported?.title, "Cracked lintel")
        XCTAssertEqual(exported?.description, "Large crack above rear door lintel.")
        XCTAssertTrue(exported?.actionRequired == true)
        XCTAssertEqual(exported?.reviewStatus, "confirmed")
    }

    // MARK: - Suspected asbestos maps correctly

    func test_build_hazard_suspectedAsbestos_mapsCorrectly() {
        let visit = makeVisit()
        var draft = makeDraft()

        var hazard = CapturedHazardObservationDraft()
        hazard.category = .asbestos
        hazard.severity = .critical
        hazard.title = "Suspected ACM on pipe lagging"
        hazard.actionRequired = true

        draft.hazardObservations.append(hazard)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let exported = capture.hazardObservations?.first
        XCTAssertEqual(exported?.category, "asbestos", "Asbestos category must map to raw value 'asbestos'")
        XCTAssertEqual(exported?.severity, "critical")
        XCTAssertTrue(exported?.actionRequired == true)
    }

    // MARK: - Unknown material maps to nil

    func test_build_boundary_unknownMaterial_mapsToNil() {
        let visit = makeVisit()
        var draft = makeDraft()

        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.material = nil // explicitly unknown
        record.boundaries.append(boundary)
        draft.fabricRecords.append(record)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let exported = capture.floorPlanFabric?.rooms.first?.boundaries.first
        XCTAssertNil(exported?.material, "Unknown material must map to nil in the contract")
    }

    // MARK: - Rejected status persists

    func test_build_rejectedBoundary_reviewStatusIsRejected() {
        let visit = makeVisit()
        var draft = makeDraft()

        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.reviewStatus = .rejected
        record.boundaries.append(boundary)
        draft.fabricRecords.append(record)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let exported = capture.floorPlanFabric?.rooms.first?.boundaries.first
        XCTAssertEqual(exported?.reviewStatus, "rejected")
    }

    func test_build_pendingOpening_reviewStatusIsPending() {
        let visit = makeVisit()
        var draft = makeDraft()

        var record = CapturedFloorPlanFabricDraft()
        var opening = CapturedOpeningDraft()
        opening.reviewStatus = .pending
        record.openings.append(opening)
        draft.fabricRecords.append(record)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let exported = capture.floorPlanFabric?.rooms.first?.openings.first
        XCTAssertEqual(exported?.reviewStatus, "pending")
    }

    func test_build_confirmedHazard_reviewStatusIsConfirmed() {
        let visit = makeVisit()
        var draft = makeDraft()

        var hazard = CapturedHazardObservationDraft()
        hazard.reviewStatus = .confirmed
        hazard.title = "Test hazard"
        draft.hazardObservations.append(hazard)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertEqual(capture.hazardObservations?.first?.reviewStatus, "confirmed")
    }

    // MARK: - No heat-loss output

    func test_build_fabricRecord_noHeatLossOutput() throws {
        let visit = makeVisit()
        var draft = makeDraft()

        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.boundaryType = .external
        boundary.lengthM = 5.0
        boundary.heightM = 2.4
        boundary.material = "cavity wall"
        record.boundaries.append(boundary)
        draft.fabricRecords.append(record)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let data = try JSONEncoder().encode(capture)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("heatLoss"),      "Heat-loss output must not appear in capture")
        XCTAssertFalse(json.contains("uValue"),        "U-value must not appear in capture")
        XCTAssertFalse(json.contains("thermalResist"), "Thermal resistance must not appear in capture")
    }

    // MARK: - No risk score output

    func test_build_hazardRecord_noRiskScoreOutput() throws {
        let visit = makeVisit()
        var draft = makeDraft()

        var hazard = CapturedHazardObservationDraft()
        hazard.category = .asbestos
        hazard.severity = .high
        hazard.title = "Test"
        draft.hazardObservations.append(hazard)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let data = try JSONEncoder().encode(capture)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("riskScore"),      "Risk score must not appear in capture")
        XCTAssertFalse(json.contains("riskAssessment"), "Risk assessment must not appear in capture")
        XCTAssertFalse(json.contains("remediation"),    "Remediation advice must not appear in capture")
    }

    // MARK: - hasFabricMeasurements indicator

    func test_hasFabricMeasurements_falseWhenEmpty() {
        let draft = makeDraft()
        XCTAssertFalse(draft.hasFabricMeasurements)
    }

    func test_hasFabricMeasurements_trueWhenConfirmedBoundaryExists() {
        var draft = makeDraft()
        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.reviewStatus = .confirmed
        record.boundaries.append(boundary)
        draft.fabricRecords.append(record)
        XCTAssertTrue(draft.hasFabricMeasurements)
    }

    func test_hasFabricMeasurements_falseWhenOnlyRejected() {
        var draft = makeDraft()
        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.reviewStatus = .rejected
        record.boundaries.append(boundary)
        draft.fabricRecords.append(record)
        XCTAssertFalse(draft.hasFabricMeasurements)
    }

    // MARK: - hasHazardObservations indicator

    func test_hasHazardObservations_falseWhenEmpty() {
        let draft = makeDraft()
        XCTAssertFalse(draft.hasHazardObservations)
    }

    func test_hasHazardObservations_trueWhenConfirmedHazardExists() {
        var draft = makeDraft()
        var hazard = CapturedHazardObservationDraft()
        hazard.reviewStatus = .confirmed
        hazard.title = "Test"
        draft.hazardObservations.append(hazard)
        XCTAssertTrue(draft.hasHazardObservations)
    }

    // MARK: - Completion still works without fabric / hazard data

    func test_readiness_doesNotRequireFabricOrHazards() {
        var draft = makeDraft()
        // Populate the required seven flags via existing evidence only.
        var room = CapturedRoomScanDraft()
        room.reviewStatus = .confirmed
        draft.roomScans.append(room)

        var photo = CapturedPhotoDraft(localFilename: "test.jpg")
        photo.reviewStatus = .confirmed
        draft.photos.append(photo)

        var boilerPin = CapturedObjectPinDraft(type: .boiler)
        boilerPin.reviewStatus = .confirmed
        draft.objectPins.append(boilerPin)

        var fluePin = CapturedObjectPinDraft(type: .flue)
        fluePin.reviewStatus = .confirmed
        draft.objectPins.append(fluePin)

        var cylPin = CapturedObjectPinDraft(type: .cylinder)
        cylPin.reviewStatus = .confirmed
        draft.objectPins.append(cylPin)

        var note = CapturedVoiceNoteDraft()
        note.transcript = "Test note"
        note.reviewStatus = .confirmed
        draft.voiceNotes.append(note)

        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        // All seven base flags should pass without any fabric or hazard data.
        XCTAssertTrue(readiness.hasRooms)
        XCTAssertTrue(readiness.hasPhotos)
        XCTAssertTrue(readiness.hasBoiler)
        XCTAssertTrue(readiness.hasFlue)
        XCTAssertTrue(readiness.hasHotWaterSystem)
        XCTAssertTrue(readiness.hasHeatingSystem)
        XCTAssertTrue(readiness.hasNotes)
    }

    // MARK: - Opening linked to boundary maps correctly

    func test_build_openingLinkedToBoundary_linkedBoundaryIdPreserved() {
        let visit = makeVisit()
        var draft = makeDraft()

        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        var opening  = CapturedOpeningDraft()
        opening.linkedBoundaryId = boundary.id
        record.boundaries.append(boundary)
        record.openings.append(opening)
        draft.fabricRecords.append(record)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let exportedOpening = capture.floorPlanFabric?.rooms.first?.openings.first
        XCTAssertEqual(exportedOpening?.linkedBoundaryId, boundary.id.uuidString)
    }

    // MARK: - Review counts include fabric and hazards

    func test_pendingReviewCount_includesFabricBoundaries() {
        var draft = makeDraft()
        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.reviewStatus = .pending
        record.boundaries.append(boundary)
        draft.fabricRecords.append(record)
        XCTAssertEqual(draft.pendingReviewCount, 1)
    }

    func test_rejectedReviewCount_includesFabricOpenings() {
        var draft = makeDraft()
        var record = CapturedFloorPlanFabricDraft()
        var opening = CapturedOpeningDraft()
        opening.reviewStatus = .rejected
        record.openings.append(opening)
        draft.fabricRecords.append(record)
        XCTAssertEqual(draft.rejectedReviewCount, 1)
    }

    func test_pendingReviewCount_includesHazards() {
        var draft = makeDraft()
        var hazard = CapturedHazardObservationDraft()
        hazard.reviewStatus = .pending
        hazard.title = "Test"
        draft.hazardObservations.append(hazard)
        XCTAssertEqual(draft.pendingReviewCount, 1)
    }
}
