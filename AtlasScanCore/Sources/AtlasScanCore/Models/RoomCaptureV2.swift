/// RoomCaptureV2 — Represents one room captured during the spatial walkthrough.
///
/// Each room has:
/// - A UUID (parent for all evidence in that space)
/// - An actual polygon (vertices, not a bounding box)
/// - Fabric classification per wall segment
/// - Pinned engineering objects
/// - A reference to the USDZ mesh asset for Van Mode review

import Foundation

// MARK: - Room capture

public struct RoomCaptureV2: Codable, Identifiable, Sendable {
    public let id: UUID          // == roomId used elsewhere
    public var displayName: String

    // ── Geometry ─────────────────────────────────────────────────────────────
    /// Ordered polygon vertices in the horizontal (X, Z) plane.
    /// Coordinate space: right-handed Y-up, metric metres.
    public var polygonVertices: [Vertex2D]

    /// Floor-level Y coordinate (metres above reference datum).
    public var floorLevelY: Double

    /// Ceiling height above floor (metres).
    public var ceilingHeightM: Double
    /// Raw ceiling-height sample from capture before normalization/QA handling.
    public var rawCapturedCeilingHeightM: Double?

    // ── Fabric ───────────────────────────────────────────────────────────────
    public var fabricCapture: FloorPlanFabricCaptureV1?

    // ── Pinned objects ───────────────────────────────────────────────────────
    public var pinnedObjects: [SpatialPinV1]
    public var ghostAppliancePlacements: [GhostAppliancePlacementV1]
    public var customApplianceDefinitions: [CustomApplianceDefinitionV1]

    // ── Spatial measurements ─────────────────────────────────────────────────
    /// Point-to-point spatial measurements captured during the room scan.
    /// Decoded with `decodeIfPresent` so records written before this field was
    /// added decode cleanly — existing rooms simply start with no measurements.
    public var measurements: [SpatialMeasurementV1]

    // ── Van-mode asset ───────────────────────────────────────────────────────
    /// Relative path under `Documents/captures/{visitId}/` to the .usdz mesh.
    public var usdzAssetPath: String?

    // ── Timestamps ───────────────────────────────────────────────────────────
    public let capturedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        polygonVertices: [Vertex2D] = [],
        floorLevelY: Double = 0.0,
        ceilingHeightM: Double = 2.4,
        rawCapturedCeilingHeightM: Double? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.polygonVertices = polygonVertices
        self.floorLevelY = floorLevelY
        self.ceilingHeightM = ceilingHeightM
        self.rawCapturedCeilingHeightM = rawCapturedCeilingHeightM
        self.fabricCapture = nil
        self.pinnedObjects = []
        self.ghostAppliancePlacements = []
        self.customApplianceDefinitions = []
        self.measurements = []
        self.usdzAssetPath = nil
        self.capturedAt = capturedAt
    }

    // MARK: - Backward-compatible Codable

    private enum CodingKeys: String, CodingKey {
        case id, displayName, polygonVertices, floorLevelY, ceilingHeightM
        case rawCapturedCeilingHeightM, fabricCapture
        case pinnedObjects, ghostAppliancePlacements, customApplianceDefinitions
        case measurements
        case usdzAssetPath, capturedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        polygonVertices = try c.decode([Vertex2D].self, forKey: .polygonVertices)
        floorLevelY = try c.decode(Double.self, forKey: .floorLevelY)
        ceilingHeightM = try c.decode(Double.self, forKey: .ceilingHeightM)
        rawCapturedCeilingHeightM = try c.decodeIfPresent(Double.self, forKey: .rawCapturedCeilingHeightM)
        fabricCapture = try c.decodeIfPresent(FloorPlanFabricCaptureV1.self, forKey: .fabricCapture)
        pinnedObjects = try c.decodeIfPresent([SpatialPinV1].self, forKey: .pinnedObjects) ?? []
        ghostAppliancePlacements = try c.decodeIfPresent([GhostAppliancePlacementV1].self, forKey: .ghostAppliancePlacements) ?? []
        customApplianceDefinitions = try c.decodeIfPresent([CustomApplianceDefinitionV1].self, forKey: .customApplianceDefinitions) ?? []
        // Backward-compat: measurements absent in records written before this field.
        measurements = try c.decodeIfPresent([SpatialMeasurementV1].self, forKey: .measurements) ?? []
        usdzAssetPath = try c.decodeIfPresent(String.self, forKey: .usdzAssetPath)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
    }

    // MARK: Helpers

    /// Returns the area of the polygon using the shoelace formula (m²).
    public var floorAreaM2: Double {
        RoomPolygon(vertices: polygonVertices).area
    }

    /// True when the room has a valid closed floor outline polygon.
    public var hasClosedFloorPolygon: Bool {
        polygonVertices.count >= 3 && floorAreaM2 > 0.0001
    }

    /// Wall segments derived from the polygon vertices (for fabric tagging).
    public var wallSegments: [WallSegmentV1] {
        guard polygonVertices.count >= 2 else { return [] }
        return polygonVertices.indices.map { i in
            let next = (i + 1) % polygonVertices.count
            return WallSegmentV1(
                roomId: id,
                startVertex: polygonVertices[i],
                endVertex: polygonVertices[next],
                fabric: fabricCapture?.segments[safe: i]?.fabric ?? .externalWall
            )
        }
    }
}

