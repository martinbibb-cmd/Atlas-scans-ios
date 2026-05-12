/// ExistingEquipmentPinV1 — A pin marking a *real, captured* piece of
/// equipment in the surveyed property (e.g. an existing boiler, gas meter,
/// stop tap, radiator).
///
/// Deliberately distinct from any "proposed equipment preview" type. Per the
/// continuous-survey rebuild brief:
///
///     ExistingEquipmentPinV1   = real captured object
///     ProposedEquipmentPreviewV1 = future proposal visualisation
///
/// Only `ExistingEquipmentPinV1` is part of the production capture flow.
/// Proposed-equipment previews remain a separate, DEBUG-gated concept and
/// must not be conflated with this type.

import Foundation

// MARK: - Equipment categories

/// The category of real equipment captured at a pin location.
/// Mirrors the brief's evidence-types list. `other` is the catch-all.
public enum EquipmentObjectCategory: String, Codable, Sendable, CaseIterable {
    case existingBoiler        = "existing_boiler"
    case existingCylinder      = "existing_cylinder"
    case gasMeter              = "gas_meter"
    case stopTap               = "stop_tap"
    case radiator
    case flueTerminal          = "flue_terminal"
    case condensateRoute       = "condensate_route"
    case pipeRoutePoint        = "pipe_route_point"
    case consumerUnit          = "consumer_unit"
    case other

    /// User-facing label used in `TagObjectSheet` and review screens.
    public var displayName: String {
        switch self {
        case .existingBoiler:   return "Existing boiler"
        case .existingCylinder: return "Existing cylinder"
        case .gasMeter:         return "Gas meter"
        case .stopTap:          return "Stop tap"
        case .radiator:         return "Radiator"
        case .flueTerminal:     return "Flue terminal"
        case .condensateRoute:  return "Condensate route"
        case .pipeRoutePoint:   return "Pipe route point"
        case .consumerUnit:     return "Consumer unit"
        case .other:            return "Other"
        }
    }
}

// MARK: - Anchor confidence

/// How spatially trustworthy a pin's position is.
///
/// - `worldLocked`: Anchored to a world-tracked AR anchor; safe to render
///   back into AR on room re-entry.
/// - `raycastEstimated`: Position came from a raycast hit but no persistent
///   anchor; may drift between sessions.
/// - `screenOnly`: Only a screen-space position was captured; *must* be
///   surfaced as `needsReview` and must not be drawn as a precise AR marker.
/// - `manual`: User dropped or moved the pin manually; spatial precision is
///   not guaranteed.
public enum AnchorConfidence: String, Codable, Sendable, CaseIterable {
    case worldLocked      = "world_locked"
    case raycastEstimated = "raycast_estimated"
    case screenOnly       = "screen_only"
    case manual

    /// Whether this pin should be rendered back into AR on room re-entry.
    /// Only `worldLocked` pins can be re-rendered with confidence.
    public var canRenderInAR: Bool {
        self == .worldLocked
    }

    /// Whether a pin captured at this confidence requires engineer review
    /// before it can be considered final.
    public var requiresReview: Bool {
        self == .screenOnly || self == .manual
    }

    /// User-facing label used in `TagObjectSheet` and review screens.
    public var displayName: String {
        switch self {
        case .worldLocked:      return "World-locked"
        case .raycastEstimated: return "Raycast-estimated"
        case .screenOnly:       return "Screen only"
        case .manual:           return "Manual"
        }
    }
}

// MARK: - Pin review status

public enum PinReviewStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case confirmed
    case needsReview = "needs_review"
    case rejected
}

// MARK: - World transform (codable)

