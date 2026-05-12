import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - ScanToMindHandoffTests
//
// Tests for the Scan → Mind handoff feature.
//
// Covers:
//   - Canonical payload shape: kind, schemaVersion (Int), visit, capture
//   - buildHandoffFromDraft: visit.visitId == capture.sessionId
//   - buildHandoffFromDraft: has expected reason
//   - buildHandoffFromDraft: visit.visitId matches draft.id.uuidString
//   - quotePlannerEvidence is included in the handoff when anchors present
//   - quotePlannerEvidence is nil when no anchors
//   - buildHandoff (visit-based) with quotePlanner reason succeeds
//   - makeQuotePlannerURL contains sessionRef
//   - makeQuotePlannerURL contains percent-encoded payload for small sessions
//   - makeQuotePlannerURL falls back to sessionRef-only when payload too large
//   - The quote-planner URL is not a raw JSON dump
//   - Payload round-trips: decoded handoff has matching visit.visitId
//   - quotePlanner reason raw value is "quote_planner"
//   - JSON fixture round-trip using canonical payload

final class ScanToMindHandoffTests: XCTestCase {

    // MARK: - Helpers

    private func makeVisit(visitNumber: String = "JOB-HANDOFF-TEST") -> AtlasScanVisit {
        AtlasScanVisit(visitNumber: visitNumber)
    }

    private func makeDraft(
        visitReference: String = "JOB-HANDOFF-TEST",
        complete: Bool = false
    ) -> CaptureSessionDraft {
        var draft = CaptureSessionStore.newSession(visitReference: visitReference)
        // Add minimal evidence so CaptureSessionExporter.export succeeds.
        var scan = CapturedRoomScanDraft()
        scan.roomLabel = "Kitchen"
        draft.roomScans.append(scan)
        draft.photos.append(CapturedPhotoDraft(localFilename: "overview.jpg"))
        if complete {
            draft.propertyAddress = "1 Atlas Way"

            var boiler = CapturedObjectPinDraft(type: .boiler)
            boiler.roomId = scan.id
            boiler.pinSource = .manual
            boiler.reviewStatus = .confirmed

            var flue = CapturedObjectPinDraft(type: .flue)
            flue.roomId = scan.id
            flue.pinSource = .manual
            flue.reviewStatus = .confirmed

            draft.objectPins.append(contentsOf: [boiler, flue])

            var note = CapturedVoiceNoteDraft()
            note.roomId = scan.id
            note.transcript = "Boiler and flue confirmed."
            note.reviewStatus = .confirmed
            draft.voiceNotes.append(note)
        }
        return draft
    }

    private func makeAnchor(kind: QuoteAnchorKind) -> CapturedQuotePlannerAnchorDraft {
        var anchor = CapturedQuotePlannerAnchorDraft()
        anchor.kind = kind
        anchor.provenance = .manual
        return anchor
    }

    // MARK: - ScanToMindHandoffReasonV1 raw values

    func test_quotePlannerReason_hasCorrectRawValue() {
        XCTAssertEqual(ScanToMindHandoffReasonV1.quotePlanner.rawValue, "quote_planner")
    }

    func test_quotePlannerReason_isInAllCases() {
        XCTAssertTrue(ScanToMindHandoffReasonV1.allCases.contains(.quotePlanner))
    }

    // MARK: - Canonical payload shape

