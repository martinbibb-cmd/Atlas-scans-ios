import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - QuotePlannerEvidenceTests
//
// Tests for the quote-planner anchor feature.
//
// Covers:
//   - Encode a SessionCaptureV2 with a candidate boiler location
//   - Encode gas meter + proposed boiler + flue terminal anchors
//   - Existing exports without quotePlannerEvidence still work
//   - Confidence/provenance is preserved correctly
//   - Empty anchor list produces nil quotePlannerEvidence
//   - Builder maps draft anchors to contract types correctly
//   - Round-trip JSON encoding/decoding preserves all fields

final class QuotePlannerEvidenceTests: XCTestCase {

    // MARK: - Helpers

    private func makeVisit() -> AtlasScanVisit {
        AtlasScanVisit(visitNumber: "JOB-QP-TEST")
    }

    private func makeDraft() -> CaptureSessionDraft {
        CaptureSessionStore.newSession(visitReference: "JOB-QP-TEST")
    }

    private func makeAnchor(
        kind: QuoteAnchorKind,
        label: String? = nil,
        provenance: QuoteAnchorProvenance = .manual
    ) -> CapturedQuotePlannerAnchorDraft {
        var anchor = CapturedQuotePlannerAnchorDraft()
        anchor.kind = kind
        anchor.label = label
        anchor.provenance = provenance
        return anchor
    }

    // MARK: - Empty draft: quotePlannerEvidence is nil

    func test_build_emptyDraft_quotePlannerEvidenceIsNil() {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        XCTAssertNil(capture.quotePlannerEvidence,
                     "quotePlannerEvidence must be nil when no anchors recorded")
    }

    func test_build_emptyDraft_roundTripsAsValidJSON() throws {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let data = try JSONEncoder().encode(capture)
        let result = validateSessionCaptureV2(data)
        XCTAssertTrue(result.isSuccess, "Empty draft must produce valid payload; errors: \(result.errors)")
    }

    // MARK: - Single boiler anchor

