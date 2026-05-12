import Foundation

// MARK: - ScanToMindHandoffV1
//
// URL-based handoff payload from Atlas Scan to Atlas Mind.
//
// Produced by ScanToMindHandoffBuilder and carried to Mind via a
// percent-encoded JSON query parameter on the /receive-scan route:
//
//   https://next.atlas-phm.uk/receive-scan?payload=<percent-encoded JSON>
//
// Canonical shape (v1):
//   {
//     "kind": "scan-to-mind-handoff",
//     "schemaVersion": 1,
//     "exportedAt": "...",
//     "sourceApp": "scan_ios",
//     "targetApp": "mind_pwa",
//     "reason": "complete_capture" | "save_progress" | "review_in_mind" | "quote_planner",
//     "visit": { "version": "1.0", "visitId": "...", ... },
//     "capture": { ... }
//   }
//
// Design rules:
//   • Embeds the full SessionCaptureV2 so Mind can preload the visit.
//   • visit carries lifecycle state and readiness at the moment of handoff.
//   • reason clarifies why the handoff was initiated.
//   • sourceApp and targetApp are fixed string identifiers, not the
//     HandoffSourceApp enum, to keep this type self-contained.
//   • schemaVersion is a numeric Int (1), not a string.
//   • kind must be "scan-to-mind-handoff" for consumer-side validation.

// MARK: - ScanToMindHandoffV1

/// URL-based handoff envelope from Atlas Scan (iOS) to Atlas Mind (PWA).
///
/// Carried as a percent-encoded JSON query parameter on Mind's
/// `/receive-scan` route.  Atlas Mind reads this payload to preload
/// the visit and display the appropriate capture summary.
public enum HandoffCompletionStatusV1: String, Codable, Sendable {
    case complete
    case incompleteDraft = "incomplete_draft"
}

public struct ScanToMindHandoffV1: Codable, Sendable {

    // MARK: Schema identity

    /// Discriminator; always `"scan-to-mind-handoff"`.
    ///
    /// Mind uses this to route the payload to the correct handler.
    public let kind: String

    /// Numeric schema version; always `1` for this generation.
    ///
    /// Intentionally an `Int` (not `String`) so consumers can use `>=` guards.
    public let schemaVersion: Int

    // MARK: Routing

    /// Identifier of the producing app; always `"scan_ios"`.
    public let sourceApp: String

    /// Identifier of the consuming app; always `"mind_pwa"`.
    public let targetApp: String

    // MARK: Timestamp

    /// ISO-8601 timestamp of when this handoff was generated.
    public let exportedAt: String

    // MARK: Handoff reason

    /// Why this handoff was initiated.
    public let reason: ScanToMindHandoffReasonV1

    // MARK: Visit snapshot

    /// Lifecycle and readiness state of the visit at the moment of handoff.
    public let visit: HandoffVisitSnapshotV1

    // MARK: Capture payload

    /// Full capture data for this visit.
    public let capture: SessionCaptureV2

    /// Human-readable readiness gaps that still need review.
    public let missingEvidence: [String]

    /// Whether the handoff is fully complete or still requires review.
    public let completionStatus: HandoffCompletionStatusV1

    /// Structured room → capture-point evidence graph for Mind rendering.
    public let spatialEvidenceGraph: SpatialEvidenceGraphV1

    /// Engineer-visible unresolved evidence items that require review.
    public let unresolvedEvidence: [UnresolvedSpatialEvidenceV1]

    /// Equipment evidence groups derived from the capture's object pins.
    ///
    /// Groups the session's pins by function (heat source, hot water storage,
    /// flue/external, emitters, heating components) and applies identity and
    /// anchor-confidence classification rules.
    ///
    /// Atlas Mind consumes this to display structured equipment evidence cards
    /// instead of a flat generic object-pin list.
    public let equipmentEvidenceGroups: EquipmentEvidenceGroupsV1

    // MARK: Init

