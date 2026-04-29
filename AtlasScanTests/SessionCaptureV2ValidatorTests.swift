import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - SessionCaptureV2ValidatorTests
//
// Tests for validateSessionCaptureV2() against the AtlasContracts package.
//
// Covers:
//   - Fixture generated via CaptureSessionExporter passes validateSessionCaptureV2()
//   - Wrong schemaVersion is rejected
//   - Missing required fields are each rejected
//   - Totally empty JSON object fails validation
//   - Raw audio fields are absent from the exported JSON

final class SessionCaptureV2ValidatorTests: XCTestCase {

    // MARK: - Fixture helpers

    /// Returns a well-formed CaptureSessionDraft with at least one artefact.
    private func makeExportableDraft(visitReference: String = "JOB-FIXTURE-2025") -> CaptureSessionDraft {
        var draft = CaptureSessionStore.newSession(visitReference: visitReference)
        draft.propertyAddress = "12 Test Street, London"
        draft.customerName = "Test Customer"

        // Room scan
        var scan = CapturedRoomScanDraft()
        scan.roomLabel = "Boiler Room"
        scan.rawWidthM = 3.2
        scan.rawDepthM = 2.8
        scan.rawHeightM = 2.4
        scan.confidence = .high
        draft.roomScans.append(scan)

        // Photo
        var photo = CapturedPhotoDraft(localFilename: "boiler_front.jpg")
        photo.roomId = scan.id
        photo.kind = .plant
        draft.photos.append(photo)

        // Voice note — transcript only, no audio
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Boiler located under the stairs. Serial number visible on front plate."
        note.roomId = scan.id
        draft.voiceNotes.append(note)

        // Object pin
        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.label = "Worcester Bosch 30i"
        pin.roomId = scan.id
        draft.objectPins.append(pin)

        return draft
    }

    /// Encodes a SessionCaptureV2 to JSON via the exporter pipeline.
    private func exportedFixtureData() throws -> Data {
        let draft = makeExportableDraft()
        let result = try CaptureSessionExporter.export(draft)
        return result.jsonData
    }

    // MARK: - Valid fixture (generated from exporter)

    func test_exporterGeneratedFixture_passesValidator() throws {
        let data = try exportedFixtureData()
        let result = validateSessionCaptureV2(data)
        XCTAssertTrue(result.isSuccess, "Exporter-generated fixture must pass validateSessionCaptureV2(). Errors: \(result.errors)")
    }

    func test_exporterGeneratedFixture_decodesCorrectSchemaVersion() throws {
        let data = try exportedFixtureData()
        let result = validateSessionCaptureV2(data)
        XCTAssertEqual(result.capture?.schemaVersion, currentSessionCaptureVersion)
    }

    func test_exporterGeneratedFixture_schemaVersionInSupportedList() throws {
        let data = try exportedFixtureData()
        let result = validateSessionCaptureV2(data)
        XCTAssertTrue(
            supportedSessionCaptureVersions.contains(result.capture?.schemaVersion ?? ""),
            "schemaVersion from fixture must be in supportedSessionCaptureVersions"
        )
    }

    func test_exporterGeneratedFixture_roundTrips() throws {
        let data = try exportedFixtureData()
        let result = validateSessionCaptureV2(data)
        guard let capture = result.capture else {
            return XCTFail("Validation failed: \(result.errors)")
        }
        // Re-encode and re-validate to confirm idempotency
        let reEncoded = try CaptureSessionExporter.encode(capture)
        let reValidated = validateSessionCaptureV2(reEncoded)
        XCTAssertTrue(reValidated.isSuccess, "Re-encoded fixture must still pass validation")
    }

    // MARK: - Wrong schemaVersion

    func test_wrongSchemaVersion_fails() throws {
        let data = try mutatedFixture { $0["schemaVersion"] = "99.0" }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(
            result.errors.contains(where: { $0.contains("schemaVersion") }),
            "Error must mention schemaVersion"
        )
    }

