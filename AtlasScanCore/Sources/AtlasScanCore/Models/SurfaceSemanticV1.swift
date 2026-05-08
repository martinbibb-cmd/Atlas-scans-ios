/// SurfaceSemanticV1 — Richer surface classification for spatial evidence.
///
/// Replaces the coarse two-or-three value surface type with a vocabulary
/// rich enough for installation reasoning: radiator placement, flue routing,
/// service clearances, cupboard fitment, and drilling / access warnings.
///
/// Detection defaults:
/// - Scan-derived wall surfaces default to `.externalWall` until the engineer
///   explicitly reviews and reclassifies them. This is the conservative
///   assumption — treating an unknown wall as external ensures heat-loss
///   calculations are never under-specified.
/// - Horizontal upward-facing surfaces (normal pointing up, large positive Y) default to `.floor`.
/// - Horizontal downward-facing surfaces (normal pointing down, large negative Y) default to `.ceiling`.
/// - Unclassified / no-plane surfaces default to `.unknown` and must be shown
///   in a review state so the engineer can correct them.

import Foundation
import simd

// MARK: - SurfaceSemanticV1

/// Semantic classification of the physical surface a spatial element is
/// attached to, measured from, or routed across.
///
/// Used by:
/// - `GhostAppliancePlacementV1` — records which surface the appliance sits on
/// - `LiveCapturePointV1`        — records the surface the capture probe hit
/// - Measurements                — records start and end surface context
/// - Routing anchors             — future use
public enum SurfaceSemanticV1: String, Codable, CaseIterable, Sendable {

    // MARK: Wall types

    /// A wall forming part of the external thermal envelope of the property.
    case externalWall  = "external_wall"

    /// A wall separating two rooms within the same dwelling.
    case internalWall  = "internal_wall"

    /// A wall shared with an adjoining property.
    case partyWall     = "party_wall"

    // MARK: Horizontal surfaces

    /// The floor surface of a room.
    case floor         = "floor"

    /// The ceiling surface of a room.
    case ceiling       = "ceiling"

    // MARK: Built-in furniture / structure

    /// The side panel of a built-in cupboard or housing unit.
    case cupboardSide  = "cupboard_side"

    /// The base or floor panel of a built-in cupboard or housing unit.
    case cupboardBase  = "cupboard_base"

    /// A kitchen or utility worktop surface.
    case worktop       = "worktop"

    // MARK: Special spaces

    /// A utility room, plant room, or enclosed service space.
    case utilitySpace  = "utility_space"

    /// A loft or roof-space surface.
    case loftSpace     = "loft_space"

    // MARK: Fallback

    /// Surface type is not yet known; requires engineer review.
    case unknown       = "unknown"

    // MARK: - Display properties

    /// Human-readable label for pickers and review UI.
    public var displayName: String {
        switch self {
        case .externalWall:  return "External Wall"
        case .internalWall:  return "Internal Wall"
        case .partyWall:     return "Party Wall"
        case .floor:         return "Floor"
        case .ceiling:       return "Ceiling"
        case .cupboardSide:  return "Cupboard Side"
        case .cupboardBase:  return "Cupboard Base"
        case .worktop:       return "Worktop"
        case .utilitySpace:  return "Utility Space"
        case .loftSpace:     return "Loft Space"
        case .unknown:       return "Unknown"
        }
    }

    /// SF Symbol name for use in semantic-picker and review UI.
    public var symbolName: String {
        switch self {
        case .externalWall:  return "house.fill"
        case .internalWall:  return "rectangle.split.2x1"
        case .partyWall:     return "building.2.fill"
        case .floor:         return "square.fill"
        case .ceiling:       return "arrow.up.to.line"
        case .cupboardSide:  return "door.left.hand.closed"
        case .cupboardBase:  return "tray.fill"
        case .worktop:       return "rectangle.fill"
        case .utilitySpace:  return "wrench.and.screwdriver.fill"
        case .loftSpace:     return "triangle.fill"
        case .unknown:       return "questionmark.circle"
        }
    }

    // MARK: - Category helpers

    /// True when this semantic represents a vertical wall-like surface.
    public var isWallType: Bool {
        switch self {
        case .externalWall, .internalWall, .partyWall, .cupboardSide:
            return true
        default:
            return false
        }
    }

    /// True when this semantic represents a horizontal surface.
    public var isHorizontalType: Bool {
        switch self {
        case .floor, .ceiling, .cupboardBase, .worktop:
            return true
        default:
            return false
        }
    }

    /// True when the surface classification is uncertain and requires review.
    public var requiresReview: Bool {
        self == .unknown
    }
}

// MARK: - Default derivation

public extension SurfaceSemanticV1 {

    /// Derives a default `SurfaceSemanticV1` from the coarse
    /// `GhostPlacementPlaneV1` stored on a placement or probe result.
    ///
    /// Scan-derived wall surfaces default to `.externalWall` because until the
    /// engineer explicitly reviews and reclassifies them, the conservative
    /// assumption avoids under-specifying heat-loss or clearance calculations.
    ///
    /// - Parameter plane: The coarse placement plane from the AR probe.
    /// - Returns: The most specific semantic that can safely be inferred.
    static func derived(from plane: GhostPlacementPlaneV1) -> SurfaceSemanticV1 {
        switch plane {
        case .wall:    return .externalWall
        case .floor:   return .floor
        case .ceiling: return .ceiling
        case .worktop: return .worktop
        case .unknown: return .unknown
        }
    }

    /// Derives a `SurfaceSemanticV1` from an AR hit-normal vector.
    ///
    /// Rules:
    /// - Normal pointing strongly upward (Y > 0.85) → `.floor`
    ///   (the surface normal faces up, meaning the engineer is standing on it)
    /// - Normal pointing strongly downward (Y < -0.85) → `.ceiling`
    ///   (the surface normal faces down, meaning it is above the engineer)
    /// - All other normals → `.externalWall`
    ///   (vertical or oblique = assumed wall, conservative default)
    ///
    /// Returns `.unknown` when `normal` is nil or near-zero.
    ///
    /// - Parameter normal: The surface normal vector from the AR raycast hit.
    /// - Returns: A conservative surface semantic.
    static func derived(fromHitNormal normal: SIMD3<Double>?) -> SurfaceSemanticV1 {
        guard let n = normal else { return .unknown }
        let length = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
        guard length > 0.0001 else { return .unknown }
        let ny = n.y / length
        if ny > 0.85  { return .floor }
        if ny < -0.85 { return .ceiling }
        return .externalWall
    }
}