    public init(
        visit: HandoffVisitSnapshotV1,
        capture: SessionCaptureV2,
        reason: ScanToMindHandoffReasonV1,
        exportedAt: String,
        missingEvidence: [String]? = nil,
        completionStatus: HandoffCompletionStatusV1? = nil,
        spatialEvidenceGraph: SpatialEvidenceGraphV1? = nil,
        unresolvedEvidence: [UnresolvedSpatialEvidenceV1]? = nil,
        equipmentEvidenceGroups: EquipmentEvidenceGroupsV1? = nil
    ) {
        let evidenceGraph = spatialEvidenceGraph
            ?? SpatialEvidenceGraphV1.fromCapture(capture, visitId: visit.visitId)
        self.kind = "scan-to-mind-handoff"
        self.schemaVersion = 1
        self.sourceApp = "scan_ios"
        self.targetApp = "mind_pwa"
        self.exportedAt = exportedAt
        self.reason = reason
        self.visit = visit
        self.capture = capture
        self.missingEvidence = missingEvidence ?? visit.readiness.missingItems
        self.completionStatus = completionStatus ?? (visit.readiness.isReady ? .complete : .incompleteDraft)
        self.spatialEvidenceGraph = evidenceGraph
        self.unresolvedEvidence = unresolvedEvidence ?? evidenceGraph.defaultUnresolvedEvidence()
        self.equipmentEvidenceGroups = equipmentEvidenceGroups
            ?? EquipmentEvidenceMapper.buildGroups(from: capture.objectPins, visitId: visit.visitId)
    }

    // MARK: - Custom Codable

    private enum CodingKeys: String, CodingKey {
        case kind, schemaVersion, sourceApp, targetApp
        case exportedAt, reason, visit, capture
        case missingEvidence, completionStatus
        case spatialEvidenceGraph, unresolvedEvidence
        case equipmentEvidenceGroups
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        sourceApp = try c.decode(String.self, forKey: .sourceApp)
        targetApp = try c.decode(String.self, forKey: .targetApp)
        exportedAt = try c.decode(String.self, forKey: .exportedAt)
        reason = try c.decode(ScanToMindHandoffReasonV1.self, forKey: .reason)
        visit = try c.decode(HandoffVisitSnapshotV1.self, forKey: .visit)
        capture = try c.decode(SessionCaptureV2.self, forKey: .capture)
        missingEvidence = try c.decodeIfPresent([String].self, forKey: .missingEvidence)
            ?? visit.readiness.missingItems
        completionStatus = try c.decodeIfPresent(HandoffCompletionStatusV1.self, forKey: .completionStatus)
            ?? (visit.readiness.isReady ? .complete : .incompleteDraft)
        spatialEvidenceGraph = try c.decode(SpatialEvidenceGraphV1.self, forKey: .spatialEvidenceGraph)
        unresolvedEvidence = try c.decode([UnresolvedSpatialEvidenceV1].self, forKey: .unresolvedEvidence)
        // Backward-compat: derive from capture.objectPins when absent in older payloads.
        equipmentEvidenceGroups = try c.decodeIfPresent(EquipmentEvidenceGroupsV1.self, forKey: .equipmentEvidenceGroups)
            ?? EquipmentEvidenceMapper.buildGroups(from: capture.objectPins, visitId: visit.visitId)
    }
}

// MARK: - SpatialEvidenceGraphV1

public struct SpatialEvidenceGraphV1: Codable, Sendable {
    public let visitId: String
    public let rooms: [SpatialEvidenceRoomV1]

    public init(visitId: String, rooms: [SpatialEvidenceRoomV1]) {
        self.visitId = visitId
        self.rooms = rooms
    }
}

public struct SpatialEvidenceRoomV1: Codable, Sendable {
    public let roomId: String
    public let roomName: String
    public let geometryStatus: String
    public let floorAreaM2: Double?
    public let ceilingHeightM: Double?
    public let capturePoints: [SpatialEvidencePointV1]
    public let roomWarnings: [String]

