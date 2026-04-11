import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - AtlasPropertyVoiceProjectionTests
//
// Tests for the projection of structured voice-extracted facts into
// the AtlasPropertyV1 canonical handoff payload.

final class AtlasPropertyVoiceProjectionTests: XCTestCase {

    // MARK: - No facts → no sessionKnowledge

    func test_toAtlasPropertyV1_noExtractedFacts_sessionKnowledgeIsNil() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()
        XCTAssertNil(property.sessionKnowledge)
    }

    // MARK: - Low-confidence facts are not projected

    func test_toAtlasPropertyV1_onlyLowConfidenceFacts_sessionKnowledgeIsNil() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.extractedFacts = [
            ExtractedSessionFact(
                category: .householdComposition,
                value: "Possible family",
                confidence: .low,
                sourceNoteID: UUID()
            )
        ]
        let property = session.toAtlasPropertyV1()
        XCTAssertNil(property.sessionKnowledge)
    }

    // MARK: - Medium/high-confidence facts are projected

    func test_toAtlasPropertyV1_mediumConfidenceFact_isProjected() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.extractedFacts = [
            ExtractedSessionFact(
                category: .householdComposition,
                value: "Family of five",
                confidence: .medium,
                sourceNoteID: UUID()
            )
        ]
        let property = session.toAtlasPropertyV1()
        XCTAssertNotNil(property.sessionKnowledge)
        XCTAssertEqual(property.sessionKnowledge?.extractedFacts.count, 1)
    }

    func test_toAtlasPropertyV1_highConfidenceFact_isProjected() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.extractedFacts = [
            ExtractedSessionFact(
                category: .customerConstraint,
                value: "Customer wants to keep airing cupboard free",
                confidence: .high,
                sourceNoteID: UUID()
            )
        ]
        let property = session.toAtlasPropertyV1()
        XCTAssertNotNil(property.sessionKnowledge)
        XCTAssertEqual(property.sessionKnowledge?.extractedFacts.count, 1)
    }

    // MARK: - Mixed confidence — only medium+ projected

    func test_toAtlasPropertyV1_mixedConfidence_onlyMediumPlusProjected() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let highFact = ExtractedSessionFact(
            category: .householdComposition,
            value: "Family of five",
            confidence: .high,
            sourceNoteID: UUID()
        )
        let lowFact = ExtractedSessionFact(
            category: .waterQuality,
            value: "Maybe hard water",
            confidence: .low,
            sourceNoteID: UUID()
        )
        session.extractedFacts = [highFact, lowFact]
        let property = session.toAtlasPropertyV1()
        XCTAssertNotNil(property.sessionKnowledge)
        XCTAssertEqual(property.sessionKnowledge?.extractedFacts.count, 1)
        XCTAssertEqual(property.sessionKnowledge?.extractedFacts[0].confidence, "high")
    }

    // MARK: - Projected fact fields

    func test_toAtlasPropertyV1_projectedFact_hasCorrectCategory() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.extractedFacts = [
            ExtractedSessionFact(
                category: .currentSystemIssue,
                value: "Combi struggles",
                confidence: .medium,
                sourceNoteID: UUID()
            )
        ]
        let property = session.toAtlasPropertyV1()
        let fact = property.sessionKnowledge?.extractedFacts[0]
        XCTAssertEqual(fact?.category, "current_system_issue")
    }

    func test_toAtlasPropertyV1_projectedFact_preservesSourceNoteID() {
        let noteID = UUID()
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.extractedFacts = [
            ExtractedSessionFact(
                category: .customerPriority,
                value: "Low disruption important",
                confidence: .high,
                sourceNoteID: noteID
            )
        ]
        let property = session.toAtlasPropertyV1()
        let fact = property.sessionKnowledge?.extractedFacts[0]
        XCTAssertEqual(fact?.sourceNoteID, noteID.uuidString)
    }

    func test_toAtlasPropertyV1_projectedFact_nilSourceNoteID_isNilInPayload() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.extractedFacts = [
            ExtractedSessionFact(
                category: .installerNote,
                value: "Manual entry",
                confidence: .high,
                sourceNoteID: nil
            )
        ]
        let property = session.toAtlasPropertyV1()
        let fact = property.sessionKnowledge?.extractedFacts[0]
        XCTAssertNil(fact?.sourceNoteID)
    }

    func test_toAtlasPropertyV1_projectedFact_preservesRoomID() {
        let roomID = UUID()
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.extractedFacts = [
            ExtractedSessionFact(
                category: .bathroomCount,
                value: "Two bathrooms",
                confidence: .high,
                sourceNoteID: nil,
                roomID: roomID
            )
        ]
        let property = session.toAtlasPropertyV1()
        let fact = property.sessionKnowledge?.extractedFacts[0]
        XCTAssertEqual(fact?.roomID, roomID.uuidString)
    }

    // MARK: - Codability of AtlasPropertyV1 with sessionKnowledge

    func test_atlasPropertyV1_withSessionKnowledge_isEncodable() throws {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.extractedFacts = [
            ExtractedSessionFact(
                category: .householdComposition,
                value: "Family of three",
                confidence: .high,
                sourceNoteID: UUID()
            )
        ]
        let property = session.toAtlasPropertyV1()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertNoThrow(try encoder.encode(property))
    }

    func test_atlasPropertyV1_withoutSessionKnowledge_isEncodable() throws {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let property = session.toAtlasPropertyV1()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertNoThrow(try encoder.encode(property))
    }

    func test_atlasPropertyV1_roundTrip_sessionKnowledgePreserved() throws {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let noteID = UUID()
        session.extractedFacts = [
            ExtractedSessionFact(
                category: .customerConstraint,
                value: "No access to loft",
                confidence: .high,
                sourceNoteID: noteID
            )
        ]
        let property = session.toAtlasPropertyV1()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(property)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AtlasPropertyV1.self, from: data)
        XCTAssertEqual(decoded.sessionKnowledge?.extractedFacts.count, 1)
        XCTAssertEqual(decoded.sessionKnowledge?.extractedFacts[0].sourceNoteID, noteID.uuidString)
    }
}
