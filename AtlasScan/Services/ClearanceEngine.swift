import Foundation
import CoreGraphics

// MARK: - ClearanceStatus

/// Traffic-light status for a placed object's clearance check.
/// Guidance only — not a compliance approval.
enum ClearanceStatus {
    case clear    // green  — appears clear
    case warning  // amber  — tight / check manually
    case conflict // red    — likely conflict

    var displayMessage: String {
        switch self {
        case .clear:    return "Pass — service and install clearances available"
        case .warning:  return "Tight fit — install possible, servicing constrained"
        case .conflict: return "Blocked — clearance conflict detected"
        }
    }

    /// Short outcome label (one word). Used in summary banners and accessibility values.
    var shortLabel: String {
        switch self {
        case .clear:    return "Pass"
        case .warning:  return "Tight fit"
        case .conflict: return "Blocked"
        }
    }

    var symbolName: String {
        switch self {
        case .clear:    return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .conflict: return "xmark.circle.fill"
        }
    }
}

// MARK: - ClearanceSource

/// Identifies what is causing a clearance conflict.
///
/// Used in `ClearanceIssue.source` to give engineers actionable context —
/// e.g. "Blocked by wall" vs "Blocked by adjacent object".
///
/// Current detection is boundary-based (normalised room bounds [0,1]);
/// object-to-object collision detection is not yet included.
enum ClearanceSource: Equatable {
    /// The conflict is caused by a room wall or boundary.
    case wall
    /// The conflict is caused by another placed object (identified by its UUID).
    case object(UUID)
    /// The conflict is caused by ceiling height limitation.
    case ceiling
    /// The source cannot be determined from current scan data.
    case unknown
}

// MARK: - ClearanceIssue

/// A single identified clearance concern with a severity level and human-readable message.
struct ClearanceIssue {

    enum Kind: String {
        case frontAccessRestricted      = "front_restricted"
        case tooCloseToSideWall         = "too_close_side"
        case rearClearanceInsufficient  = "rear_insufficient"
        case openingWithinAccessZone    = "opening_access"
        case ceilingHeightLimiting      = "ceiling_limiting"
        case enclosedInstallation       = "enclosed"
        /// Another tagged object physically intrudes into this object's clearance zone.
        /// `source` will be `.object(UUID)` identifying the intruding object.
        case objectIntrusion            = "object_intrusion"
    }

    enum Severity {
        case warning
        case conflict
    }

    let kind: Kind
    let severity: Severity
    let message: String

    /// Directional label identifying which side or zone is affected.
    /// Examples: "front", "left", "right", "rear", "top".
    /// `nil` when the issue is not side-specific (e.g., ceiling height, enclosed install).
    let sideLabel: String?

    /// What is causing this clearance conflict.
    /// `nil` when the source is not yet populated (e.g., legacy call sites).
    let source: ClearanceSource?

    init(
        kind: Kind,
        severity: Severity,
        message: String,
        sideLabel: String? = nil,
        source: ClearanceSource? = nil
    ) {
        self.kind = kind
        self.severity = severity
        self.message = message
        self.sideLabel = sideLabel
        self.source = source
    }

    /// A human-readable description of what is causing the conflict, suitable for
    /// display in the issue sheet below the primary message.
    ///
    /// - Parameter objectName: Display name for the intruding object when `source` is
    ///   `.object(UUID)`. Pass the object's `displayLabel` when available so the UI
    ///   shows "Blocked by hot water cylinder" instead of a raw UUID.
    ///   Falls back to "Blocked by adjacent object" when `nil`.
    /// - Returns: `nil` when no source is available.
    func sourceDescription(objectName: String? = nil) -> String? {
        switch source {
        case .wall:             return "Blocked by wall"
        case .ceiling:          return "Blocked by ceiling"
        case .object:           return "Blocked by \(objectName ?? "adjacent object")"
        case .unknown:          return "Source not determined"
        case nil:               return nil
        }
    }
}

// MARK: - ClearanceResult

/// Full result of a clearance evaluation for one placed object.
/// Includes visual overlay geometry expressed in normalised room coordinates (0…1).
///
/// Three-layer clearance geometry:
///
///   footprintRect       — physical installed envelope of the unit itself.
///                         Solid border, strongest fill. Outermost container for the
///                         other two zones.
///
///   installMinimumRect  — tightest clearance that permits physical installation
///                         per manufacturer guidance.
///                         Dotted border, medium fill. Always contains footprintRect.
///
///   serviceAccessRect   — full working space required for routine service / maintenance.
///                         Dashed border, light fill. Always contains installMinimumRect.
///
/// COMPATIBILITY — clearanceRect is a backward-compatible computed alias for
/// serviceAccessRect. Existing callers that read clearanceRect continue to work
/// without change.
struct ClearanceResult {
    var status: ClearanceStatus
    var issues: [ClearanceIssue]

