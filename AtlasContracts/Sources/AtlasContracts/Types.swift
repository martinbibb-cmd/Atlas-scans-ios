import Foundation

// MARK: - Coordinate convention

/// Coordinate convention used in the scan bundle.
/// 'metric_m' — SI metres, right-handed, Y-up (default for RoomPlan-style output).
public typealias ScanCoordinateConvention = String

// MARK: - Confidence

/// Banded confidence rating for a scanned entity.
///
/// - high:   good coverage, measurement uncertainty < 5 cm
/// - medium: partial coverage or occlusion, uncertainty 5–20 cm
/// - low:    estimated / inferred, uncertainty > 20 cm
public enum ScanConfidenceBand: String, Codable, Sendable, CaseIterable {
    case high
    case medium
    case low
}

// MARK: - QA Flag

/// A QA flag attached to a scanned entity or to the whole bundle.
public struct ScanQAFlag: Codable, Sendable {
    /// Machine-readable flag code.
    public let code: String
    /// Human-readable description.
    public let message: String
    /// Severity level: 'info' | 'warning' | 'error'.
    public let severity: String
    /// Optional reference to the affected entity within the bundle.
    public let entityId: String?

    public init(code: String, message: String, severity: String, entityId: String? = nil) {
        self.code = code
        self.message = message
        self.severity = severity
        self.entityId = entityId
    }
}

// MARK: - Geometry primitives

/// A 2-D point in scan coordinate space (horizontal plane, metres).
public struct ScanPoint2D: Codable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A 3-D point in scan coordinate space (x/y horizontal, z vertical, metres).
public struct ScanPoint3D: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: - Opening

/// An opening detected on a wall by the scanner (door, window, or unknown).
public struct ScanOpening: Codable, Sendable {
    public let id: String
    /// Opening width in metres.
    public let widthM: Double
    /// Opening height in metres (0 if not captured).
    public let heightM: Double
    /// Distance from the wall's start point to the opening centre, in metres.
    public let offsetM: Double
    /// Opening type: 'door' | 'window' | 'unknown'.
    public let type: String
    public let confidence: ScanConfidenceBand

    public init(
        id: String,
        widthM: Double,
        heightM: Double,
        offsetM: Double,
        type: String,
        confidence: ScanConfidenceBand
    ) {
        self.id = id
        self.widthM = widthM
        self.heightM = heightM
        self.offsetM = offsetM
        self.type = type
        self.confidence = confidence
    }
}

// MARK: - Wall

/// A wall segment detected by the scanner.
public struct ScanWall: Codable, Sendable {
    public let id: String
    /// Wall start point in scan coordinate space.
    public let start: ScanPoint3D
    /// Wall end point in scan coordinate space.
    public let end: ScanPoint3D
    /// Wall height (ceiling-to-floor) in metres; 0 if not captured.
    public let heightM: Double
    /// Estimated wall thickness in millimetres; 0 if unknown.
    public let thicknessMm: Double
    /// Wall kind: 'internal' | 'external' | 'unknown'.
    public let kind: String
    /// Openings (doors / windows) on this wall.
    public let openings: [ScanOpening]
    public let confidence: ScanConfidenceBand

    public init(
        id: String,
        start: ScanPoint3D,
        end: ScanPoint3D,
        heightM: Double,
        thicknessMm: Double,
        kind: String,
        openings: [ScanOpening],
        confidence: ScanConfidenceBand
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.heightM = heightM
        self.thicknessMm = thicknessMm
        self.kind = kind
        self.openings = openings
        self.confidence = confidence
    }
}

// MARK: - Detected object

/// An object detected in the room — used for both scanner-detected and
/// manually-tagged service objects.
public struct ScanDetectedObject: Codable, Sendable {

    /// Axis-aligned bounding box in scan coordinate space.
    public struct BoundingBox: Codable, Sendable {
        public let minX: Double
        public let minY: Double
        public let maxX: Double
        public let maxY: Double
        public let minZ: Double
        public let maxZ: Double

        public init(
            minX: Double, minY: Double,
            maxX: Double, maxY: Double,
            minZ: Double, maxZ: Double
        ) {
            self.minX = minX; self.minY = minY
            self.maxX = maxX; self.maxY = maxY
            self.minZ = minZ; self.maxZ = maxZ
        }
    }

    public let id: String
    /// Broad object class (e.g. 'boiler', 'radiator', 'furniture').
    public let category: String
    /// Best-guess label for the object.
    public let label: String
    public let boundingBox: BoundingBox
    public let confidence: ScanConfidenceBand

