import XCTest
@testable import AtlasScan

// MARK: - SessionKnowledgeExtractorTests
//
// Tests for conservative keyword extraction from voice note text.

final class SessionKnowledgeExtractorTests: XCTestCase {

    // MARK: - Explicit hint (high confidence)

    func test_extractFacts_explicitHint_producesHighConfidenceFact() {
        let note = VoiceNote(
            localFilename: "test.m4a",
            caption: "Family of five, two adults, three children.",
            extractionHint: .householdComposition
        )
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)

        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts[0].category, .householdComposition)
        XCTAssertEqual(facts[0].confidence, .high)
        XCTAssertEqual(facts[0].sourceNoteID, note.id)
    }

    func test_extractFacts_explicitHint_emptyCaption_producesNoFacts() {
        let note = VoiceNote(
            localFilename: "test.m4a",
            caption: "",
            extractionHint: .customerPriority
        )
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertTrue(facts.isEmpty)
    }

    func test_extractFacts_explicitHint_onlyTranscript_producesHighConfidenceFact() {
        var note = VoiceNote(
            localFilename: "test.m4a",
            caption: "",
            extractionHint: .customerConstraint
        )
        note.transcript = "Customer wants to keep airing cupboard free."
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts[0].confidence, .high)
    }

    // MARK: - Household composition

    func test_extractFacts_householdComposition_familyOfKeyword() {
        let note = makeNote(caption: "Family of five people living here.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertTrue(facts.contains { $0.category == .householdComposition })
    }

    func test_extractFacts_householdComposition_twoAdults() {
        let note = makeNote(caption: "Two adults and three children.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertTrue(facts.contains { $0.category == .householdComposition })
    }

    func test_extractFacts_noHouseholdKeyword_noHouseholdFact() {
        let note = makeNote(caption: "The boiler is in the cupboard.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertFalse(facts.contains { $0.category == .householdComposition })
    }

    // MARK: - Customer constraint

    func test_extractFacts_constraintKind_producesHighConfidence() {
        let note = VoiceNote(
            localFilename: "test.m4a",
            caption: "Low disruption is important.",
            kind: .constraint
        )
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        let constraintFacts = facts.filter { $0.category == .customerConstraint }
        XCTAssertFalse(constraintFacts.isEmpty)
        XCTAssertEqual(constraintFacts[0].confidence, .high)
    }

    func test_extractFacts_constraintKeyword_mediumConfidence() {
        let note = makeNote(caption: "Customer wants to keep airing cupboard free.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        let constraintFacts = facts.filter { $0.category == .customerConstraint }
        XCTAssertFalse(constraintFacts.isEmpty)
        XCTAssertEqual(constraintFacts[0].confidence, .medium)
    }

    // MARK: - Customer priority

    func test_extractFacts_recommendationKind_producesPriority() {
        let note = VoiceNote(
            localFilename: "test.m4a",
            caption: "Quiet operation is preferred.",
            kind: .recommendation
        )
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertTrue(facts.contains { $0.category == .customerPriority })
    }

    func test_extractFacts_priorityKeyword_producesFactHigherThanLow() {
        let note = makeNote(caption: "Customer wants quick hot water in the morning.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        let priorityFacts = facts.filter { $0.category == .customerPriority }
        XCTAssertFalse(priorityFacts.isEmpty)
        XCTAssertGreaterThanOrEqual(priorityFacts[0].confidence, .medium)
    }

    // MARK: - Current system

    func test_extractFacts_combiKeyword_producesSystemTypeFact() {
        let note = makeNote(caption: "Current combi struggles when both showers run.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertTrue(facts.contains { $0.category == .currentSystemType })
    }

    func test_extractFacts_issueKind_producesSystemIssueFact() {
        let note = VoiceNote(
            localFilename: "test.m4a",
            caption: "Boiler keeps cutting out.",
            kind: .issue
        )
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertTrue(facts.contains { $0.category == .currentSystemIssue })
    }

    // MARK: - Water quality

    func test_extractFacts_hardWaterKeyword_producesWaterQualityFact() {
        let note = makeNote(caption: "Hard water area, scaling around taps.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertTrue(facts.contains { $0.category == .waterQuality })
    }

    // MARK: - Provenance

    func test_extractFacts_preservesSourceNoteID() {
        let note = makeNote(caption: "Family of four occupants.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        let householdFacts = facts.filter { $0.category == .householdComposition }
        XCTAssertFalse(householdFacts.isEmpty)
        XCTAssertEqual(householdFacts[0].sourceNoteID, note.id)
    }

    func test_extractFacts_preservesRoomID() {
        let roomID = UUID()
        let note = VoiceNote(
            linkedRoomID: roomID,
            localFilename: "test.m4a",
            caption: "Family of three."
        )
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertTrue(facts.allSatisfy { $0.roomID == roomID })
    }

    // MARK: - Multiple notes

    func test_extractFacts_multipleNotes_aggregatesCorrectly() {
        let note1 = makeNote(caption: "Family of five.")
        let note2 = makeNote(caption: "Hard water area, scaling observed.")
        let note3 = makeNote(caption: "No useful info here.")

        let facts = SessionKnowledgeExtractor.extractFacts(from: [note1, note2, note3])
        XCTAssertTrue(facts.contains { $0.category == .householdComposition })
        XCTAssertTrue(facts.contains { $0.category == .waterQuality })
    }

    // MARK: - Verbatim snippet (voice-to-fact accuracy)

    func test_extractFacts_householdKeyword_populatesVerbatimSnippet() {
        let note = makeNote(caption: "Family of five people living here.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        let household = facts.first { $0.category == .householdComposition }
        XCTAssertNotNil(household?.verbatimSnippet)
        XCTAssertEqual(household?.verbatimSnippet, "family of")
    }

    func test_extractFacts_waterQualityKeyword_populatesVerbatimSnippet() {
        let note = makeNote(caption: "Hard water area, scaling around taps.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        let wq = facts.first { $0.category == .waterQuality }
        XCTAssertNotNil(wq?.verbatimSnippet)
    }

    func test_extractFacts_explicitHint_verbatimSnippetIsNil() {
        // Explicit hint path does not extract a keyword snippet — the whole note is the value.
        let note = VoiceNote(
            localFilename: "test.m4a",
            caption: "Family of five, two adults, three children.",
            extractionHint: .householdComposition
        )
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        XCTAssertEqual(facts.count, 1)
        XCTAssertNil(facts[0].verbatimSnippet)
    }

    func test_extractFacts_constraintKindTrigger_verbatimSnippetIsNil() {
        // Kind-driven extraction (no keyword match needed) produces no snippet.
        let note = VoiceNote(
            localFilename: "test.m4a",
            caption: "Low disruption is important.",
            kind: .constraint
        )
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        let constraintFacts = facts.filter { $0.category == .customerConstraint }
        XCTAssertFalse(constraintFacts.isEmpty)
        XCTAssertNil(constraintFacts[0].verbatimSnippet)
    }

    func test_extractFacts_constraintKeyword_populatesVerbatimSnippet() {
        let note = makeNote(caption: "Customer wants to keep airing cupboard free.")
        let facts = SessionKnowledgeExtractor.extractFacts(from: note)
        let constraintFacts = facts.filter { $0.category == .customerConstraint }
        XCTAssertFalse(constraintFacts.isEmpty)
        XCTAssertNotNil(constraintFacts[0].verbatimSnippet)
    }

    // MARK: - Helpers

    private func makeNote(caption: String) -> VoiceNote {
        VoiceNote(localFilename: "test.m4a", caption: caption)
    }
}