    /// Short caveat note about scan confidence, or `nil` when confidence is high.
    var confidenceNote: String?

    /// Guidance note from the selected appliance profile, or `nil` when no profile is chosen.
    var profileNote: String?

    /// Physical footprint of the object in normalised room coordinates.
    /// Represents the installed envelope of the unit itself.
    var footprintRect: CGRect

    /// Install-minimum clearance zone in normalised room coordinates.
    /// The tightest clearance that permits physical installation per manufacturer guidance.
    var installMinimumRect: CGRect

    /// Full service-access zone in normalised room coordinates.
    /// The working space required for routine servicing and maintenance.
    var serviceAccessRect: CGRect

    /// COMPATIBILITY ALIAS — equals `serviceAccessRect`.
    /// Retained so that existing callers of `clearanceRect` continue to compile
    /// and behave correctly without modification. New code should use
    /// `serviceAccessRect` directly.
    var clearanceRect: CGRect {
        serviceAccessRect
    }
}

// MARK: - ClearanceRule

/// Required clearance dimensions for one service object category.
/// All dimensions are in metres and represent typical residential installation guidance.
struct ClearanceRule {

    /// Approximate installed width of the object.
    let footprintWidthMetres: Double

    /// Approximate installed depth (front to back) of the object.
    let footprintDepthMetres: Double

    /// Minimum front clearance for physical installation (tighter than service access).
    /// Represents the smallest space that permits the unit to be installed.
    let installMinFrontMetres: Double

    /// Required clear working / service space in front of the object.
    let frontClearanceMetres: Double

    /// Required clear space on each side.
    let sideClearanceMetres: Double

    /// Required clear space behind the object (small or zero for wall-back installs).
    let rearClearanceMetres: Double

    /// Minimum room ceiling height for safe installation and servicing.
    let minCeilingHeightMetres: Double
}

// MARK: - ClearanceEngine

/// Local geometry-based clearance guidance for placed service objects.
///
/// All results are guidance only — not compliance approval. Status messages are
/// outcome-first ("Pass", "Tight fit", "Blocked") with hedged detail text.
///
/// Architecture: no RoomPlan or UIKit dependencies; uses only Foundation + CoreGraphics
/// and the app's local room/object models.
enum ClearanceEngine {

    // MARK: - Supported categories

    /// Object categories for which clearance evaluation is available.
    static let supportedCategories: Set<ServiceObjectCategory> = [
        .boiler, .cylinder, .manifold, .radiator,
    ]

    /// Returns the clearance rule for a supported category, or `nil`.
    static func rule(for category: ServiceObjectCategory) -> ClearanceRule? {
        switch category {
        case .boiler:
            // Typical combi or system boiler — Gas Safe / manufacturer guidance approximation
            return ClearanceRule(
                footprintWidthMetres:   0.60,
                footprintDepthMetres:   0.50,
                installMinFrontMetres:  0.30,
                frontClearanceMetres:   0.60,
                sideClearanceMetres:    0.15,
                rearClearanceMetres:    0.05,
                minCeilingHeightMetres: 2.00
            )
        case .cylinder:
            // Typical unvented cylinder (standing)
            return ClearanceRule(
                footprintWidthMetres:   0.55,
                footprintDepthMetres:   0.55,
                installMinFrontMetres:  0.25,
                frontClearanceMetres:   0.50,
                sideClearanceMetres:    0.10,
                rearClearanceMetres:    0.05,
                minCeilingHeightMetres: 1.90
            )
        case .manifold:
            // UFH / zoned manifold — typically wall-mounted or in a low cabinet
            return ClearanceRule(
                footprintWidthMetres:   0.50,
                footprintDepthMetres:   0.15,
                installMinFrontMetres:  0.30,
                frontClearanceMetres:   0.60,
                sideClearanceMetres:    0.10,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.80
            )
        case .radiator:
            // Panel radiator — wall-mounted; front and side clearance for airflow and cleaning
            return ClearanceRule(
                footprintWidthMetres:   0.60,
                footprintDepthMetres:   0.12,
                installMinFrontMetres:  0.03,
                frontClearanceMetres:   0.05,
                sideClearanceMetres:    0.05,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.50
            )
        default:
            return nil
        }
    }

    // MARK: - Private: overall status

    private static func overallStatus(from issues: [ClearanceIssue]) -> ClearanceStatus {
        for issue in issues where issue.severity == .conflict { return .conflict }
        for issue in issues where issue.severity == .warning  { return .warning  }
        return .clear
    }
}
