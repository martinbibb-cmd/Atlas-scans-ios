/// SurfaceSemanticV1Tests — Unit tests for the SurfaceSemanticV1 type.
///
/// Covers:
/// - Default derivation from GhostPlacementPlaneV1
/// - Hit-normal-based derivation
/// - Round-trip Codable serialisation
/// - GhostAppliancePlacementV1 backward-compat decoding (no surfaceSemantic field)
/// - withSurfaceSemantic(_:) mutation helper
/// - needsReview flags unknown surface semantic

import XCTest
import AtlasScanCore

final class SurfaceSemanticV1Tests: XCTestCase {

    // MARK: - Derivation from GhostPlacementPlaneV1

    func test_derived_fromPlane_wall_givesExternalWall() {
        XCTAssertEqual(SurfaceSemanticV1.derived(from: .wall), .externalWall,
                       "Scan-derived walls must default to externalWall (conservative assumption).")
    }

    func test_derived_fromPlane_floor_givesFloor() {
        XCTAssertEqual(SurfaceSemanticV1.derived(from: .floor), .floor)
    }

    func test_derived_fromPlane_ceiling_givesCeiling() {
        XCTAssertEqual(SurfaceSemanticV1.derived(from: .ceiling), .ceiling)
    }

    func test_derived_fromPlane_worktop_givesWorktop() {
        XCTAssertEqual(SurfaceSemanticV1.derived(from: .worktop), .worktop)
    }

    func test_derived_fromPlane_unknown_givesUnknown() {
        XCTAssertEqual(SurfaceSemanticV1.derived(from: .unknown), .unknown)
    }

    // MARK: - Derivation from hit normal

    func test_derived_fromHitNormal_nil_givesUnknown() {
        XCTAssertEqual(SurfaceSemanticV1.derived(fromHitNormal: nil), .unknown)
    }

    func test_derived_fromHitNormal_zeroVector_givesUnknown() {
        XCTAssertEqual(SurfaceSemanticV1.derived(fromHitNormal: SIMD3<Double>(0, 0, 0)), .unknown)
    }

    func test_derived_fromHitNormal_stronglyUpward_givesFloor() {
        // Normal pointing up = surface is below engineer = floor.
        XCTAssertEqual(SurfaceSemanticV1.derived(fromHitNormal: SIMD3<Double>(0, 1, 0)), .floor)
    }

    func test_derived_fromHitNormal_nearlyUpward_givesFloor() {
        // Y = 0.9 > threshold 0.85 → floor.
        XCTAssertEqual(SurfaceSemanticV1.derived(fromHitNormal: SIMD3<Double>(0.1, 0.9, 0.1)), .floor)
    }

    func test_derived_fromHitNormal_stronglyDownward_givesCeiling() {
        // Normal pointing down = surface is above engineer = ceiling.
        XCTAssertEqual(SurfaceSemanticV1.derived(fromHitNormal: SIMD3<Double>(0, -1, 0)), .ceiling)
    }

    func test_derived_fromHitNormal_nearlyDownward_givesCeiling() {
        // Y = -0.9 < threshold -0.85 → ceiling.
        XCTAssertEqual(SurfaceSemanticV1.derived(fromHitNormal: SIMD3<Double>(0.1, -0.9, 0.1)), .ceiling)
    }

    func test_derived_fromHitNormal_vertical_givesExternalWall() {
        // Purely vertical / side-facing normal → external wall (conservative).
        XCTAssertEqual(SurfaceSemanticV1.derived(fromHitNormal: SIMD3<Double>(0, 0, -1)), .externalWall)
        XCTAssertEqual(SurfaceSemanticV1.derived(fromHitNormal: SIMD3<Double>(1, 0, 0)), .externalWall)
        XCTAssertEqual(SurfaceSemanticV1.derived(fromHitNormal: SIMD3<Double>(0, 0.5, -1)), .externalWall)
    }

    // MARK: - Codable round-trip

