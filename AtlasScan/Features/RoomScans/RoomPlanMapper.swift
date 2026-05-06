import Foundation

// MARK: - RoomPlanScanResult
//
// A plain-struct representation of a completed RoomPlan capture.
//
// Intentionally decoupled from the RoomPlan framework types so the mapper
// can be unit-tested on any simulator without LiDAR hardware.

struct RoomPlanScanResult {

    /// Approximate room width in metres (bounding box, x-axis).
    var widthM: Double?

    /// Approximate room depth in metres (bounding box, z-axis).
    var depthM: Double?

    /// Approximate ceiling height in metres.
    var heightM: Double?

    /// Normalised floor plan outline (0…1 coordinate space, rectangular).
    var outlinePoints: [NormalisedPoint]

    /// Objects detected by RoomPlan inside the room.
    var detectedObjects: [RoomPlanDetectedObject]

    /// Raw RoomPlan metadata serialised to JSON. Nil when unavailable.
    var rawJSON: String?

    /// Relative path to the exported USDZ scan asset, when saved during capture.
    ///
    /// Format: `captures/<visitId>/<scanId>.usdz` — resolved against the app's
    /// Application Support directory.  Nil when the capture was manual or when
    /// the USDZ export failed.
    var rawScanAssetRef: String?

    /// Per-segment wall lengths in metres, in polygon vertex order.
    ///
    /// Populated during LiDAR capture by the Anti-Square geometry engine.
    /// Each entry corresponds to the wall segment between `outlinePoints[i]`
    /// and `outlinePoints[(i+1) % outlinePoints.count]`.
    /// Nil for manually entered scans or when polygon extraction fails.
    var wallSegmentLengthsM: [Double]?

    init(
        widthM: Double? = nil,
        depthM: Double? = nil,
        heightM: Double? = nil,
        outlinePoints: [NormalisedPoint] = [],
        detectedObjects: [RoomPlanDetectedObject] = [],
        rawJSON: String? = nil,
        rawScanAssetRef: String? = nil,
        wallSegmentLengthsM: [Double]? = nil
    ) {
        self.widthM = widthM
        self.depthM = depthM
        self.heightM = heightM
        self.outlinePoints = outlinePoints
        self.detectedObjects = detectedObjects
        self.rawJSON = rawJSON
        self.rawScanAssetRef = rawScanAssetRef
        self.wallSegmentLengthsM = wallSegmentLengthsM
    }
}

// MARK: - RoomPlanDetectedObject

/// An object detected by RoomPlan, with normalised position on the floor plan.
struct RoomPlanDetectedObject {
    var category: RoomPlanObjectCategory
    var label: String
    /// Normalised x position on the floor plan (0…1).
    var normalisedPositionX: Double
    /// Normalised y position on the floor plan (0…1).
    var normalisedPositionY: Double
}

// MARK: - RoomPlanObjectCategory
//
// Maps Apple's CapturedRoom.Object.Category to our own vocabulary.
// Kept separate from CapturedRoom types so this file compiles on any device.

enum RoomPlanObjectCategory: String, CaseIterable {
    case bathtub      = "bathtub"
    case bed          = "bed"
    case chair        = "chair"
    case dishwasher   = "dishwasher"
    case fireplace    = "fireplace"
    case oven         = "oven"
    case refrigerator = "refrigerator"
    case sink         = "sink"
    case sofa         = "sofa"
    case stairs       = "stairs"
    case stove        = "stove"
    case television   = "television"
    case toilet       = "toilet"
    case washerDryer  = "washer_dryer"
    case storage      = "storage"
    case table        = "table"
    case unknown      = "unknown"

    /// Maps this detected object category to the closest `ObjectPinType`.
    /// Heating-relevant objects are mapped first; everything else becomes `.genericNote`.
    var objectPinType: ObjectPinType {
        switch self {
        case .stove, .oven: return .boiler
        case .sink:         return .stopTap
        default:            return .genericNote
        }
    }

