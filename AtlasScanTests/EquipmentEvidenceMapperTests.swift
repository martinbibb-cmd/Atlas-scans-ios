import XCTest
@testable import AtlasScan
import AtlasScanCore

// MARK: - EquipmentEvidenceMapperTests
//
// Tests for EquipmentEvidenceMapper (AtlasScanCore V2 flow).
//
// Covers:
//   - Grouping: each PinObjectCategoryV1 routes to the correct evidence group
//   - Multi-room aggregation
//   - Identity resolution: catalogue template / engineer-entered / unknown
//   - Manual entry edge cases (nil manufacturer+model → unknown)
//   - Anchor confidence summaries for all SpatialPinAnchorConfidence cases
//   - isSpatiallyAnchored rules (world_locked/high + confirmed required)
//   - isConfirmedEvidence rules (confirmed + non-screen-only)
//   - screen_only tracking via screenOnlyPinIds
//   - Group count helpers (confirmedCount, pendingCount, needsIdentificationCount)
//   - Handoff integration: equipmentEvidenceGroups is populated and round-trips

final class EquipmentEvidenceMapperTests: XCTestCase {

    // MARK: - Helpers

    private func makePin(
        roomId: UUID = UUID(),
        objectType: PinnedObjectType = .boiler,
        objectCategory: PinObjectCategoryV1 = .heatSource,
        label: String? = nil,
        selectedTemplateId: String? = nil,
        manualEntry: SpatialPinManualEntryV1? = nil,
        anchorConfidence: SpatialPinAnchorConfidence = .worldLocked,
        reviewStatus: SpatialPinReviewStatus = .confirmed,
        provenance: SpatialPinProvenance = .manualCapture
    ) -> SpatialPinV1 {
        SpatialPinV1(
            roomId: roomId,
            positionX: 1.0, positionY: 1.0, positionZ: 1.0,
            objectType: objectType,
            label: label,
            objectCategory: objectCategory,
            selectedTemplateId: selectedTemplateId,
            manualEntry: manualEntry,
            anchorConfidence: anchorConfidence,
            reviewStatus: reviewStatus,
            provenance: provenance
        )
    }

    private func makeRoom(pins: [SpatialPinV1], roomId: UUID = UUID()) -> RoomCaptureV2 {
        var room = RoomCaptureV2(id: roomId, displayName: "Test Room")
        room.pinnedObjects = pins
        return room
    }

    private func buildGroups(pins: [SpatialPinV1]) -> EquipmentEvidenceGroupsV1 {
        EquipmentEvidenceMapper.buildGroups(from: [makeRoom(pins: pins)], visitId: "test-visit")
    }

    // MARK: - Grouping tests