public enum GhostPlacementPlaneV1: String, Codable, CaseIterable, Sendable {
    case wall
    case floor
    case ceiling
    case worktop
    case unknown
}

public struct GhostApplianceClearanceOffsetsMmV1: Codable, Equatable, Sendable {
    public let top: Int
    public let bottom: Int
    public let front: Int
    public let back: Int
    public let left: Int
    public let right: Int

    public init(
        top: Int = 0,
        bottom: Int = 0,
        front: Int = 0,
        back: Int = 0,
        left: Int = 0,
        right: Int = 0
    ) {
        self.top = top
        self.bottom = bottom
        self.front = front
        self.back = back
        self.left = left
        self.right = right
    }
}

public struct GhostApplianceDimensionsMmV1: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let depth: Int

    public init(width: Int, height: Int, depth: Int) {
        self.width = width
        self.height = height
        self.depth = depth
    }
}

public struct GhostAppliancePlacementV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let roomId: UUID
    public let capturePointId: UUID
    public let applianceModelId: String
    public let customApplianceDefinitionId: String?
    public let screenPoint: CGPointCodable
    public let placementPlane: GhostPlacementPlaneV1
    /// Richer semantic surface type for this placement.
    /// Derived from `placementPlane` when loading legacy records that predate
    /// this field.  Defaults to `SurfaceSemanticV1.derived(from: placementPlane)`
    /// when not explicitly set.
    public let surfaceSemantic: SurfaceSemanticV1
    public let planeNormalX: Double
    public let planeNormalY: Double
    public let planeNormalZ: Double
    public let worldPositionX: Double
    public let worldPositionY: Double
    public let worldPositionZ: Double
    public let rotationYaw: Double
    public let dimensionsMm: GhostApplianceDimensionsMmV1
    public let clearanceOffsetsMm: GhostApplianceClearanceOffsetsMmV1
    public let anchorConfidence: SpatialPinAnchorConfidence
    public let createdAt: Date
    public let notes: String?

    public init(
        id: UUID = UUID(),
        roomId: UUID,
        capturePointId: UUID,
        applianceModelId: String,
        customApplianceDefinitionId: String? = nil,
        screenPoint: CGPointCodable = .init(x: 0.5, y: 0.5),
        placementPlane: GhostPlacementPlaneV1 = .unknown,
        surfaceSemantic: SurfaceSemanticV1? = nil,
        planeNormalX: Double = 0,
        planeNormalY: Double = 0,
        planeNormalZ: Double = 0,
        worldPositionX: Double = 0,
        worldPositionY: Double = 0,
        worldPositionZ: Double = 0,
        rotationYaw: Double = 0,
        dimensionsMm: GhostApplianceDimensionsMmV1,
        clearanceOffsetsMm: GhostApplianceClearanceOffsetsMmV1 = .init(),
        anchorConfidence: SpatialPinAnchorConfidence = .screenOnly,
        createdAt: Date = Date(),
        notes: String? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.capturePointId = capturePointId
        self.applianceModelId = applianceModelId
        self.customApplianceDefinitionId = customApplianceDefinitionId
        self.screenPoint = screenPoint
        self.placementPlane = placementPlane
        self.surfaceSemantic = surfaceSemantic ?? SurfaceSemanticV1.derived(from: placementPlane)
        self.planeNormalX = planeNormalX
        self.planeNormalY = planeNormalY
        self.planeNormalZ = planeNormalZ
        self.worldPositionX = worldPositionX
        self.worldPositionY = worldPositionY
        self.worldPositionZ = worldPositionZ
        self.rotationYaw = rotationYaw
        self.dimensionsMm = dimensionsMm
        self.clearanceOffsetsMm = clearanceOffsetsMm
        self.anchorConfidence = anchorConfidence
        self.createdAt = createdAt
        self.notes = notes
    }

    public var worldPosition: SIMD3<Double> {
        SIMD3(worldPositionX, worldPositionY, worldPositionZ)
    }

    /// True when this placement requires engineer review.
    ///
    /// A placement needs review when:
    /// - It has no resolved world anchor (`screenOnly` confidence), or
    /// - The surface semantic is still unknown (no surface has been confirmed).
    public var needsReview: Bool {
        anchorConfidence == .screenOnly || surfaceSemantic == .unknown
    }

    public func translated(
        dx: Double = 0,
        dy: Double = 0,
        dz: Double = 0,
        rotationYawDelta: Double = 0
    ) -> GhostAppliancePlacementV1 {
        GhostAppliancePlacementV1(
            id: id,
            roomId: roomId,
            capturePointId: capturePointId,
            applianceModelId: applianceModelId,
            customApplianceDefinitionId: customApplianceDefinitionId,
            screenPoint: screenPoint,
            placementPlane: placementPlane,
            surfaceSemantic: surfaceSemantic,
            planeNormalX: planeNormalX,
            planeNormalY: planeNormalY,
            planeNormalZ: planeNormalZ,
            worldPositionX: worldPositionX + dx,
            worldPositionY: worldPositionY + dy,
            worldPositionZ: worldPositionZ + dz,
            rotationYaw: rotationYaw + rotationYawDelta,
            dimensionsMm: dimensionsMm,
            clearanceOffsetsMm: clearanceOffsetsMm,
            anchorConfidence: anchorConfidence,
            createdAt: createdAt,
            notes: notes
        )
    }

    /// Returns a copy of this placement with the surface semantic replaced.
    public func withSurfaceSemantic(_ semantic: SurfaceSemanticV1) -> GhostAppliancePlacementV1 {
        GhostAppliancePlacementV1(
            id: id,
            roomId: roomId,
            capturePointId: capturePointId,
            applianceModelId: applianceModelId,
            customApplianceDefinitionId: customApplianceDefinitionId,
            screenPoint: screenPoint,
            placementPlane: placementPlane,
            surfaceSemantic: semantic,
            planeNormalX: planeNormalX,
            planeNormalY: planeNormalY,
            planeNormalZ: planeNormalZ,
            worldPositionX: worldPositionX,
            worldPositionY: worldPositionY,
            worldPositionZ: worldPositionZ,
            rotationYaw: rotationYaw,
            dimensionsMm: dimensionsMm,
            clearanceOffsetsMm: clearanceOffsetsMm,
            anchorConfidence: anchorConfidence,
            createdAt: createdAt,
            notes: notes
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case roomId
        case capturePointId
        case applianceModelId
        case customApplianceDefinitionId
        case screenPoint
        case placementPlane
        case surfaceSemantic
        case planeNormalX
        case planeNormalY
        case planeNormalZ
        case worldPositionX
        case worldPositionY
        case worldPositionZ
        case rotationYaw
        case dimensionsMm
        case clearanceOffsetsMm
        case anchorConfidence
        case createdAt
        case notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        roomId = try container.decode(UUID.self, forKey: .roomId)
        capturePointId = try container.decode(UUID.self, forKey: .capturePointId)
        applianceModelId = try container.decode(String.self, forKey: .applianceModelId)
        customApplianceDefinitionId = try container.decodeIfPresent(String.self, forKey: .customApplianceDefinitionId)
        screenPoint = try container.decodeIfPresent(CGPointCodable.self, forKey: .screenPoint) ?? .init(x: 0.5, y: 0.5)
        placementPlane = try container.decode(GhostPlacementPlaneV1.self, forKey: .placementPlane)
        // Backward compat: derive from placementPlane when surfaceSemantic is absent
        // (records written before this field was added).
        let decodedSemantic = try container.decodeIfPresent(SurfaceSemanticV1.self, forKey: .surfaceSemantic)
        surfaceSemantic = decodedSemantic ?? SurfaceSemanticV1.derived(from: placementPlane)
        planeNormalX = try container.decode(Double.self, forKey: .planeNormalX)
        planeNormalY = try container.decode(Double.self, forKey: .planeNormalY)
        planeNormalZ = try container.decode(Double.self, forKey: .planeNormalZ)
        worldPositionX = try container.decode(Double.self, forKey: .worldPositionX)
        worldPositionY = try container.decode(Double.self, forKey: .worldPositionY)
        worldPositionZ = try container.decode(Double.self, forKey: .worldPositionZ)
        rotationYaw = try container.decode(Double.self, forKey: .rotationYaw)
        dimensionsMm = try container.decode(GhostApplianceDimensionsMmV1.self, forKey: .dimensionsMm)
        clearanceOffsetsMm = try container.decode(GhostApplianceClearanceOffsetsMmV1.self, forKey: .clearanceOffsetsMm)
        anchorConfidence = try container.decode(SpatialPinAnchorConfidence.self, forKey: .anchorConfidence)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

public struct CustomApplianceDefinitionV1: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let brand: String
    public let modelName: String
    public let applianceType: String
    public let dimensionsMm: GhostApplianceDimensionsMmV1
    public let clearanceOffsetsMm: GhostApplianceClearanceOffsetsMmV1
    public let createdAt: Date

    public init(
        id: String,
        brand: String,
        modelName: String,
        applianceType: String,
        dimensionsMm: GhostApplianceDimensionsMmV1,
        clearanceOffsetsMm: GhostApplianceClearanceOffsetsMmV1,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.brand = brand
        self.modelName = modelName
        self.applianceType = applianceType
        self.dimensionsMm = dimensionsMm
        self.clearanceOffsetsMm = clearanceOffsetsMm
        self.createdAt = createdAt
    }
}

// MARK: - Spatial pin (boiler, cylinder, flue terminal, etc.)

public struct SpatialPinV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let roomId: UUID
    public var visitId: UUID?
    public var externalAreaId: UUID?
    public var locationContext: PinPlacementLocationContext
    public var capturePointId: UUID?

    /// 3-D world-space position (Y-up, metric metres).
    public let positionX: Double
    public let positionY: Double
    public let positionZ: Double

    /// Screen-space aim marker normalised to 0...1.
    /// UI-only context that must not be treated as persistent spatial truth.
    public var screenPositionX: Double?
    public var screenPositionY: Double?

    public var objectType: PinnedObjectType
    public var label: String?
    public var objectCategory: PinObjectCategoryV1
    public var selectedTemplateId: String?
    public var manualEntry: SpatialPinManualEntryV1?

    /// Confidence of the underlying placement anchor.
    public var anchorConfidence: SpatialPinAnchorConfidence
    public var reviewStatus: SpatialPinReviewStatus
    public var provenance: SpatialPinProvenance

    /// Hardware spec linked to this pin (e.g. the boiler model).
    public var hardwareSpecId: UUID?

    /// Optional durable appliance model key from `ApplianceDefinitionV1`.
    public var modelId: String?

    /// The semantic surface this pin is attached to.
    /// Nil when the surface type has not been assessed (legacy records).
    public var surfaceSemantic: SurfaceSemanticV1?

    /// True when the world-space position is not at origin.
    public var hasNonZeroWorldPosition: Bool {
        abs(positionX) > 0.0001 || abs(positionY) > 0.0001 || abs(positionZ) > 0.0001
    }

    /// True when the pin has a usable world-space anchor.
    public var hasResolvedWorldAnchor: Bool {
        switch anchorConfidence {
        case .screenOnly:
            return false
        case .raycastEstimated, .worldLocked, .high, .medium, .low, .estimated:
            return hasNonZeroWorldPosition
        }
    }

    public init(
        id: UUID = UUID(),
        roomId: UUID,
        visitId: UUID? = nil,
        externalAreaId: UUID? = nil,
        locationContext: PinPlacementLocationContext = .unknownNeedsReview,
        capturePointId: UUID? = nil,
        positionX: Double,
        positionY: Double,
        positionZ: Double,
        screenPositionX: Double? = nil,
        screenPositionY: Double? = nil,
        objectType: PinnedObjectType,
        label: String? = nil,
        objectCategory: PinObjectCategoryV1 = .heatingSystemComponents,
        selectedTemplateId: String? = nil,
        manualEntry: SpatialPinManualEntryV1? = nil,
        anchorConfidence: SpatialPinAnchorConfidence = .raycastEstimated,
        reviewStatus: SpatialPinReviewStatus = .needsReview,
        provenance: SpatialPinProvenance = .manualCapture,
        hardwareSpecId: UUID? = nil,
        modelId: String? = nil,
        surfaceSemantic: SurfaceSemanticV1? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.visitId = visitId
        self.externalAreaId = externalAreaId
        self.locationContext = locationContext
        self.capturePointId = capturePointId
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.screenPositionX = screenPositionX
        self.screenPositionY = screenPositionY
        self.objectType = objectType
        self.label = label
        self.objectCategory = objectCategory
        self.selectedTemplateId = selectedTemplateId
        self.manualEntry = manualEntry
        self.anchorConfidence = anchorConfidence
        self.reviewStatus = reviewStatus
        self.provenance = provenance
        self.hardwareSpecId = hardwareSpecId
        self.modelId = modelId
        self.surfaceSemantic = surfaceSemantic
    }

    private enum CodingKeys: String, CodingKey {
        case id, roomId, visitId, externalAreaId, locationContext, capturePointId
        case positionX, positionY, positionZ, screenPositionX, screenPositionY
        case objectType, label, objectCategory, selectedTemplateId, manualEntry
        case anchorConfidence, reviewStatus, provenance
        case hardwareSpecId, modelId, surfaceSemantic
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        roomId = try container.decode(UUID.self, forKey: .roomId)
        visitId = try container.decodeIfPresent(UUID.self, forKey: .visitId)
        externalAreaId = try container.decodeIfPresent(UUID.self, forKey: .externalAreaId)
        locationContext = try container.decodeIfPresent(PinPlacementLocationContext.self, forKey: .locationContext) ?? .unknownNeedsReview
        capturePointId = try container.decodeIfPresent(UUID.self, forKey: .capturePointId)
        positionX = try container.decodeIfPresent(Double.self, forKey: .positionX) ?? 0
        positionY = try container.decodeIfPresent(Double.self, forKey: .positionY) ?? 0
        positionZ = try container.decodeIfPresent(Double.self, forKey: .positionZ) ?? 0
        screenPositionX = try container.decodeIfPresent(Double.self, forKey: .screenPositionX)
        screenPositionY = try container.decodeIfPresent(Double.self, forKey: .screenPositionY)
        objectType = try container.decodeIfPresent(PinnedObjectType.self, forKey: .objectType) ?? .other
        label = try container.decodeIfPresent(String.self, forKey: .label)
        objectCategory = try container.decodeIfPresent(PinObjectCategoryV1.self, forKey: .objectCategory) ?? .heatingSystemComponents
        selectedTemplateId = try container.decodeIfPresent(String.self, forKey: .selectedTemplateId)
        manualEntry = try container.decodeIfPresent(SpatialPinManualEntryV1.self, forKey: .manualEntry)
        anchorConfidence = try container.decodeIfPresent(SpatialPinAnchorConfidence.self, forKey: .anchorConfidence) ?? .screenOnly
        reviewStatus = try container.decodeIfPresent(SpatialPinReviewStatus.self, forKey: .reviewStatus)
            ?? (anchorConfidence == .screenOnly ? .needsReview : .confirmed)
        provenance = try container.decodeIfPresent(SpatialPinProvenance.self, forKey: .provenance) ?? .manualCapture
        hardwareSpecId = try container.decodeIfPresent(UUID.self, forKey: .hardwareSpecId)
        modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
        surfaceSemantic = try container.decodeIfPresent(SurfaceSemanticV1.self, forKey: .surfaceSemantic)
    }
}

