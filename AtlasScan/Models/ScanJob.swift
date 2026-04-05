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

    // MARK: Multi-room structure

    /// Engineer-defined connections between rooms (doors, archways, etc.).
    /// Empty in jobs created before multi-room linking was available.
    var roomAdjacencies: [RoomAdjacency]

    /// Optional layout overrides for the property plan canvas.
    /// Positions are computed automatically from room index when no override exists.
    var roomPlacements: [RoomPlacementOverride]

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
        roomAdjacencies: [RoomAdjacency] = [],
        roomPlacements: [RoomPlacementOverride] = [],
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
        self.roomAdjacencies = roomAdjacencies
        self.roomPlacements = roomPlacements
        self.status = status
        self.exportDraftState = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Decodable — backward-compatible with pre-multi-room job files

    private enum CodingKeys: String, CodingKey {
        case id, jobReference, propertyAddress, engineerName, atlasJobID
        case rooms, roomAdjacencies, roomPlacements
        case status, exportDraftState, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,                  forKey: .id)
        jobReference     = try c.decode(String.self,                forKey: .jobReference)
        propertyAddress  = try c.decode(String.self,                forKey: .propertyAddress)
        engineerName     = try c.decode(String.self,                forKey: .engineerName)
        atlasJobID       = try c.decodeIfPresent(String.self,       forKey: .atlasJobID)
        rooms            = try c.decode([ScannedRoom].self,         forKey: .rooms)
        // New fields — default to empty arrays for jobs saved before multi-room linking was added.
        roomAdjacencies  = try c.decodeIfPresent([RoomAdjacency].self,         forKey: .roomAdjacencies) ?? []
        roomPlacements   = try c.decodeIfPresent([RoomPlacementOverride].self, forKey: .roomPlacements)  ?? []
        status           = try c.decode(ScanJobStatus.self,         forKey: .status)
        exportDraftState = try c.decodeIfPresent(ExportDraftState.self, forKey: .exportDraftState)
        createdAt        = try c.decode(Date.self,                  forKey: .createdAt)
        updatedAt        = try c.decode(Date.self,                  forKey: .updatedAt)
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
        // Remove adjacencies and placement overrides that reference the deleted room.
        roomAdjacencies.removeAll { $0.fromRoomID == id || $0.toRoomID == id }
        roomPlacements.removeAll { $0.id == id }
        touch()
    }

    mutating func updateRoom(_ updated: ScannedRoom) {
        guard let index = rooms.firstIndex(where: { $0.id == updated.id }) else { return }
        rooms[index] = updated
        touch()
    }

    // MARK: Adjacency helpers

    mutating func addAdjacency(_ adjacency: RoomAdjacency) {
        roomAdjacencies.append(adjacency)
        touch()
    }

    mutating func removeAdjacency(id: UUID) {
        roomAdjacencies.removeAll { $0.id == id }
        touch()
    }

    mutating func updateAdjacency(_ updated: RoomAdjacency) {
        guard let index = roomAdjacencies.firstIndex(where: { $0.id == updated.id }) else { return }
        roomAdjacencies[index] = updated
        touch()
    }

    /// Returns all adjacencies that involve the given room (as either end).
    func adjacencies(for roomID: UUID) -> [RoomAdjacency] {
        roomAdjacencies.filter { $0.fromRoomID == roomID || $0.toRoomID == roomID }
    }

    // MARK: Room placement helpers

    mutating func setRoomPlacement(_ placement: RoomPlacementOverride) {
        if let index = roomPlacements.firstIndex(where: { $0.id == placement.id }) {
            roomPlacements[index] = placement
        } else {
            roomPlacements.append(placement)
        }
        touch()
    }

    func roomPlacement(for roomID: UUID) -> RoomPlacementOverride? {
        roomPlacements.first { $0.id == roomID }
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
