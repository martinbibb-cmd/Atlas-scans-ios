import XCTest
import AtlasContracts

// MARK: - VisitCompletionValidatorTests
//
// Unit tests for the pure completion validator.
// Covers:
//   - All readiness flags false → not completable, all seven items listed
//   - All readiness flags true  → completable, no missing items
//   - Each individual missing flag → correct VisitCompletionMissingItem produced
//   - CompletionMethod display names
//   - VisitCompletionMissingItem human-readable descriptions

final class VisitCompletionValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeReadiness(
        hasRooms: Bool = true,
        hasPhotos: Bool = true,
        hasHeatingSystem: Bool = true,
        hasHotWaterSystem: Bool = true,
        hasBoiler: Bool = true,
        hasFlue: Bool = true,
        hasNotes: Bool = true
    ) -> VisitReadinessV1 {
        VisitReadinessV1(
            hasRooms: hasRooms,
            hasPhotos: hasPhotos,
            hasHeatingSystem: hasHeatingSystem,
            hasHotWaterSystem: hasHotWaterSystem,
            hasBoiler: hasBoiler,
            hasFlue: hasFlue,
            hasNotes: hasNotes
        )
    }

    // MARK: - All flags false

    func test_allFlagsFalse_notCompletable() {
        let readiness = makeReadiness(
            hasRooms: false,
            hasPhotos: false,
            hasHeatingSystem: false,
            hasHotWaterSystem: false,
            hasBoiler: false,
            hasFlue: false,
            hasNotes: false
        )
        let result = validateVisitForCompletion(readiness: readiness)
        XCTAssertFalse(result.isCompletable)
    }

    func test_allFlagsFalse_allSevenItemsListed() {
        let readiness = makeReadiness(
            hasRooms: false,
            hasPhotos: false,
            hasHeatingSystem: false,
            hasHotWaterSystem: false,
            hasBoiler: false,
            hasFlue: false,
            hasNotes: false
        )
        let result = validateVisitForCompletion(readiness: readiness)
        XCTAssertEqual(result.missingItems.count, 7)
        XCTAssertTrue(result.missingItems.contains(.rooms))
        XCTAssertTrue(result.missingItems.contains(.photos))
        XCTAssertTrue(result.missingItems.contains(.heatingSystem))
        XCTAssertTrue(result.missingItems.contains(.hotWaterSystem))
        XCTAssertTrue(result.missingItems.contains(.boiler))
        XCTAssertTrue(result.missingItems.contains(.flue))
        XCTAssertTrue(result.missingItems.contains(.notes))
    }

    // MARK: - All flags true

    func test_allFlagsTrue_isCompletable() {
        let readiness = makeReadiness()
        let result = validateVisitForCompletion(readiness: readiness)
        XCTAssertTrue(result.isCompletable)
    }

    func test_allFlagsTrue_noMissingItems() {
        let readiness = makeReadiness()
        let result = validateVisitForCompletion(readiness: readiness)
        XCTAssertTrue(result.missingItems.isEmpty)
    }

    // MARK: - Individual missing flags

    func test_missingRooms_producesMissingItemRooms() {
        let result = validateVisitForCompletion(readiness: makeReadiness(hasRooms: false))
        XCTAssertFalse(result.isCompletable)
        XCTAssertTrue(result.missingItems.contains(.rooms))
    }

    func test_missingPhotos_producesMissingItemPhotos() {
        let result = validateVisitForCompletion(readiness: makeReadiness(hasPhotos: false))
        XCTAssertFalse(result.isCompletable)
        XCTAssertTrue(result.missingItems.contains(.photos))
    }

    func test_missingHeatingSystem_producesMissingItemHeatingSystem() {
        let result = validateVisitForCompletion(readiness: makeReadiness(hasHeatingSystem: false))
        XCTAssertFalse(result.isCompletable)
        XCTAssertTrue(result.missingItems.contains(.heatingSystem))
    }

    func test_missingHotWaterSystem_producesMissingItemHotWaterSystem() {
        let result = validateVisitForCompletion(readiness: makeReadiness(hasHotWaterSystem: false))
        XCTAssertFalse(result.isCompletable)
        XCTAssertTrue(result.missingItems.contains(.hotWaterSystem))
    }

    func test_missingBoiler_producesMissingItemBoiler() {
        let result = validateVisitForCompletion(readiness: makeReadiness(hasBoiler: false))
        XCTAssertFalse(result.isCompletable)
        XCTAssertTrue(result.missingItems.contains(.boiler))
    }

    func test_missingFlue_producesMissingItemFlue() {
        let result = validateVisitForCompletion(readiness: makeReadiness(hasFlue: false))
        XCTAssertFalse(result.isCompletable)
        XCTAssertTrue(result.missingItems.contains(.flue))
    }

    func test_missingNotes_producesMissingItemNotes() {
        let result = validateVisitForCompletion(readiness: makeReadiness(hasNotes: false))
        XCTAssertFalse(result.isCompletable)
        XCTAssertTrue(result.missingItems.contains(.notes))
    }

    // MARK: - Missing item ordering

    func test_missingItemsOrder_followsRequiredItemOrder() {
        // Omit several flags and confirm the order is deterministic.
        let result = validateVisitForCompletion(readiness: makeReadiness(
            hasRooms: false,
            hasPhotos: false,
            hasNotes: false
        ))
        XCTAssertEqual(result.missingItems[0], .rooms)
        XCTAssertEqual(result.missingItems[1], .photos)
        XCTAssertEqual(result.missingItems[2], .notes)
    }

    // MARK: - Human-readable descriptions

    func test_humanReadableDescription_rooms() {
        XCTAssertEqual(
            VisitCompletionMissingItem.rooms.humanReadableDescription,
            "Add at least one room"
        )
    }

    func test_humanReadableDescription_photos() {
        XCTAssertEqual(
            VisitCompletionMissingItem.photos.humanReadableDescription,
            "Add at least one photo"
        )
    }

    func test_humanReadableDescription_heatingSystem() {
        XCTAssertEqual(
            VisitCompletionMissingItem.heatingSystem.humanReadableDescription,
            "Confirm heating system"
        )
    }

    func test_humanReadableDescription_hotWaterSystem() {
        XCTAssertEqual(
            VisitCompletionMissingItem.hotWaterSystem.humanReadableDescription,
            "Confirm hot water system"
        )
    }

    func test_humanReadableDescription_boiler() {
        XCTAssertEqual(
            VisitCompletionMissingItem.boiler.humanReadableDescription,
            "Tag the boiler"
        )
    }

    func test_humanReadableDescription_flue() {
        XCTAssertEqual(
            VisitCompletionMissingItem.flue.humanReadableDescription,
            "Tag the flue"
        )
    }

    func test_humanReadableDescription_notes() {
        XCTAssertEqual(
            VisitCompletionMissingItem.notes.humanReadableDescription,
            "Add notes or transcript"
        )
    }

    // MARK: - CompletionMethod

    func test_completionMethod_manualDisplayName() {
        XCTAssertEqual(CompletionMethod.manual.displayName, "Manual")
    }

    func test_completionMethod_manualRawValue() {
        XCTAssertEqual(CompletionMethod.manual.rawValue, "manual")
    }

    func test_completionMethod_roundTrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(CompletionMethod.manual)
        let decoded = try decoder.decode(CompletionMethod.self, from: data)
        XCTAssertEqual(decoded, .manual)
    }
}