public enum SpatialPinAnchorConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case estimated
    case raycastEstimated = "raycast_estimated"
    case worldLocked = "world_locked"
    case screenOnly = "screen_only"
}

public enum PinnedObjectType: String, Codable, CaseIterable, Sendable {
    case boiler
    case heatPump
    case hotWaterCylinder
    case flueTerminal
    case nearbyOpening    // window / door near flue
    case electricalPanel
    case gasmeter
    case other
}

public enum PinPlacementLocationContext: String, Codable, CaseIterable, Sendable {
    case wall
    case floor
    case ceiling
    case cupboard
    case airingCupboard = "airing_cupboard"
    case externalWall = "external_wall"
    case unknownNeedsReview = "unknown_needs_review"
}

public enum PinObjectCategoryV1: String, Codable, CaseIterable, Sendable {
    case heatSource = "heat_source"
    case hotWaterStorage = "hot_water_storage"
    case heatingSystemComponents = "heating_system_components"
    case flueExternal = "flue_external"
    case emitters = "emitters"
}

public enum SpatialPinReviewStatus: String, Codable, CaseIterable, Sendable {
    case confirmed
    case needsReview = "needs_review"
}

public enum SpatialPinProvenance: String, Codable, CaseIterable, Sendable {
    case manualCapture = "manual_capture"
    case roomScanInference = "room_scan_inference"
}

