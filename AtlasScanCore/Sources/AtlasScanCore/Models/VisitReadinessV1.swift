/// VisitReadinessV1 — 7-flag logic gate.

import Foundation

public struct VisitReadinessV1: Codable, Sendable {
    public var hasRooms: Bool
    public var hasPhotos: Bool
    public var hasBoilerDetails: Bool
    public var hasFlueDetails: Bool
    public var hasClearanceCheck: Bool
    public var hasTranscripts: Bool
    public var hasPropertyAddress: Bool

    public var isReady: Bool {
        hasRooms && hasPhotos && hasBoilerDetails && hasFlueDetails
            && hasClearanceCheck && hasTranscripts && hasPropertyAddress
    }

    public init(
        hasRooms: Bool = false,
        hasPhotos: Bool = false,
        hasBoilerDetails: Bool = false,
        hasFlueDetails: Bool = false,
        hasClearanceCheck: Bool = false,
        hasTranscripts: Bool = false,
        hasPropertyAddress: Bool = false
    ) {
        self.hasRooms = hasRooms
        self.hasPhotos = hasPhotos
        self.hasBoilerDetails = hasBoilerDetails
        self.hasFlueDetails = hasFlueDetails
        self.hasClearanceCheck = hasClearanceCheck
        self.hasTranscripts = hasTranscripts
        self.hasPropertyAddress = hasPropertyAddress
    }

    public static func derive(from session: SessionCaptureV2) -> VisitReadinessV1 {
        let hasBoiler = session.rooms.contains { room in
            room.pinnedObjects.contains { $0.objectType == .boiler || $0.objectType == .heatPump }
        }
        let hasFlue = session.rooms.contains { room in
            room.pinnedObjects.contains { $0.objectType == .flueTerminal }
        }
        let hasClearance = session.qaFlags.contains {
            $0.type == .clearancePass || $0.type == .clearanceConflict
        }
        return VisitReadinessV1(
            hasRooms: !session.rooms.isEmpty,
            hasPhotos: !session.photos.isEmpty,
            hasBoilerDetails: hasBoiler,
            hasFlueDetails: hasFlue,
            hasClearanceCheck: hasClearance,
            hasTranscripts: !session.transcripts.isEmpty,
            hasPropertyAddress: !(session.propertyAddress?.isEmpty ?? true)
        )
    }

    public var unmetConditions: [String] {
        var missing: [String] = []
        if !hasRooms            { missing.append("At least one room must be captured") }
        if !hasPhotos           { missing.append("At least one photo must be attached") }
        if !hasBoilerDetails    { missing.append("Boiler or heat-pump must be pinned") }
        if !hasFlueDetails      { missing.append("Flue terminal must be captured") }
        if !hasClearanceCheck   { missing.append("Clearance check must be completed") }
        if !hasTranscripts      { missing.append("At least one voice note must be recorded") }
        if !hasPropertyAddress  { missing.append("Property address must be entered") }
        return missing
    }
}
