import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - SpatialAlignmentTests
//
// Tests covering:
//   1. AtlasSpatialModelV1 / AtlasAnchorV1 / AtlasWorldPositionV1 round-trip
//   2. AtlasVerticalRelationV1 round-trip
//   3. AtlasInferredRouteV1 round-trip (including no-ghost-data fields)
//   4. AtlasSpatialModelV1.isEmpty
//   5. AtlasPropertyV1 backward-compatible decode (spatialModel nil when absent)
//   6. SpatialAlignmentEngine.getRelativePosition
//   7. SpatialAlignmentEngine.buildVerticalRelations
//   8. SpatialAlignmentEngine.buildAlignmentInsights
//   9. SpatialAlignmentEngine.inferredRouteLength
//  10. SpatialAlignmentSelectors

final class SpatialAlignmentTests: XCTestCase {

    // MARK: - Fixtures

    private func makeConfirmedPosition(x: Double = 0, y: Double = 0, z: Double = 0) -> AtlasWorldPositionV1 {
        AtlasWorldPositionV1(x: x, y: y, z: z, confidence: .confirmed, source: .lidar)
    }

    private func makeInferredPosition(x: Double = 0, y: Double = 0, z: Double = 0) -> AtlasWorldPositionV1 {
        AtlasWorldPositionV1(x: x, y: y, z: z, confidence: .inferred, source: .derived)
    }

    private func makeAnchor(
        id: String,
        label: String,
        x: Double = 0, y: Double = 0, z: Double = 0,
        confidence: AtlasWorldPositionV1.PositionConfidence = .confirmed
    ) -> AtlasAnchorV1 {
        let pos = AtlasWorldPositionV1(
            x: x, y: y, z: z,
            confidence: confidence,
            source: confidence == .confirmed ? .manual : .derived
        )
        return AtlasAnchorV1(id: id, label: label, worldPosition: pos)
    }

    // MARK: - 1. AtlasWorldPositionV1 round-trip

    func test_worldPosition_roundTrip() throws {
        let pos = AtlasWorldPositionV1(x: 1.5, y: 2.4, z: -0.8, confidence: .confirmed, source: .lidar)
        let data = try JSONEncoder().encode(pos)
        let decoded = try JSONDecoder().decode(AtlasWorldPositionV1.self, from: data)
        XCTAssertEqual(decoded.x, 1.5)
        XCTAssertEqual(decoded.y, 2.4)
        XCTAssertEqual(decoded.z, -0.8)
        XCTAssertEqual(decoded.confidence, .confirmed)
        XCTAssertEqual(decoded.source, .lidar)
    }

    func test_worldPosition_inferredRoundTrip() throws {
        let pos = makeInferredPosition(x: 3, y: 1, z: 2)
        let data = try JSONEncoder().encode(pos)
        let decoded = try JSONDecoder().decode(AtlasWorldPositionV1.self, from: data)
        XCTAssertEqual(decoded.confidence, .inferred)
        XCTAssertEqual(decoded.source, .derived)
    }

    // MARK: - 2. AtlasAnchorV1 round-trip

