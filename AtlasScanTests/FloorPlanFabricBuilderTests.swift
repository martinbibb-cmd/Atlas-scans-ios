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

    // MARK: - Derived wall drafts from room scan

    func test_derivedWallDrafts_fromScanWithDimensions_produces4Walls() {
        var scan = CapturedRoomScanDraft()
        scan.rawWidthM = 4.0
        scan.rawDepthM = 3.0
        scan.rawHeightM = 2.4
        let walls = scan.derivedWallDrafts()
        XCTAssertEqual(walls.count, 4, "derivedWallDrafts must produce exactly 4 walls")
    }

    func test_derivedWallDrafts_allDefaultToExternal() {
        var scan = CapturedRoomScanDraft()
        scan.rawWidthM = 4.0
        scan.rawDepthM = 3.0
        let walls = scan.derivedWallDrafts()
        XCTAssertTrue(walls.allSatisfy { $0.boundaryType == .external },
                      "All scan-derived walls must default to .external")
    }

    func test_derivedWallDrafts_allDefaultToPending() {
        var scan = CapturedRoomScanDraft()
        scan.rawWidthM = 4.0
        scan.rawDepthM = 3.0
        let walls = scan.derivedWallDrafts()
        XCTAssertTrue(walls.allSatisfy { $0.reviewStatus == .pending },
                      "All scan-derived walls must default to .pending review status")
    }

    func test_derivedWallDrafts_wallsMarkedScanDerived() {
        var scan = CapturedRoomScanDraft()
        scan.rawWidthM = 4.0
        scan.rawDepthM = 3.0
        let walls = scan.derivedWallDrafts()
        XCTAssertTrue(walls.allSatisfy { $0.source == .scanDerived },
                      "All scan-derived walls must have source .scanDerived")
    }

    func test_derivedWallDrafts_widthWallsUseRawWidth() {
        var scan = CapturedRoomScanDraft()
        scan.rawWidthM = 5.0
        scan.rawDepthM = 3.0
        let walls = scan.derivedWallDrafts()
        // Walls 1 and 3 (0-indexed: 0 and 2) should have rawWidthM as length.
        let widthWalls = walls.enumerated().filter { _, w in w.wallIndex == 1 || w.wallIndex == 3 }
        XCTAssertTrue(widthWalls.allSatisfy { _, w in w.lengthM == 5.0 },
                      "Width-side walls (1 and 3) must carry rawWidthM as length")
    }

    func test_derivedWallDrafts_noScanDimensions_stillProduces4Walls() {
        let scan = CapturedRoomScanDraft()
        let walls = scan.derivedWallDrafts()
        XCTAssertEqual(walls.count, 4, "derivedWallDrafts must produce 4 walls even without dimensions")
        XCTAssertTrue(walls.allSatisfy { $0.lengthM == nil }, "Walls without scan dimensions must have nil lengthM")
    }

    func test_derivedWallDrafts_emptyPolygonSegments_fallsBackToRectangularWalls() {
        var scan = CapturedRoomScanDraft()
        scan.rawWidthM = 4.0
        scan.rawDepthM = 3.0
        scan.wallSegmentLengthsM = []

        let walls = scan.derivedWallDrafts()

        XCTAssertEqual(walls.count, 4)
        XCTAssertEqual(walls.map(\.wallIndex), [1, 2, 3, 4])
        XCTAssertEqual(walls.map(\.lengthM), [4.0, 3.0, 4.0, 3.0])
    }

    func test_derivedWallDrafts_validPolygonSegments_disableRectangularFallback() {
        var scan = CapturedRoomScanDraft()
        scan.rawWidthM = 10.0
        scan.rawDepthM = 10.0
        scan.wallSegmentLengthsM = [2.2, 1.8, 2.5, 1.9, 2.0]

        let walls = scan.derivedWallDrafts()

        XCTAssertEqual(walls.count, 5, "Polygon-derived wall count must match segment count")
        XCTAssertEqual(walls.map(\.wallIndex), [1, 2, 3, 4, 5])
        XCTAssertEqual(walls.map(\.lengthM), [2.2, 1.8, 2.5, 1.9, 2.0])
    }

    // MARK: - applyDerivedWalls helper

    func test_applyDerivedWalls_populatesBoundariesWhenEmpty() {
        var scan = CapturedRoomScanDraft()
        scan.rawWidthM = 4.0
        scan.rawDepthM = 3.0
        var record = CapturedFloorPlanFabricDraft()
        record.applyDerivedWalls(from: scan)
        XCTAssertEqual(record.boundaries.count, 4, "applyDerivedWalls must populate 4 boundaries")
    }

    func test_applyDerivedWalls_doesNotOverwriteExistingBoundaries() {
        var scan = CapturedRoomScanDraft()
        scan.rawWidthM = 4.0
        var record = CapturedFloorPlanFabricDraft()
        var existing = CapturedBoundaryDraft()
        existing.boundaryType = .party
        record.boundaries.append(existing)
        record.applyDerivedWalls(from: scan)
        // Should still have exactly 1 boundary (the existing one was not overwritten).
        XCTAssertEqual(record.boundaries.count, 1)
        XCTAssertEqual(record.boundaries.first?.boundaryType, .party)
    }

    // MARK: - Wall type can be changed from external to party

    func test_boundary_externalCanBeChangedToParty() {
        var boundary = CapturedBoundaryDraft()
        boundary.boundaryType = .external
        boundary.boundaryType = .party
        XCTAssertEqual(boundary.boundaryType, .party)
    }

    // MARK: - constructionType maps to material on export

    func test_build_constructionType_mapsToMaterialString() {
        let visit = makeVisit()
        var draft = makeDraft()
        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.constructionType = .solidBrick
        boundary.material = nil  // no override
        record.boundaries.append(boundary)
        draft.fabricRecords.append(record)
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let exported = capture.floorPlanFabric?.rooms.first?.boundaries.first
        XCTAssertEqual(exported?.material, "Solid brick",
                       "constructionType .solidBrick must export as material string when no override is set")
    }

    func test_build_constructionType_unknownExportsNilMaterial() {
        let visit = makeVisit()
        var draft = makeDraft()
        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.constructionType = .unknown
        boundary.material = nil
        record.boundaries.append(boundary)
        draft.fabricRecords.append(record)
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let exported = capture.floorPlanFabric?.rooms.first?.boundaries.first
        XCTAssertNil(exported?.material, "constructionType .unknown must export nil material")
    }

    func test_build_materialOverride_takesPrecedenceOverConstructionType() {
        let visit = makeVisit()
        var draft = makeDraft()
        var record = CapturedFloorPlanFabricDraft()
        var boundary = CapturedBoundaryDraft()
        boundary.constructionType = .cavityWall
        boundary.material = "cavity wall + 50mm PIR"  // free-text override
        record.boundaries.append(boundary)
        draft.fabricRecords.append(record)
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let exported = capture.floorPlanFabric?.rooms.first?.boundaries.first
        XCTAssertEqual(exported?.material, "cavity wall + 50mm PIR",
                       "Free-text material override must take precedence over constructionType")
    }

    // MARK: - Hazard observation photo linking

    func test_hazard_canSaveWithLinkedPhotoOnly() {
        // A hazard with no title but a linked photo ID must still have a UUID link stored.
        var hazard = CapturedHazardObservationDraft()
        hazard.title = ""
        let photoId = UUID()
        hazard.linkedPhotoIds.append(photoId)
        XCTAssertEqual(hazard.linkedPhotoIds.count, 1)
        XCTAssertEqual(hazard.linkedPhotoIds.first, photoId)
    }

    func test_build_hazard_exportsLinkedPhotoIds() {
        let visit = makeVisit()
        var draft = makeDraft()

        let photoId1 = UUID()
        let photoId2 = UUID()
        var hazard = CapturedHazardObservationDraft()
        hazard.category = .gas
        hazard.title = "Gas smell"
        hazard.linkedPhotoIds = [photoId1, photoId2]
        draft.hazardObservations.append(hazard)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let exported = capture.hazardObservations?.first
        XCTAssertEqual(exported?.linkedPhotoIds, [photoId1.uuidString, photoId2.uuidString],
                       "Hazard linked photo IDs must be exported in order")
    }

    func test_hazard_newDomainCategories_mapCorrectly() throws {
        let visit = makeVisit()
        var draft = makeDraft()

        let categories: [HazardCategory] = [.flue, .access, .workingAtHeight, .customerProperty]
        for category in categories {
            var hazard = CapturedHazardObservationDraft()
            hazard.category = category
            hazard.title = category.displayName
            draft.hazardObservations.append(hazard)
        }

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let exportedCategories = capture.hazardObservations?.map(\.category) ?? []
        XCTAssertTrue(exportedCategories.contains("flue"))
        XCTAssertTrue(exportedCategories.contains("access"))
        XCTAssertTrue(exportedCategories.contains("working_at_height"))
        XCTAssertTrue(exportedCategories.contains("customer_property"))
    }

    // MARK: - Object pin wall context

    func test_objectPinType_radiatorIsWallMounted() {
        XCTAssertTrue(ObjectPinType.radiator.isWallMounted)
    }

    func test_objectPinType_towelRailIsWallMounted() {
        XCTAssertTrue(ObjectPinType.towelRail.isWallMounted)
    }

    func test_objectPinType_fanConvectorIsWallMounted() {
        XCTAssertTrue(ObjectPinType.fanConvector.isWallMounted)
    }

    func test_objectPinType_boilerIsNotWallMounted() {
        XCTAssertFalse(ObjectPinType.boiler.isWallMounted)
    }

    func test_objectPin_attachedWallIdCanBeSet() {
        var pin = CapturedObjectPinDraft(type: .radiator)
        let wallId = UUID()
        pin.attachedWallId = wallId
        XCTAssertEqual(pin.attachedWallId, wallId)
    }

    func test_objectPin_attachedWallIdDefaultsToNil() {
        let pin = CapturedObjectPinDraft(type: .radiator)
        XCTAssertNil(pin.attachedWallId, "attachedWallId must default to nil")
    }
}