    public init(
        roomId: String,
        roomName: String,
        geometryStatus: String,
        floorAreaM2: Double? = nil,
        ceilingHeightM: Double? = nil,
        capturePoints: [SpatialEvidencePointV1],
        roomWarnings: [String] = []
    ) {
        self.roomId = roomId
        self.roomName = roomName
        self.geometryStatus = geometryStatus
        self.floorAreaM2 = floorAreaM2
        self.ceilingHeightM = ceilingHeightM
        self.capturePoints = capturePoints
        self.roomWarnings = roomWarnings
    }
}

public struct SpatialEvidencePointV1: Codable, Sendable {
    public let capturePointId: String
    public let anchorConfidence: String
    public let surfaceSemantic: String?
    public let needsReview: Bool
    public let objectPins: [SpatialEvidenceObjectPinV1]
    public let photos: [SpatialEvidencePhotoV1]
    public let voiceNotes: [SpatialEvidenceVoiceNoteV1]
    public let transcripts: [SpatialEvidenceTranscriptV1]
    public let ghostAppliances: [SpatialEvidenceGhostApplianceV1]
    public let measurements: [SpatialEvidenceMeasurementV1]

    public init(
        capturePointId: String,
        anchorConfidence: String,
        surfaceSemantic: String? = nil,
        needsReview: Bool,
        objectPins: [SpatialEvidenceObjectPinV1],
        photos: [SpatialEvidencePhotoV1],
        voiceNotes: [SpatialEvidenceVoiceNoteV1],
        transcripts: [SpatialEvidenceTranscriptV1],
        ghostAppliances: [SpatialEvidenceGhostApplianceV1],
        measurements: [SpatialEvidenceMeasurementV1]
    ) {
        self.capturePointId = capturePointId
        self.anchorConfidence = anchorConfidence
        self.surfaceSemantic = surfaceSemantic
        self.needsReview = needsReview
        self.objectPins = objectPins
        self.photos = photos
        self.voiceNotes = voiceNotes
        self.transcripts = transcripts
        self.ghostAppliances = ghostAppliances
        self.measurements = measurements
    }
}

public struct SpatialEvidenceObjectPinV1: Codable, Sendable {
    public let id: String
    public let type: String
    public let label: String?
    public let anchorConfidence: String?
    public let surfaceSemantic: String?
    public let needsReview: Bool
}

public struct SpatialEvidencePhotoV1: Codable, Sendable {
    public let id: String
    public let localFilename: String
    public let kind: String
    public let linkedObjectId: String?
    public let anchorConfidence: String?
    public let needsReview: Bool
}

public struct SpatialEvidenceVoiceNoteV1: Codable, Sendable {
    public let id: String
    public let transcriptExcerpt: String
    public let linkedObjectId: String?
    public let anchorConfidence: String?
    public let needsReview: Bool
}

public struct SpatialEvidenceTranscriptV1: Codable, Sendable {
    public let id: String
    public let text: String
}

public struct SpatialEvidenceGhostApplianceV1: Codable, Sendable {
    public let id: String
    public let modelId: String
    public let dimensions: [String: Int]
    public let plane: String
    public let surfaceSemantic: String?
    public let needsReview: Bool
}

public struct SpatialEvidenceMeasurementV1: Codable, Sendable {
    public let id: String
    public let distanceMeters: Double
    public let verticalOffsetMeters: Double
    public let needsReview: Bool
}

public struct UnresolvedSpatialEvidenceV1: Codable, Sendable, Hashable {
    public let kind: String
    public let message: String
    public let roomId: String?
    public let capturePointId: String?
    public let evidenceId: String?
}

private extension SpatialEvidenceGraphV1 {
    static let maxTranscriptExcerptLength = 140
    static let unanchoredCapturePointId = "unanchored"
    static let anchorConfidenceScreenOnly = "screen_only"
    static let anchorConfidenceEstimated = "estimated"
    static let warningRoomOutlineIncomplete = "Room outline incomplete"
    static let warningScreenOnlyNeedsReview = "Room-note-only evidence needs review"
    static let warningUnknownSurfaceSemantic = "Unknown surface semantic"