    func test_anchor_roundTrip() throws {
        let anchor = AtlasAnchorV1(
            id: "anc-001",
            label: "boiler",
            worldPosition: makeConfirmedPosition(x: 2, y: 0.9, z: 1.5),
            roomId: "kitchen"
        )
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AtlasAnchorV1.self, from: data)
        XCTAssertEqual(decoded.id, "anc-001")
        XCTAssertEqual(decoded.label, "boiler")
        XCTAssertEqual(decoded.roomId, "kitchen")
        XCTAssertEqual(decoded.worldPosition.y, 0.9)
    }

    func test_anchor_roundTrip_nilRoomId() throws {
        let anchor = AtlasAnchorV1(
            id: "anc-002",
            label: "cylinder",
            worldPosition: makeConfirmedPosition(y: 3.2)
        )
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(AtlasAnchorV1.self, from: data)
        XCTAssertNil(decoded.roomId)
    }

    // MARK: - 3. AtlasVerticalRelationV1 round-trip

    func test_verticalRelation_roundTrip() throws {
        let rel = AtlasVerticalRelationV1(
            fromAnchorId: "a1",
            toAnchorId: "a2",
            verticalDistanceM: 2.3,
            relation: .above
        )
        let data = try JSONEncoder().encode(rel)
        let decoded = try JSONDecoder().decode(AtlasVerticalRelationV1.self, from: data)
        XCTAssertEqual(decoded.fromAnchorId, "a1")
        XCTAssertEqual(decoded.toAnchorId, "a2")
        XCTAssertEqual(decoded.verticalDistanceM, 2.3, accuracy: 0.001)
        XCTAssertEqual(decoded.relation, .above)
    }

    func test_verticalRelation_allCases() {
        let cases: [AtlasVerticalRelationV1.VerticalRelation] = [.above, .below, .sameLevel]
        XCTAssertEqual(cases.count, AtlasVerticalRelationV1.VerticalRelation.allCases.count)
    }

    // MARK: - 4. AtlasInferredRouteV1 round-trip

    func test_inferredRoute_roundTrip() throws {
        let route = AtlasInferredRouteV1(
            id: "route-001",
            type: .pipe,
            path: [
                makeInferredPosition(x: 0, y: 0, z: 0),
                makeInferredPosition(x: 0, y: 2, z: 0)
            ],
            reason: "Vertical rise from boiler to cylinder"
        )
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(AtlasInferredRouteV1.self, from: data)
        XCTAssertEqual(decoded.id, "route-001")
        XCTAssertEqual(decoded.type, .pipe)
        XCTAssertEqual(decoded.confidence, "inferred", "confidence must always be 'inferred'")
        XCTAssertEqual(decoded.reason, "Vertical rise from boiler to cylinder")
        XCTAssertEqual(decoded.path.count, 2)
    }

    func test_inferredRoute_confidenceAlwaysInferred() {
        // No-ghost-data rule: confidence is always "inferred" regardless of init args.
        let route = AtlasInferredRouteV1(
            id: "r",
            type: .cable,
            path: [],
            reason: "test"
        )
        XCTAssertEqual(route.confidence, "inferred")
    }

    // MARK: - 5. AtlasSpatialModelV1.isEmpty

    func test_spatialModel_isEmpty_trueWhenEmpty() {
        XCTAssertTrue(AtlasSpatialModelV1().isEmpty)
    }

    func test_spatialModel_isEmpty_falseWithAnchor() {
        let model = AtlasSpatialModelV1(anchors: [makeAnchor(id: "a", label: "boiler")])
        XCTAssertFalse(model.isEmpty)
    }

    func test_spatialModel_isEmpty_falseWithRoute() {
        let route = AtlasInferredRouteV1(id: "r", type: .pipe, path: [], reason: "test")
        let model = AtlasSpatialModelV1(inferredRoutes: [route])
        XCTAssertFalse(model.isEmpty)
    }

    // MARK: - 6. AtlasPropertyV1 backward-compatible decode (spatialModel nil when absent)

    func test_atlasPropertyV1_decodesWithoutSpatialModel() throws {
        let prop = AtlasPropertyV1(
            schemaVersion: "1.0",
            propertyID: "p1",
            jobReference: "JOB-001",
            propertyAddress: "1 Test Street",
            engineerName: "Alice",
            atlasJobID: nil,
            capturedAt: "2025-01-01T10:00:00Z",
            handoffAt: "2025-01-01T11:00:00Z",
            scanState: "completed",
            reviewState: "pending",
            rooms: [],
            adjacencies: [],
            sessionObjects: [],
            evidenceSummary: AtlasEvidenceSummaryV1(
                totalPhotos: 0,
                totalVoiceNotes: 0,
                sessionPhotoCount: 0,
                sessionVoiceNoteCount: 0
            )
        )
        let encoder = JSONEncoder()
        var dict = try JSONSerialization.jsonObject(with: encoder.encode(prop)) as! [String: Any]
        dict.removeValue(forKey: "spatialModel")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(AtlasPropertyV1.self, from: data)
        XCTAssertNil(decoded.spatialModel)
    }

    func test_atlasPropertyV1_roundTripWithSpatialModel() throws {
        let spatialModel = AtlasSpatialModelV1(
            anchors: [makeAnchor(id: "a1", label: "boiler", y: 0.9)],
            verticalRelations: [],
            inferredRoutes: []
        )
        let prop = AtlasPropertyV1(
            schemaVersion: "1.0",
            propertyID: "p1",
            jobReference: "JOB-001",
            propertyAddress: "1 Test Street",
            engineerName: "Bob",
            atlasJobID: nil,
            capturedAt: "2025-01-01T10:00:00Z",
            handoffAt: "2025-01-01T11:00:00Z",
            scanState: "completed",
            reviewState: "pending",
            rooms: [],
            adjacencies: [],
            sessionObjects: [],
            evidenceSummary: AtlasEvidenceSummaryV1(
                totalPhotos: 0, totalVoiceNotes: 0,
                sessionPhotoCount: 0, sessionVoiceNoteCount: 0
            ),
            spatialModel: spatialModel
        )
        let data = try JSONEncoder().encode(prop)
        let decoded = try JSONDecoder().decode(AtlasPropertyV1.self, from: data)
        XCTAssertNotNil(decoded.spatialModel)
        XCTAssertEqual(decoded.spatialModel?.anchors.first?.label, "boiler")
    }

    // MARK: - 7. SpatialAlignmentEngine.getRelativePosition

    func test_getRelativePosition_directlyAbove() {
        let user = AtlasWorldPositionV1(x: 0, y: 0, z: 0, confidence: .confirmed, source: .manual)
        let target = makeAnchor(id: "a", label: "cylinder", y: 2.5)
        let result = SpatialAlignmentEngine.getRelativePosition(userPosition: user, target: target)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.distanceM, 0, accuracy: 0.001)
        XCTAssertEqual(result!.verticalOffsetM, 2.5, accuracy: 0.001)
    }

    func test_getRelativePosition_bearing() {
        let user = AtlasWorldPositionV1(x: 0, y: 0, z: 0, confidence: .confirmed, source: .manual)
        let target = makeAnchor(id: "a", label: "boiler", x: 1.0, z: 1.0)
        let result = SpatialAlignmentEngine.getRelativePosition(userPosition: user, target: target)
        XCTAssertNotNil(result)
        // dx=1, dz=1 → bearing = atan2(1,1) = 45°
        XCTAssertEqual(result!.bearingDeg, 45, accuracy: 0.01)
    }

    func test_getRelativePosition_northBearing() {
        // Target directly along +z axis → bearing = 0
        let user = AtlasWorldPositionV1(x: 0, y: 0, z: 0, confidence: .confirmed, source: .manual)
        let target = makeAnchor(id: "a", label: "pump", z: 3.0)
        let result = SpatialAlignmentEngine.getRelativePosition(userPosition: user, target: target)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.bearingDeg, 0, accuracy: 0.01)
    }

    func test_getRelativePosition_confidencePreserved() {
        let user = AtlasWorldPositionV1(x: 0, y: 0, z: 0, confidence: .confirmed, source: .manual)
        let target = makeAnchor(id: "a", label: "pump", confidence: .inferred)
        let result = SpatialAlignmentEngine.getRelativePosition(userPosition: user, target: target)
        XCTAssertEqual(result?.confidence, .inferred)
    }

    // MARK: - 8. SpatialAlignmentEngine.buildVerticalRelations

    func test_buildVerticalRelations_aboveBelow() {
        let boiler   = makeAnchor(id: "b", label: "boiler",   y: 0.9)
        let cylinder = makeAnchor(id: "c", label: "cylinder", y: 3.2)
        let relations = SpatialAlignmentEngine.buildVerticalRelations(for: [boiler, cylinder])
        XCTAssertEqual(relations.count, 1)
        let rel = relations[0]
        XCTAssertEqual(rel.fromAnchorId, "b")
        XCTAssertEqual(rel.toAnchorId, "c")
        XCTAssertEqual(rel.verticalDistanceM, 3.2 - 0.9, accuracy: 0.001)
        XCTAssertEqual(rel.relation, .above)
    }

    func test_buildVerticalRelations_sameLevel() {
        let a = makeAnchor(id: "a", label: "rad1", y: 1.0)
        let b = makeAnchor(id: "b", label: "rad2", y: 1.05)
        let relations = SpatialAlignmentEngine.buildVerticalRelations(
            for: [a, b],
            sameLevelThresholdM: 0.1
        )
        XCTAssertEqual(relations.first?.relation, .sameLevel)
    }

    func test_buildVerticalRelations_pairCount() {
        let anchors = (0..<4).map { i in makeAnchor(id: "a\(i)", label: "obj\(i)", y: Double(i)) }
        let relations = SpatialAlignmentEngine.buildVerticalRelations(for: anchors)
        // n*(n-1)/2 = 4*3/2 = 6
        XCTAssertEqual(relations.count, 6)
    }

    // MARK: - 9. SpatialAlignmentEngine.buildAlignmentInsights

    func test_buildAlignmentInsights_returnsInsights() {
        let boiler   = makeAnchor(id: "b", label: "boiler",   y: 0.9)
        let cylinder = makeAnchor(id: "c", label: "cylinder", y: 3.2)
        let rel = AtlasVerticalRelationV1(
            fromAnchorId: "b", toAnchorId: "c",
            verticalDistanceM: 2.3, relation: .above
        )
        let model = AtlasSpatialModelV1(
            anchors: [boiler, cylinder],
            verticalRelations: [rel]
        )
        let insights = SpatialAlignmentEngine.buildAlignmentInsights(model: model)
        XCTAssertFalse(insights.isEmpty)
        XCTAssertEqual(insights.first?.label, "cylinder")
        XCTAssertEqual(insights.first?.relation, "above")
    }

    func test_buildAlignmentInsights_inferredRouteIncluded() {
        let route = AtlasInferredRouteV1(
            id: "r1", type: .pipe,
            path: [
                makeInferredPosition(y: 0),
                makeInferredPosition(y: 2)
            ],
            reason: "Test reason"
        )
        let model = AtlasSpatialModelV1(inferredRoutes: [route])
        let insights = SpatialAlignmentEngine.buildAlignmentInsights(model: model)
        XCTAssertTrue(insights.contains { $0.confidence == .inferred && $0.inferenceReason == "Test reason" })
    }

    // MARK: - 10. SpatialAlignmentEngine.inferredRouteLength

    func test_inferredRouteLength_twoPoints() {
        let route = AtlasInferredRouteV1(
            id: "r", type: .pipe,
            path: [
                makeInferredPosition(x: 0, y: 0, z: 0),
                makeInferredPosition(x: 3, y: 4, z: 0)
            ],
            reason: "test"
        )
        // Distance = sqrt(9 + 16) = 5
        XCTAssertEqual(SpatialAlignmentEngine.inferredRouteLength(route), 5.0, accuracy: 0.001)
    }

    func test_inferredRouteLength_singlePoint() {
        let route = AtlasInferredRouteV1(id: "r", type: .pipe, path: [makeInferredPosition()], reason: "test")
        XCTAssertEqual(SpatialAlignmentEngine.inferredRouteLength(route), 0)
    }

    // MARK: - 11. SpatialAlignmentSelectors

    func test_selectors_anchorById() {
        let a = makeAnchor(id: "x1", label: "boiler")
        let model = AtlasSpatialModelV1(anchors: [a])
        XCTAssertNotNil(SpatialAlignmentSelectors.anchor(id: "x1", in: model))
        XCTAssertNil(SpatialAlignmentSelectors.anchor(id: "missing", in: model))
    }

    func test_selectors_anchorsInRoom() {
        let a = AtlasAnchorV1(id: "a1", label: "boiler", worldPosition: makeConfirmedPosition(), roomId: "kitchen")
        let b = AtlasAnchorV1(id: "a2", label: "pump",   worldPosition: makeConfirmedPosition(), roomId: "utility")
        let model = AtlasSpatialModelV1(anchors: [a, b])
        XCTAssertEqual(SpatialAlignmentSelectors.anchors(inRoom: "kitchen", model: model).count, 1)
        XCTAssertEqual(SpatialAlignmentSelectors.anchors(inRoom: "utility", model: model).count, 1)
        XCTAssertTrue(SpatialAlignmentSelectors.anchors(inRoom: "other", model: model).isEmpty)
    }

    func test_selectors_confirmedAndInferred() {
        let confirmed = makeAnchor(id: "c", label: "boiler", confidence: .confirmed)
        let inferred  = makeAnchor(id: "i", label: "pump",   confidence: .inferred)
        let model = AtlasSpatialModelV1(anchors: [confirmed, inferred])
        XCTAssertEqual(SpatialAlignmentSelectors.confirmedAnchors(in: model).count, 1)
        XCTAssertEqual(SpatialAlignmentSelectors.inferredAnchors(in: model).count, 1)
    }

    func test_selectors_verticalRelationBetween() {
        let rel = AtlasVerticalRelationV1(fromAnchorId: "a", toAnchorId: "b", verticalDistanceM: 1.5, relation: .above)
        let model = AtlasSpatialModelV1(verticalRelations: [rel])
        XCTAssertNotNil(SpatialAlignmentSelectors.verticalRelation(between: "a", and: "b", in: model))
        XCTAssertNotNil(SpatialAlignmentSelectors.verticalRelation(between: "b", and: "a", in: model))
        XCTAssertNil(SpatialAlignmentSelectors.verticalRelation(between: "a", and: "x", in: model))
    }

    func test_selectors_totalInferredPipeLengthM() {
        let route = AtlasInferredRouteV1(
            id: "r", type: .pipe,
            path: [makeInferredPosition(z: 0), makeInferredPosition(z: 3)],
            reason: "test"
        )
        let model = AtlasSpatialModelV1(inferredRoutes: [route])
        XCTAssertEqual(SpatialAlignmentSelectors.totalInferredPipeLengthM(in: model), 3.0, accuracy: 0.001)
    }

    func test_selectors_modelSummary_empty() {
        let summary = SpatialAlignmentSelectors.modelSummary(AtlasSpatialModelV1())
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("0 anchors"))
    }

    func test_selectors_modelSummary_withContent() {
        let model = AtlasSpatialModelV1(
            anchors: [makeAnchor(id: "a", label: "boiler")],
            verticalRelations: [
                AtlasVerticalRelationV1(fromAnchorId: "a", toAnchorId: "b", verticalDistanceM: 1, relation: .above)
            ]
        )
        let summary = SpatialAlignmentSelectors.modelSummary(model)
        XCTAssertTrue(summary.contains("1 anchor"))
        XCTAssertTrue(summary.contains("1 vertical relation"))
    }
}
