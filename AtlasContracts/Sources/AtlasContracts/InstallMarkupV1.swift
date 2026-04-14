import Foundation

// MARK: - InstallMarkupV1
//
// Canonical install markup models produced by Atlas Scan iOS and consumed by
// Atlas Recommendation engine and Atlas reports.
//
// Design rules:
//   • atlas-scans-ios CREATES these models from engineer gesture/drawing input.
//   • atlas-contracts DEFINES the schema — this file is the single source of truth.
//   • atlas-recommendation CONSUMES them to derive routing complexity, material
//     estimates, and install feasibility signals.
//   • Markup is always structured data — never stored as images or free-form paths.
//   • InstallLayerModelV1 separates existing from proposed so the engine can compare.

// MARK: - Version constants

/// Current schema version for install markup contracts.
public let currentInstallMarkupVersion: String = "1.0"

/// Supported install markup schema versions.
public let supportedInstallMarkupVersions: [String] = ["1.0"]

// MARK: - Shared geometry

/// A 2-D path point in normalised room coordinates (0…1, 0…1).
///
/// Used for routes drawn on a floor-plan or wall-photo canvas.
/// The coordinate origin is the top-left corner of the bounding canvas;
/// x increases rightward, y increases downward.
public struct InstallPathPointV1: Codable, Sendable, Equatable {

    /// Normalised horizontal position within the room canvas (0 = left, 1 = right).
    public let x: Double

    /// Normalised vertical position within the room canvas (0 = top, 1 = bottom).
    public let y: Double

    /// Approximate height above floor in metres, when known (e.g. from LiDAR).
    /// Nil for 2-D plan drawings where height is unknown.
    public let heightM: Double?

    public init(x: Double, y: Double, heightM: Double? = nil) {
        self.x = x
        self.y = y
        self.heightM = heightM
    }
}

// MARK: - InstallObjectModelV1

/// A spatially-placed install object captured by the engineer on a floor plan
/// or wall photo.
///
/// Covers heat sources (boilers, cylinders, heat pumps) and emitters (radiators,
/// towel rails) as well as ancillary plant (pumps, valves, expansion vessels).
///
/// Source field distinguishes measured scan data from manual engineer placement
/// or system inference — consumers should weight confidence accordingly.
public struct InstallObjectModelV1: Codable, Sendable, Identifiable {

    // MARK: Identity

    /// UUID for this install object record.
    public let id: String

    // MARK: Classification

    /// Object type string matching `ServiceObjectCategory` raw values.
    /// Examples: "boiler", "cylinder", "radiator", "heat_pump".
    public let type: String

    /// Engineer-assigned or category-derived label.
    public let label: String

    // MARK: Spatial placement

    /// Normalised position on the canvas (0…1 in both axes).
    public let position: InstallPathPointV1

    /// Object footprint width in metres (horizontal in plan view). Nil if unknown.
    public let widthM: Double?

    /// Object footprint depth in metres (vertical / depth in plan view). Nil if unknown.
    public let depthM: Double?

    /// Rotation about the vertical axis in radians (0 = facing canvas-right).
    public let rotationRad: Double

    // MARK: Provenance

    /// How this object was placed.
    /// One of: "scan" | "manual" | "inferred"
    ///   scan     — derived from RoomPlan / LiDAR geometry
    ///   manual   — engineer gesture-placed on floor plan or photo
    ///   inferred — automatically suggested by the system
    public let source: String

    /// Which install layer this object belongs to.
    /// One of: "existing" | "proposed"
    public let layer: String

    /// Optional UUID of the room this object is sited in.
    public let roomID: String?

    // MARK: Init

    public init(
        id: String,
        type: String,
        label: String,
        position: InstallPathPointV1,
        widthM: Double? = nil,
        depthM: Double? = nil,
        rotationRad: Double = 0,
        source: String,
        layer: String,
        roomID: String? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.position = position
        self.widthM = widthM
        self.depthM = depthM
        self.rotationRad = rotationRad
        self.source = source
        self.layer = layer
        self.roomID = roomID
    }
}

// MARK: - InstallRouteModelV1

/// A drawn pipe or gas route captured by the engineer.
///
/// Routes are defined as ordered sequences of `InstallPathPointV1` waypoints
/// on a floor-plan or wall-photo canvas.  The engine uses route geometry to
/// compute total run lengths, routing complexity, number of bends, visibility
/// (surface-mounted vs concealed), and material quantities.
public struct InstallRouteModelV1: Codable, Sendable, Identifiable {

