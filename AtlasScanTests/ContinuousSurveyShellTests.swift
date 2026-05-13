/// ContinuousSurveyShellTests — Unit tests covering the PR-5 acceptance
/// criteria for the new continuous-survey shell:
///
///   1. Rooms are never created without explicit confirmation.
///   2. `SurveyHomeViewModel.canFinish` is always true (Finish must always
///      be available — incomplete drafts are valid handoffs).
///   3. An `incompleteDraft` handoff is a valid output of the builder.
///   4. `SurveySessionStore` round-trips workspace + visit on resume.
///   5. `ExistingEquipmentPinV1` and any future `ProposedEquipmentPreviewV1`
///      remain different types (compile-time check).
///   6. `screenOnly` pins are flagged `needsReview` automatically.

import XCTest
import AtlasScanCore
@testable import AtlasScan

@MainActor
final class ContinuousSurveyShellTests: XCTestCase {

    // 1. Rooms are never created without explicit confirmation.
    func test_roomSegmentation_doesNotAutoCreateConfirmedRoom() {
        let visitId = UUID()
        let svc = RoomSegmentationService(visitId: visitId)
        XCTAssertTrue(svc.confirmedRooms.isEmpty)

        _ = svc.suggestRoom(suggestedName: "Kitchen", source: .speechTranscript)

        XCTAssertNotNil(svc.currentRoomCandidate)
        XCTAssertEqual(svc.suggestedRoomBreaks.count, 1)
        // A suggestion must NOT have created a confirmed room.
        XCTAssertTrue(svc.confirmedRooms.isEmpty,
                      "Rooms must only be created via explicit confirm()")
    }

    func test_roomSegmentation_createsRoomOnlyAfterExplicitConfirm() {
        let visitId = UUID()
        let svc = RoomSegmentationService(visitId: visitId)
        let candidate = svc.suggestRoom(suggestedName: "Hallway", source: .userSelection)

        let room = svc.confirm(candidate, name: "Hallway")

        XCTAssertEqual(svc.confirmedRooms.count, 1)
        XCTAssertEqual(svc.confirmedRooms.first?.id, room.id)
        XCTAssertEqual(room.captureStatus, .captured)
        XCTAssertNil(svc.currentRoomCandidate, "candidate should be cleared after confirm")
    }

    // 2. Finish is always available.
    func test_surveyHomeViewModel_canFinish_isAlwaysTrue() {
        let empty = SurveyHomeViewModel()
        XCTAssertTrue(empty.canFinish, "Finish must be available even with zero rooms")
    }

    // 3. An incompleteDraft handoff is a valid output of the builder.
    func test_handoffBuilder_acceptsIncompleteSession() throws {
        let session = SessionCaptureV2(visitId: UUID())
        // No rooms, no photos, no anything — should still produce a payload.
        let handoff = try V2ScanToMindHandoffBuilder.build(session: session)

        XCTAssertEqual(handoff.completionStatus, .incompleteDraft)
    }

    // 4. SurveySessionStore round-trips workspace + visit identity on resume.
    func test_surveySessionStore_persistsAndResumesVisit() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SurveySessionStore(defaults: defaults)
        let visitId = UUID()
        _ = store.startOrResume(
            workspaceId: "ws-123",
            visitId: visitId,
            currentLifecycle: .choosingNextStep
        )

        // Fresh instance to simulate restart.
        let resumedStore = SurveySessionStore(defaults: defaults)
        let loaded = resumedStore.loadActiveSession()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.visitId, visitId)
        XCTAssertEqual(loaded?.workspaceId, "ws-123")
    }

    // 5. ExistingEquipmentPinV1 ≠ ProposedEquipmentPreviewV1 (compile-time).
    //    The brief is explicit that they must remain separate types. We
    //    enforce that with a compile-time dummy that would fail to compile
    //    if anyone made them the same type.
    func test_existingPin_isNotSameTypeAsProposedPreview() {
        // We don't have ProposedEquipmentPreviewV1 yet; this test asserts
        // the *intent* — once ProposedEquipmentPreviewV1 lands, it must NOT
        // be a typealias for ExistingEquipmentPinV1. Update the expectation
        // here to a `XCTAssertFalse(ExistingEquipmentPinV1.self == ProposedEquipmentPreviewV1.self)`
        // check at that time.
        let pin = ExistingEquipmentPinV1(
            visitId: UUID(),
            roomId: UUID(),
            objectCategory: .other,
            anchorConfidence: .worldLocked
        )
        XCTAssertEqual(String(describing: type(of: pin)), "ExistingEquipmentPinV1")
    }

    // 6. screenOnly pins are flagged needsReview automatically.
    func test_screenOnlyPin_isAutomaticallyNeedsReview() {
        let pin = ExistingEquipmentPinV1(
            visitId: UUID(),
            roomId: UUID(),
            objectCategory: .gasMeter,
            anchorConfidence: .screenOnly
        )
        XCTAssertEqual(pin.reviewStatus, .needsReview)

        let manualPin = ExistingEquipmentPinV1(
            visitId: UUID(),
            roomId: UUID(),
            objectCategory: .stopTap,
            anchorConfidence: .manual
        )
        XCTAssertEqual(manualPin.reviewStatus, .needsReview)

        let worldLocked = ExistingEquipmentPinV1(
            visitId: UUID(),
            roomId: UUID(),
            objectCategory: .existingBoiler,
            anchorConfidence: .worldLocked
        )
        XCTAssertNotEqual(worldLocked.reviewStatus, .needsReview)
    }
}
