import XCTest
@testable import AtlasScan

// MARK: - VisitHandoffPackBuilderTests
//
// Coverage:
//   • empty-but-valid completed visit builds pack safely
//   • customer summary includes high-level findings only
//   • engineer summary includes technical sections
//   • room/object/planning counts derive correctly
//   • consolidated notes included in engineer summary
//   • missing optional fields do not crash builder
//   • read-only: review flow does not expose mutation (store guard test)

final class VisitHandoffPackBuilderTests: XCTestCase {

    private let builder = VisitHandoffPackBuilder()

    // MARK: - Helpers

    private func makeCompletedSession(
        address: String = "1 Test Street",
        rooms: [ScannedRoom] = [],
        objects: [TaggedObject] = [],
        annotations: [PlanningAnnotation] = [],
        markupObjects: [InstallMarkupObject] = [],
        voiceNotes: [VoiceNote] = []
    ) -> PropertyScanSession {
        var session = PropertyScanSession(propertyAddress: address)
        session.visitLifecycle = .complete
        session.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        session.completionMethod = .manual
        for room in rooms { session.addRoom(room) }
        for obj in objects { session.addTaggedObject(obj) }
        for ann in annotations { session.addPlanningAnnotation(ann) }
        for mu in markupObjects { session.installMarkupObjects.append(mu) }
        for vn in voiceNotes { session.addVoiceNote(vn) }
        return session
    }

    // MARK: - Basic pack building

    func test_buildHandoffPack_emptySession_doesNotCrash() {
        let session = makeCompletedSession()
        let pack = builder.buildHandoffPack(for: session)
        XCTAssertEqual(pack.propertyAddress, "1 Test Street")
        XCTAssertNotNil(pack.completedAt)
    }

    func test_buildHandoffPack_setsVisitID() {
        let session = makeCompletedSession()
        let pack = builder.buildHandoffPack(for: session)
        XCTAssertEqual(pack.visitID, session.id)
    }

    func test_buildHandoffPack_setsJobReference() {
        let session = makeCompletedSession()
        let pack = builder.buildHandoffPack(for: session)
        XCTAssertEqual(pack.jobReference, session.jobReference)
    }

    func test_buildHandoffPack_setsCompletedAt() {
        let session = makeCompletedSession()
        let pack = builder.buildHandoffPack(for: session)
        XCTAssertEqual(pack.completedAt, session.completedAt)
    }

    // MARK: - Customer summary: findings

    func test_customerFindings_includesBoilerWhenPresent() {
        let session = makeCompletedSession(
            objects: [TaggedObject(roomID: UUID(), category: .boiler)]
        )
        let findings = builder.deriveCustomerFindingsSummary(from: session)
        XCTAssertTrue(findings.contains(where: { $0.contains("Boiler") }))
    }

    func test_customerFindings_includesFlueWhenPresent() {
        let session = makeCompletedSession(
            objects: [TaggedObject(roomID: UUID(), category: .flue)]
        )
        let findings = builder.deriveCustomerFindingsSummary(from: session)
        XCTAssertTrue(findings.contains(where: { $0.contains("Flue") || $0.contains("flue") }))
    }

    func test_customerFindings_includesCylinderWhenPresent() {
        let session = makeCompletedSession(
            objects: [TaggedObject(roomID: UUID(), category: .cylinder)]
        )
        let findings = builder.deriveCustomerFindingsSummary(from: session)
        XCTAssertTrue(findings.contains(where: { $0.contains("cylinder") || $0.contains("Hot water") }))
    }

    func test_customerFindings_includesRoomCount() {
        var session = makeCompletedSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
        session.addRoom(ScannedRoom(jobID: session.id, name: "Living Room"))
        let findings = builder.deriveCustomerFindingsSummary(from: session)
        XCTAssertTrue(findings.contains(where: { $0.contains("2") && $0.contains("room") }))
    }

    func test_customerFindings_includesEmitterCountWhenPresent() {
        let session = makeCompletedSession(
            objects: [
                TaggedObject(roomID: UUID(), category: .radiator),
                TaggedObject(roomID: UUID(), category: .radiator)
            ]
        )
        let findings = builder.deriveCustomerFindingsSummary(from: session)
        XCTAssertTrue(findings.contains(where: { $0.contains("2") && $0.contains("emitter") }))
    }

    func test_customerFindings_emptySession_returnsSurveyComplete() {
        let session = makeCompletedSession()
        let findings = builder.deriveCustomerFindingsSummary(from: session)
        XCTAssertFalse(findings.isEmpty, "should return at least one fallback line")
    }

    func test_customerFindings_doesNotContainEngineeringJargon() {
        let session = makeCompletedSession(
            objects: [TaggedObject(roomID: UUID(), category: .boiler)]
        )
        let findings = builder.deriveCustomerFindingsSummary(from: session)
        let joined = findings.joined(separator: " ").lowercased()
        // These are raw engineering terms that should not appear in customer copy
        XCTAssertFalse(joined.contains("markup"))
        XCTAssertFalse(joined.contains("lidar"))
        XCTAssertFalse(joined.contains("uuid"))
    }

