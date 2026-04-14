import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - SpatialEvidence3DTests
//
// Tests covering:
//   1. AtlasContracts SpatialEvidence3D / ExternalClearanceSceneV1 round-trip
//   2. Local RoomScanEvidence → SpatialEvidence3D projection
//   3. Local ExternalClearanceScene → ExternalClearanceSceneV1 projection
//   4. ExternalClearanceScene compliance evaluation
//   5. PropertyScanSession backward-compatible decode

final class SpatialEvidence3DTests: XCTestCase {

    // MARK: - AtlasVec3V1

    func test_vec3_roundTrip() throws {
        let v = AtlasVec3V1(x: 1.5, y: 2.5, z: -3.0)
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(AtlasVec3V1.self, from: data)
        XCTAssertEqual(decoded.x, 1.5)
        XCTAssertEqual(decoded.y, 2.5)
        XCTAssertEqual(decoded.z, -3.0)
    }

    // MARK: - SpatialEvidence3D round-trip

    func test_spatialEvidence3D_roundTrip() throws {
        let evidence = SpatialEvidence3D(
            id: "eid-001",
            propertyID: "prop-001",
            sourceSessionId: "sess-001",
            format: "usdz",
            fileUrl: "file:///scans/room.usdz",
            previewImageUrl: "file:///scans/preview.jpg",
            linkedRoomIds: ["room-1", "room-2"],
            bounds: SpatialEvidence3D.Bounds(width: 4.2, length: 5.8, height: 2.4),
            captureMeta: SpatialEvidence3D.CaptureMeta(
                device: "iPhone 15 Pro",
                timestamp: "2025-01-01T10:00:00.000Z",
                confidence: 0.92
            )
        )
        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(SpatialEvidence3D.self, from: data)
        XCTAssertEqual(decoded.id, "eid-001")
        XCTAssertEqual(decoded.propertyID, "prop-001")
        XCTAssertEqual(decoded.kind, "internal_room_scan")
        XCTAssertEqual(decoded.format, "usdz")
        XCTAssertEqual(decoded.linkedRoomIds, ["room-1", "room-2"])
        XCTAssertEqual(decoded.bounds?.width, 4.2)
        XCTAssertEqual(decoded.captureMeta?.confidence, 0.92)
    }

    func test_spatialEvidence3D_optionalFieldsNil() throws {
        let evidence = SpatialEvidence3D(
            id: "eid-002",
            propertyID: "prop-001",
            sourceSessionId: "sess-001",
            format: "glb",
            fileUrl: ""
        )
        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(SpatialEvidence3D.self, from: data)
        XCTAssertNil(decoded.previewImageUrl)
        XCTAssertNil(decoded.bounds)
        XCTAssertNil(decoded.captureMeta)
        XCTAssertTrue(decoded.linkedRoomIds.isEmpty)
    }

    // MARK: - ExternalClearanceSceneV1 round-trip

    func test_externalClearanceScene_roundTrip() throws {
        let scene = ExternalClearanceSceneV1(
            id: "scene-001",
            propertyID: "prop-001",
            sourceSessionId: "sess-001",
            evidence: ExternalClearanceSceneV1.Evidence(
                previewImageUrl: "file:///preview.jpg",
                modelUrl: nil,
                pointCloudUrl: nil
            ),
            flueTerminal: ExternalClearanceSceneV1.FlueTerminal(
                position3D: AtlasVec3V1(x: 1, y: 2.5, z: 0.5),
                normal: nil,
                heightAboveGroundM: 2.5
            ),
            nearbyFeatures: [
                ExternalClearanceSceneV1.NearbyFeature(
                    id: "feat-001",
                    type: .window,
                    position3D: AtlasVec3V1(x: 1.3, y: 2.5, z: 0.5),
                    distanceToTerminalM: 0.28
                )
            ],
            measurements: [
                ClearanceMeasurementV1(
                    id: "meas-001",
                    kind: .terminalToOpening,
                    valueM: 0.28,
                    source: .measured
                )
            ],
            compliance: ExternalClearanceSceneV1.ComplianceSummary(
                standardRef: "BS 5440",
                warnings: ["Terminal is 280 mm from an opening — minimum 300 mm required."],
                pass: false
            )
        )
        let data = try JSONEncoder().encode(scene)
        let decoded = try JSONDecoder().decode(ExternalClearanceSceneV1.self, from: data)
        XCTAssertEqual(decoded.id, "scene-001")
        XCTAssertEqual(decoded.kind, "external_flue_clearance")
        XCTAssertEqual(decoded.nearbyFeatures.first?.type, .window)
        XCTAssertEqual(decoded.measurements.first?.valueM, 0.28)
        XCTAssertEqual(decoded.compliance?.pass, false)
        XCTAssertFalse(decoded.compliance?.warnings.isEmpty ?? true)
    }

