import XCTest
@testable import AtlasScan

// MARK: - SessionKnowledgeSummaryTests
//
// Tests for SessionKnowledgeExtractor.knowledgeSummary(:) and
// PropertyScanSession.knowledgeSummary computed property.

final class SessionKnowledgeSummaryTests: XCTestCase {

    // MARK: - Empty facts

    func test_knowledgeSummary_noFacts_nothingKnown() {
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [])
        XCTAssertFalse(summary.householdKnown)
        XCTAssertFalse(summary.systemKnown)
        XCTAssertFalse(summary.bathroomsKnown)
        XCTAssertFalse(summary.prioritiesKnown)
        XCTAssertFalse(summary.constraintsKnown)
    }

    func test_knowledgeSummary_noFacts_hasMissingEssentials() {
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [])
        XCTAssertFalse(summary.missingEssentials.isEmpty)
    }

    func test_knowledgeSummary_noFacts_hasNoFacts() {
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [])
        XCTAssertFalse(summary.hasAnyFacts)
    }

    // MARK: - With high-confidence facts

    func test_knowledgeSummary_highConfidenceHousehold_householdKnown() {
        let fact = makeHighFact(category: .householdComposition)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertTrue(summary.householdKnown)
        XCTAssertTrue(summary.hasAnyFacts)
    }

    func test_knowledgeSummary_highConfidenceSystem_systemKnown() {
        let fact = makeHighFact(category: .currentSystemType)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertTrue(summary.systemKnown)
    }

    func test_knowledgeSummary_highConfidenceSystemIssue_systemKnown() {
        let fact = makeHighFact(category: .currentSystemIssue)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertTrue(summary.systemKnown)
    }

    func test_knowledgeSummary_highConfidenceBathrooms_bathroomsKnown() {
        let fact = makeHighFact(category: .bathroomCount)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertTrue(summary.bathroomsKnown)
    }

    func test_knowledgeSummary_hotWaterUsage_bathroomsKnown() {
        let fact = makeHighFact(category: .hotWaterUsage)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertTrue(summary.bathroomsKnown)
    }

    func test_knowledgeSummary_highConfidencePriority_prioritiesKnown() {
        let fact = makeHighFact(category: .customerPriority)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertTrue(summary.prioritiesKnown)
    }

    func test_knowledgeSummary_highConfidenceConstraint_constraintsKnown() {
        let fact = makeHighFact(category: .customerConstraint)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertTrue(summary.constraintsKnown)
    }

    // MARK: - Low confidence does not satisfy "known"

    func test_knowledgeSummary_lowConfidenceHousehold_householdNotKnown() {
        let fact = makeFact(category: .householdComposition, confidence: .low)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertFalse(summary.householdKnown)
    }

    func test_knowledgeSummary_lowConfidenceHousehold_appearsInWarnings() {
        let fact = makeFact(category: .householdComposition, confidence: .low)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertFalse(summary.reviewWarnings.isEmpty)
    }

    // MARK: - Missing essentials

    func test_knowledgeSummary_noHousehold_missingEssentialIncludesHousehold() {
        let fact = makeHighFact(category: .currentSystemType)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertTrue(summary.missingEssentials.contains { $0.lowercased().contains("household") })
    }

    func test_knowledgeSummary_noSystem_missingEssentialIncludesSystem() {
        let fact = makeHighFact(category: .householdComposition)
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: [fact])
        XCTAssertTrue(summary.missingEssentials.contains { $0.lowercased().contains("system") })
    }

    func test_knowledgeSummary_allEssentials_allSatisfied() {
        let facts: [ExtractedSessionFact] = [
            makeHighFact(category: .householdComposition),
            makeHighFact(category: .currentSystemType),
        ]
        let summary = SessionKnowledgeExtractor.knowledgeSummary(from: facts)
        XCTAssertTrue(summary.missingEssentials.isEmpty)
    }

    // MARK: - Session integration

    func test_session_knowledgeSummary_usesExtractedFacts() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.extractedFacts = [makeHighFact(category: .householdComposition)]
        XCTAssertTrue(session.knowledgeSummary.householdKnown)
    }

    func test_session_knowledgeSummary_emptySession_nothingKnown() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertFalse(session.knowledgeSummary.householdKnown)
        XCTAssertFalse(session.knowledgeSummary.systemKnown)
    }

    func test_session_refreshExtractedFacts_populatesFromNotes() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let note = VoiceNote(
            localFilename: "test.m4a",
            caption: "Family of five.",
            extractionHint: .householdComposition
        )
        session.voiceNotes = [note]
        session.refreshExtractedFacts()

        XCTAssertFalse(session.extractedFacts.isEmpty)
        XCTAssertTrue(session.knowledgeSummary.householdKnown)
    }

    func test_session_addExtractedFact_persists() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let fact = makeHighFact(category: .customerPriority)
        session.addExtractedFact(fact)
        XCTAssertEqual(session.extractedFacts.count, 1)
    }

    func test_session_removeExtractedFact_removesById() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let fact = makeHighFact(category: .customerPriority)
        session.addExtractedFact(fact)
        session.removeExtractedFact(id: fact.id)
        XCTAssertTrue(session.extractedFacts.isEmpty)
    }

    // MARK: - Backward compatibility

    func test_extractedFact_decode_missingConfidence_defaultsToMedium() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "category": "household_composition",
          "value": "Family of three",
          "createdAt": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let fact = try decoder.decode(ExtractedSessionFact.self, from: json)
        XCTAssertEqual(fact.confidence, .medium)
    }

    func test_session_decode_missingExtractedFacts_defaultsToEmpty() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "jobReference": "JOB-123",
          "propertyAddress": "1 Test Street",
          "engineerName": "",
          "scanState": "not_started",
          "reviewState": "pending",
          "syncState": "local_only",
          "handoffState": "not_sent",
          "rooms": [],
          "roomAdjacencies": [],
          "roomPlacements": [],
          "taggedObjects": [],
          "photos": [],
          "voiceNotes": [],
          "issues": [],
          "createdAt": 0,
          "updatedAt": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let session = try decoder.decode(PropertyScanSession.self, from: json)
        XCTAssertTrue(session.extractedFacts.isEmpty)
    }

    // MARK: - Helpers

    private func makeHighFact(category: SessionFactCategory) -> ExtractedSessionFact {
        makeFact(category: category, confidence: .high)
    }

    private func makeFact(category: SessionFactCategory, confidence: ConfidenceLevel) -> ExtractedSessionFact {
        ExtractedSessionFact(
            category: category,
            value: "Test value for \(category.displayName)",
            confidence: confidence,
            sourceNoteID: UUID()
        )
    }
}