    static func isUnknownSurface(_ semantic: String?) -> Bool {
        semantic == nil || semantic == "unknown"
    }

    static func transcriptExcerpt(_ transcript: String) -> String {
        String(transcript.prefix(maxTranscriptExcerptLength))
    }

    static func fromCapture(_ capture: SessionCaptureV2, visitId: String) -> SpatialEvidenceGraphV1 {
        let rooms = capture.roomScans.map { room -> SpatialEvidenceRoomV1 in
            let roomId = room.id
            let roomPins = capture.objectPins.filter { $0.roomId == roomId }
            let roomPhotos = capture.photos.filter { $0.roomId == roomId }
            let roomVoiceNotes = capture.voiceNotes.filter { $0.roomId == roomId }

            var groupedPins: [String: [CapturedObjectPinV2]] = [:]
            var groupedPhotos: [String: [CapturedPhotoV2]] = [:]
            var groupedVoiceNotes: [String: [CapturedVoiceNoteV2]] = [:]

            for pin in roomPins {
                let key = pin.capturePointId ?? Self.unanchoredCapturePointId
                groupedPins[key] = (groupedPins[key] ?? []) + [pin]
            }
            for photo in roomPhotos {
                let key = photo.capturePointId ?? Self.unanchoredCapturePointId
                groupedPhotos[key] = (groupedPhotos[key] ?? []) + [photo]
            }
            for note in roomVoiceNotes {
                let key = note.capturePointId ?? Self.unanchoredCapturePointId
                groupedVoiceNotes[key] = (groupedVoiceNotes[key] ?? []) + [note]
            }

            let capturePointKeys = Set(groupedPins.keys)
                .union(groupedPhotos.keys)
                .union(groupedVoiceNotes.keys)
                .sorted()

            let points: [SpatialEvidencePointV1] = capturePointKeys.map { key in
                let pins = groupedPins[key] ?? []
                let photos = groupedPhotos[key] ?? []
                let notes = groupedVoiceNotes[key] ?? []

                let pointNeedsReview =
                    pins.contains(where: \.needsReview) ||
                    photos.contains(where: \.needsReview) ||
                    notes.contains(where: \.needsReview)

                let anchorConfidence = pins.compactMap(\.anchorConfidence).first
                    ?? photos.compactMap(\.anchorConfidence).first
                    ?? notes.compactMap(\.anchorConfidence).first
                    ?? (key == Self.unanchoredCapturePointId ? Self.anchorConfidenceScreenOnly : Self.anchorConfidenceEstimated)
                let surfaceSemantic = pins.compactMap(\.surfaceSemantic).first

                return SpatialEvidencePointV1(
                    capturePointId: key,
                    anchorConfidence: anchorConfidence,
                    surfaceSemantic: surfaceSemantic,
                    needsReview: pointNeedsReview,
                    objectPins: pins.map {
                        SpatialEvidenceObjectPinV1(
                            id: $0.id,
                            type: $0.type,
                            label: $0.label,
                            anchorConfidence: $0.anchorConfidence,
                            surfaceSemantic: $0.surfaceSemantic,
                            needsReview: $0.needsReview
                        )
                    },
                    photos: photos.map {
                        SpatialEvidencePhotoV1(
                            id: $0.id,
                            localFilename: $0.localFilename,
                            kind: $0.kind,
                            linkedObjectId: $0.linkedObjectId,
                            anchorConfidence: $0.anchorConfidence,
                            needsReview: $0.needsReview
                        )
                    },
                    voiceNotes: notes.map {
                        SpatialEvidenceVoiceNoteV1(
                            id: $0.id,
                            transcriptExcerpt: Self.transcriptExcerpt($0.transcript),
                            linkedObjectId: $0.linkedObjectId,
                            anchorConfidence: $0.anchorConfidence,
                            needsReview: $0.needsReview
                        )
                    },
                    transcripts: notes.map {
                        SpatialEvidenceTranscriptV1(id: $0.id, text: $0.transcript)
                    },
                    ghostAppliances: [],
                    measurements: []
                )
            }

            var warnings: [String] = []
            if room.rawWidthM == nil || room.rawDepthM == nil || room.rawHeightM == nil {
                warnings.append(Self.warningRoomOutlineIncomplete)
            }
            if points.contains(where: { $0.anchorConfidence == Self.anchorConfidenceScreenOnly }) {
                warnings.append(Self.warningScreenOnlyNeedsReview)
            }
            if points.contains(where: { Self.isUnknownSurface($0.surfaceSemantic) }) {
                warnings.append(Self.warningUnknownSurfaceSemantic)
            }

            let geometryStatus: String
            if room.rawWidthM != nil && room.rawDepthM != nil && room.rawHeightM != nil {
                geometryStatus = "captured"
            } else if room.rawWidthM != nil || room.rawDepthM != nil || room.rawHeightM != nil {
                geometryStatus = "draft"
            } else {
                geometryStatus = "incomplete"
            }

            let floorArea: Double?
            if let width = room.rawWidthM, let depth = room.rawDepthM {
                floorArea = width * depth
            } else {
                floorArea = nil
            }
            return SpatialEvidenceRoomV1(
                roomId: roomId,
                roomName: room.roomLabel ?? "Unlabeled room",
                geometryStatus: geometryStatus,
                floorAreaM2: floorArea,
                ceilingHeightM: room.rawHeightM,
                capturePoints: points,
                roomWarnings: warnings
            )
        }

        return SpatialEvidenceGraphV1(visitId: visitId, rooms: rooms)
    }

