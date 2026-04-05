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
        case .clear:    return "Likely fits"
        case .warning:  return "Tight clearance — check manually"
        case .conflict: return "Restricted access likely"
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
    }

    enum Severity {
        case warning
        case conflict
    }

    let kind: Kind
    let severity: Severity
    let message: String
}

// MARK: - ClearanceResult

/// Full result of a clearance evaluation for one placed object.
/// Includes visual overlay geometry expressed in normalised room coordinates (0…1).
struct ClearanceResult {
    var status: ClearanceStatus
    var issues: [ClearanceIssue]

    /// Short caveat note about scan confidence, or `nil` when confidence is high.
    var confidenceNote: String?

    /// Physical footprint of the object in normalised room coordinates.
    var footprintRect: CGRect

    /// Total required clearance envelope (footprint + service/access zones)
    /// in normalised room coordinates.
    var clearanceRect: CGRect
}

// MARK: - ClearanceRule

/// Required clearance dimensions for one service object category.
/// All dimensions are in metres and represent typical residential installation guidance.
struct ClearanceRule {

    /// Approximate installed width of the object.
    let footprintWidthMetres: Double

    /// Approximate installed depth (front to back) of the object.
    let footprintDepthMetres: Double

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
/// All results are guidance only — not compliance approval. Wording is deliberately
/// hedged ("Likely fits", "check manually") to avoid false certainty.
///
/// Architecture: no RoomPlan or UIKit dependencies; uses only Foundation + CoreGraphics
/// and the app's local room/object models.
enum ClearanceEngine {

    // MARK: - Supported categories

    /// Object categories for which clearance evaluation is available in V1.
    static let supportedCategories: Set<ServiceObjectCategory> = [
        .boiler, .cylinder, .manifold, .radiator,
    ]

    // MARK: - Public API

    /// Evaluates clearance for a placed object within a room.
    ///
    /// Returns `nil` when the category is unsupported or the object has no position.
    static func evaluate(object: TaggedObject, in room: ScannedRoom) -> ClearanceResult? {
        guard supportedCategories.contains(object.category),
              let pos = object.normalizedPosition,
              let rule = Self.rule(for: object.category)
        else { return nil }

        let (roomWidth, roomHeight) = estimateRoomDimensions(room)
        let polygon = PlacementService.layoutPolygon(for: room)
        let facing = determineFacing(pos: pos, roomWidth: roomWidth, roomHeight: roomHeight)

        let (footprintRect, clearanceRect) = overlayRects(
            pos: pos, rule: rule, facing: facing,
            roomWidth: roomWidth, roomHeight: roomHeight
        )

        var issues: [ClearanceIssue] = []
        issues += wallProximityIssues(
            pos: pos, rule: rule, facing: facing,
            roomWidth: roomWidth, roomHeight: roomHeight
        )
        issues += openingProximityIssues(
            clearanceRect: clearanceRect,
            room: room,
            polygon: polygon
        )
        if let issue = ceilingIssue(rule: rule, room: room) {
            issues.append(issue)
        }
        if let issue = enclosedIssue(object: object) {
            issues.append(issue)
        }

        return ClearanceResult(
            status: overallStatus(from: issues),
            issues: issues,
            confidenceNote: confidenceNote(for: object, room: room),
            footprintRect: footprintRect,
            clearanceRect: clearanceRect
        )
    }

    /// Returns the clearance rule for a supported category, or `nil`.
    static func rule(for category: ServiceObjectCategory) -> ClearanceRule? {
        switch category {
        case .boiler:
            // Typical combi or system boiler — Gas Safe / manufacturer guidance approximation
            return ClearanceRule(
                footprintWidthMetres:   0.60,
                footprintDepthMetres:   0.50,
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
                frontClearanceMetres:   0.05,
                sideClearanceMetres:    0.05,
                rearClearanceMetres:    0.00,
                minCeilingHeightMetres: 1.50
            )
        default:
            return nil
        }
    }

    // MARK: - Room dimension estimation

    /// Estimates room width (x-axis) and height (y-axis) in metres.
    ///
    /// Priority: wall bearing geometry → floor area square root → 4 m × 4 m default.
    static func estimateRoomDimensions(_ room: ScannedRoom) -> (widthMetres: Double, heightMetres: Double) {
        let hasGeometry = room.walls.count >= 3
            && room.walls.contains { $0.bearingDegrees != nil }

        if hasGeometry {
            let raw = rawWallPolygonPoints(from: room.walls)
            let xs = raw.map(\.x)
            let ys = raw.map(\.y)
            let w = (xs.max() ?? 4.0) - (xs.min() ?? 0.0)
            let h = (ys.max() ?? 4.0) - (ys.min() ?? 0.0)
            if w > 0.5 && h > 0.5 { return (w, h) }
        }

        if let area = room.areaSquareMetres, area > 0 {
            let side = area.squareRoot()
            return (side, side)
        }

        return (4.0, 4.0)
    }