    func test_heatSourcePin_appearsInHeatSourceGroup() {
        let groups = buildGroups(pins: [makePin(objectCategory: .heatSource)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.count, 1)
        XCTAssertEqual(groups.hotWaterStorageEvidence.pins.count, 0)
        XCTAssertEqual(groups.flueExternalEvidence.pins.count, 0)
        XCTAssertEqual(groups.emitterEvidence.pins.count, 0)
        XCTAssertEqual(groups.heatingComponentEvidence.pins.count, 0)
    }

    func test_hotWaterStoragePin_appearsInHotWaterGroup() {
        let groups = buildGroups(pins: [makePin(objectType: .hotWaterCylinder, objectCategory: .hotWaterStorage)])
        XCTAssertEqual(groups.hotWaterStorageEvidence.pins.count, 1)
        XCTAssertEqual(groups.heatSourceEvidence.pins.count, 0)
    }

    func test_flueExternalPin_appearsInFlueGroup() {
        let groups = buildGroups(pins: [makePin(objectType: .flueTerminal, objectCategory: .flueExternal)])
        XCTAssertEqual(groups.flueExternalEvidence.pins.count, 1)
    }

    func test_emitterPin_appearsInEmitterGroup() {
        let groups = buildGroups(pins: [makePin(objectCategory: .emitters)])
        XCTAssertEqual(groups.emitterEvidence.pins.count, 1)
    }

    func test_heatingComponentPin_appearsInComponentGroup() {
        let groups = buildGroups(pins: [makePin(objectCategory: .heatingSystemComponents)])
        XCTAssertEqual(groups.heatingComponentEvidence.pins.count, 1)
    }

    func test_multipleRooms_pinsAreAggregated() {
        let boilerRoom  = makeRoom(pins: [makePin(objectCategory: .heatSource)])
        let cylinderRoom = makeRoom(pins: [makePin(objectType: .hotWaterCylinder, objectCategory: .hotWaterStorage)])
        let groups = EquipmentEvidenceMapper.buildGroups(from: [boilerRoom, cylinderRoom], visitId: "v1")
        XCTAssertEqual(groups.heatSourceEvidence.pins.count, 1)
        XCTAssertEqual(groups.hotWaterStorageEvidence.pins.count, 1)
    }

    func test_emptySession_producesAllEmptyGroups() {
        let groups = EquipmentEvidenceMapper.buildGroups(from: [], visitId: "v1")
        XCTAssertTrue(groups.allGroups.allSatisfy { $0.pins.isEmpty })
    }

    // MARK: - Identity resolution

    func test_pinWithTemplateId_hasIdentitySourceCatalogueTemplate() {
        let groups = buildGroups(pins: [makePin(selectedTemplateId: "tmpl-boiler-42")])
        let evidence = groups.heatSourceEvidence.pins.first!
        XCTAssertEqual(evidence.identitySource, "catalogue_template")
        XCTAssertEqual(evidence.selectedTemplateId, "tmpl-boiler-42")
        XCTAssertEqual(evidence.catalogueLabel, "tmpl-boiler-42",
                       "Template ID should be carried as placeholder label for Mind to resolve")
    }

    func test_pinWithManufacturerAndModel_hasIdentitySourceEngineerEntered() {
        let entry = SpatialPinManualEntryV1(manufacturer: "Worcester Bosch", model: "Greenstar 30i")
        let groups = buildGroups(pins: [makePin(manualEntry: entry)])
        let evidence = groups.heatSourceEvidence.pins.first!
        XCTAssertEqual(evidence.identitySource, "engineer_entered")
        XCTAssertNotNil(evidence.manualEntry)
        XCTAssertEqual(evidence.manualEntry?.manufacturer, "Worcester Bosch")
        XCTAssertEqual(evidence.manualEntry?.model, "Greenstar 30i")
    }

    func test_pinWithManufacturerOnly_hasIdentitySourceEngineerEntered() {
        let entry = SpatialPinManualEntryV1(manufacturer: "Vaillant")
        let groups = buildGroups(pins: [makePin(manualEntry: entry)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.identitySource, "engineer_entered")
    }

    func test_pinWithModelOnly_hasIdentitySourceEngineerEntered() {
        let entry = SpatialPinManualEntryV1(model: "EcoFIT Pure 825")
        let groups = buildGroups(pins: [makePin(manualEntry: entry)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.identitySource, "engineer_entered")
    }

    func test_pinWithNoIdentity_isUnknown() {
        let groups = buildGroups(pins: [makePin()])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.identitySource, "unknown")
    }

    func test_manualEntryWithNilManufacturerAndNilModel_isUnknown() {
        let entry = SpatialPinManualEntryV1(manufacturer: nil, model: nil, notes: "Check during visit")
        let groups = buildGroups(pins: [makePin(manualEntry: entry)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.identitySource, "unknown",
                       "Notes alone are not sufficient to establish identity")
    }

    func test_manualEntryAllFieldsPreservedOnHandoff() {
        let entry = SpatialPinManualEntryV1(
            manufacturer: "Baxi",
            model: "Duo-tec 28",
            type: "combination",
            widthMm: 390,
            heightMm: 720,
            depthMm: 330,
            flueOrientation: "rear",
            notes: "Annual service 2023"
        )
        let groups = buildGroups(pins: [makePin(manualEntry: entry)])
        let stored = groups.heatSourceEvidence.pins.first!.manualEntry
        XCTAssertEqual(stored?.manufacturer, "Baxi")
        XCTAssertEqual(stored?.model, "Duo-tec 28")
        XCTAssertEqual(stored?.type, "combination")
        XCTAssertEqual(stored?.widthMm, 390)
        XCTAssertEqual(stored?.heightMm, 720)
        XCTAssertEqual(stored?.depthMm, 330)
        XCTAssertEqual(stored?.flueOrientation, "rear")
        XCTAssertEqual(stored?.notes, "Annual service 2023")
    }

    // MARK: - Anchor confidence summaries

    func test_screenOnly_hasRoomNoteOnlyAnchorSummary() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .screenOnly)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.anchorSummary,
                       "room note only — not spatially anchored")
    }