public struct SpatialPinManualEntryV1: Codable, Equatable, Sendable {
    public let manufacturer: String?
    public let model: String?
    public let type: String?
    public let widthMm: Int?
    public let heightMm: Int?
    public let depthMm: Int?
    public let flueOrientation: String?
    public let notes: String?
    public let photoEvidenceRecommended: Bool

    public init(
        manufacturer: String? = nil,
        model: String? = nil,
        type: String? = nil,
        widthMm: Int? = nil,
        heightMm: Int? = nil,
        depthMm: Int? = nil,
        flueOrientation: String? = nil,
        notes: String? = nil,
        photoEvidenceRecommended: Bool = true
    ) {
        self.manufacturer = manufacturer
        self.model = model
        self.type = type
        self.widthMm = widthMm
        self.heightMm = heightMm
        self.depthMm = depthMm
        self.flueOrientation = flueOrientation
        self.notes = notes
        self.photoEvidenceRecommended = photoEvidenceRecommended
    }
}

// MARK: - SpatialMeasurementV1

/// A point-to-point spatial measurement captured between two `LiveCapturePointV1` locations.
///
/// Links to the two capture points used as endpoints, records world-space positions,
/// derived distances, and the surface semantics at each end.  Atlas Mind evaluates
/// the measurements for installation reasoning (flue clearances, routing, etc.).
///
/// `needsReview` is true when either endpoint was screen-only (no resolved world anchor).
public struct SpatialMeasurementV1: Codable, Identifiable, Sendable {