    func test_build_singleBoilerAnchor_producesQuotePlannerEvidence() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .existingBoiler, label: "Kitchen boiler"))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertNotNil(capture.quotePlannerEvidence)
        XCTAssertEqual(capture.quotePlannerEvidence?.candidateLocations.count, 1)
        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertEqual(loc?.kind, "existing_boiler")
        XCTAssertEqual(loc?.label, "Kitchen boiler")
    }

    func test_build_boilerAnchor_manualProvenance_givesConfirmedConfidence() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .existingBoiler, provenance: .manual))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertEqual(loc?.confidence, "confirmed")
        XCTAssertEqual(loc?.provenance, "manual")
    }

    func test_build_boilerAnchor_roundTripsJSON() throws {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .existingBoiler, label: "Kitchen boiler"))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let data = try JSONEncoder().encode(capture)
        let decoded = try JSONDecoder().decode(SessionCaptureV2.self, from: data)

        XCTAssertNotNil(decoded.quotePlannerEvidence)
        XCTAssertEqual(decoded.quotePlannerEvidence?.candidateLocations.first?.kind, "existing_boiler")
        XCTAssertEqual(decoded.quotePlannerEvidence?.candidateLocations.first?.label, "Kitchen boiler")
    }

    // MARK: - Multiple anchors (gas meter + proposed boiler + flue terminal)

    func test_build_multipleAnchors_allExported() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .gasMeter, provenance: .manual))
        draft.quotePlannerAnchors.append(makeAnchor(kind: .proposedBoiler, provenance: .arPin))
        draft.quotePlannerAnchors.append(makeAnchor(kind: .proposedFlueTerminal, provenance: .floorPlanTap))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertEqual(capture.quotePlannerEvidence?.candidateLocations.count, 3)
        let kinds = capture.quotePlannerEvidence?.candidateLocations.map(\.kind) ?? []
        XCTAssertTrue(kinds.contains("gas_meter"))
        XCTAssertTrue(kinds.contains("proposed_boiler"))
        XCTAssertTrue(kinds.contains("proposed_flue_terminal"))
    }

    // MARK: - Confidence/provenance preservation

    func test_build_arPinProvenance_givesMeasuredConfidence() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .proposedBoiler, provenance: .arPin))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertEqual(loc?.confidence, "measured")
        XCTAssertEqual(loc?.provenance, "ar_pin")
    }

    func test_build_roomScanObjectProvenance_givesNeedsVerificationConfidence() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .existingBoiler, provenance: .roomScanObject))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertEqual(loc?.confidence, "needs_verification")
        XCTAssertEqual(loc?.provenance, "room_scan_object")
    }

    func test_build_screenOnlyProvenance_givesEstimatedConfidence() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .proposedBoiler, provenance: .floorPlanTap))
        draft.quotePlannerAnchors.append(makeAnchor(kind: .proposedCylinder, provenance: .photoAnnotation))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let locs = capture.quotePlannerEvidence?.candidateLocations ?? []
        XCTAssertTrue(locs.allSatisfy { $0.confidence == "estimated" })
    }

    // MARK: - Existing exports without quotePlannerEvidence remain valid

    func test_existingCapture_withoutQuotePlanner_decodesSuccessfully() throws {
        // Simulate a pre-existing payload that has no quotePlannerEvidence key.
        let json = """
        {
            "schemaVersion": "2.0",
            "sessionId": "existing-session-id",
            "visitReference": "JOB-LEGACY",
            "capturedAt": "2025-01-01T10:00:00.000Z",
            "exportedAt": "2025-01-01T11:00:00.000Z",
            "deviceModel": "iPhone 15 Pro",
            "roomScans": [],
            "photos": [],
            "voiceNotes": [],
            "objectPins": [],
            "floorPlanSnapshots": [],
            "qaFlags": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SessionCaptureV2.self, from: data)

        XCTAssertNil(decoded.quotePlannerEvidence,
                     "Legacy payload without quotePlannerEvidence must decode successfully with nil")
        XCTAssertEqual(decoded.sessionId, "existing-session-id")
    }

    // MARK: - Anchor ID is preserved

    func test_build_anchorId_preserved() {
        let visit = makeVisit()
        var draft = makeDraft()
        var anchor = makeAnchor(kind: .gasMeter)
        draft.quotePlannerAnchors.append(anchor)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertEqual(loc?.id, anchor.id.uuidString)
    }

    // MARK: - roomId is carried through

    func test_build_anchorWithRoomId_isPreserved() {
        let visit = makeVisit()
        var draft = makeDraft()
        let roomId = UUID()
        var anchor = makeAnchor(kind: .existingCylinder)
        anchor.roomId = roomId
        draft.quotePlannerAnchors.append(anchor)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertEqual(loc?.roomId, roomId.uuidString)
    }

    // MARK: - Coordinates are carried through

    func test_build_anchorWithCoordinates_isPreserved() {
        let visit = makeVisit()
        var draft = makeDraft()
        var anchor = makeAnchor(kind: .gasMeter, provenance: .arPin)
        anchor.coordinateX = 1.5
        anchor.coordinateY = 0.0
        anchor.coordinateZ = 2.3
        draft.quotePlannerAnchors.append(anchor)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertNotNil(loc?.coordinates)
        XCTAssertEqual(loc?.coordinates?.x, 1.5)
        XCTAssertEqual(loc?.coordinates?.y, 0.0)
        XCTAssertEqual(loc?.coordinates?.z, 2.3)
    }

    func test_build_anchorWithPartialCoordinates_coordinatesIsNil() {
        let visit = makeVisit()
        var draft = makeDraft()
        var anchor = makeAnchor(kind: .gasMeter)
        anchor.coordinateX = 1.5
        anchor.coordinateY = nil  // missing Y — no spatial lock
        anchor.coordinateZ = 2.3
        draft.quotePlannerAnchors.append(anchor)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertNil(loc?.coordinates,
                     "Partial coordinates must produce nil; all three components required")
    }

    // MARK: - Linked photos and pins

    func test_build_linkedPhotoIds_arePreserved() {
        let visit = makeVisit()
        var draft = makeDraft()
        let photoId = UUID()
        var anchor = makeAnchor(kind: .existingBoiler)
        anchor.linkedPhotoIds = [photoId]
        draft.quotePlannerAnchors.append(anchor)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertEqual(loc?.linkedPhotoIds, [photoId.uuidString])
    }

    func test_build_linkedObjectPinIds_arePreserved() {
        let visit = makeVisit()
        var draft = makeDraft()
        let pinId = UUID()
        var anchor = makeAnchor(kind: .existingBoiler)
        anchor.linkedObjectPinIds = [pinId]
        draft.quotePlannerAnchors.append(anchor)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let loc = capture.quotePlannerEvidence?.candidateLocations.first
        XCTAssertEqual(loc?.linkedObjectPinIds, [pinId.uuidString])
    }

    // MARK: - All anchor kinds round-trip

    func test_allAnchorKinds_roundTripAsRawValues() throws {
        let visit = makeVisit()
        var draft = makeDraft()
        for kind in QuoteAnchorKind.allCases {
            draft.quotePlannerAnchors.append(makeAnchor(kind: kind))
        }

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let data = try JSONEncoder().encode(capture)
        let decoded = try JSONDecoder().decode(SessionCaptureV2.self, from: data)

        let exportedKinds = decoded.quotePlannerEvidence?.candidateLocations.map(\.kind) ?? []
        XCTAssertEqual(exportedKinds.count, QuoteAnchorKind.allCases.count)
        for kind in QuoteAnchorKind.allCases {
            XCTAssertTrue(exportedKinds.contains(kind.rawValue),
                          "Kind '\(kind.rawValue)' missing from exported payload")
        }
    }

    // MARK: - candidateRoutes helpers

    private func makeRoute(
        routeType: CandidateRouteType,
        status: CandidateRouteStatus = .proposed,
        installMethod: CandidateRouteInstallMethod? = nil,
        provenance: QuoteAnchorProvenance = .manual,
        notes: String = ""
    ) -> CapturedCandidateRouteDraft {
        var route = CapturedCandidateRouteDraft()
        route.routeType = routeType
        route.status = status
        route.installMethod = installMethod
        route.provenance = provenance
        route.notes = notes
        return route
    }

    // MARK: - Empty draft: candidateRoutes is empty

    func test_build_emptyDraft_candidateRoutesIsEmpty() {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        XCTAssertNil(capture.quotePlannerEvidence,
                     "quotePlannerEvidence must be nil when no anchors or routes recorded")
    }

    // MARK: - Candidate gas route exports

    func test_build_candidateGasRoute_exports() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.candidateRoutes.append(makeRoute(routeType: .gas, status: .proposed))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertNotNil(capture.quotePlannerEvidence)
        XCTAssertEqual(capture.quotePlannerEvidence?.candidateRoutes.count, 1)
        let route = capture.quotePlannerEvidence?.candidateRoutes.first
        XCTAssertEqual(route?.routeType, "gas")
        XCTAssertEqual(route?.status, "proposed")
    }

    // MARK: - Candidate condensate route exports

    func test_build_candidateCondensateRoute_exports() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.candidateRoutes.append(makeRoute(routeType: .condensate, status: .proposed,
                                               installMethod: .surface))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertNotNil(capture.quotePlannerEvidence)
        let route = capture.quotePlannerEvidence?.candidateRoutes.first
        XCTAssertEqual(route?.routeType, "condensate")
        XCTAssertEqual(route?.installMethod, "surface")
    }

    // MARK: - Route with no scale does not claim measured coordinates

    func test_build_routeWithNoScale_waypointCoordinatesAreNil() {
        let visit = makeVisit()
        var draft = makeDraft()
        var route = makeRoute(routeType: .heatingFlow)
        var waypoint = CandidateRouteWaypointDraft()
        // Deliberately set no 3-D coordinates (notes-only route).
        waypoint.planX = 0.3
        waypoint.planY = 0.5
        route.waypoints.append(waypoint)
        draft.candidateRoutes.append(route)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let exportedWaypoint = capture.quotePlannerEvidence?.candidateRoutes.first?.waypoints.first
        XCTAssertNotNil(exportedWaypoint, "Waypoint must be exported")
        XCTAssertNil(exportedWaypoint?.coordinates,
                     "Waypoint without 3-D coordinates must export nil coordinates; no measured length claimed")
        XCTAssertEqual(exportedWaypoint?.planX, 0.3)
        XCTAssertEqual(exportedWaypoint?.planY, 0.5)
    }

    // MARK: - Assumed route remains assumed

    func test_build_assumedRoute_remainsAssumed() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.candidateRoutes.append(makeRoute(routeType: .gas, status: .assumed))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        let route = capture.quotePlannerEvidence?.candidateRoutes.first
        XCTAssertEqual(route?.status, "assumed",
                       "Assumed route status must survive the builder unchanged")
    }

    // MARK: - All route types round-trip

    func test_allRouteTypes_roundTripAsRawValues() throws {
        let visit = makeVisit()
        var draft = makeDraft()
        for routeType in CandidateRouteType.allCases {
            draft.candidateRoutes.append(makeRoute(routeType: routeType))
        }

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let data = try JSONEncoder().encode(capture)
        let decoded = try JSONDecoder().decode(SessionCaptureV2.self, from: data)

        let exportedTypes = decoded.quotePlannerEvidence?.candidateRoutes.map(\.routeType) ?? []
        XCTAssertEqual(exportedTypes.count, CandidateRouteType.allCases.count)
        for routeType in CandidateRouteType.allCases {
            XCTAssertTrue(exportedTypes.contains(routeType.rawValue),
                          "Route type '\(routeType.rawValue)' missing from exported payload")
        }
    }

    // MARK: - Route notes exported

    func test_build_routeWithNotes_notesExported() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.candidateRoutes.append(makeRoute(routeType: .gas, notes: "Run through utility room"))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertEqual(capture.quotePlannerEvidence?.candidateRoutes.first?.notes,
                       "Run through utility room")
    }

    func test_build_routeWithEmptyNotes_notesIsNil() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.candidateRoutes.append(makeRoute(routeType: .gas, notes: ""))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertNil(capture.quotePlannerEvidence?.candidateRoutes.first?.notes,
                     "Empty notes must export as nil")
    }

    // MARK: - Route ID is preserved

    func test_build_routeId_preserved() {
        let visit = makeVisit()
        var draft = makeDraft()
        let route = makeRoute(routeType: .condensate)
        draft.candidateRoutes.append(route)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertEqual(capture.quotePlannerEvidence?.candidateRoutes.first?.id,
                       route.id.uuidString)
    }

    // MARK: - Anchors + routes together produce evidence

    func test_build_anchorsAndRoutes_bothExported() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .existingBoiler))
        draft.candidateRoutes.append(makeRoute(routeType: .gas))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)

        XCTAssertNotNil(capture.quotePlannerEvidence)
        XCTAssertEqual(capture.quotePlannerEvidence?.candidateLocations.count, 1)
        XCTAssertEqual(capture.quotePlannerEvidence?.candidateRoutes.count, 1)
    }

    // MARK: - Existing payload without candidateRoutes decodes with empty array

    func test_existingCapture_withQuotePlannerButNoCandidateRoutes_decodesSuccessfully() throws {
        let json = """
        {
            "schemaVersion": "2.0",
            "sessionId": "legacy-session-id",
            "visitReference": "JOB-LEGACY-ROUTE",
            "capturedAt": "2025-01-01T10:00:00.000Z",
            "exportedAt": "2025-01-01T11:00:00.000Z",
            "deviceModel": "iPhone 15 Pro",
            "roomScans": [],
            "photos": [],
            "voiceNotes": [],
            "objectPins": [],
            "floorPlanSnapshots": [],
            "qaFlags": [],
            "quotePlannerEvidence": {
                "candidateLocations": []
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SessionCaptureV2.self, from: data)

        XCTAssertNotNil(decoded.quotePlannerEvidence)
        XCTAssertEqual(decoded.quotePlannerEvidence?.candidateRoutes.count, 0,
                       "Legacy payload without candidateRoutes must decode as empty array")
    }
}
