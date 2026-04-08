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

    /// Voice notes recorded in this room.
    var voiceNotes: [VoiceNote]

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
        voiceNotes: [VoiceNote] = [],
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
        self.voiceNotes = voiceNotes
        self.notes = notes
        self.isReviewed = isReviewed
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Decodable — backward-compatible with earlier room files

    private enum CodingKeys: String, CodingKey {
        case id, jobID, name, floor
        case areaSquareMetres, ceilingHeightMetres
        case walls, openings, geometryCaptured
        case taggedObjects, photos, voiceNotes, notes, isReviewed
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(UUID.self,    forKey: .id)
        jobID                = try c.decode(UUID.self,    forKey: .jobID)
        name                 = try c.decode(String.self,  forKey: .name)
        floor                = try c.decodeIfPresent(Int.self, forKey: .floor) ?? 0
        areaSquareMetres     = try c.decodeIfPresent(Double.self, forKey: .areaSquareMetres)
        ceilingHeightMetres  = try c.decodeIfPresent(Double.self, forKey: .ceilingHeightMetres)
        walls                = try c.decodeIfPresent([ScannedWall].self,    forKey: .walls)    ?? []
        openings             = try c.decodeIfPresent([ScannedOpening].self, forKey: .openings) ?? []
        geometryCaptured     = try c.decodeIfPresent(Bool.self,             forKey: .geometryCaptured) ?? false
        taggedObjects        = try c.decodeIfPresent([TaggedObject].self,   forKey: .taggedObjects) ?? []
        photos               = try c.decodeIfPresent([TaggedPhoto].self,    forKey: .photos)   ?? []
        voiceNotes           = try c.decodeIfPresent([VoiceNote].self,      forKey: .voiceNotes) ?? []
        notes                = try c.decodeIfPresent(String.self,           forKey: .notes)    ?? ""
        isReviewed           = try c.decodeIfPresent(Bool.self,             forKey: .isReviewed) ?? false
        createdAt            = try c.decode(Date.self,  forKey: .createdAt)
        updatedAt            = try c.decode(Date.self,  forKey: .updatedAt)
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
        // Cascade: remove any photos linked to the deleted object.
        photos.removeAll { $0.taggedObjectID == id }
        touch()
    }

    mutating func updateTaggedObject(_ updated: TaggedObject) {
        guard let index = taggedObjects.firstIndex(where: { $0.id == updated.id }) else { return }
        taggedObjects[index] = updated
        touch()
    }

    // MARK: Photo helpers

    mutating func addPhoto(_ photo: TaggedPhoto) {
        photos.append(photo)
        touch()
    }

    mutating func removePhoto(id: UUID) {
        photos.removeAll { $0.id == id }
        touch()
    }

    /// Remove all photos linked to a specific tagged object.
    mutating func removePhotos(forObjectID objectID: UUID) {
        photos.removeAll { $0.taggedObjectID == objectID }
        touch()
    }

    // MARK: Voice note helpers

    mutating func addVoiceNote(_ note: VoiceNote) {
        voiceNotes.append(note)
        touch()
    }

    mutating func removeVoiceNote(id: UUID) {
        voiceNotes.removeAll { $0.id == id }
        touch()
    }

    mutating func updateVoiceNote(_ updated: VoiceNote) {
        guard let index = voiceNotes.firstIndex(where: { $0.id == updated.id }) else { return }
        voiceNotes[index] = updated
        touch()
    }
}
