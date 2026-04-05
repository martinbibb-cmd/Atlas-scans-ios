import Foundation

// MARK: - ScanBundleV1
//
// Contract shape for the Atlas Scan export bundle.
// Must remain in sync with atlas-contracts / ScanBundleV1.
// This file defines the encodable contract types only — no business logic.

// MARK: Root bundle

struct ScanBundleV1: Codable {
    let schemaVersion: String                   // e.g. "1.0.0"
    let bundleID: String                        // UUID string
    let exportedAt: String                      // ISO-8601
    let job: ContractScanJob
    let rooms: [ContractRoom]
}

// MARK: Job

struct ContractScanJob: Codable {
    let id: String
    let jobReference: String
    let propertyAddress: String
    let engineerName: String
    let atlasJobID: String?
    let status: String
    let createdAt: String
    let updatedAt: String
}

// MARK: Room

struct ContractRoom: Codable {
    let id: String
    let jobID: String
    let name: String
    let floor: Int
    let areaSquareMetres: Double?
    let ceilingHeightMetres: Double?
    let geometryCaptured: Bool
    let isReviewed: Bool
    let notes: String
    let walls: [ContractWall]
    let openings: [ContractOpening]
    let taggedObjects: [ContractTaggedObject]
    let photos: [ContractPhoto]
}

// MARK: Wall

struct ContractWall: Codable {
    let id: String
    let index: Int
    let lengthMetres: Double?
    let heightMetres: Double?
    let isExternalWall: Bool
    let hasWindow: Bool
    let hasDoor: Bool
    let bearingDegrees: Double?
}

// MARK: Opening

struct ContractOpening: Codable {
    let id: String
    let kind: String
    let wallIndex: Int
    let widthMetres: Double?
    let heightMetres: Double?
    let connectsToRoomID: String?
}

// MARK: Tagged object

struct ContractTaggedObject: Codable {
    let id: String
    let roomID: String
    let category: String
    let label: String
    let normalizedX: Double?
    let normalizedY: Double?
    let wallIndex: Int?
    let quickFieldValues: [String: String]
    let notes: String
    let isConfirmed: Bool
    let confidence: String
    let createdAt: String
    let updatedAt: String
}

// MARK: Photo

struct ContractPhoto: Codable {
    let id: String
    let roomID: String
    let taggedObjectID: String?
    let filename: String
    let caption: String
    let isKeyEvidence: Bool
    let capturedAt: String
}

// MARK: - BundleSchemaVersion

enum BundleSchemaVersion {
    static let current = "1.0.0"
}