    // MARK: - Private: raw polygon (before normalisation)

    /// Builds raw (un-normalised) wall polygon vertices using the same algorithm
    /// as PlacementService.normalizedWallPolygon, but without the scaling step.
    private static func rawWallPolygonPoints(from walls: [ScannedWall]) -> [CGPoint] {
        var x = 0.0, y = 0.0
        let defaultLen = 3.0
        return walls.map { wall in
            let pt = CGPoint(x: x, y: y)
            let length = wall.lengthMetres ?? defaultLen
            let bearing = (wall.bearingDegrees ?? 0.0) * .pi / 180.0
            x += length * sin(bearing)
            y -= length * cos(bearing)   // screen-space Y convention
            return pt
        }
    }

    // MARK: - Private: facing direction

    /// Cardinal direction the front of the object faces (away from its back wall).
    enum ObjectFacing { case up, down, left, right }

    /// Determines facing from the object's normalised position within the room.
    /// The nearest room edge is treated as the back wall; the object faces away from it.
    static func determineFacing(
        pos: NormalizedPoint2D,
        roomWidth: Double,
        roomHeight: Double
    ) -> ObjectFacing {
        let distLeft   = pos.x * roomWidth
        let distRight  = (1.0 - pos.x) * roomWidth
        let distTop    = pos.y * roomHeight
        let distBottom = (1.0 - pos.y) * roomHeight

        let minDist = min(distLeft, distRight, distTop, distBottom)
        if minDist == distTop    { return .down  }  // near top → faces room (down)
        if minDist == distBottom { return .up    }  // near bottom → faces room (up)
        if minDist == distLeft   { return .right }  // near left → faces room (right)
        return .left
    }

    // MARK: - Private: overlay rectangles

    /// Computes the normalised footprint and clearance envelope rectangles.
    static func overlayRects(
        pos: NormalizedPoint2D,
        rule: ClearanceRule,
        facing: ObjectFacing,
        roomWidth: Double,
        roomHeight: Double
    ) -> (footprint: CGRect, clearance: CGRect) {
        let fpHalfW = (rule.footprintWidthMetres / 2.0) / roomWidth
        let fpHalfD = (rule.footprintDepthMetres / 2.0) / roomHeight

        let footprintRect = CGRect(
            x: pos.x - fpHalfW, y: pos.y - fpHalfD,
            width: fpHalfW * 2,  height: fpHalfD * 2
        )

        let frontN = rule.frontClearanceMetres
        let sideN  = rule.sideClearanceMetres
        let rearN  = rule.rearClearanceMetres

        let clearanceRect: CGRect
        switch facing {
        case .down:
            // back = top wall, front extends downward
            let clHalfW = (rule.footprintWidthMetres / 2.0 + sideN) / roomWidth
            let top     = pos.y - fpHalfD - rearN  / roomHeight
            let bottom  = pos.y + fpHalfD + frontN / roomHeight
            clearanceRect = CGRect(x: pos.x - clHalfW, y: top, width: clHalfW * 2, height: bottom - top)

        case .up:
            // back = bottom wall, front extends upward
            let clHalfW = (rule.footprintWidthMetres / 2.0 + sideN) / roomWidth
            let top     = pos.y - fpHalfD - frontN / roomHeight
            let bottom  = pos.y + fpHalfD + rearN  / roomHeight
            clearanceRect = CGRect(x: pos.x - clHalfW, y: top, width: clHalfW * 2, height: bottom - top)

        case .right:
            // back = left wall, front extends rightward
            let clHalfH = (rule.footprintDepthMetres / 2.0 + sideN) / roomHeight
            let left    = pos.x - fpHalfW - rearN  / roomWidth
            let right   = pos.x + fpHalfW + frontN / roomWidth
            clearanceRect = CGRect(x: left, y: pos.y - clHalfH, width: right - left, height: clHalfH * 2)

        case .left:
            // back = right wall, front extends leftward
            let clHalfH = (rule.footprintDepthMetres / 2.0 + sideN) / roomHeight
            let left    = pos.x - fpHalfW - frontN / roomWidth
            let right   = pos.x + fpHalfW + rearN  / roomWidth
            clearanceRect = CGRect(x: left, y: pos.y - clHalfH, width: right - left, height: clHalfH * 2)
        }

        return (footprintRect, clearanceRect)
    }

    // MARK: - Private: wall proximity