    // MARK: - Customer summary: plan

    func test_customerPlan_includesProposedEmittersWhenPresent() {
        let session = makeCompletedSession(
            markupObjects: [
                InstallMarkupObject(
                    categoryRawValue: "radiator",
                    label: "New rad",
                    position: NormalizedPoint2D(x: 0.5, y: 0.5),
                    layer: .proposed
                )
            ]
        )
        let plan = builder.deriveCustomerPlanSummary(from: session)
        XCTAssertTrue(plan.contains(where: { $0.contains("radiator") || $0.contains("Proposed") }))
    }

    func test_customerPlan_includesAccessNotesWhenPresent() {
        let session = makeCompletedSession(
            annotations: [
                PlanningAnnotation(text: "Scaffold needed", kind: .accessNote)
            ]
        )
        let plan = builder.deriveCustomerPlanSummary(from: session)
        XCTAssertTrue(plan.contains(where: { $0.contains("Access") || $0.contains("consideration") }))
    }

    func test_customerPlan_emptySession_returnsEmptyArray() {
        let session = makeCompletedSession()
        let plan = builder.deriveCustomerPlanSummary(from: session)
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Customer summary: what to expect

    func test_whatToExpect_isNonEmpty() {
        let lines = builder.deriveCustomerWhatToExpect()
        XCTAssertFalse(lines.isEmpty)
    }

    func test_whatToExpect_isDeterministic() {
        let first = builder.deriveCustomerWhatToExpect()
        let second = builder.deriveCustomerWhatToExpect()
        XCTAssertEqual(first, second)
    }

    // MARK: - Engineer summary: rooms

    func test_engineerSummary_roomCount_matchesSession() {
        var session = makeCompletedSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
        session.addRoom(ScannedRoom(jobID: session.id, name: "Loft"))
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertEqual(summary.roomCount, 2)
    }

    func test_engineerSummary_roomEntry_containsName() {
        var session = makeCompletedSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Utility Room"))
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertTrue(summary.rooms.contains(where: { $0.name == "Utility Room" }))
    }

    // MARK: - Engineer summary: key objects

    func test_engineerSummary_keyObjects_includesBoiler() {
        let session = makeCompletedSession(
            objects: [TaggedObject(roomID: UUID(), category: .boiler)]
        )
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertTrue(summary.keyObjects.contains(where: { $0.category == "Boiler" }))
    }

    func test_engineerSummary_keyObjects_doesNotIncludeRadiator() {
        let session = makeCompletedSession(
            objects: [TaggedObject(roomID: UUID(), category: .radiator)]
        )
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertFalse(summary.keyObjects.contains(where: { $0.category.lowercased() == "radiator" }))
    }

    // MARK: - Engineer summary: proposed emitters

    func test_engineerSummary_proposedEmitterCount_matchesMarkup() {
        let session = makeCompletedSession(
            markupObjects: [
                InstallMarkupObject(
                    categoryRawValue: "radiator",
                    label: "Rad 1",
                    position: NormalizedPoint2D(x: 0.5, y: 0.5),
                    layer: .proposed
                ),
                InstallMarkupObject(
                    categoryRawValue: "towel_rail",
                    label: "TR 1",
                    position: NormalizedPoint2D(x: 0.5, y: 0.5),
                    layer: .proposed
                )
            ]
        )
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertEqual(summary.proposedEmitterCount, 2)
    }

    func test_engineerSummary_existingMarkupObjects_notCountedAsProposed() {
        let session = makeCompletedSession(
            markupObjects: [
                InstallMarkupObject(
                    categoryRawValue: "radiator",
                    label: "Existing rad",
                    position: NormalizedPoint2D(x: 0.5, y: 0.5),
                    layer: .existing
                )
            ]
        )
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertEqual(summary.proposedEmitterCount, 0)
    }

    // MARK: - Engineer summary: planning notes

    func test_engineerSummary_accessNotes_includesAnnotationText() {
        let session = makeCompletedSession(
            annotations: [
                PlanningAnnotation(text: "Ladder required for loft", kind: .accessNote)
            ]
        )
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertEqual(summary.accessNoteCount, 1)
        XCTAssertEqual(summary.accessNotes.first, "Ladder required for loft")
    }

    func test_engineerSummary_specNotes_included() {
        let session = makeCompletedSession(
            annotations: [
                PlanningAnnotation(text: "22mm pipe throughout", kind: .specNote)
            ]
        )
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertEqual(summary.specNotes.first, "22mm pipe throughout")
    }

    func test_engineerSummary_roomPlanNotes_included() {
        let session = makeCompletedSession(
            annotations: [
                PlanningAnnotation(text: "Relocate rad to east wall", kind: .roomPlanNote)
            ]
        )
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertEqual(summary.roomPlanNotes.first, "Relocate rad to east wall")
    }

    // MARK: - Engineer summary: consolidated notes

    func test_engineerSummary_fieldNotes_includeVoiceNoteTranscripts() {
        let vn = VoiceNote(
            localFilename: "",
            caption: "Boiler is in poor condition",
            kind: .observation,
            transcriptStatus: .completed,
            transcript: "Boiler is in poor condition"
        )
        let session = makeCompletedSession(voiceNotes: [vn])
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertTrue(summary.consolidatedFieldNotes.contains("Boiler is in poor condition"))
    }

    func test_engineerSummary_fieldNotes_emptyWhenNoNotes() {
        let session = makeCompletedSession()
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertTrue(summary.consolidatedFieldNotes.isEmpty)
    }

    // MARK: - Technical summary helper

    func test_engineerTechnicalSummary_includesBoilerLocation() {
        var session = makeCompletedSession()
        let room = ScannedRoom(jobID: session.id, name: "Kitchen")
        session.addRoom(room)
        var boiler = TaggedObject(roomID: room.id, category: .boiler)
        boiler.label = "Worcester Boiler"
        session.addTaggedObject(boiler)
        let lines = builder.deriveEngineerTechnicalSummary(from: session)
        XCTAssertTrue(lines.contains(where: { $0.contains("Kitchen") }))
    }

    func test_engineerTechnicalSummary_flueUnassigned_whenNoFlue() {
        let session = makeCompletedSession()
        let lines = builder.deriveEngineerTechnicalSummary(from: session)
        XCTAssertTrue(lines.contains(where: { $0.contains("unassigned") }))
    }

    func test_engineerTechnicalSummary_proposedEmitterCount() {
        let session = makeCompletedSession(
            markupObjects: [
                InstallMarkupObject(
                    categoryRawValue: "radiator",
                    label: "Rad A",
                    position: NormalizedPoint2D(x: 0.5, y: 0.5),
                    layer: .proposed
                ),
                InstallMarkupObject(
                    categoryRawValue: "radiator",
                    label: "Rad B",
                    position: NormalizedPoint2D(x: 0.5, y: 0.5),
                    layer: .proposed
                )
            ]
        )
        let lines = builder.deriveEngineerTechnicalSummary(from: session)
        XCTAssertTrue(lines.contains(where: { $0.contains("2") && $0.contains("proposed emitter") }))
    }

    // MARK: - Missing optional fields do not crash

    func test_buildHandoffPack_nilCompletedAt_doesNotCrash() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.visitLifecycle = .complete
        session.completedAt = nil
        session.completionMethod = nil
        session.completedByUserId = nil
        let pack = builder.buildHandoffPack(for: session)
        XCTAssertNil(pack.completedAt)
        XCTAssertNil(pack.engineerSummary.completedAt)
        XCTAssertNil(pack.engineerSummary.completionMethod)
    }

