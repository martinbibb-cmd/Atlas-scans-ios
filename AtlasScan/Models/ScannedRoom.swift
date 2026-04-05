import Foundation

// MARK: - ScannedRoom

/// Represents a single room captured during a scan session.
/// Layer 1 (geometry) + Layer 2 (service tags) + Layer 3 (evidence).
struct ScannedRoom: Identifiable, Codable {

    var id: UUID = UUID()

    /// Owning scan job
    var jobID: UUID

    var name: String

    var floor: Int

    // MARK: Geometry (Layer 1)

    /// Approximate floor area in square metres
    var areaSquareMetres: Double?

    /// Approximate ceiling height in metres
    var ceilingHeightMetres: Double?

    var walls: [ScannedWall]

    var openings: [ScannedOpening]

    /// Whether geometry was captured by scanner (true) or manually sketched (false)
    var geometryCaptured: Bool

    // MARK: Service Tags (Layer 2)

    var taggedObjects: [TaggedObject]

    // MARK: Evidence (Layer 3)

    var photos: [TaggedPhoto]

    var notes: String

    /// Whether the engineer has signed off this room as complete
    var isReviewed: Bool

    var createdAt: Date
    var updatedAt: Date

    // MARK: Init

    init(
        id: UUID = UUID(),
        jobID: UUID,
        name: String,
        floor: Int = 0,
        areaSquareMetres: Double? = nil,
        ceilingHeightMetres: Double? = nil,
        walls: [ScannedWall] = [],
        openings: [ScannedOpening] = [],
        geometryCaptured: Bool = false,
        taggedObjects: [TaggedObject] = [],
        photos: [TaggedPhoto] = [],
        notes: String = "",
        isReviewed: Bool = false
    ) {
        self.id = id
        self.jobID = jobID
        self.name = name
        self.floor = floor
        self.areaSquareMetres = areaSquareMetres
        self.ceilingHeightMetres = ceilingHeightMetres
        self.walls = walls
        self.openings = openings
        self.geometryCaptured = geometryCaptured
        self.taggedObjects = taggedObjects
        self.photos = photos
        self.notes = notes
        self.isReviewed = isReviewed
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Helpers

    var displayFloor: String {
        switch floor {
        case 0: return "Ground Floor"
        case 1: return "First Floor"
        case 2: return "Second Floor"
        case -1: return "Basement"
        default: return "Floor \(floor)"
        }
    }

    mutating func touch() {
        updatedAt = Date()
    }

    mutating func addTaggedObject(_ object: TaggedObject) {
        taggedObjects.append(object)
        touch()
    }

    mutating func removeTaggedObject(id: UUID) {
        taggedObjects.removeAll { $0.id == id }
        touch()
    }

    mutating func updateTaggedObject(_ updated: TaggedObject) {
        guard let index = taggedObjects.firstIndex(where: { $0.id == updated.id }) else { return }
        taggedObjects[index] = updated
        touch()
    }
}