    private static func wallProximityIssues(
        pos: NormalizedPoint2D,
        rule: ClearanceRule,
        facing: ObjectFacing,
        roomWidth: Double,
        roomHeight: Double
    ) -> [ClearanceIssue] {
        var issues: [ClearanceIssue] = []

        let distLeft   = pos.x * roomWidth
        let distRight  = (1.0 - pos.x) * roomWidth
        let distTop    = pos.y * roomHeight
        let distBottom = (1.0 - pos.y) * roomHeight

        let requiredFront = rule.footprintDepthMetres / 2.0 + rule.frontClearanceMetres
        let requiredSide  = rule.footprintWidthMetres / 2.0 + rule.sideClearanceMetres

        let frontDist: Double
        let sideDist1: Double
        let sideDist2: Double

        switch facing {
        case .down:
            frontDist = distBottom; sideDist1 = distLeft;  sideDist2 = distRight
        case .up:
            frontDist = distTop;    sideDist1 = distLeft;  sideDist2 = distRight
        case .right:
            frontDist = distRight;  sideDist1 = distTop;   sideDist2 = distBottom
        case .left:
            frontDist = distLeft;   sideDist1 = distTop;   sideDist2 = distBottom
        }

        // Front clearance
        if frontDist < requiredFront {
            issues.append(ClearanceIssue(
                kind: .frontAccessRestricted,
                severity: .conflict,
                message: "Front service space restricted"
            ))
        } else if frontDist < requiredFront * 1.20 {
            issues.append(ClearanceIssue(
                kind: .frontAccessRestricted,
                severity: .warning,
                message: "Tight clearance in front — check manually"
            ))
        }

        // Side clearance (flag if either side is tight)
        let minSide = min(sideDist1, sideDist2)
        if minSide < requiredSide {
            issues.append(ClearanceIssue(
                kind: .tooCloseToSideWall,
                severity: .conflict,
                message: "Too close to side wall"
            ))
        } else if minSide < requiredSide * 1.30 {
            issues.append(ClearanceIssue(
                kind: .tooCloseToSideWall,
                severity: .warning,
                message: "Tight on side — check manually"
            ))
        }

        return issues
    }

    // MARK: - Private: opening proximity

    private static func openingProximityIssues(
        clearanceRect: CGRect,
        room: ScannedRoom,
        polygon: [CGPoint]
    ) -> [ClearanceIssue] {
        var issues: [ClearanceIssue] = []
        for opening in room.openings {
            guard opening.wallIndex < polygon.count else { continue }
            let a = polygon[opening.wallIndex]
            let b = polygon[(opening.wallIndex + 1) % polygon.count]
            // Approximate the opening's position at the midpoint of its wall segment
            let pt = CGPoint(
                x: a.x + 0.5 * (b.x - a.x),
                y: a.y + 0.5 * (b.y - a.y)
            )
            guard clearanceRect.contains(pt) else { continue }
            let msg = opening.kind == .door
                ? "Door swing overlaps working area"
                : "Opening/obstruction within access zone"
            issues.append(ClearanceIssue(kind: .openingWithinAccessZone, severity: .warning, message: msg))
            break   // one opening warning per object is sufficient
        }
        return issues
    }

    // MARK: - Private: ceiling height

    private static func ceilingIssue(rule: ClearanceRule, room: ScannedRoom) -> ClearanceIssue? {
        guard let ceilingH = room.ceilingHeightMetres else { return nil }
        if ceilingH < rule.minCeilingHeightMetres {
            return ClearanceIssue(
                kind: .ceilingHeightLimiting,
                severity: .conflict,
                message: "Ceiling height may be limiting"
            )
        }
        if ceilingH < rule.minCeilingHeightMetres * 1.05 {
            return ClearanceIssue(
                kind: .ceilingHeightLimiting,
                severity: .warning,
                message: "Ceiling height — check manually"
            )
        }
        return nil
    }

    // MARK: - Private: enclosed installation

    private static func enclosedIssue(object: TaggedObject) -> ClearanceIssue? {
        let isEnclosed = object.quickFieldValues["enclosed"]?.lowercased() == "true"
            || object.quickFieldValues["cupboard"]?.lowercased() == "true"
        guard isEnclosed else { return nil }
        return ClearanceIssue(
            kind: .enclosedInstallation,
            severity: .warning,
            message: "Enclosed — check cupboard working space"
        )
    }

    // MARK: - Private: confidence note

    private static func confidenceNote(for object: TaggedObject, room: ScannedRoom) -> String? {
        if !room.geometryCaptured {
            return "Scan confidence low in this area — geometry not captured by scanner"
        }
        if object.confidence == .low || object.confidence == .unknown {
            return "Low scan confidence — verify placement manually"
        }
        return nil
    }

    // MARK: - Private: overall status

    private static func overallStatus(from issues: [ClearanceIssue]) -> ClearanceStatus {
        for issue in issues where issue.severity == .conflict { return .conflict }
        for issue in issues where issue.severity == .warning  { return .warning  }
        return .clear
    }
}
