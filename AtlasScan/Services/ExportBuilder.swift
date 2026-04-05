import Foundation
import AtlasContracts
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ExportBuilder
//
// Converts a ScanJob into a shared-contract ScanBundleV1 payload and validates it.
// Follows the pattern: local app models → export mapper → AtlasContracts bundle.
// Does not contain any recommendation or business logic — export only.

final class ExportBuilder {

    // MARK: - Geometry fallback constants

    /// Default wall length in metres, used when no geometry has been captured.
    /// 3 m is a representative minimum room dimension for typical UK residential rooms.
    private static let defaultWallLengthM: Double = 3.0

    /// Default floor area in m², used when no geometry has been captured.
    /// 20 m² is a representative small-room size (e.g. a single bedroom).
    private static let defaultRoomAreaM2: Double = 20.0

    /// Half-width of the bounding box assigned to a tagged service object, in metres.
    /// Produces a 50 cm × 50 cm footprint, representative of a typical wall-mounted
    /// or floor-standing service object (boiler, radiator, cylinder, etc.).
    private static let serviceObjectHalfBoxM: Double = 0.25

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: App-level validation

    /// Returns a list of ValidationIssues for the given job.
    /// A non-empty list with blocking issues means the job should not be exported.
    func validate(job: ScanJob) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if job.propertyAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(
                severity: .blocking,
                message: "Property address is required before export."
            ))
        }

        if job.rooms.isEmpty {
            issues.append(ValidationIssue(
                severity: .blocking,
                message: "At least one room must be added before export."
            ))
        }

        for room in job.rooms {
            if room.name.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Room has no name.",
                    roomID: room.id
                ))
            }

            if !room.isReviewed {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Room '\(room.name)' has not been marked as reviewed.",
                    roomID: room.id
                ))
            }

            if room.taggedObjects.isEmpty {
                issues.append(ValidationIssue(
                    severity: .info,
                    message: "Room '\(room.name)' has no tagged service objects.",
                    roomID: room.id
                ))
            }
        }

        return issues
    }

    // MARK: Build shared-contract bundle

    /// Maps a ScanJob into a shared-contract ScanBundleV1.
    ///
    /// Translation: local app models → export mapper → AtlasContracts bundle.
    func buildBundle(from job: ScanJob) -> ScanBundleV1 {
        ScanBundleV1(
            version: currentScanBundleVersion,
            bundleId: UUID().uuidString,
            rooms: job.rooms.map { contractRoom(from: $0) },
            anchors: [],
            qaFlags: buildQAFlags(from: job),
            meta: contractMeta(from: job)
        )
    }

    /// Encodes a ScanBundleV1 to pretty-printed JSON data.
    func encode(bundle: ScanBundleV1) throws -> Data {
        try encoder.encode(bundle)
    }

    // MARK: Contract-level validation

    /// Validates encoded bundle JSON against the shared AtlasContracts schema.
    ///
    /// Call after `encode(bundle:)` to confirm the output is spec-compliant
    /// before sharing or saving.
    func validateBundle(data: Data) -> ScanValidationResult {
        AtlasContracts.validateScanBundle(data)
    }

    // MARK: - Private mapping

    private func contractMeta(from job: ScanJob) -> ScanMeta {
        var notes: [String] = []
        if !job.propertyAddress.isEmpty {
            notes.append("address: \(job.propertyAddress)")
        }
        if !job.engineerName.isEmpty {
            notes.append("engineer: \(job.engineerName)")
        }
        if !job.jobReference.isEmpty {
            notes.append("ref: \(job.jobReference)")
        }

        return ScanMeta(
            capturedAt: iso8601.string(from: job.createdAt),
            deviceModel: currentDeviceModel(),
            scannerApp: "AtlasScan 1.0",
            coordinateConvention: "metric_m",
            propertyRef: job.atlasJobID,
            operatorNotes: notes.isEmpty ? nil : notes.joined(separator: "; ")
        )
    }

    private func buildQAFlags(from job: ScanJob) -> [ScanQAFlag] {
        var flags: [ScanQAFlag] = []

        for room in job.rooms {
            for object in room.taggedObjects {
                guard !object.quickFieldValues.isEmpty else { continue }
                // Encode service-object quick fields as a QA info flag so the
                // Atlas importer can extract engineering-specific metadata that
                // has no first-class slot in ScanDetectedObject.
                if let payload = encodeQuickFields(object.quickFieldValues) {
                    flags.append(ScanQAFlag(
                        code: "atlas.service_fields",
                        message: payload,
                        severity: "info",
                        entityId: object.id.uuidString
                    ))
                }
            }
        }

        return flags
    }

    private func contractRoom(from room: ScannedRoom) -> ScanRoom {
        let wallCoords = computeWallCoordinates(room.walls)

        let walls = room.walls.enumerated().map { idx, wall in
            contractWall(
                from: wall,
                coords: wallCoords[idx],
                openings: room.openings.filter { $0.wallIndex == wall.index }
            )
        }

        let polygon = wallCoords.map { ScanPoint2D(x: $0.start.x, y: $0.start.y) }

        return ScanRoom(
            id: room.id.uuidString,
            label: room.name,
            floorIndex: room.floor,
            polygon: polygon,
            areaM2: room.areaSquareMetres ?? 0.0,
            heightM: room.ceilingHeightMetres ?? 0.0,
            walls: walls,
            detectedObjects: room.taggedObjects.map { contractObject(from: $0, room: room) },
            confidence: room.geometryCaptured ? .medium : .low
        )
    }

    private func contractWall(
        from wall: ScannedWall,
        coords: WallCoords,
        openings: [ScannedOpening]
    ) -> ScanWall {
        ScanWall(
            id: wall.id.uuidString,
            start: coords.start,
            end: coords.end,
            heightM: wall.heightMetres ?? 0.0,
            thicknessMm: 0.0,
            kind: wall.isExternalWall ? "external" : "internal",
            openings: openings.map { contractOpening(from: $0, wall: wall) },
            confidence: .medium
        )
    }

    private func contractOpening(from opening: ScannedOpening, wall: ScannedWall) -> ScanOpening {
        let wallLength = wall.lengthMetres ?? defaultWallLengthM
        // Offset is placed at the wall midpoint as a placeholder; once real
        // RoomPlan geometry is integrated in the next PR, the actual measured
        // offset from the wall's start point will be used here.
        return ScanOpening(
            id: opening.id.uuidString,
            widthM: opening.widthMetres ?? 0.9,
            heightM: opening.heightMetres ?? 2.1,
            offsetM: wallLength / 2.0,
            type: openingType(from: opening.kind),
            confidence: .medium
        )
    }

    private func contractObject(from object: TaggedObject, room: ScannedRoom) -> ScanDetectedObject {
        // Square-room approximation: compute a side length from the area so we
        // can map normalised 0…1 positions to metric coordinates. Non-square
        // rooms will have some positional error here, but accuracy improves once
        // real RoomPlan geometry is integrated in the next PR.
        let side = sqrt(room.areaSquareMetres ?? defaultRoomAreaM2)
        let cx = (object.normalizedPosition?.x ?? 0.5) * side
        let cy = (object.normalizedPosition?.y ?? 0.5) * side
        let halfBoxSize = serviceObjectHalfBoxM

        return ScanDetectedObject(
            id: object.id.uuidString,
            category: object.category.rawValue,
            label: object.displayLabel,
            boundingBox: ScanDetectedObject.BoundingBox(
                minX: cx - halfBoxSize, minY: cy - halfBoxSize,
                maxX: cx + halfBoxSize, maxY: cy + halfBoxSize,
                minZ: 0.0, maxZ: halfBoxSize * 2
            ),
            confidence: contractConfidence(from: object.confidence)
        )
    }

    // MARK: - Helpers

    private typealias WallCoords = (start: ScanPoint3D, end: ScanPoint3D)

    /// Computes approximate start/end 3-D coordinates for each wall by placing
    /// them head-to-tail from the origin using the wall's bearing as direction.
    /// Both start and end z-coordinates are 0 (floor level); wall height is
    /// carried separately in `ScanWall.heightM`.
    private func computeWallCoordinates(_ walls: [ScannedWall]) -> [WallCoords] {
        var result: [WallCoords] = []
        var x = 0.0, y = 0.0

        for wall in walls {
            let length = wall.lengthMetres ?? defaultWallLengthM
            let bearing = (wall.bearingDegrees ?? 0.0) * .pi / 180.0
            let dx = length * sin(bearing)
            let dy = length * cos(bearing)
            result.append((
                start: ScanPoint3D(x: x, y: y, z: 0.0),
                end: ScanPoint3D(x: x + dx, y: y + dy, z: 0.0)
            ))
            x += dx
            y += dy
        }

        return result
    }

    private func openingType(from kind: OpeningKind) -> String {
        switch kind {
        case .door:   return "door"
        case .window: return "window"
        default:      return "unknown"
        }
    }

    private func contractConfidence(from level: ConfidenceLevel) -> ScanConfidenceBand {
        switch level {
        case .high:    return .high
        case .medium:  return .medium
        case .low, .unknown: return .low
        }
    }

    private func encodeQuickFields(_ fields: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    private func currentDeviceModel() -> String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "unknown"
        #endif
    }
}