    /// Human-readable label for this category.
    var displayLabel: String {
        switch self {
        case .bathtub:     return "Bathtub"
        case .bed:         return "Bed"
        case .chair:       return "Chair"
        case .dishwasher:  return "Dishwasher"
        case .fireplace:   return "Fireplace"
        case .oven:        return "Oven"
        case .refrigerator: return "Refrigerator"
        case .sink:        return "Sink"
        case .sofa:        return "Sofa"
        case .stairs:      return "Stairs"
        case .stove:       return "Stove / Boiler"
        case .television:  return "Television"
        case .toilet:      return "Toilet"
        case .washerDryer: return "Washer / Dryer"
        case .storage:     return "Storage"
        case .table:       return "Table"
        case .unknown:     return "Detected Object"
        }
    }
}

// MARK: - RoomPlanMapper
//
// Pure (side-effect-free) mapper from RoomPlanScanResult to the app's
// draft capture model.
//
// Rules:
//   • Always produces a valid CapturedRoomScanDraft — even from empty results.
//   • LiDAR-inferred object pins are marked .inferred and .lidar.
//   • Does NOT overwrite existing manual pins in the session store.
//   • Does NOT write to disk or network — the caller must persist the results.

enum RoomPlanMapper {

    // MARK: - Map scan result

    /// Converts a `RoomPlanScanResult` into a `CapturedRoomScanDraft` and a list
    /// of LiDAR-inferred `CapturedObjectPinDraft` values.
    ///
    /// - Parameters:
    ///   - result:    The completed RoomPlan scan result.
    ///   - roomIndex: 1-based room index used to generate the default label.
    /// - Returns: A tuple of the room scan draft and any LiDAR-inferred object pins.
    static func map(
        _ result: RoomPlanScanResult,
        roomIndex: Int
    ) -> (scan: CapturedRoomScanDraft, pins: [CapturedObjectPinDraft]) {

        var scan = CapturedRoomScanDraft()
        scan.roomLabel            = "Room \(roomIndex)"
        scan.rawWidthM            = result.widthM
        scan.rawDepthM            = result.depthM
        scan.rawHeightM           = result.heightM
        scan.rawScanAssetRef      = result.rawScanAssetRef
        scan.wallSegmentLengthsM  = result.wallSegmentLengthsM
        scan.confidence           = .high
        scan.captureSource        = .lidar
        scan.lidarMetadata        = result.rawJSON
        scan.reviewStatus         = .pending   // LiDAR scans require engineer review

        if !result.outlinePoints.isEmpty {
            var plan = FloorPlanDraft()
            plan.outlinePoints = result.outlinePoints
            scan.floorPlan = plan
        }

        let pins = result.detectedObjects.map { obj -> CapturedObjectPinDraft in
            var pin = CapturedObjectPinDraft(type: obj.category.objectPinType)
            pin.label                 = obj.label
            pin.roomId                = scan.id
            pin.approximatePositionX  = obj.normalisedPositionX
            pin.approximatePositionY  = obj.normalisedPositionY
            pin.pinSource             = .lidar
            pin.pinConfidence         = .inferred
            pin.reviewStatus          = .pending  // LiDAR-inferred pins require review
            return pin
        }

        return (scan, pins)
    }

    // MARK: - Auto floor plan snapshot

    /// Creates a `CapturedFloorPlanSnapshotDraft` with an auto-generated image
    /// reference filename for the given LiDAR room scan.
    ///
    /// The image is expected to be rendered and saved by the UI layer (e.g.
    /// `FloorPlanEditorView.saveSnapshot()`). This method only produces the
    /// draft metadata record.
    static func autoSnapshot(for scan: CapturedRoomScanDraft) -> CapturedFloorPlanSnapshotDraft {
        var snapshot = CapturedFloorPlanSnapshotDraft(imageRef: "lidar_\(scan.id.uuidString).png")
        snapshot.roomId = scan.id
        return snapshot
    }
}