    func defaultUnresolvedEvidence() -> [UnresolvedSpatialEvidenceV1] {
        var unresolved: [UnresolvedSpatialEvidenceV1] = []
        for room in rooms {
            if room.roomWarnings.contains(Self.warningRoomOutlineIncomplete) {
                unresolved.append(
                    UnresolvedSpatialEvidenceV1(
                        kind: "incomplete_room_outline",
                        message: Self.warningRoomOutlineIncomplete,
                        roomId: room.roomId,
                        capturePointId: nil,
                        evidenceId: nil
                    )
                )
            }
            if room.roomWarnings.contains(Self.warningUnknownSurfaceSemantic) {
                unresolved.append(
                    UnresolvedSpatialEvidenceV1(
                        kind: "unknown_surface_semantic",
                        message: Self.warningUnknownSurfaceSemantic,
                        roomId: room.roomId,
                        capturePointId: nil,
                        evidenceId: nil
                    )
                )
            }
            for point in room.capturePoints where point.anchorConfidence == Self.anchorConfidenceScreenOnly {
                unresolved.append(
                    UnresolvedSpatialEvidenceV1(
                        kind: "screen_only_point",
                        message: Self.warningScreenOnlyNeedsReview,
                        roomId: room.roomId,
                        capturePointId: point.capturePointId,
                        evidenceId: nil
                    )
                )
            }
            for point in room.capturePoints where point.needsReview {
                unresolved.append(
                    UnresolvedSpatialEvidenceV1(
                        kind: "evidence_needs_review",
                        message: "Evidence needs review",
                        roomId: room.roomId,
                        capturePointId: point.capturePointId,
                        evidenceId: nil
                    )
                )
            }
            for point in room.capturePoints {
                for ghost in point.ghostAppliances where ghost.needsReview {
                    unresolved.append(
                        UnresolvedSpatialEvidenceV1(
                            kind: "ghost_appliance_needs_review",
                            message: "Possible appliance found — needs review",
                            roomId: room.roomId,
                            capturePointId: point.capturePointId,
                            evidenceId: ghost.id
                        )
                    )
                }
                for measurement in point.measurements where measurement.needsReview {
                    unresolved.append(
                        UnresolvedSpatialEvidenceV1(
                            kind: "measurement_needs_review",
                            message: "Measurement needs review",
                            roomId: room.roomId,
                            capturePointId: point.capturePointId,
                            evidenceId: measurement.id
                        )
                    )
                }
            }
        }
        return unresolved
    }
}

