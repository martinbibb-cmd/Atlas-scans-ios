import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - ScanToMindHandoffTests
//
// Tests for the quote-planner handoff feature.
//
// Covers:
//   - Completed visit creates a handoff with reason .quotePlanner
//   - Handoff includes quotePlannerEvidence when anchors are present
//   - buildHandoffFromDraft produces visitId == sessionId
//   - makeQuotePlannerURL contains sessionRef
//   - makeQuotePlannerURL contains percent-encoded payload for small sessions
//   - makeQuotePlannerURL falls back to sessionRef-only when payload is too large
//   - The quote-planner URL is not a raw JSON dump — it is properly percent-encoded
//   - Payload round-trips: decoded handoff has matching visitId and sessionId
//   - quotePlanner reason raw value is "quote_planner"

final class ScanToMindHandoffTests: XCTestCase {

    // MARK: - Helpers

    private func makeVisit(visitNumber: String = "JOB-HANDOFF-TEST") -> AtlasScanVisit {
        AtlasScanVisit(visitNumber: visitNumber)
    }

    private func makeDraft(visitReference: String = "JOB-HANDOFF-TEST") -> CaptureSessionDraft {
        var draft = CaptureSessionStore.newSession(visitReference: visitReference)
        // Add minimal evidence so CaptureSessionExporter.export succeeds.
        var scan = CapturedRoomScanDraft()
        scan.roomLabel = "Kitchen"
        draft.roomScans.append(scan)
        draft.photos.append(CapturedPhotoDraft(localFilename: "overview.jpg"))
        return draft
    }

    private func makeAnchor(kind: QuoteAnchorKind) -> CapturedQuotePlannerAnchorDraft {
        var anchor = CapturedQuotePlannerAnchorDraft()
        anchor.kind = kind
        anchor.provenance = .manual
        return anchor
    }

    // MARK: - ScanToMindHandoffReasonV1.quotePlanner raw value

    func test_quotePlannerReason_hasCorrectRawValue() {
        XCTAssertEqual(ScanToMindHandoffReasonV1.quotePlanner.rawValue, "quote_planner")
    }

    func test_quotePlannerReason_isInAllCases() {
        XCTAssertTrue(ScanToMindHandoffReasonV1.allCases.contains(.quotePlanner))
    }

    // MARK: - buildHandoffFromDraft

    func test_buildHandoffFromDraft_visitIdEqualsSessionId() {
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
        XCTAssertEqual(handoff.visitId, handoff.sessionId,
                       "buildHandoffFromDraft must produce matching visitId and sessionId")
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

    func test_buildHandoffFromDraft_sessionIdMatchesDraftId() {
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
        XCTAssertEqual(handoff.sessionId, draft.id.uuidString,
                       "sessionId must equal draft.id.uuidString")
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
        XCTAssertTrue(urlString.contains(handoff.visitId),
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
        XCTAssertTrue(urlString.contains(handoff.visitId),
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

        XCTAssertEqual(decoded.visitId, handoff.visitId)
        XCTAssertEqual(decoded.sessionId, handoff.sessionId)
        XCTAssertEqual(decoded.reason, .quotePlanner)
        XCTAssertNotNil(decoded.capture.quotePlannerEvidence)
        XCTAssertEqual(decoded.capture.quotePlannerEvidence?.candidateLocations.first?.kind,
                       QuoteAnchorKind.proposedBoiler.rawValue)
    }

    // MARK: - sourceApp / targetApp identity

    func test_quotePlannerHandoff_sourceApp_isScanIOS() {
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
        XCTAssertEqual(handoff.sourceApp, "scan_ios")
        XCTAssertEqual(handoff.targetApp, "mind_pwa")
    }
}