    public let id: UUID
    public let roomId: UUID

    // ── Capture point references ──────────────────────────────────────────────
    public let startCapturePointId: UUID
    public let endCapturePointId: UUID

    // ── World-space positions ─────────────────────────────────────────────────
    public let startWorldPositionX: Double
    public let startWorldPositionY: Double
    public let startWorldPositionZ: Double
    public let endWorldPositionX: Double
    public let endWorldPositionY: Double
    public let endWorldPositionZ: Double

    // ── Derived distances ─────────────────────────────────────────────────────
    /// Straight-line distance between the two world-space positions (metres).
    public let distanceMeters: Double
    /// Horizontal (XZ-plane) distance, ignoring vertical offset (metres).
    public let horizontalDistanceMeters: Double
    /// Signed vertical offset: positive = end is above start (metres).
    public let verticalOffsetMeters: Double

    // ── Surface context ───────────────────────────────────────────────────────
    public let startSurfaceSemantic: SurfaceSemanticV1
    public let endSurfaceSemantic: SurfaceSemanticV1

    // ── Quality ───────────────────────────────────────────────────────────────
    /// Confidence level for the weaker of the two endpoints.
    public let anchorConfidence: SpatialPinAnchorConfidence

    // ── Meta ──────────────────────────────────────────────────────────────────
    public let createdAt: Date
    public let notes: String?