    func test_buildHandoffPack_populatedAddress_usesAddress() {
        let session = PropertyScanSession(jobReference: "JOB-999", propertyAddress: "1 High Street")
        let pack = builder.buildHandoffPack(for: session)
        XCTAssertEqual(pack.customerSummary.title, "1 High Street")
    }

    func test_buildHandoffPack_titleFallsBackToJobReference_whenAddressIsEmpty() {
        // PropertyScanSession.init replaces an empty propertyAddress with jobReference,
        // so create a session and then clear it to test the builder's defensive fallback.
        var session = PropertyScanSession(jobReference: "JOB-999", propertyAddress: "Temp")
        session.propertyAddress = ""
        let pack = builder.buildHandoffPack(for: session)
        XCTAssertFalse(pack.customerSummary.title.isEmpty,
                       "title should fall back to jobReference when address is empty")
        XCTAssertEqual(pack.customerSummary.title, "JOB-999")
    }

    func test_buildHandoffPack_noRooms_producesEmptyRoomList() {
        let session = makeCompletedSession()
        let summary = builder.buildEngineerSummary(for: session)
        XCTAssertTrue(summary.rooms.isEmpty)
    }

    // MARK: - Read-only: FieldVisitStore blocks mutation after completion

    @MainActor
    func test_completedStore_updateBlocked() {
        let store = ScanSessionStore()
        var session = PropertyScanSession(propertyAddress: "1 Test St")
        session.visitLifecycle = .complete
        let visitStore = FieldVisitStore(session: session, sessionStore: store)
        // Attempt mutation — should be blocked by the completion guard.
        visitStore.update { $0.propertyAddress = "MUTATED" }
        XCTAssertEqual(visitStore.session.propertyAddress, "1 Test St",
                       "mutation after completion must be blocked")
    }

    @MainActor
    func test_completedStore_canBuildHandoffPack() {
        let store = ScanSessionStore()
        var session = PropertyScanSession(propertyAddress: "Handoff Test")
        session.visitLifecycle = .complete
        let visitStore = FieldVisitStore(session: session, sessionStore: store)
        let pack = builder.buildHandoffPack(for: visitStore.session)
        XCTAssertEqual(pack.propertyAddress, "Handoff Test")
    }
}