    func test_codable_roundTrip_allCases() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for semantic in SurfaceSemanticV1.allCases {
            let data = try encoder.encode(semantic)
            let decoded = try decoder.decode(SurfaceSemanticV1.self, from: data)
            XCTAssertEqual(decoded, semantic, "Round-trip failed for \(semantic.rawValue)")
        }
    }

    // MARK: - GhostAppliancePlacementV1 backward compat

    func test_ghostPlacement_missingSemanticField_derivesFromPlacementPlane() throws {
        // Simulate a JSON payload written before surfaceSemantic was added.
        let legacyJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "roomId": "00000000-0000-0000-0000-000000000002",
            "capturePointId": "00000000-0000-0000-0000-000000000003",
            "applianceModelId": "atlas-combi-basic",
            "placementPlane": "wall",
            "planeNormalX": 0, "planeNormalY": 0, "planeNormalZ": -1,
            "worldPositionX": 1.0, "worldPositionY": 1.2, "worldPositionZ": 0.5,
            "rotationYaw": 0,
            "dimensionsMm": { "width": 600, "height": 700, "depth": 300 },
            "clearanceOffsetsMm": { "top": 0, "bottom": 0, "front": 0, "back": 0, "left": 0, "right": 0 },
            "anchorConfidence": "high",
            "createdAt": 0
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let placement = try JSONDecoder().decode(GhostAppliancePlacementV1.self, from: data)
        XCTAssertEqual(placement.surfaceSemantic, .externalWall,
                       "Legacy wall placement should derive externalWall from placementPlane.")
    }

    func test_ghostPlacement_missingSemanticField_floor_derivesFloor() throws {
        let legacyJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "roomId": "00000000-0000-0000-0000-000000000002",
            "capturePointId": "00000000-0000-0000-0000-000000000003",
            "applianceModelId": "atlas-cylinder-basic",
            "placementPlane": "floor",
            "planeNormalX": 0, "planeNormalY": 1, "planeNormalZ": 0,
            "worldPositionX": 1.0, "worldPositionY": 0.0, "worldPositionZ": 0.5,
            "rotationYaw": 0,
            "dimensionsMm": { "width": 450, "height": 1050, "depth": 450 },
            "clearanceOffsetsMm": { "top": 0, "bottom": 0, "front": 0, "back": 0, "left": 0, "right": 0 },
            "anchorConfidence": "high",
            "createdAt": 0
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let placement = try JSONDecoder().decode(GhostAppliancePlacementV1.self, from: data)
        XCTAssertEqual(placement.surfaceSemantic, .floor)
    }

    // MARK: - withSurfaceSemantic(_:)

    func test_withSurfaceSemantic_returnsCopyWithNewSemantic() {
        let original = GhostAppliancePlacementV1(
            roomId: UUID(),
            capturePointId: UUID(),
            applianceModelId: "test",
            placementPlane: .wall,
            surfaceSemantic: .externalWall,
            dimensionsMm: .init(width: 600, height: 700, depth: 300)
        )
        let updated = original.withSurfaceSemantic(.internalWall)
        XCTAssertEqual(updated.surfaceSemantic, .internalWall)
        XCTAssertEqual(updated.id, original.id, "ID must be preserved.")
        XCTAssertEqual(updated.placementPlane, original.placementPlane, "placementPlane must not change.")
    }

    // MARK: - needsReview

    func test_needsReview_screenOnly_isTrue() {
        let placement = GhostAppliancePlacementV1(
            roomId: UUID(),
            capturePointId: UUID(),
            applianceModelId: "test",
            placementPlane: .wall,
            surfaceSemantic: .externalWall,
            dimensionsMm: .init(width: 600, height: 700, depth: 300),
            anchorConfidence: .screenOnly
        )
        XCTAssertTrue(placement.needsReview)
    }

    func test_needsReview_unknownSemantic_isTrue() {
        let placement = GhostAppliancePlacementV1(
            roomId: UUID(),
            capturePointId: UUID(),
            applianceModelId: "test",
            placementPlane: .unknown,
            surfaceSemantic: .unknown,
            dimensionsMm: .init(width: 600, height: 700, depth: 300),
            anchorConfidence: .high
        )
        XCTAssertTrue(placement.needsReview)
    }

    func test_needsReview_knownSemanticHighConfidence_isFalse() {
        let placement = GhostAppliancePlacementV1(
            roomId: UUID(),
            capturePointId: UUID(),
            applianceModelId: "test",
            placementPlane: .wall,
            surfaceSemantic: .externalWall,
            dimensionsMm: .init(width: 600, height: 700, depth: 300),
            anchorConfidence: .high
        )
        XCTAssertFalse(placement.needsReview)
    }

    // MARK: - Display properties

    func test_displayName_neverEmpty() {
        for semantic in SurfaceSemanticV1.allCases {
            XCTAssertFalse(semantic.displayName.isEmpty, "\(semantic.rawValue) has no displayName.")
        }
    }

    func test_symbolName_neverEmpty() {
        for semantic in SurfaceSemanticV1.allCases {
            XCTAssertFalse(semantic.symbolName.isEmpty, "\(semantic.rawValue) has no symbolName.")
        }
    }

    func test_requiresReview_onlyForUnknown() {
        XCTAssertTrue(SurfaceSemanticV1.unknown.requiresReview)
        for semantic in SurfaceSemanticV1.allCases where semantic != .unknown {
            XCTAssertFalse(semantic.requiresReview, "\(semantic.rawValue) should not require review.")
        }
    }
}