    // MARK: Init

    public init(
        id: UUID = UUID(),
        roomId: UUID,
        startCapturePointId: UUID,
        endCapturePointId: UUID,
        startWorldPosition: SIMD3<Double>,
        endWorldPosition: SIMD3<Double>,
        startSurfaceSemantic: SurfaceSemanticV1 = .unknown,
        endSurfaceSemantic: SurfaceSemanticV1 = .unknown,
        anchorConfidence: SpatialPinAnchorConfidence = .estimated,
        createdAt: Date = Date(),
        notes: String? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.startCapturePointId = startCapturePointId
        self.endCapturePointId = endCapturePointId
        self.startWorldPositionX = startWorldPosition.x
        self.startWorldPositionY = startWorldPosition.y
        self.startWorldPositionZ = startWorldPosition.z
        self.endWorldPositionX = endWorldPosition.x
        self.endWorldPositionY = endWorldPosition.y
        self.endWorldPositionZ = endWorldPosition.z
        let dx = endWorldPosition.x - startWorldPosition.x
        let dy = endWorldPosition.y - startWorldPosition.y
        let dz = endWorldPosition.z - startWorldPosition.z
        self.distanceMeters = (dx * dx + dy * dy + dz * dz).squareRoot()
        self.horizontalDistanceMeters = (dx * dx + dz * dz).squareRoot()
        self.verticalOffsetMeters = dy
        self.startSurfaceSemantic = startSurfaceSemantic
        self.endSurfaceSemantic = endSurfaceSemantic
        self.anchorConfidence = anchorConfidence
        self.createdAt = createdAt
        self.notes = notes
    }

    // MARK: Helpers

    public var startWorldPosition: SIMD3<Double> {
        SIMD3(startWorldPositionX, startWorldPositionY, startWorldPositionZ)
    }

    public var endWorldPosition: SIMD3<Double> {
        SIMD3(endWorldPositionX, endWorldPositionY, endWorldPositionZ)
    }

    /// True when the measurement requires engineer review.
    /// A measurement needs review when either endpoint is screen-only (no world anchor)
    /// or either surface semantic is still unknown.
    public var needsReview: Bool {
        anchorConfidence == .screenOnly ||
        startSurfaceSemantic == .unknown ||
        endSurfaceSemantic == .unknown
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