    public init(
        id: String,
        category: String,
        label: String,
        boundingBox: BoundingBox,
        confidence: ScanConfidenceBand
    ) {
        self.id = id
        self.category = category
        self.label = label
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

// MARK: - Anchor

/// A georeferencing anchor linking scan coordinate space to the real world.
public struct ScanAnchor: Codable, Sendable {
    public let id: String
    /// Anchor type: 'gps' | 'qr_code' | 'manual' | 'unknown'.
    public let type: String
    public let position: ScanPoint3D
    public let realWorldRef: String?
    public let confidence: ScanConfidenceBand

    public init(
        id: String,
        type: String,
        position: ScanPoint3D,
        realWorldRef: String? = nil,
        confidence: ScanConfidenceBand
    ) {
        self.id = id
        self.type = type
        self.position = position
        self.realWorldRef = realWorldRef
        self.confidence = confidence
    }
}

// MARK: - Room

/// A room captured during a scan session.
public struct ScanRoom: Codable, Sendable {
    public let id: String
    /// Scanner's suggested room label (free text; may be empty).
    public let label: String
    /// Storey index: 0 = ground floor, 1 = first floor, -1 = basement.
    public let floorIndex: Int
    /// Floor polygon boundary in scan coordinate space (metric_m).
    public let polygon: [ScanPoint2D]
    /// Calculated floor area in m².
    public let areaM2: Double
    /// Ceiling height in metres.
    public let heightM: Double
    public let walls: [ScanWall]
    /// All objects detected or manually tagged inside this room.
    public let detectedObjects: [ScanDetectedObject]
    public let confidence: ScanConfidenceBand

    public init(
        id: String,
        label: String,
        floorIndex: Int,
        polygon: [ScanPoint2D],
        areaM2: Double,
        heightM: Double,
        walls: [ScanWall],
        detectedObjects: [ScanDetectedObject],
        confidence: ScanConfidenceBand
    ) {
        self.id = id
        self.label = label
        self.floorIndex = floorIndex
        self.polygon = polygon
        self.areaM2 = areaM2
        self.heightM = heightM
        self.walls = walls
        self.detectedObjects = detectedObjects
        self.confidence = confidence
    }
}

// MARK: - Scan metadata

/// Metadata about the scan session that produced this bundle.
public struct ScanMeta: Codable, Sendable {
    /// ISO-8601 timestamp of when the scan was taken.
    public let capturedAt: String
    /// Scanner hardware identifier (e.g. 'iPhone 15 Pro').
    public let deviceModel: String
    /// App name and version (e.g. 'AtlasScan 1.0').
    public let scannerApp: String
    /// Coordinate system used in this bundle (always 'metric_m').
    public let coordinateConvention: String
    /// Optional Atlas property / visit ID this scan is for.
    public let propertyRef: String?
    /// Free-text notes from the operator (may include job details).
    public let operatorNotes: String?

    public init(
        capturedAt: String,
        deviceModel: String,
        scannerApp: String,
        coordinateConvention: String,
        propertyRef: String? = nil,
        operatorNotes: String? = nil
    ) {
        self.capturedAt = capturedAt
        self.deviceModel = deviceModel
        self.scannerApp = scannerApp
        self.coordinateConvention = coordinateConvention
        self.propertyRef = propertyRef
        self.operatorNotes = operatorNotes
    }
}

// MARK: - Top-level bundle

/// ScanBundleV1 — the top-level unit of data sent from a native scan client.
///
/// - version:  contract version string; must be in supportedScanBundleVersions.
/// - bundleId: unique identifier for this bundle (generated by the scan client).
/// - rooms:    list of captured rooms.
/// - anchors:  optional georeferencing anchors.
/// - qaFlags:  QA flags raised by the scan client during capture.
/// - meta:     capture-session metadata.
public struct ScanBundleV1: Codable, Sendable {
    public let version: String
    public let bundleId: String
    public let rooms: [ScanRoom]
    public let anchors: [ScanAnchor]
    public let qaFlags: [ScanQAFlag]
    public let meta: ScanMeta

    public init(
        version: String,
        bundleId: String,
        rooms: [ScanRoom],
        anchors: [ScanAnchor],
        qaFlags: [ScanQAFlag],
        meta: ScanMeta
    ) {
        self.version = version
        self.bundleId = bundleId
        self.rooms = rooms
        self.anchors = anchors
        self.qaFlags = qaFlags
        self.meta = meta
    }
}