    func test_featureType_allCasesHaveRawValues() {
        for type_ in ExternalClearanceSceneV1.FeatureType.allCases {
            XCTAssertFalse(type_.rawValue.isEmpty)
            XCTAssertFalse(type_.displayName.isEmpty)
            XCTAssertFalse(type_.symbolName.isEmpty)
        }
    }

    func test_measurementKind_displayNames() {
        XCTAssertFalse(ClearanceMeasurementV1.MeasurementKind.terminalToOpening.displayName.isEmpty)
        XCTAssertFalse(ClearanceMeasurementV1.MeasurementKind.terminalToBoundary.displayName.isEmpty)
        XCTAssertFalse(ClearanceMeasurementV1.MeasurementKind.terminalToEaves.displayName.isEmpty)
    }

    // MARK: - RoomScanEvidence → SpatialEvidence3D projection

    func test_roomScanEvidence_projection_idPreserved() {
        let propID = UUID()
        let captID = UUID()
        let evidence = RoomScanEvidence(
            propertySessionID: propID,
            captureSessionID: captID,
            localFileURLString: "file:///scans/room.usdz",
            assetFormat: .usdz
        )
        let contract = evidence.toSpatialEvidence3D()
        XCTAssertEqual(contract.id, evidence.id.uuidString)
        XCTAssertEqual(contract.propertyID, propID.uuidString)
        XCTAssertEqual(contract.sourceSessionId, captID.uuidString)
        XCTAssertEqual(contract.kind, "internal_room_scan")
        XCTAssertEqual(contract.format, "usdz")
    }

    func test_roomScanEvidence_projection_linkedRoomIDs() {
        let roomIDs = [UUID(), UUID()]
        let evidence = RoomScanEvidence(
            propertySessionID: UUID(),
            captureSessionID: UUID(),
            linkedRoomIDs: roomIDs
        )
        let contract = evidence.toSpatialEvidence3D()
        XCTAssertEqual(contract.linkedRoomIds, roomIDs.map(\.uuidString))
    }

    func test_roomScanEvidence_projection_bounds() {
        var evidence = RoomScanEvidence(
            propertySessionID: UUID(),
            captureSessionID: UUID()
        )
        evidence.bounds = RoomScanEvidence.Bounds(width: 4.0, length: 5.5, height: 2.4)
        let contract = evidence.toSpatialEvidence3D()
        XCTAssertEqual(contract.bounds?.width, 4.0)
        XCTAssertEqual(contract.bounds?.length, 5.5)
        XCTAssertEqual(contract.bounds?.height, 2.4)
    }

    // MARK: - ExternalClearanceScene → ExternalClearanceSceneV1 projection

    func test_externalClearanceSceneLocal_projection_idPreserved() {
        let propID = UUID()
        let captID = UUID()
        let scene = ExternalClearanceScene(
            propertySessionID: propID,
            captureSessionID: captID
        )
        let contract = scene.toExternalClearanceSceneV1()
        XCTAssertEqual(contract.id, scene.id.uuidString)
        XCTAssertEqual(contract.propertyID, propID.uuidString)
        XCTAssertEqual(contract.kind, "external_flue_clearance")
    }

    func test_externalClearanceSceneLocal_projection_features() {
        var scene = ExternalClearanceScene(
            propertySessionID: UUID(),
            captureSessionID: UUID()
        )
        scene.nearbyFeatures = [
            NearbyFeatureCapture(kind: .window, x: 1, y: 2, z: 3, distanceToTerminalM: 0.35)
        ]
        let contract = scene.toExternalClearanceSceneV1()
        XCTAssertEqual(contract.nearbyFeatures.count, 1)
        XCTAssertEqual(contract.nearbyFeatures.first?.type, .window)
        XCTAssertEqual(contract.nearbyFeatures.first?.distanceToTerminalM, 0.35)
    }