/// Minimal codable representation of a 4x4 world transform, stored as a
/// row-major flat array of 16 doubles. Avoids importing `simd` here so this
/// type compiles cleanly on non-Apple platforms (e.g. SwiftPM Linux builds).
/// Bridging helpers to/from `simd_float4x4` live alongside the AR renderer.
///
/// Note: A separate, AtlasScanCore-level `WorldTransformV1` exists for the
/// underlying `SpatialPinV1`. We deliberately keep this survey-shell type
/// distinct so that the new equipment-pin model is not coupled to the
/// AtlasScanCore type system as it evolves.
public struct EquipmentPinWorldTransformV1: Codable, Sendable, Equatable {
    /// Row-major 16 doubles. Always exactly 16 entries.
    public let matrix: [Double]

    public init(matrix: [Double]) {
        precondition(matrix.count == 16, "EquipmentPinWorldTransformV1 requires exactly 16 entries")
        self.matrix = matrix
    }
}

// MARK: - Screen-space position (codable)

public struct ScreenPositionV1: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

// MARK: - The pin

public struct ExistingEquipmentPinV1: Codable, Identifiable, Sendable, Equatable {
    public let pinId: UUID
    public let visitId: UUID
    public let workspaceId: String?
    public var roomId: UUID?
    public var capturePointId: UUID?

    public var objectCategory: EquipmentObjectCategory
    public var label: String?

    public var anchorConfidence: AnchorConfidence
    public var worldTransform: EquipmentPinWorldTransformV1?
    public var screenPosition: ScreenPositionV1?

    public var linkedPhotoIds: [UUID]
    public var reviewStatus: PinReviewStatus

    public let createdAt: Date
    public var updatedAt: Date

    /// `Identifiable` conformance — pin id is the stable identity.
    public var id: UUID { pinId }

    public init(
        pinId: UUID = UUID(),
        visitId: UUID,
        workspaceId: String? = nil,
        roomId: UUID? = nil,
        capturePointId: UUID? = nil,
        objectCategory: EquipmentObjectCategory,
        label: String? = nil,
        anchorConfidence: AnchorConfidence,
        worldTransform: EquipmentPinWorldTransformV1? = nil,
        screenPosition: ScreenPositionV1? = nil,
        linkedPhotoIds: [UUID] = [],
        reviewStatus: PinReviewStatus? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.pinId = pinId
        self.visitId = visitId
        self.workspaceId = workspaceId
        self.roomId = roomId
        self.capturePointId = capturePointId
        self.objectCategory = objectCategory
        self.label = label
        self.anchorConfidence = anchorConfidence
        self.worldTransform = worldTransform
        self.screenPosition = screenPosition
        self.linkedPhotoIds = linkedPhotoIds
        // Default review status follows the brief: uncertain pins are flagged
        // for review automatically.
        self.reviewStatus = reviewStatus
            ?? (anchorConfidence.requiresReview ? .needsReview : .pending)
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case pinId, visitId, workspaceId, roomId, capturePointId
        case objectCategory, label
        case anchorConfidence, worldTransform, screenPosition
        case linkedPhotoIds, reviewStatus
        case createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pinId = try c.decode(UUID.self, forKey: .pinId)
        visitId = try c.decode(UUID.self, forKey: .visitId)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        roomId = try c.decodeIfPresent(UUID.self, forKey: .roomId)
        capturePointId = try c.decodeIfPresent(UUID.self, forKey: .capturePointId)
        objectCategory = try c.decodeIfPresent(EquipmentObjectCategory.self, forKey: .objectCategory) ?? .other
        label = try c.decodeIfPresent(String.self, forKey: .label)
        anchorConfidence = try c.decodeIfPresent(AnchorConfidence.self, forKey: .anchorConfidence) ?? .manual
        worldTransform = try c.decodeIfPresent(EquipmentPinWorldTransformV1.self, forKey: .worldTransform)
        screenPosition = try c.decodeIfPresent(ScreenPositionV1.self, forKey: .screenPosition)
        linkedPhotoIds = try c.decodeIfPresent([UUID].self, forKey: .linkedPhotoIds) ?? []
        reviewStatus = try c.decodeIfPresent(PinReviewStatus.self, forKey: .reviewStatus)
            ?? (anchorConfidence.requiresReview ? .needsReview : .pending)
        let created = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        createdAt = created
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
    }
}
