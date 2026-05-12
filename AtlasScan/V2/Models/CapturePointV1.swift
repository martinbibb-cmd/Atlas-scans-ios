/// CapturePointV1 — A logical "moment" in the continuous survey where the
/// engineer paused to capture evidence (a photo, a tag, a note, a measurement,
/// or any combination).
///
/// Photos, pins, notes and measurements all carry a `capturePointId` so that
/// review can group them ("at this moment in the kitchen, the engineer took
/// 2 photos, tagged the boiler, and recorded a note"). This keeps related
/// evidence linked even when the underlying spatial anchor is uncertain.

import Foundation

public struct CapturePointV1: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let visitId: UUID
    public let workspaceId: String?
    /// The room the user was in when this capture point was created.
    /// `nil` means "no room confirmed yet" — pre-confirmation captures can
    /// still be linked once a room is confirmed.
    public var roomId: UUID?
    /// When this capture moment occurred.
    public let createdAt: Date
    /// Optional engineer-supplied caption for the whole moment.
    public var caption: String?

    public init(
        id: UUID = UUID(),
        visitId: UUID,
        workspaceId: String? = nil,
        roomId: UUID? = nil,
        createdAt: Date = Date(),
        caption: String? = nil
    ) {
        self.id = id
        self.visitId = visitId
        self.workspaceId = workspaceId
        self.roomId = roomId
        self.createdAt = createdAt
        self.caption = caption
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case id, visitId, workspaceId, roomId, createdAt, caption
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        visitId = try c.decode(UUID.self, forKey: .visitId)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        roomId = try c.decodeIfPresent(UUID.self, forKey: .roomId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
    }
}
