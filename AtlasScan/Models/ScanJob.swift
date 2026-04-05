import Foundation

// MARK: - ScanJob

/// Top-level container for a scan session at a single property.
struct ScanJob: Identifiable, Codable {

    var id: UUID = UUID()

    // MARK: Job identity

    var jobReference: String

    var propertyAddress: String

    var engineerName: String

    /// Optional link to an Atlas job / recommendation ID
    var atlasJobID: String?

    // MARK: Rooms (Layer 1 + 2 + 3)

    var rooms: [ScannedRoom]

    // MARK: Status

    var status: ScanJobStatus

    // MARK: Export state (Layer 4)

    var exportDraftState: ExportDraftState?

    // MARK: Timestamps

    var createdAt: Date
    var updatedAt: Date

    // MARK: Init

    init(
        id: UUID = UUID(),
        jobReference: String = "",
        propertyAddress: String,
        engineerName: String = "",
        atlasJobID: String? = nil,
        rooms: [ScannedRoom] = [],
        status: ScanJobStatus = .draft
    ) {
        self.id = id
        if jobReference.isEmpty {
            let stamp = Int(Date().timeIntervalSince1970)
            self.jobReference = "JOB-\(stamp)"
        } else {
            self.jobReference = jobReference
        }
        self.propertyAddress = propertyAddress
        self.engineerName = engineerName
        self.atlasJobID = atlasJobID
        self.rooms = rooms
        self.status = status
        self.exportDraftState = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Helpers

    var totalTaggedObjects: Int {
        rooms.reduce(0) { $0 + $1.taggedObjects.count }
    }

    var totalReviewedRooms: Int {
        rooms.filter(\.isReviewed).count
    }

    var isReadyToExport: Bool {
        !rooms.isEmpty && rooms.allSatisfy(\.isReviewed)
    }

    mutating func touch() {
        updatedAt = Date()
    }

    mutating func addRoom(_ room: ScannedRoom) {
        rooms.append(room)
        touch()
    }

    mutating func removeRoom(id: UUID) {
        rooms.removeAll { $0.id == id }
        touch()
    }

    mutating func updateRoom(_ updated: ScannedRoom) {
        guard let index = rooms.firstIndex(where: { $0.id == updated.id }) else { return }
        rooms[index] = updated
        touch()
    }
}

// MARK: - ScanJobStatus

enum ScanJobStatus: String, Codable, CaseIterable {
    case draft      = "draft"
    case inProgress = "in_progress"
    case reviewing  = "reviewing"
    case exported   = "exported"

    var displayName: String {
        switch self {
        case .draft:        return "Draft"
        case .inProgress:   return "In Progress"
        case .reviewing:    return "Reviewing"
        case .exported:     return "Exported"
        }
    }

    var symbolName: String {
        switch self {
        case .draft:        return "doc"
        case .inProgress:   return "camera.viewfinder"
        case .reviewing:    return "checkmark.circle"
        case .exported:     return "arrow.up.doc"
        }
    }
}
