import Foundation

// MARK: - ExportBuilder
//
// Converts a ScanJob into a ScanBundleV1 contract payload and validates it.
// Does not contain any recommendation or business logic — export only.

final class ExportBuilder {

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

    // MARK: Validate

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

    // MARK: Build bundle

    /// Builds a ScanBundleV1 from the given ScanJob.
    func buildBundle(from job: ScanJob) -> ScanBundleV1 {
        ScanBundleV1(
            schemaVersion: BundleSchemaVersion.current,
            bundleID: UUID().uuidString,
            exportedAt: iso8601.string(from: Date()),
            job: contractJob(from: job),
            rooms: job.rooms.map { contractRoom(from: $0) }
        )
    }

    /// Encodes a ScanBundleV1 to pretty-printed JSON data.
    func encode(bundle: ScanBundleV1) throws -> Data {
        try encoder.encode(bundle)
    }

    // MARK: - Private mapping

    private func contractJob(from job: ScanJob) -> ContractScanJob {
        ContractScanJob(
            id: job.id.uuidString,
            jobReference: job.jobReference,
            propertyAddress: job.propertyAddress,
            engineerName: job.engineerName,
            atlasJobID: job.atlasJobID,
            status: job.status.rawValue,
            createdAt: iso8601.string(from: job.createdAt),
            updatedAt: iso8601.string(from: job.updatedAt)
        )
    }

    private func contractRoom(from room: ScannedRoom) -> ContractRoom {
        ContractRoom(
            id: room.id.uuidString,
            jobID: room.jobID.uuidString,
            name: room.name,
            floor: room.floor,
            areaSquareMetres: room.areaSquareMetres,
            ceilingHeightMetres: room.ceilingHeightMetres,
            geometryCaptured: room.geometryCaptured,
            isReviewed: room.isReviewed,
            notes: room.notes,
            walls: room.walls.map { contractWall(from: $0) },
            openings: room.openings.map { contractOpening(from: $0) },
            taggedObjects: room.taggedObjects.map { contractObject(from: $0) },
            photos: room.photos.map { contractPhoto(from: $0) }
        )
    }

    private func contractWall(from wall: ScannedWall) -> ContractWall {
        ContractWall(
            id: wall.id.uuidString,
            index: wall.index,
            lengthMetres: wall.lengthMetres,
            heightMetres: wall.heightMetres,
            isExternalWall: wall.isExternalWall,
            hasWindow: wall.hasWindow,
            hasDoor: wall.hasDoor,
            bearingDegrees: wall.bearingDegrees
        )
    }

    private func contractOpening(from opening: ScannedOpening) -> ContractOpening {
        ContractOpening(
            id: opening.id.uuidString,
            kind: opening.kind.rawValue,
            wallIndex: opening.wallIndex,
            widthMetres: opening.widthMetres,
            heightMetres: opening.heightMetres,
            connectsToRoomID: opening.connectsToRoomID?.uuidString
        )
    }

    private func contractObject(from object: TaggedObject) -> ContractTaggedObject {
        ContractTaggedObject(
            id: object.id.uuidString,
            roomID: object.roomID.uuidString,
            category: object.category.rawValue,
            label: object.displayLabel,
            normalizedX: object.normalizedPosition?.x,
            normalizedY: object.normalizedPosition?.y,
            wallIndex: object.wallIndex,
            quickFieldValues: object.quickFieldValues,
            notes: object.notes,
            isConfirmed: object.isConfirmed,
            confidence: object.confidence.rawValue,
            createdAt: iso8601.string(from: object.createdAt),
            updatedAt: iso8601.string(from: object.updatedAt)
        )
    }

    private func contractPhoto(from photo: TaggedPhoto) -> ContractPhoto {
        ContractPhoto(
            id: photo.id.uuidString,
            roomID: photo.roomID.uuidString,
            taggedObjectID: photo.taggedObjectID?.uuidString,
            filename: photo.filename,
            caption: photo.caption,
            isKeyEvidence: photo.isKeyEvidence,
            capturedAt: iso8601.string(from: photo.capturedAt)
        )
    }
}