    func test_externalClearanceSceneLocal_projection_measurements() {
        var scene = ExternalClearanceScene(
            propertySessionID: UUID(),
            captureSessionID: UUID()
        )
        scene.measurements = [
            ClearanceMeasurementCapture(kind: .terminalToOpening, valueM: 0.28, source: .measured)
        ]
        let contract = scene.toExternalClearanceSceneV1()
        XCTAssertEqual(contract.measurements.first?.kind, .terminalToOpening)
        XCTAssertEqual(contract.measurements.first?.valueM, 0.28)
        XCTAssertEqual(contract.measurements.first?.source, .measured)
    }

    // MARK: - Compliance evaluation

    func test_compliance_passingMeasurements() {
        var scene = ExternalClearanceScene(
            propertySessionID: UUID(),
            captureSessionID: UUID()
        )
        scene.measurements = [
            ClearanceMeasurementCapture(kind: .terminalToOpening,  valueM: 0.50),
            ClearanceMeasurementCapture(kind: .terminalToBoundary, valueM: 0.80),
            ClearanceMeasurementCapture(kind: .terminalToEaves,    valueM: 0.45),
        ]
        let comp = scene.evaluateCompliance()
        XCTAssertEqual(comp.pass, true)
        XCTAssertTrue(comp.warnings.isEmpty)
    }

    func test_compliance_failingOpeningMeasurement() {
        var scene = ExternalClearanceScene(
            propertySessionID: UUID(),
            captureSessionID: UUID()
        )
        scene.measurements = [
            ClearanceMeasurementCapture(kind: .terminalToOpening, valueM: 0.25)
        ]
        let comp = scene.evaluateCompliance()
        XCTAssertEqual(comp.pass, false)
        XCTAssertFalse(comp.warnings.isEmpty)
    }

    func test_compliance_marginalOpeningWarning() {
        var scene = ExternalClearanceScene(
            propertySessionID: UUID(),
            captureSessionID: UUID()
        )
        // Between 300mm and 400mm: warning but not fail
        scene.measurements = [
            ClearanceMeasurementCapture(kind: .terminalToOpening, valueM: 0.35)
        ]
        let comp = scene.evaluateCompliance()
        XCTAssertEqual(comp.pass, true)
        XCTAssertFalse(comp.warnings.isEmpty, "Should have a marginal warning")
    }

    func test_compliance_failingBoundaryMeasurement() {
        var scene = ExternalClearanceScene(
            propertySessionID: UUID(),
            captureSessionID: UUID()
        )
        scene.measurements = [
            ClearanceMeasurementCapture(kind: .terminalToBoundary, valueM: 0.45)
        ]
        let comp = scene.evaluateCompliance()
        XCTAssertEqual(comp.pass, false)
    }

    func test_compliance_nilPassWhenNoMeasurements() {
        let scene = ExternalClearanceScene(
            propertySessionID: UUID(),
            captureSessionID: UUID()
        )
        let comp = scene.evaluateCompliance()
        XCTAssertNil(comp.pass)
    }

    func test_compliance_standardRef() {
        let scene = ExternalClearanceScene(
            propertySessionID: UUID(),
            captureSessionID: UUID()
        )
        let comp = scene.evaluateCompliance()
        XCTAssertEqual(comp.standardRef, "BS 5440")
    }

    // MARK: - PropertyScanSession backward-compatible decode

    func test_session_decodeWithout3DEvidence_defaultsToEmpty() throws {
        // Sessions saved before this feature was added have no evidence fields.
        // They should decode cleanly with empty arrays.
        let sessionWithoutEvidence = PropertyScanSession(propertyAddress: "Old Street")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var dict = try JSONSerialization.jsonObject(
            with: encoder.encode(sessionWithoutEvidence)
        ) as! [String: Any]
        dict.removeValue(forKey: "roomScanEvidence")
        dict.removeValue(forKey: "externalClearanceScenes")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PropertyScanSession.self, from: data)
        XCTAssertTrue(decoded.roomScanEvidence.isEmpty)
        XCTAssertTrue(decoded.externalClearanceScenes.isEmpty)
    }

    // MARK: - ClearanceFeatureKind

    func test_clearanceFeatureKind_allCasesHaveDisplayNames() {
        for kind in ClearanceFeatureKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(kind.symbolName.isEmpty)
        }
    }

    func test_clearanceFeatureKind_contractMappingIsExhaustive() {
        // Verify that every local feature kind maps to a valid contract type.
        for kind in ClearanceFeatureKind.allCases {
            let contractType = kind.contractFeatureType
            XCTAssertFalse(contractType.rawValue.isEmpty)
        }
    }
}
