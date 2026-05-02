import Foundation
import AtlasContracts

// MARK: - Type aliases
//
// Bridge between AtlasScan naming and AtlasContracts types.

/// Lifecycle status for a field visit. Bridges to the AtlasContracts contract type.
typealias AtlasVisitStatusV1 = VisitLifecycleStatus

/// Readiness flags for a field visit. Bridges to the AtlasContracts contract type.
typealias AtlasVisitReadinessV1 = VisitReadinessV1

// MARK: - AtlasScanVisit
//
// Lightweight lifecycle envelope for a single field visit.
//
// Design:
//   • One AtlasScanVisit represents the lifecycle state of one on-site visit.
//   • Detailed capture evidence lives in CaptureSessionDraft (linked via captureSessionId).
//   • Persisted as JSON in Documents/active_visit.json by AtlasScanVisitStore.
//   • Status transitions: draft → capturing → readyToComplete → complete.
//   • Readiness is derived from the linked capture session.

struct AtlasScanVisit: Identifiable, Codable {

    // MARK: Identity

    var id: UUID = UUID()

    /// Stable string identifier for this visit.
    var visitId: String { id.uuidString }

    /// Engineer-assigned visit number / job reference.
    var visitNumber: String?

    /// Optional brand or client identifier.
    var brandId: String?

    // MARK: Lifecycle

    /// Current phase of the visit workflow.
    var status: AtlasVisitStatusV1

    /// Readiness flags derived from captured evidence.
    var readiness: AtlasVisitReadinessV1

    // MARK: Timestamps

    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    // MARK: Capture link

    /// UUID of the CaptureSessionDraft that holds the evidence for this visit.
    var captureSessionId: UUID?

    // MARK: Init

    init(visitNumber: String? = nil, brandId: String? = nil) {
        let now = Date()
        self.visitNumber = visitNumber
        self.brandId = brandId
        self.status = .capturing
        self.readiness = VisitReadinessV1(
            hasRooms: false,
            hasPhotos: false,
            hasHeatingSystem: false,
            hasHotWaterSystem: false,
            hasBoiler: false,
            hasFlue: false,
            hasNotes: false
        )
        self.createdAt = now
        self.updatedAt = now
    }
}

// MARK: - Readiness derivation

extension AtlasScanVisit {

    /// Derives visit readiness flags from a CaptureSessionDraft.
    ///
    /// Only confirmed evidence counts toward readiness.
    /// Rejected evidence is never counted.
    /// Pending evidence does not satisfy any readiness flag.
    ///
    /// Used in VisitHomeView to compute live readiness without
    /// storing a snapshot in the visit model.
    static func deriveReadiness(from draft: CaptureSessionDraft) -> VisitReadinessV1 {

        // Confirmed items only
        let confirmedPins  = draft.objectPins.filter   { $0.reviewStatus == .confirmed }
        let confirmedPhotos = draft.photos.filter      { $0.reviewStatus == .confirmed }
        let confirmedRooms  = draft.roomScans.filter   { $0.reviewStatus == .confirmed }
        let confirmedNotes  = draft.voiceNotes.filter  { $0.reviewStatus == .confirmed }

        let confirmedPinTypes = confirmedPins.map(\.type)

        // Boiler: confirmed boiler or heat-pump object
        let hasBoiler = confirmedPinTypes.contains(.boiler) || confirmedPinTypes.contains(.heatPump)

        // Flue: confirmed flue object or a confirmed photo of kind .flue
        let hasFlue = confirmedPinTypes.contains(.flue)
            || confirmedPhotos.contains(where: { $0.kind == .flue })

        // Hot water: confirmed cylinder or combi-related object
        // (combi boilers share the .boiler type; a separate cylinder covers hot water)
        let hasHotWaterSystem = confirmedPinTypes.contains(.cylinder)
            || hasBoiler    // a confirmed boiler implicitly covers a combi system

        // Heating: confirmed boiler, heat pump, or radiator
        let hasHeatingSystem = hasBoiler || confirmedPinTypes.contains(.radiator)

        // Rooms: at least one confirmed room scan
        let hasRooms = !confirmedRooms.isEmpty

        // Photos: at least one confirmed photo
        let hasPhotos = !confirmedPhotos.isEmpty

        // Notes: at least one confirmed voice note / transcript
        let hasNotes = confirmedNotes.contains(where: { !$0.transcript.isEmpty })
            || !confirmedNotes.isEmpty

        return VisitReadinessV1(
            hasRooms: hasRooms,
            hasPhotos: hasPhotos,
            hasHeatingSystem: hasHeatingSystem,
            hasHotWaterSystem: hasHotWaterSystem,
            hasBoiler: hasBoiler,
            hasFlue: hasFlue,
            hasNotes: hasNotes
        )
    }
}