    func test_raycastEstimated_hasEstimatedPositionAnchorSummary() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .raycastEstimated)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.anchorSummary, "estimated position")
    }

    func test_estimated_hasEstimatedPositionAnchorSummary() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .estimated)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.anchorSummary, "estimated position")
    }

    func test_low_hasEstimatedPositionAnchorSummary() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .low)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.anchorSummary, "estimated position")
    }

    func test_worldLocked_hasSpatiallyAnchoredAnchorSummary() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .worldLocked)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.anchorSummary, "spatially anchored")
    }

    func test_highConfidence_hasSpatiallyAnchoredAnchorSummary() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .high)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.anchorSummary, "spatially anchored")
    }

    func test_mediumConfidence_hasSpatiallyAnchoredAnchorSummary() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .medium)])
        XCTAssertEqual(groups.heatSourceEvidence.pins.first!.anchorSummary, "spatially anchored")
    }

    // MARK: - isSpatiallyAnchored rules

    func test_worldLockedAndConfirmed_isSpatiallyAnchored() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .worldLocked, reviewStatus: .confirmed)])
        XCTAssertTrue(groups.heatSourceEvidence.pins.first!.isSpatiallyAnchored)
    }

    func test_highAndConfirmed_isSpatiallyAnchored() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .high, reviewStatus: .confirmed)])
        XCTAssertTrue(groups.heatSourceEvidence.pins.first!.isSpatiallyAnchored)
    }

    func test_worldLockedAndNeedsReview_isNotSpatiallyAnchored() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .worldLocked, reviewStatus: .needsReview)])
        XCTAssertFalse(groups.heatSourceEvidence.pins.first!.isSpatiallyAnchored,
                       "world_locked alone is not sufficient; review must be confirmed")
    }

    func test_screenOnlyAndConfirmed_isNotSpatiallyAnchored() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .screenOnly, reviewStatus: .confirmed)])
        XCTAssertFalse(groups.heatSourceEvidence.pins.first!.isSpatiallyAnchored,
                       "screen_only is never spatially anchored")
    }

    func test_mediumConfidenceAndConfirmed_isNotSpatiallyAnchored() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .medium, reviewStatus: .confirmed)])
        XCTAssertFalse(groups.heatSourceEvidence.pins.first!.isSpatiallyAnchored,
                       "Only world_locked and high confidence qualify as spatially anchored")
    }

    // MARK: - isConfirmedEvidence (customer proof) rules

    func test_confirmedAndNonScreenOnly_isConfirmedEvidence() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .worldLocked, reviewStatus: .confirmed)])
        XCTAssertTrue(groups.heatSourceEvidence.pins.first!.isConfirmedEvidence)
    }

    func test_confirmedAndRaycastEstimated_isConfirmedEvidence() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .raycastEstimated, reviewStatus: .confirmed)])
        XCTAssertTrue(groups.heatSourceEvidence.pins.first!.isConfirmedEvidence,
                      "Confirmed + non-screen-only qualifies as customer proof regardless of exact anchor type")
    }

    func test_screenOnlyAndConfirmed_isNotConfirmedEvidence() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .screenOnly, reviewStatus: .confirmed)])
        XCTAssertFalse(groups.heatSourceEvidence.pins.first!.isConfirmedEvidence,
                       "screen_only pins must never become customer proof")
    }

    func test_needsReviewAndNonScreenOnly_isNotConfirmedEvidence() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .worldLocked, reviewStatus: .needsReview)])
        XCTAssertFalse(groups.heatSourceEvidence.pins.first!.isConfirmedEvidence,
                       "Pending pins are not yet customer proof")
    }

    func test_screenOnlyAndNeedsReview_isNotConfirmedEvidence() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .screenOnly, reviewStatus: .needsReview)])
        XCTAssertFalse(groups.heatSourceEvidence.pins.first!.isConfirmedEvidence)
    }

    // MARK: - screen_only pin tracking

    func test_screenOnlyPinIds_containsOnlyScreenOnlyPins() {
        let screenPin  = makePin(objectCategory: .heatSource,      anchorConfidence: .screenOnly)
        let worldPin   = makePin(objectCategory: .hotWaterStorage,  anchorConfidence: .worldLocked)
        let groups = buildGroups(pins: [screenPin, worldPin])
        XCTAssertEqual(groups.screenOnlyPinIds.count, 1)
        XCTAssertEqual(groups.screenOnlyPinIds.first, screenPin.id.uuidString)
    }

    func test_noScreenOnlyPins_screenOnlyPinIdsIsEmpty() {
        let groups = buildGroups(pins: [makePin(anchorConfidence: .worldLocked)])
        XCTAssertTrue(groups.screenOnlyPinIds.isEmpty)
    }

    // MARK: - Group count helpers

    func test_confirmedCount_countsOnlyCustomerProofPins() {
        let confirmed   = makePin(anchorConfidence: .worldLocked,    reviewStatus: .confirmed)
        let pending     = makePin(anchorConfidence: .worldLocked,    reviewStatus: .needsReview)
        let screenOnly  = makePin(anchorConfidence: .screenOnly,     reviewStatus: .confirmed)
        let groups = buildGroups(pins: [confirmed, pending, screenOnly])
        XCTAssertEqual(groups.heatSourceEvidence.confirmedCount, 1,
                       "Only the non-screen-only confirmed pin qualifies")
    }

    func test_pendingCount_countsPinsWithNeedsReview() {
        let confirmed  = makePin(anchorConfidence: .worldLocked, reviewStatus: .confirmed)
        let pending1   = makePin(anchorConfidence: .screenOnly,  reviewStatus: .needsReview)
        let pending2   = makePin(anchorConfidence: .worldLocked, reviewStatus: .needsReview)
        let groups = buildGroups(pins: [confirmed, pending1, pending2])
        XCTAssertEqual(groups.heatSourceEvidence.pendingCount, 2)
    }

    func test_needsIdentificationCount_countsPinsWithUnknownIdentity() {
        let unknown = makePin(objectCategory: .heatSource)
        let known   = makePin(objectCategory: .hotWaterStorage,
                              manualEntry: SpatialPinManualEntryV1(manufacturer: "Co", model: "M1"))
        let groups = buildGroups(pins: [unknown, known])
        XCTAssertEqual(groups.heatSourceEvidence.needsIdentificationCount, 1)
        XCTAssertEqual(groups.hotWaterStorageEvidence.needsIdentificationCount, 0)
    }

    func test_totalConfirmedCount_sumsAcrossAllGroups() {
        let boiler   = makePin(objectCategory: .heatSource,      anchorConfidence: .worldLocked, reviewStatus: .confirmed)
        let cylinder = makePin(objectCategory: .hotWaterStorage,  anchorConfidence: .worldLocked, reviewStatus: .confirmed)
        let emitter  = makePin(objectCategory: .emitters,         anchorConfidence: .screenOnly,  reviewStatus: .confirmed)
        let groups = buildGroups(pins: [boiler, cylinder, emitter])
        XCTAssertEqual(groups.totalConfirmedCount, 2,
                       "screen_only emitter must not be counted")
    }

    func test_hasAnyConfirmedHeatSource_trueWhenBoilerConfirmed() {
        let groups = buildGroups(pins: [
            makePin(objectCategory: .heatSource, anchorConfidence: .worldLocked, reviewStatus: .confirmed)
        ])
        XCTAssertTrue(groups.hasAnyConfirmedHeatSource)
    }

    func test_hasAnyConfirmedHeatSource_falseWhenOnlyPending() {
        let groups = buildGroups(pins: [
            makePin(objectCategory: .heatSource, anchorConfidence: .worldLocked, reviewStatus: .needsReview)
        ])
        XCTAssertFalse(groups.hasAnyConfirmedHeatSource)
    }

    // MARK: - Handoff integration

    func test_handoffContainsEquipmentEvidenceGroups() {
        let pin = makePin(objectCategory: .heatSource, anchorConfidence: .worldLocked, reviewStatus: .confirmed)
        var session = SessionCaptureV2(visitId: UUID())
        session.rooms.append(makeRoom(pins: [pin]))
        let readiness = VisitReadinessV1.derive(from: session)
        let handoff = ScanToMindHandoffV1(session: session, readiness: readiness)
        XCTAssertFalse(handoff.equipmentEvidenceGroups.heatSourceEvidence.pins.isEmpty)
    }

    func test_handoff_equipmentGroups_encodesAndDecodes() throws {
        let pin = makePin(
            objectCategory: .heatSource,
            manualEntry: SpatialPinManualEntryV1(manufacturer: "Ideal", model: "Logic+ 24"),
            anchorConfidence: .worldLocked,
            reviewStatus: .confirmed
        )
        var session = SessionCaptureV2(visitId: UUID())
        session.rooms.append(makeRoom(pins: [pin]))
        let readiness = VisitReadinessV1.derive(from: session)
        let handoff = ScanToMindHandoffV1(session: session, readiness: readiness)

        let data = try JSONEncoder().encode(handoff)
        let decoded = try JSONDecoder().decode(ScanToMindHandoffV1.self, from: data)

        XCTAssertFalse(decoded.equipmentEvidenceGroups.heatSourceEvidence.pins.isEmpty)
        XCTAssertEqual(
            decoded.equipmentEvidenceGroups.heatSourceEvidence.pins.first?.manualEntry?.manufacturer,
            "Ideal"
        )
    }

    func test_handoff_decodesOldPayloadWithoutEquipmentGroups_derivesFromSession() throws {
        // Simulate an older payload that does not include equipmentEvidenceGroups.
        let pin = makePin(objectCategory: .heatSource, anchorConfidence: .worldLocked, reviewStatus: .confirmed)
        var session = SessionCaptureV2(visitId: UUID())
        session.rooms.append(makeRoom(pins: [pin]))
        let readiness = VisitReadinessV1.derive(from: session)
        let handoff = ScanToMindHandoffV1(session: session, readiness: readiness)

        // Encode, then manually strip equipmentEvidenceGroups from the JSON.
        let data = try JSONEncoder().encode(handoff)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "equipmentEvidenceGroups")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(ScanToMindHandoffV1.self, from: strippedData)
        // Mapper should re-derive from decoded session.
        XCTAssertFalse(decoded.equipmentEvidenceGroups.heatSourceEvidence.pins.isEmpty,
                       "Groups should be re-derived from the session when field is absent in JSON")
    }

    // MARK: - LinkedPhotoId wiring

    func test_linkedPhoto_photoIdAppearsInEvidence() {
        let roomId = UUID()
        let pin    = makePin(roomId: roomId, objectCategory: .heatSource)
        var room   = RoomCaptureV2(id: roomId, displayName: "Kitchen")
        room.pinnedObjects = [pin]
        let photo = PhotoEvidenceV1(
            visitId: UUID(),
            roomId: roomId,
            linkedObjectId: pin.id,
            relativeFilePath: "photos/overview.jpg"
        )
        let groups = EquipmentEvidenceMapper.buildGroups(from: [room], photos: [photo], visitId: "v1")
        XCTAssertEqual(groups.heatSourceEvidence.pins.first?.linkedPhotoId, photo.id.uuidString)
    }

    func test_unlinkedPhoto_doesNotAppearInEvidence() {
        let roomId = UUID()
        let pin    = makePin(roomId: roomId, objectCategory: .heatSource)
        var room   = RoomCaptureV2(id: roomId, displayName: "Kitchen")
        room.pinnedObjects = [pin]
        let photo = PhotoEvidenceV1(
            visitId: UUID(),
            roomId: roomId,
            linkedObjectId: nil,  // not linked to any pin
            relativeFilePath: "photos/overview.jpg"
        )
        let groups = EquipmentEvidenceMapper.buildGroups(from: [room], photos: [photo], visitId: "v1")
        XCTAssertNil(groups.heatSourceEvidence.pins.first?.linkedPhotoId)
    }
}
