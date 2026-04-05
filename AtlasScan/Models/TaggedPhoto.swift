import Foundation

// MARK: - TaggedPhoto

/// A photo taken as evidence for a service object or general room context.
struct TaggedPhoto: Identifiable, Codable {

    var id: UUID = UUID()

    /// Owning room identifier
    var roomID: UUID

    /// Optional associated tagged object
    var taggedObjectID: UUID?

    /// Filename stored in local app documents directory
    var filename: String

    /// Free-form caption
    var caption: String

    /// Whether this photo is marked as a key evidence item
    var isKeyEvidence: Bool

    var capturedAt: Date

    init(
        id: UUID = UUID(),
        roomID: UUID,
        taggedObjectID: UUID? = nil,
        filename: String,
        caption: String = "",
        isKeyEvidence: Bool = false
    ) {
        self.id = id
        self.roomID = roomID
        self.taggedObjectID = taggedObjectID
        self.filename = filename
        self.caption = caption
        self.isKeyEvidence = isKeyEvidence
        self.capturedAt = Date()
    }
}