    func test_emptySchemaVersion_fails() throws {
        let data = try mutatedFixture { $0["schemaVersion"] = "" }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("schemaVersion") }))
    }

    func test_missingSchemaVersion_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "schemaVersion") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("schemaVersion") }))
    }

    // MARK: - Missing required fields

    func test_missingSessionId_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "sessionId") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("sessionId") }))
    }

    func test_missingVisitReference_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "visitReference") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("visitReference") }))
    }

    func test_missingCapturedAt_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "capturedAt") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("capturedAt") }))
    }

    func test_missingExportedAt_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "exportedAt") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("exportedAt") }))
    }

    func test_missingDeviceModel_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "deviceModel") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("deviceModel") }))
    }

    func test_missingRoomScans_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "roomScans") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("roomScans") }))
    }

    func test_missingPhotos_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "photos") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("photos") }))
    }

    func test_missingVoiceNotes_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "voiceNotes") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("voiceNotes") }))
    }

    func test_missingObjectPins_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "objectPins") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("objectPins") }))
    }

    func test_missingFloorPlanSnapshots_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "floorPlanSnapshots") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("floorPlanSnapshots") }))
    }

    func test_missingQaFlags_fails() throws {
        let data = try mutatedFixture { $0.removeValue(forKey: "qaFlags") }
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("qaFlags") }))
    }

    // MARK: - Totally empty capture

    func test_emptyJsonObject_fails() {
        let data = Data("{}".utf8)
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
        XCTAssertFalse(result.errors.isEmpty, "Empty JSON object must produce validation errors")
    }

    func test_emptyData_fails() {
        let result = validateSessionCaptureV2(Data())
        XCTAssertFalse(result.isSuccess)
    }

    func test_nonJsonInput_fails() {
        let data = Data("not json at all".utf8)
        let result = validateSessionCaptureV2(data)
        XCTAssertFalse(result.isSuccess)
    }

    // MARK: - Raw audio absent from exported JSON

    func test_exportedJson_containsNoRawAudioFields() throws {
        let data = try exportedFixtureData()
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("rawAudio"),      "rawAudio must not appear in exported JSON")
        XCTAssertFalse(json.contains("audioPath"),     "audioPath must not appear in exported JSON")
        XCTAssertFalse(json.contains("audioFilename"), "audioFilename must not appear in exported JSON")
        XCTAssertFalse(json.contains(".m4a"),          ".m4a audio extension must not appear in exported JSON")
        XCTAssertFalse(json.contains(".mp3"),          ".mp3 audio extension must not appear in exported JSON")
        XCTAssertFalse(json.contains(".wav"),          ".wav audio extension must not appear in exported JSON")
    }

    func test_exportedJson_validatedFixture_containsNoRawAudioFields() throws {
        // Run the same check after the validator decodes the payload,
        // confirming the round-tripped JSON is also clean.
        let data = try exportedFixtureData()
        let result = validateSessionCaptureV2(data)
        guard let capture = result.capture else {
            return XCTFail("Fixture must pass validation before audio-check")
        }

        let reEncoded = try CaptureSessionExporter.encode(capture)
        let json = String(data: reEncoded, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("rawAudio"),  "rawAudio must not appear after round-trip")
        XCTAssertFalse(json.contains("audioPath"), "audioPath must not appear after round-trip")
        XCTAssertFalse(json.contains(".m4a"),      ".m4a must not appear after round-trip")
    }

    // MARK: - Private helpers

    /// Decodes the exporter-generated fixture to a mutable dictionary, applies
    /// `mutation`, and re-encodes to Data for feeding into the validator.
    private func mutatedFixture(
        mutation: (inout [String: Any]) -> Void
    ) throws -> Data {
        let original = try exportedFixtureData()
        guard var dict = try JSONSerialization.jsonObject(with: original) as? [String: Any] else {
            throw XCTSkip("Could not decode fixture as dictionary")
        }
        mutation(&dict)
        return try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted])
    }
}