// MARK: - HandoffVisitSnapshotV1

/// Lifecycle and readiness snapshot for the visit being handed off.
///
/// Carries the minimum visit context that Mind needs to display
/// the capture summary without re-fetching from the server.
public struct HandoffVisitSnapshotV1: Codable, Sendable {

    // MARK: Schema identity

    /// Visit snapshot version; always `"1.0"`.
    public let version: String

    // MARK: Visit identity

    /// Stable visit UUID.
    public let visitId: String

    /// Engineer-assigned visit/job reference (e.g. "JOB-1712345678").
    public let visitNumber: String?

    /// Optional brand or client identifier.
    public let brandId: String?

    // MARK: Lifecycle state

    /// Visit lifecycle status raw value (e.g. `"complete"`).
    public let status: String

    // MARK: Readiness snapshot

    /// Readiness flags at the moment the handoff was built.
    public let readiness: VisitReadinessV1

    // MARK: Timestamps

    /// ISO-8601 timestamp of when the visit was first created.
    public let createdAt: String

    /// ISO-8601 timestamp of when the visit was last updated.
    public let updatedAt: String

    // MARK: Init

    public init(
        visitId: String,
        visitNumber: String?,
        brandId: String?,
        status: String,
        readiness: VisitReadinessV1,
        createdAt: String,
        updatedAt: String
    ) {
        self.version = "1.0"
        self.visitId = visitId
        self.visitNumber = visitNumber
        self.brandId = brandId
        self.status = status
        self.readiness = readiness
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension ScanToMindHandoffV1 {
    var geometryQAFlags: [ScanQAFlag] {
        let explicitGeometryCodes: Set<String> = [
            "UNSTABLE_GEOMETRY",
            "POLYGON_COLLAPSED",
            "WALL_COUNT_CHANGED_AFTER_CAPTURE",
            "LOW_CONFIDENCE_ROOM_SHAPE",
            "ROOM_SHAPE_NEEDS_REVIEW"
        ]
        let geometryKeywordGroups = [
            ["geometry"],
            ["polygon"],
            ["wall"],
            ["room", "shape"],
            ["room", "outline"],
            ["triangle"],
            ["tiny room"]
        ]

        return capture.qaFlags.filter { flag in
            let searchText = "\(flag.code) \(flag.message)"
            return explicitGeometryCodes.contains(flag.code)
                || geometryKeywordGroups.contains(where: { keywords in
                    keywords.allSatisfy { keyword in
                        searchText.localizedCaseInsensitiveContains(keyword)
                    }
                })
        }
    }

    var requiresReview: Bool {
        completionStatus == .incompleteDraft
            || !missingEvidence.isEmpty
            || !unresolvedEvidence.isEmpty
            || !geometryQAFlags.isEmpty
    }

    var finalOutputsAllowed: Bool {
        !requiresReview
    }
}

// MARK: - ScanToMindHandoffReasonV1

/// The reason a Scan → Mind handoff was initiated.
public enum ScanToMindHandoffReasonV1: String, Codable, Sendable, CaseIterable {

    /// Engineer completed the full capture and is handing off to Mind for review.
    case completedCapture = "complete_capture"

    /// Engineer is saving progress mid-capture; visit is not yet fully complete.
    case saveProgress = "save_progress"

    /// Engineer (or developer) is triggering the handoff to review the visit in Mind.
    case reviewInMind = "review_in_mind"

    /// Engineer is opening the Quote Planner in Atlas Mind with visit evidence preloaded.
    case quotePlanner = "quote_planner"
}
