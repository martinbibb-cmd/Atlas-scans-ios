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

    /// Object categories for which clearance evaluation is available in V1.
    static let supportedCategories: Set<ServiceObjectCategory> = [
        .boiler, .cylinder, .manifold, .radiator,
    ]

    // MARK: - Public API

    /// Evaluates clearance for a placed object within a room.
    ///
    /// Returns `nil` when the category is unsupported or the object has no position.
    ///
    /// When the object has an `applianceProfileID` that matches a profile in
    /// `ApplianceProfileLibrary`, that profile's rule and guidance note are used.
    /// Otherwise the default category rule applies.
    ///
    /// - Parameters:
    ///   - object: The object being evaluated.
    ///   - room: The room the object is placed in.
    ///   - otherObjects: Other tagged objects in the same room used for
    ///     object-to-object collision detection. Pass `room.taggedObjects` (excluding
    ///     `object`) to detect when another placed object intrudes into this object's
    ///     clearance zones. Defaults to empty (boundary-only evaluation).
    ///
    /// - Note: Object-to-object collision detection is 2D/rect-based using normalised
    ///   room coordinates. Only the physical footprint of each other object is
    ///   compared against the selected object's install-minimum and service-access zones.
    static func evaluate(
        object: TaggedObject,
        in room: ScannedRoom,
        otherObjects: [TaggedObject] = []
    ) -> ClearanceResult? {
        guard supportedCategories.contains(object.category),
              let pos = object.normalizedPosition
        else { return nil }

        // Resolve clearance rule: prefer appliance profile dimensions when set.
        let rule: ClearanceRule
        let profileNote: String?
        if let profileID = object.applianceProfileID,
           let profile = ApplianceProfileLibrary.profile(id: profileID) {
            rule = profile.rule
            profileNote = profile.guidanceNote
        } else {
            guard let categoryRule = Self.rule(for: object.category) else { return nil }
            rule = categoryRule
            profileNote = nil
        }

        let (roomWidth, roomHeight) = estimateRoomDimensions(room)
        let polygon = PlacementService.layoutPolygon(for: room)
        let facing = determineFacing(pos: pos, roomWidth: roomWidth, roomHeight: roomHeight)

        let (footprintRect, installMinimumRect, serviceAccessRect) = overlayRects(
            pos: pos, rule: rule, facing: facing,
            roomWidth: roomWidth, roomHeight: roomHeight
        )

        var issues: [ClearanceIssue] = []
        issues += wallProximityIssues(
            pos: pos, rule: rule, facing: facing,
            roomWidth: roomWidth, roomHeight: roomHeight
        )
        issues += openingProximityIssues(
            clearanceRect: serviceAccessRect,
            room: room,
            polygon: polygon
        )
        issues += objectIntrusionIssues(
            selected: object,
            pos: pos,
            installMinimumRect: installMinimumRect,
            serviceAccessRect: serviceAccessRect,
            otherObjects: otherObjects,
            roomWidth: roomWidth,
            roomHeight: roomHeight
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
            profileNote: profileNote,
            footprintRect: footprintRect,
            installMinimumRect: installMinimumRect,
            serviceAccessRect: serviceAccessRect
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

    /// Computes the normalised footprint, install-minimum, and service-access rectangles.
    ///
    /// Returns three layered halos from innermost to outermost:
    ///   1. `footprint`      — physical envelope of the installed unit
    ///   2. `installMinimum` — tightest space permitting installation
    ///   3. `serviceAccess`  — full working space for routine servicing
    static func overlayRects(
        pos: NormalizedPoint2D,
        rule: ClearanceRule,
        facing: ObjectFacing,
        roomWidth: Double,
        roomHeight: Double
    ) -> (footprint: CGRect, installMinimum: CGRect, serviceAccess: CGRect) {
        let fpHalfW = (rule.footprintWidthMetres / 2.0) / roomWidth
        let fpHalfD = (rule.footprintDepthMetres / 2.0) / roomHeight

        let footprintRect = CGRect(
            x: pos.x - fpHalfW, y: pos.y - fpHalfD,
            width: fpHalfW * 2,  height: fpHalfD * 2
        )

        let installMinimumRect = buildClearanceRect(
            pos: pos, rule: rule, facing: facing,
            frontClearance: rule.installMinFrontMetres,
            roomWidth: roomWidth, roomHeight: roomHeight,
            fpHalfW: fpHalfW, fpHalfD: fpHalfD
        )

        let serviceAccessRect = buildClearanceRect(
            pos: pos, rule: rule, facing: facing,
            frontClearance: rule.frontClearanceMetres,
            roomWidth: roomWidth, roomHeight: roomHeight,
            fpHalfW: fpHalfW, fpHalfD: fpHalfD
        )

        return (footprintRect, installMinimumRect, serviceAccessRect)
    }

    /// Builds a single clearance rectangle for the given front-clearance distance.
    private static func buildClearanceRect(
        pos: NormalizedPoint2D,
        rule: ClearanceRule,
        facing: ObjectFacing,
        frontClearance: Double,
        roomWidth: Double,
        roomHeight: Double,
        fpHalfW: Double,
        fpHalfD: Double
    ) -> CGRect {
        let sideN = rule.sideClearanceMetres
        let rearN = rule.rearClearanceMetres

        switch facing {
        case .down:
            // back = top wall, front extends downward
            let clHalfW = (rule.footprintWidthMetres / 2.0 + sideN) / roomWidth
            let top     = pos.y - fpHalfD - rearN         / roomHeight
            let bottom  = pos.y + fpHalfD + frontClearance / roomHeight
            return CGRect(x: pos.x - clHalfW, y: top, width: clHalfW * 2, height: bottom - top)

        case .up:
            // back = bottom wall, front extends upward
            let clHalfW = (rule.footprintWidthMetres / 2.0 + sideN) / roomWidth
            let top     = pos.y - fpHalfD - frontClearance / roomHeight
            let bottom  = pos.y + fpHalfD + rearN          / roomHeight
            return CGRect(x: pos.x - clHalfW, y: top, width: clHalfW * 2, height: bottom - top)

        case .right:
            // back = left wall, front extends rightward
            let clHalfH = (rule.footprintDepthMetres / 2.0 + sideN) / roomHeight
            let left    = pos.x - fpHalfW - rearN          / roomWidth
            let right   = pos.x + fpHalfW + frontClearance / roomWidth
            return CGRect(x: left, y: pos.y - clHalfH, width: right - left, height: clHalfH * 2)

        case .left:
            // back = right wall, front extends leftward
            let clHalfH = (rule.footprintDepthMetres / 2.0 + sideN) / roomHeight
            let left    = pos.x - fpHalfW - frontClearance / roomWidth
            let right   = pos.x + fpHalfW + rearN          / roomWidth
            return CGRect(x: left, y: pos.y - clHalfH, width: right - left, height: clHalfH * 2)
        }
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
        // Direction labels relative to the object's orientation.
        let sideLabel1: String   // "left" or "top" depending on facing
        let sideLabel2: String   // "right" or "bottom"

        switch facing {
        case .down:
            frontDist = distBottom; sideDist1 = distLeft;   sideDist2 = distRight
            sideLabel1 = "left";    sideLabel2 = "right"
        case .up:
            frontDist = distTop;    sideDist1 = distLeft;   sideDist2 = distRight
            sideLabel1 = "left";    sideLabel2 = "right"
        case .right:
            frontDist = distRight;  sideDist1 = distTop;    sideDist2 = distBottom
            sideLabel1 = "top";     sideLabel2 = "bottom"
        case .left:
            frontDist = distLeft;   sideDist1 = distTop;    sideDist2 = distBottom
            sideLabel1 = "top";     sideLabel2 = "bottom"
        }

        // Front clearance
        if frontDist < requiredFront {
            issues.append(ClearanceIssue(
                kind: .frontAccessRestricted,
                severity: .conflict,
                message: "Front service space restricted",
                sideLabel: "front",
                source: .wall
            ))
        } else if frontDist < requiredFront * 1.20 {
            issues.append(ClearanceIssue(
                kind: .frontAccessRestricted,
                severity: .warning,
                message: "Tight clearance in front — check manually",
                sideLabel: "front",
                source: .wall
            ))
        }

        // Side clearance — identify which side is tighter for the directional label.
        let minSide = min(sideDist1, sideDist2)
        let tightSideLabel = sideDist1 <= sideDist2 ? sideLabel1 : sideLabel2
        if minSide < requiredSide {
            issues.append(ClearanceIssue(
                kind: .tooCloseToSideWall,
                severity: .conflict,
                message: "Too close to side wall",
                sideLabel: tightSideLabel,
                source: .wall
            ))
        } else if minSide < requiredSide * 1.30 {
            issues.append(ClearanceIssue(
                kind: .tooCloseToSideWall,
                severity: .warning,
                message: "Tight on side — check manually",
                sideLabel: tightSideLabel,
                source: .wall
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
            issues.append(ClearanceIssue(kind: .openingWithinAccessZone, severity: .warning, message: msg, source: .wall))
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
                message: "Ceiling height may be limiting",
                source: .ceiling
            )
        }
        if ceilingH < rule.minCeilingHeightMetres * 1.05 {
            return ClearanceIssue(
                kind: .ceilingHeightLimiting,
                severity: .warning,
                message: "Ceiling height — check manually",
                source: .ceiling
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
            message: "Enclosed — check cupboard working space",
            source: .unknown
        )
    }

    // MARK: - Private: object-to-object intrusion

    /// Detects clearance conflicts caused by other tagged objects in the same room.
    ///
    /// For each `other` object that has a normalised position, this method computes
    /// its physical footprint rect and checks whether it overlaps with:
    ///   - `installMinimumRect` — emits a `.conflict` issue (hard block)
    ///   - `serviceAccessRect`  — emits a `.warning` issue (access constrained)
    ///
    /// Footprint dimensions come from the other object's appliance-profile rule when
    /// available, or the category default rule, or a 0.5 m × 0.5 m fallback.
    ///
    /// - Note: This is 2D/rect-based; object height and depth orientation are not
    ///   modelled. Each issue carries `source: .object(other.id)` so the UI can
    ///   resolve the UUID to a human-readable label.
    private static func objectIntrusionIssues(
        selected: TaggedObject,
        pos: NormalizedPoint2D,
        installMinimumRect: CGRect,
        serviceAccessRect: CGRect,
        otherObjects: [TaggedObject],
        roomWidth: Double,
        roomHeight: Double
    ) -> [ClearanceIssue] {
        var issues: [ClearanceIssue] = []

        for other in otherObjects {
            guard other.id != selected.id,
                  let otherPos = other.normalizedPosition
            else { continue }

            let otherFootprint = footprintRect(
                for: other, pos: otherPos,
                roomWidth: roomWidth, roomHeight: roomHeight
            )

            guard otherFootprint.intersects(installMinimumRect)
                    || otherFootprint.intersects(serviceAccessRect)
            else { continue }

            let sideLabel = intrusionSideLabel(
                fromSelected: pos, toOther: otherPos
            )

            if otherFootprint.intersects(installMinimumRect) {
                issues.append(ClearanceIssue(
                    kind: .objectIntrusion,
                    severity: .conflict,
                    message: "Install space blocked by adjacent object",
                    sideLabel: sideLabel,
                    source: .object(other.id)
                ))
            } else {
                // Overlaps service access zone only
                issues.append(ClearanceIssue(
                    kind: .objectIntrusion,
                    severity: .warning,
                    message: "Service zone overlaps adjacent object",
                    sideLabel: sideLabel,
                    source: .object(other.id)
                ))
            }
        }

        return issues
    }

    /// Computes a normalised footprint rect for an object given its position.
    ///
    /// Prefers the object's appliance-profile rule, then the category default rule,
    /// then falls back to a 0.5 m × 0.5 m bounding box.
    private static func footprintRect(
        for object: TaggedObject,
        pos: NormalizedPoint2D,
        roomWidth: Double,
        roomHeight: Double
    ) -> CGRect {
        let (fw, fd): (Double, Double)
        if let profileID = object.applianceProfileID,
           let profile = ApplianceProfileLibrary.profile(id: profileID) {
            fw = profile.rule.footprintWidthMetres
            fd = profile.rule.footprintDepthMetres
        } else if let r = Self.rule(for: object.category) {
            fw = r.footprintWidthMetres
            fd = r.footprintDepthMetres
        } else {
            fw = 0.5
            fd = 0.5
        }
        let hw = (fw / 2.0) / roomWidth
        let hd = (fd / 2.0) / roomHeight
        return CGRect(x: pos.x - hw, y: pos.y - hd, width: hw * 2, height: hd * 2)
    }

    /// Returns a directional label ("left", "right", "top", "bottom") describing
    /// where `otherPos` sits relative to `selectedPos` in normalised room coordinates.
    private static func intrusionSideLabel(
        fromSelected selectedPos: NormalizedPoint2D,
        toOther otherPos: NormalizedPoint2D
    ) -> String {
        let dx = otherPos.x - selectedPos.x
        let dy = otherPos.y - selectedPos.y
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? "right" : "left"
        } else {
            return dy >= 0 ? "bottom" : "top"
        }
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
