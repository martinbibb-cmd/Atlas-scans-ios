import Foundation

// MARK: - InstallMarkup (local capture models)
//
// App-internal models for capturing install markup during a survey session.
//
// These are the mutable, in-flight representations that the engineer creates
// via gesture-based drawing on room floor plans and wall photos.
//
// They are converted to AtlasContracts types (InstallObjectModelV1,
// InstallRouteModelV1, InstallLayerModelV1) when building the export payload
// handoff for atlas-recommendation.
//
// Architecture rule:
//   • This file owns the mutable, Codable capture-side shape.
//   • AtlasContracts owns the immutable, Sendable contract shape.
//   • PropertyScanSession.toInstallLayerModelV1() bridges the two.

// MARK: - Supporting enums

/// Which layer an object or route belongs to.
enum MarkupLayer: String, Codable, CaseIterable {
    /// The system currently installed at the property.
    case existing
    /// The proposed new installation being designed.
    case proposed
}

/// Pipe / circuit kind for a drawn route.
enum MarkupRouteKind: String, Codable, CaseIterable {
    case flow          = "flow"
    case `return`      = "return"
    case gas           = "gas"
    case coldWater     = "cold_water"
    case hotWater      = "hot_water"
    case condensate    = "condensate"
    case flue          = "flue"
    case electrical    = "electrical"
    case other         = "other"

    var displayName: String {
        switch self {
        case .flow:        return "Flow"
        case .return:      return "Return"
        case .gas:         return "Gas"
        case .coldWater:   return "Cold Water"
        case .hotWater:    return "Hot Water"
        case .condensate:  return "Condensate"
        case .flue:        return "Flue"
        case .electrical:  return "Electrical"
        case .other:       return "Other"
        }
    }

    /// SF Symbol name representing this route kind.
    var symbolName: String {
        switch self {
        case .flow:       return "flame"
        case .return:     return "arrow.uturn.left"
        case .gas:        return "g.circle"
        case .coldWater:  return "drop"
        case .hotWater:   return "drop.fill"
        case .condensate: return "humidity"
        case .flue:       return "arrow.up.to.line"
        case .electrical: return "bolt"
        case .other:      return "line.diagonal"
        }
    }
}

/// How a pipe route is physically mounted.
enum MarkupRouteMounting: String, Codable, CaseIterable {
    case surface    = "surface"
    case boxed      = "boxed"
    case underfloor = "underfloor"
    case inWall     = "in_wall"
    case unknown    = "unknown"

    var displayName: String {
        switch self {
        case .surface:    return "Surface"
        case .boxed:      return "Boxed"
        case .underfloor: return "Underfloor"
        case .inWall:     return "In Wall"
        case .unknown:    return "Unknown"
        }
    }
}

/// Spatial confidence for a drawn route.
enum MarkupRouteConfidence: String, Codable, CaseIterable {
    /// Route traced from LiDAR or scan geometry — spatially anchored.
    case measured  = "measured"
    /// Engineer drew route on canvas; scale derived from room dimensions.
    case drawn     = "drawn"
    /// System-inferred; low spatial confidence.
    case estimated = "estimated"
}

/// How the install object was added to the markup layer.
enum MarkupObjectSource: String, Codable, CaseIterable {
    /// Derived from RoomPlan / LiDAR geometry.
    case scan     = "scan"
    /// Engineer gesture-placed on floor plan or photo.
    case manual   = "manual"
    /// Automatically suggested by the system.
    case inferred = "inferred"
}

// MARK: - InstallMarkupObject

/// A spatially-placed install object on a markup layer canvas.
///
/// Represents one heat-source, emitter, or ancillary item that the engineer has
/// placed on a floor plan or wall photo.  Mutable during capture; converted to
/// `InstallObjectModelV1` at handoff time.
struct InstallMarkupObject: Identifiable, Codable {

    var id: UUID = UUID()

    /// Raw value of `ServiceObjectCategory` (e.g. "boiler", "cylinder").
    var categoryRawValue: String

    /// Engineer-assigned label; defaults to category display name if empty.
    var label: String

    /// Normalised position on the canvas (0…1 in both axes).
    var position: NormalizedPoint2D

    /// Footprint width in metres, when known.
    var widthM: Double?

    /// Footprint depth in metres, when known.
    var depthM: Double?

    /// Rotation about the vertical axis in radians.
    var rotationRad: Double

    /// How the object was placed.
    var source: MarkupObjectSource

    /// Which install layer this object belongs to.
    var layer: MarkupLayer

    /// Optional room association.
    var roomID: UUID?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        categoryRawValue: String,
        label: String = "",
        position: NormalizedPoint2D,
        widthM: Double? = nil,
        depthM: Double? = nil,
        rotationRad: Double = 0,
        source: MarkupObjectSource = .manual,
        layer: MarkupLayer = .proposed,
        roomID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.categoryRawValue = categoryRawValue
        self.label = label
        self.position = position
        self.widthM = widthM
        self.depthM = depthM
        self.rotationRad = rotationRad
        self.source = source
        self.layer = layer
        self.roomID = roomID
        self.createdAt = createdAt
    }

    /// Resolved display label: label if set, otherwise category display name.
    var displayLabel: String {
        label.isEmpty
            ? (ServiceObjectCategory(rawValue: categoryRawValue)?.displayName ?? categoryRawValue)
            : label
    }
}

// MARK: - InstallMarkupRoute

/// A drawn pipe or gas route on a markup layer canvas.
///
/// Defined as an ordered sequence of `NormalizedPoint2D` waypoints.
/// Converted to `InstallRouteModelV1` at handoff time using the room's
/// physical dimensions to scale normalised coordinates to real-world metres.
struct InstallMarkupRoute: Identifiable, Codable {

    var id: UUID = UUID()

    /// Pipe circuit kind.
    var kind: MarkupRouteKind

    /// Nominal diameter in millimetres.  0 when unknown.
    var diameterMm: Double

    /// Ordered waypoints defining the route path on the canvas.
    var path: [NormalizedPoint2D]

    /// How the pipe is physically mounted.
    var mounting: MarkupRouteMounting

    /// Spatial confidence of the drawn route.
    var confidence: MarkupRouteConfidence

    /// Which install layer this route belongs to.
    var layer: MarkupLayer

    /// Optional room association.
    var roomID: UUID?

    /// Optional engineer note.
    var notes: String

    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: MarkupRouteKind = .flow,
        diameterMm: Double = 22,
        path: [NormalizedPoint2D] = [],
        mounting: MarkupRouteMounting = .surface,
        confidence: MarkupRouteConfidence = .drawn,
        layer: MarkupLayer = .proposed,
        roomID: UUID? = nil,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.diameterMm = diameterMm
        self.path = path
        self.mounting = mounting
        self.confidence = confidence
        self.layer = layer
        self.roomID = roomID
        self.notes = notes
        self.createdAt = createdAt
    }
}