    // MARK: Identity

    /// UUID for this route record.
    public let id: String

    // MARK: Classification

    /// Pipe circuit kind.
    /// One of: "flow" | "return" | "gas" | "cold_water" | "hot_water" |
    ///         "condensate" | "flue" | "electrical" | "other"
    public let kind: String

    /// Nominal pipe diameter in millimetres.
    /// Common values: 15, 22, 28, 35, 42 (UK copper pipe sizes).
    /// 0 when unknown.
    public let diameterMm: Double

    // MARK: Geometry

    /// Ordered waypoints defining the route path on the canvas.
    public let path: [InstallPathPointV1]

    // MARK: Install characteristics

    /// How the pipe is mounted.
    /// One of: "surface" | "boxed" | "underfloor" | "in_wall" | "unknown"
    public let mounting: String

    /// Confidence level for the route geometry.
    /// One of: "measured" | "drawn" | "estimated"
    ///   measured  — spatially anchored from scan or reference markers
    ///   drawn     — engineer-drawn on canvas; scale from room dimensions
    ///   estimated — system-inferred; low spatial confidence
    public let confidence: String

    // MARK: Layer + context

    /// Which install layer this route belongs to.
    /// One of: "existing" | "proposed"
    public let layer: String

    /// Optional UUID of the room this route primarily traverses.
    public let roomID: String?

    /// Optional free-text engineer note about this route.
    public let notes: String?

    // MARK: Init

    public init(
        id: String,
        kind: String,
        diameterMm: Double,
        path: [InstallPathPointV1],
        mounting: String,
        confidence: String,
        layer: String,
        roomID: String? = nil,
        notes: String? = nil
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
    }
}

// MARK: - InstallAnnotationV1

/// A free-text spatial annotation on the install layer canvas.
public struct InstallAnnotationV1: Codable, Sendable {

    /// UUID for this annotation.
    public let id: String

    /// Normalised anchor position on the canvas.
    public let position: InstallPathPointV1

    /// Annotation text entered by the engineer.
    public let text: String

    public init(id: String, position: InstallPathPointV1, text: String) {
        self.id = id
        self.position = position
        self.text = text
    }
}

// MARK: - InstallLayerModelV1

/// The complete install markup layer for one property or room.
///
/// Separates existing system geometry from proposed installation to enable:
///   • before/after visual comparison in reports
///   • complexity and disruption analysis in the recommendation engine
///   • incremental capture (existing first, proposed on top)
///
/// The engine MUST treat `existing` routes/objects as ground-truth constraints
/// and `proposed` routes/objects as the target installation intent.
public struct InstallLayerModelV1: Codable, Sendable {

    // MARK: Schema

    /// Schema version; must be in `supportedInstallMarkupVersions`.
    public let schemaVersion: String

    // MARK: Objects

    /// Install objects on the existing layer (boilers, radiators currently in place).
    public let existingObjects: [InstallObjectModelV1]

    /// Install objects on the proposed layer (new boiler location, added cylinder, etc.).
    public let proposedObjects: [InstallObjectModelV1]

    // MARK: Routes

    /// Existing pipe/gas routes currently installed at the property.
    public let existingRoutes: [InstallRouteModelV1]

    /// Proposed pipe/gas routes for the new installation.
    public let proposedRoutes: [InstallRouteModelV1]

    // MARK: Annotations

    /// Spatial text annotations added by the engineer.
    public let annotations: [InstallAnnotationV1]

    // MARK: Init

    public init(
        schemaVersion: String = currentInstallMarkupVersion,
        existingObjects: [InstallObjectModelV1] = [],
        proposedObjects: [InstallObjectModelV1] = [],
        existingRoutes: [InstallRouteModelV1] = [],
        proposedRoutes: [InstallRouteModelV1] = [],
        annotations: [InstallAnnotationV1] = []
    ) {
        self.schemaVersion = schemaVersion
        self.existingObjects = existingObjects
        self.proposedObjects = proposedObjects
        self.existingRoutes = existingRoutes
        self.proposedRoutes = proposedRoutes
        self.annotations = annotations
    }

    /// Returns `true` when the layer carries no objects, routes, or annotations.
    public var isEmpty: Bool {
        existingObjects.isEmpty
        && proposedObjects.isEmpty
        && existingRoutes.isEmpty
        && proposedRoutes.isEmpty
        && annotations.isEmpty
    }
}
