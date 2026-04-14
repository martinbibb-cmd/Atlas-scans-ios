import Foundation
import AtlasContracts

// MARK: - RoomScanEvidence
//
// Local (offline-first) representation of an indoor room-scan evidence record.
// Mirrors AtlasContracts.SpatialEvidence3D for the canonical handoff payload.
//
// Design rules:
//   • Evidence only — no maths derived from the asset file.
//   • AtlasRoomV1 / heat-loss engine must NOT consume the asset.
//   • Heavy file (USDZ / GLB) lives at localFileURL; only metadata is Codable.
//   • linkedRoomIDs wires the evidence to ScannedRoom(s) for display.

/// An indoor room-scan evidence record produced by a RoomPlan session.
///
/// Stored locally in `PropertyScanSession.roomScanEvidence` and projected to
/// `SpatialEvidence3D` on Atlas Mind handoff.
struct RoomScanEvidence: Identifiable, Codable, Equatable {

    // MARK: Identity

    var id: UUID

    /// UUID of the originating `PropertyScanSession`.
    var propertySessionID: UUID

    /// Stable identifier for the RoomPlan / AR capture session that produced this asset.
    var captureSessionID: UUID

    // MARK: Asset file references

    /// Local filesystem URL for the 3-D model file (USDZ / GLB).
    /// Stored as a bookmark-resolvable relative path string to survive app restarts.
    var localFileURLString: String?

    /// Asset format: `.usdz` | `.glb` | `.realitykit`.
    var assetFormat: AssetFormat

    /// Local filesystem URL for the preview thumbnail image.
    var previewImageURLString: String?

    // MARK: Linkage

    /// IDs of `ScannedRoom` instances this evidence is linked to.
    var linkedRoomIDs: [UUID]

    // MARK: Spatial bounds (from RoomPlan geometry)

    /// Approximate bounding dimensions of the captured room in metres.
    var bounds: Bounds?

    // MARK: Capture metadata

    /// Device and timestamp provenance captured at scan time.
    var captureMeta: CaptureMeta?

    // MARK: Init

    init(
        id: UUID = UUID(),
        propertySessionID: UUID,
        captureSessionID: UUID,
        localFileURLString: String? = nil,
        assetFormat: AssetFormat = .usdz,
        previewImageURLString: String? = nil,
        linkedRoomIDs: [UUID] = [],
        bounds: Bounds? = nil,
        captureMeta: CaptureMeta? = nil
    ) {
        self.id = id
        self.propertySessionID = propertySessionID
        self.captureSessionID = captureSessionID
        self.localFileURLString = localFileURLString
        self.assetFormat = assetFormat
        self.previewImageURLString = previewImageURLString
        self.linkedRoomIDs = linkedRoomIDs
        self.bounds = bounds
        self.captureMeta = captureMeta
    }
}

// MARK: - RoomScanEvidence.AssetFormat

extension RoomScanEvidence {

    /// The 3-D file format of the captured room asset.
    enum AssetFormat: String, Codable, CaseIterable {
        case usdz       = "usdz"
        case glb        = "glb"
        case realitykit = "realitykit"
    }
}

// MARK: - RoomScanEvidence.Bounds

extension RoomScanEvidence {

    /// Axis-aligned bounding dimensions of the captured room in metres.
    struct Bounds: Codable, Equatable {
        var width: Double
        var length: Double
        var height: Double
    }
}

// MARK: - RoomScanEvidence.CaptureMeta

extension RoomScanEvidence {

    /// Device and timestamp provenance recorded at capture time.
    struct CaptureMeta: Codable, Equatable {
        var device: String
        var timestamp: Date
        var confidence: Double?
    }
}

// MARK: - AtlasContracts projection

extension RoomScanEvidence {

    /// Projects this local record to a `SpatialEvidence3D` for Atlas handoff.
    ///
    /// Converts local UUIDs to strings and encodes the local file URL as a
    /// `file://` URL string.  The receiving side (Atlas web) should treat
    /// `fileUrl` as an opaque reference until the file has been uploaded.
    func toSpatialEvidence3D() -> SpatialEvidence3D {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let contractBounds = bounds.map { b in
            SpatialEvidence3D.Bounds(width: b.width, length: b.length, height: b.height)
        }

        let contractMeta = captureMeta.map { m in
            SpatialEvidence3D.CaptureMeta(
                device: m.device,
                timestamp: iso.string(from: m.timestamp),
                confidence: m.confidence
            )
        }

        return SpatialEvidence3D(
            id: id.uuidString,
            propertyID: propertySessionID.uuidString,
            sourceSessionId: captureSessionID.uuidString,
            format: assetFormat.rawValue,
            fileUrl: localFileURLString ?? "",
            previewImageUrl: previewImageURLString,
            linkedRoomIds: linkedRoomIDs.map(\.uuidString),
            bounds: contractBounds,
            captureMeta: contractMeta
        )
    }
}
