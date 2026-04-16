import Foundation
import AtlasContracts
#if canImport(UIKit)
import UIKit
#endif

// MARK: - VisitSessionMapper

/// Maps a `PropertyScanSession` to the canonical `AtlasPropertyV1` handoff payload.
///
/// Rules:
///   - UI-only state must NOT leak into the exported payload.
///   - Raw audio files are excluded; transcript text is included.
///   - All types are sourced from `AtlasContracts` — no local mirrors.
///   - The mapper is pure (no side effects) and testable without a running app.
enum VisitSessionMapper {

    // MARK: Top-level mapping

    /// Converts `session` into an `AtlasPropertyV1` handoff payload.
    static func toAtlasPropertyV1(_ session: PropertyScanSession) -> AtlasPropertyV1 {
        let iso = iso8601Formatter()
        let now = iso.string(from: Date())

        return AtlasPropertyV1(
            schemaVersion: currentAtlasPropertyVersion,
            propertyID: session.id.uuidString,
            jobReference: session.jobReference,
            propertyAddress: session.propertyAddress,
            engineerName: session.engineerName,
            atlasJobID: session.atlasJobID,
            capturedAt: iso.string(from: session.createdAt),
            handoffAt: now,
            scanState: session.scanState.rawValue,
            reviewState: session.reviewState.rawValue,
            rooms: session.rooms.map { mapRoom($0, session: session) },
            adjacencies: session.roomAdjacencies.map(mapAdjacency),
            sessionObjects: session.taggedObjects.map { mapObject($0, roomID: nil) },
            evidenceSummary: AtlasEvidenceSummaryV1(
                totalPhotos: session.totalPhotos,
                totalVoiceNotes: session.totalVoiceNotes,
                sessionPhotoCount: session.photos.count,
                sessionVoiceNoteCount: session.voiceNotes.count
            ),
            sessionKnowledge: mapSessionKnowledge(session),
            spatialEvidence3d: mapSpatialEvidence(session),
            externalClearanceScenes: mapClearanceScenes(session),
            installLayer: session.toInstallLayerModelV1()
        )
    }

    // MARK: - Room mapping

    private static func mapRoom(
        _ room: ScannedRoom,
        session: PropertyScanSession
    ) -> AtlasPropertyRoomV1 {
        let photoCount = room.photos.count
        let voiceNoteCount = room.voiceNotes.count

        return AtlasPropertyRoomV1(
            id: room.id.uuidString,
            name: room.name,
            floorIndex: room.floor,
            geometryCaptured: room.geometryCaptured,
            areaM2: room.areaSquareMetres,
            heightM: room.ceilingHeightMetres,
            isReviewed: room.isReviewed,
            objects: room.taggedObjects.map { mapObject($0, roomID: room.id) },
            photoCount: photoCount,
            voiceNoteCount: voiceNoteCount
        )
    }

    // MARK: - Object mapping

    private static func mapObject(_ obj: TaggedObject, roomID: UUID?) -> AtlasPropertyObjectV1 {
        AtlasPropertyObjectV1(
            id: obj.id.uuidString,
            category: obj.category.rawValue,
            label: obj.displayLabel,
            roomID: roomID?.uuidString,
            placementMode: obj.placementMode.rawValue,
            confidence: obj.confidence.rawValue,
            photoCount: obj.linkedPhotoIDs.count,
            voiceNoteCount: obj.linkedVoiceNoteIDs.count,
            quickFields: obj.quickFieldValues,
            worldAnchor: mapWorldAnchor(obj.worldAnchor)
        )
    }

    private static func mapWorldAnchor(_ anchor: WorldAnchor3D?) -> AtlasWorldAnchorV1? {
        guard let a = anchor else { return nil }
        return AtlasWorldAnchorV1(
            x: a.x,
            y: a.y,
            z: a.z,
            screenX: a.screenX,
            screenY: a.screenY,
            anchorConfidence: a.anchorConfidence.rawValue
        )
    }

    // MARK: - Adjacency mapping

    private static func mapAdjacency(_ adj: RoomAdjacency) -> AtlasPropertyAdjacencyV1 {
        AtlasPropertyAdjacencyV1(
            id: adj.id.uuidString,
            fromRoomID: adj.fromRoomID.uuidString,
            toRoomID: adj.toRoomID.uuidString,
            kind: adj.kind.rawValue,
            isConfirmed: adj.isConfirmed,
            openingID: adj.openingID?.uuidString,
            notes: adj.notes
        )
    }

    // MARK: - Session knowledge mapping

    private static func mapSessionKnowledge(_ session: PropertyScanSession) -> AtlasSessionKnowledgeV1? {
        // Only include medium/high-confidence facts as specified by the contract.
        let qualifyingFacts = session.extractedFacts.filter { $0.confidence >= .medium }
        guard !qualifyingFacts.isEmpty else { return nil }
        let iso = iso8601Formatter()
        return AtlasSessionKnowledgeV1(
            extractedFacts: qualifyingFacts.map { fact in
                AtlasExtractedFactV1(
                    id: fact.id.uuidString,
                    category: fact.category.rawValue,
                    value: fact.value,
                    confidence: fact.confidence.rawValue,
                    sourceNoteID: fact.sourceNoteID?.uuidString,
                    roomID: fact.roomID?.uuidString,
                    objectID: fact.objectID?.uuidString,
                    createdAt: iso.string(from: fact.createdAt)
                )
            }
        )
    }

    // MARK: - Spatial evidence mapping

    private static func mapSpatialEvidence(_ session: PropertyScanSession) -> [SpatialEvidence3D]? {
        guard !session.roomScanEvidence.isEmpty else { return nil }
        return session.roomScanEvidence.map { $0.toSpatialEvidence3D() }
    }

    // MARK: - Clearance scene mapping

    private static func mapClearanceScenes(_ session: PropertyScanSession) -> [ExternalClearanceSceneV1]? {
        guard !session.externalClearanceScenes.isEmpty else { return nil }
        return session.externalClearanceScenes.map { $0.toExternalClearanceSceneV1() }
    }

    // MARK: - ISO-8601 formatter

    private static func iso8601Formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
}

// MARK: - VisitSessionMapper + encode / validate

extension VisitSessionMapper {

    /// Encodes the mapped `AtlasPropertyV1` to JSON data.
    static func encode(_ property: AtlasPropertyV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(property)
    }
}