    func test_handoff_kind_isCorrect() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: makeVisit(), draft: draft)
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(draft, capture: capture, reason: .reviewInMind)
        XCTAssertEqual(handoff.kind, "scan-to-mind-handoff")
    }

    func test_handoff_schemaVersion_isNumericOne() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: makeVisit(), draft: draft)
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(draft, capture: capture, reason: .reviewInMind)
        XCTAssertEqual(handoff.schemaVersion, 1)
    }

    func test_handoff_sourceApp_isScanIOS() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: makeVisit(), draft: draft)
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(draft, capture: capture, reason: .quotePlanner)
        XCTAssertEqual(handoff.sourceApp, "scan_ios")
        XCTAssertEqual(handoff.targetApp, "mind_pwa")
    }

    func test_handoff_visit_hasVersionOne() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: makeVisit(), draft: draft)
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(draft, capture: capture, reason: .reviewInMind)
        XCTAssertEqual(handoff.visit.version, "1.0")
    }

    func test_handoff_visit_hasStatus() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: makeVisit(), draft: draft)
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(draft, capture: capture, reason: .reviewInMind)
        XCTAssertFalse(handoff.visit.status.isEmpty, "visit.status must be non-empty")
    }

    // MARK: - buildHandoffFromDraft

    func test_buildHandoffFromDraft_visitIdEqualsCaptureSessionId() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(
            visit: makeVisit(),
            draft: draft
        )
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .quotePlanner
        )
        XCTAssertEqual(handoff.visit.visitId, handoff.capture.sessionId,
                       "visit.visitId must equal capture.sessionId")
    }

    func test_buildHandoffFromDraft_hasQuotePlannerReason() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(
            visit: makeVisit(),
            draft: draft
        )
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .quotePlanner
        )
        XCTAssertEqual(handoff.reason, .quotePlanner)
    }

    func test_buildHandoffFromDraft_visitIdMatchesDraftId() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(
            visit: makeVisit(),
            draft: draft
        )
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .quotePlanner
        )
        XCTAssertEqual(handoff.visit.visitId, draft.id.uuidString,
                       "visit.visitId must equal draft.id.uuidString")
    }

    // MARK: - quotePlannerEvidence is included in the handoff

    func test_handoff_includesQuotePlannerEvidence_whenAnchorsPresent() {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .existingBoiler))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .quotePlanner
        )

        XCTAssertNotNil(handoff.capture.quotePlannerEvidence,
                        "Handoff capture must include quotePlannerEvidence when anchors are present")
        XCTAssertEqual(handoff.capture.quotePlannerEvidence?.candidateLocations.count, 1)
    }

    func test_handoff_quotePlannerEvidenceNil_whenNoAnchors() {
        let visit = makeVisit()
        let draft = makeDraft()

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .quotePlanner
        )

        XCTAssertNil(handoff.capture.quotePlannerEvidence,
                     "quotePlannerEvidence must be nil when no anchors were captured")
    }

    // MARK: - buildHandoff (visit-based) with quotePlanner reason

    func test_buildHandoff_withQuotePlannerReason_succeeds() throws {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .gasMeter))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = try ScanToMindHandoffBuilder.buildHandoff(
            visit: visit,
            capture: capture,
            reason: .quotePlanner
        )

        XCTAssertEqual(handoff.reason, .quotePlanner)
        XCTAssertNotNil(handoff.capture.quotePlannerEvidence)
    }

    func test_buildHandoff_visitSnapshot_matchesVisitFields() throws {
        var visit = makeVisit(visitNumber: "JOB-SNAP-001")
        visit.brandId = "BRAND-A"
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = try ScanToMindHandoffBuilder.buildHandoff(
            visit: visit,
            capture: capture,
            reason: .completedCapture
        )
        XCTAssertEqual(handoff.visit.visitId, visit.visitId)
        XCTAssertEqual(handoff.visit.visitNumber, "JOB-SNAP-001")
        XCTAssertEqual(handoff.visit.brandId, "BRAND-A")
        XCTAssertEqual(handoff.visit.status, visit.status.rawValue)
    }

    // MARK: - makeQuotePlannerURL

    func test_makeQuotePlannerURL_containsSessionRef() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(
            visit: makeVisit(),
            draft: draft
        )
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .quotePlanner
        )

        let url = OpenAtlasMind.makeQuotePlannerURL(for: handoff)
        let urlString = url.absoluteString

        XCTAssertTrue(urlString.contains("sessionRef="),
                      "Quote planner URL must contain sessionRef parameter")
        XCTAssertTrue(urlString.contains(handoff.visit.visitId),
                      "Quote planner URL must contain the visitId as sessionRef value")
    }

    func test_makeQuotePlannerURL_containsPayload_forSmallSession() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(
            visit: makeVisit(),
            draft: draft
        )
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .quotePlanner
        )

        let url = OpenAtlasMind.makeQuotePlannerURL(for: handoff)
        let urlString = url.absoluteString

        // A minimal session should fit within the URL length limit.
        XCTAssertTrue(urlString.contains("payload="),
                      "Minimal session payload must be included in the quote planner URL")
    }

    func test_makeQuotePlannerURL_isNotRawJSONDump() {
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(
            visit: makeVisit(),
            draft: draft
        )
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .quotePlanner
        )

        let url = OpenAtlasMind.makeQuotePlannerURL(for: handoff)
        let urlString = url.absoluteString

        // The URL must NOT contain unencoded curly braces — it must be percent-encoded.
        XCTAssertFalse(urlString.contains("{"),
                       "URL must not contain raw JSON braces — payload must be percent-encoded")
        XCTAssertFalse(urlString.contains("}"),
                       "URL must not contain raw JSON braces — payload must be percent-encoded")
    }

    func test_makeQuotePlannerURL_fallsBackToSessionRefOnly_whenPayloadExceedsLimit() throws {
        // Build a session large enough to exceed the URL length limit by stuffing a long transcript.
        let draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = String(repeating: "x", count: 20_000)
        var largeDraft = draft
        largeDraft.voiceNotes.append(note)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(
            visit: makeVisit(),
            draft: largeDraft
        )
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            largeDraft,
            capture: capture,
            reason: .quotePlanner
        )

        let url = OpenAtlasMind.makeQuotePlannerURL(for: handoff)
        let urlString = url.absoluteString

        // The URL must not exceed the limit.
        XCTAssertLessThanOrEqual(urlString.count, 8_000,
                                 "Quote planner URL must not exceed 8,000 characters")

        // The sessionRef must still be present even when payload is omitted.
        XCTAssertTrue(urlString.contains("sessionRef="),
                      "sessionRef must be present in the fallback URL")
        XCTAssertTrue(urlString.contains(handoff.visit.visitId),
                      "visitId must be the sessionRef value in the fallback URL")
    }

    // MARK: - Payload round-trip

    func test_quotePlannerHandoff_roundTrips_viaURLEncoding() throws {
        let visit = makeVisit()
        var draft = makeDraft()
        draft.quotePlannerAnchors.append(makeAnchor(kind: .proposedBoiler))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = try ScanToMindHandoffBuilder.buildHandoff(
            visit: visit,
            capture: capture,
            reason: .quotePlanner
        )

        let encoded = try ScanToMindPayloadEncoder.encodeForURL(handoff)
        let decoded = try ScanToMindPayloadEncoder.decodeFromURLPayload(encoded)

        XCTAssertEqual(decoded.visit.visitId, handoff.visit.visitId)
        XCTAssertEqual(decoded.capture.sessionId, handoff.capture.sessionId)
        XCTAssertEqual(decoded.reason, .quotePlanner)
        XCTAssertNotNil(decoded.capture.quotePlannerEvidence)
        XCTAssertEqual(decoded.capture.quotePlannerEvidence?.candidateLocations.first?.kind,
                       QuoteAnchorKind.proposedBoiler.rawValue)
    }

    func test_incompleteDraft_handoffImport_roundTripsAndRequiresReview() throws {
        let visit = makeVisit()
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = try ScanToMindHandoffBuilder.buildHandoff(
            visit: visit,
            capture: capture,
            reason: .reviewInMind
        )

        let encoded = try ScanToMindPayloadEncoder.encodeForURL(handoff)
        let decoded = try ScanToMindPayloadEncoder.decodeFromURLPayload(encoded)

        XCTAssertEqual(decoded.completionStatus, .incompleteDraft)
        XCTAssertFalse(decoded.missingEvidence.isEmpty, "Incomplete imports must retain missing evidence.")
        XCTAssertTrue(decoded.requiresReview, "Incomplete imports must remain review-required, not failed.")
    }

    func test_complete_handoffImport_roundTripsWithoutReviewLock() throws {
        let visit = makeVisit()
        let draft = makeDraft(complete: true)
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = try ScanToMindHandoffBuilder.buildHandoff(
            visit: visit,
            capture: capture,
            reason: .completedCapture
        )

        let encoded = try ScanToMindPayloadEncoder.encodeForURL(handoff)
        let decoded = try ScanToMindPayloadEncoder.decodeFromURLPayload(encoded)

        XCTAssertEqual(decoded.completionStatus, .complete)
        XCTAssertTrue(decoded.missingEvidence.isEmpty)
        XCTAssertFalse(decoded.requiresReview)
        XCTAssertTrue(decoded.finalOutputsAllowed)
    }

    // MARK: - JSON fixture round-trip (canonical shape)

    func test_canonicalPayload_encodesAndDecodes() throws {
        let visit = makeVisit(visitNumber: "JOB-FIXTURE-001")
        let draft = makeDraft()
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = try ScanToMindHandoffBuilder.buildHandoff(
            visit: visit,
            capture: capture,
            reason: .completedCapture
        )

        // Encode to JSON.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(handoff)
        let jsonString = try XCTUnwrap(String(data: jsonData, encoding: .utf8))

        // Top-level keys must be present.
        XCTAssertTrue(jsonString.contains("\"kind\""), "JSON must contain 'kind' key")
        XCTAssertTrue(jsonString.contains("\"schemaVersion\""), "JSON must contain 'schemaVersion' key")
        XCTAssertTrue(jsonString.contains("\"visit\""), "JSON must contain 'visit' key")
        XCTAssertTrue(jsonString.contains("\"capture\""), "JSON must contain 'capture' key")

        // schemaVersion must be encoded as a number, not a quoted string.
        XCTAssertTrue(jsonString.contains("\"schemaVersion\":1"),
                      "schemaVersion must be encoded as numeric 1, not a string")

        // kind must be the discriminator.
        XCTAssertTrue(jsonString.contains("\"kind\":\"scan-to-mind-handoff\""),
                      "kind must equal 'scan-to-mind-handoff'")

        // Round-trip decode.
        let decoded = try JSONDecoder().decode(ScanToMindHandoffV1.self, from: jsonData)
        XCTAssertEqual(decoded.kind, "scan-to-mind-handoff")
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.visit.visitId, handoff.visit.visitId)
        XCTAssertEqual(decoded.capture.sessionId, handoff.capture.sessionId)
    }

    func test_handoff_includesSpatialEvidenceGraph_groupedByRoomAndCapturePoint() {
        let visit = makeVisit()
        var draft = makeDraft()
        let roomId = draft.roomScans.first?.id
        let capturePointId = UUID()

        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.roomId = roomId
        pin.capturePointId = capturePointId
        pin.pinConfidence = .manual
        pin.reviewStatus = .confirmed
        draft.objectPins = [pin]

        var photo = CapturedPhotoDraft(localFilename: "cp-photo.jpg")
        photo.roomId = roomId
        photo.capturePointId = capturePointId
        draft.photos.append(photo)

        var note = CapturedVoiceNoteDraft()
        note.roomId = roomId
        note.capturePointId = capturePointId
        note.transcript = "Boiler evidence transcript"
        draft.voiceNotes.append(note)

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .reviewInMind
        )

        XCTAssertFalse(handoff.spatialEvidenceGraph.rooms.isEmpty)
        let roomGraph = handoff.spatialEvidenceGraph.rooms.first
        XCTAssertEqual(roomGraph?.roomId, roomId?.uuidString)
        let point = roomGraph?.capturePoints.first(where: { $0.capturePointId == capturePointId.uuidString })
        XCTAssertNotNil(point)
        XCTAssertEqual(point?.objectPins.count, 1)
        XCTAssertEqual(point?.photos.count, 1)
        XCTAssertEqual(point?.voiceNotes.count, 1)
        XCTAssertEqual(point?.transcripts.count, 1)
    }

    func test_handoff_unresolvedEvidence_includesScreenOnlyAndUnknownSurfaceWarnings() {
        let visit = makeVisit()
        var draft = makeDraft()
        let roomId = draft.roomScans.first?.id
        let capturePointId = UUID()

        var pin = CapturedObjectPinDraft(type: .genericNote)
        pin.roomId = roomId
        pin.capturePointId = capturePointId
        pin.pinConfidence = .needsReview
        pin.reviewStatus = .pending
        draft.objectPins = [pin]

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
            draft,
            capture: capture,
            reason: .reviewInMind
        )

        XCTAssertTrue(
            handoff.unresolvedEvidence.contains(where: { $0.kind == "screen_only_point" }),
            "Unresolved evidence must contain screen-only review items"
        )
        XCTAssertTrue(
            handoff.unresolvedEvidence.contains(where: { $0.kind == "unknown_surface_semantic" }),
            "Unresolved evidence must contain unknown surface semantic items"
        )
    }
}
