/// SessionCaptureV2 — Root data envelope for an Atlas Scan V2 session.

import Foundation

public struct SessionCaptureV2: Codable, Identifiable, Sendable {
    public let id: UUID
    public let version: String
    public let visitId: UUID
    public var visitReference: String?
    public var visitLabel: String?
    public let capturedAt: Date
    public var propertyAddress: String?
    public var rooms: [RoomCaptureV2]
    public var transcripts: [ProcessedTranscriptV1]
    public var photos: [PhotoEvidenceV1]
    public var voiceNotes: [VoiceNoteV1]
    public var qaFlags: [QAFlagV1]

    public init(
        visitId: UUID = UUID(),
        visitReference: String? = nil,
        visitLabel: String? = nil,
        capturedAt: Date = Date(),
        propertyAddress: String? = nil
    ) {
        self.id = UUID()
        self.version = "2.0"
        self.visitId = visitId
        self.visitReference = visitReference
        self.visitLabel = visitLabel
        self.capturedAt = capturedAt
        self.propertyAddress = propertyAddress
        self.rooms = []
        self.transcripts = []
        self.photos = []
        self.voiceNotes = []
        self.qaFlags = []
    }
}

public extension SessionCaptureV2 {
    mutating func addRoom(_ room: RoomCaptureV2) {
        rooms.append(room)
    }

    mutating func emitQAFlag(_ flag: QAFlagV1) {
        guard !qaFlags.contains(where: {
            $0.type == flag.type && $0.roomId == flag.roomId
        }) else { return }
        qaFlags.append(flag)
    }
}
