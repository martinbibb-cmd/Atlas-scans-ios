import Foundation

// MARK: - PlanningOverlayV1
//
// Minimal planning overlay contract.
//
// Design rules:
//   • One PlanningOverlayV1 represents the proposed installation layer for a visit.
//   • It is derived from install markup objects, routes, and planning annotations
//     in the in-app PropertyScanSession.
//   • atlas-scans-ios PRODUCES this shape from engineer markup work.
//   • atlas-contracts DEFINES the schema — this file is the single source of truth.
//   • derivePlanningReadiness is a pure, side-effect-free function.
//   • This contract captures PROPOSED state only; existing system geometry is
//     tracked separately in InstallLayerModelV1.

// MARK: - ProposedEmitterV1

/// A proposed emitter (radiator, towel rail, UFH zone, etc.) in the planning overlay.
public struct ProposedEmitterV1: Codable, Sendable, Equatable {

    /// Stable string identifier (UUID string).
    public let id: String

    /// Object type raw value matching ServiceObjectCategory (e.g. "radiator").
    public let type: String

    /// Engineer-assigned display label; may be empty.
    public let label: String

    /// UUID string of the room this emitter is placed in; nil for unplaced emitters.
    public let roomID: String?

    /// Optional planning note for this proposed emitter.
    public let note: String

    /// True when this proposed emitter is intended to replace an existing emitter.
    public let replacesExisting: Bool

    public init(
        id: String,
        type: String,
        label: String = "",
        roomID: String? = nil,
        note: String = "",
        replacesExisting: Bool = false
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.roomID = roomID
        self.note = note
        self.replacesExisting = replacesExisting
    }
}

// MARK: - RouteMarkupV1

/// A proposed pipe or service route in the planning overlay.
public struct RouteMarkupV1: Codable, Sendable, Equatable {

    /// Stable string identifier (UUID string).
    public let id: String

    /// Circuit kind (e.g. "flow", "return", "gas").  Matches MarkupRouteKind raw values.
    public let kind: String

    /// UUID string of the room this route primarily traverses; nil when not room-scoped.
    public let roomID: String?

    /// Optional engineer note for this route.
    public let notes: String

    public init(id: String, kind: String, roomID: String? = nil, notes: String = "") {
        self.id = id
        self.kind = kind
        self.roomID = roomID
        self.notes = notes
    }
}

// MARK: - PlanningNoteV1

/// A text annotation in the planning overlay.
///
/// Used for access notes, room plan notes, and specification notes.
public struct PlanningNoteV1: Codable, Sendable, Equatable {

    /// Stable string identifier (UUID string).
    public let id: String

    /// Note text entered by the engineer.
    public let text: String

    /// UUID string of the room this note relates to; nil for property-level notes.
    public let roomID: String?

    /// Note kind raw value (e.g. "access_note", "room_plan_note", "spec_note").
    public let kind: String

    public init(id: String, text: String, roomID: String? = nil, kind: String = "general") {
        self.id = id
        self.text = text
        self.roomID = roomID
        self.kind = kind
    }
}

// MARK: - PlanningOverlayV1

/// The proposed installation planning layer for a single field visit.
///
/// Captures:
///   • proposed emitters (radiators, towel rails, UFH zones)
///   • proposed pipe/service routes
///   • access notes (constraints on installation routes)
///   • room plan notes (per-room planning comments)
///   • spec notes (material or design specification notes)
public struct PlanningOverlayV1: Codable, Sendable {

    /// Proposed emitters placed during planning.
    public var proposedEmitters: [ProposedEmitterV1]

    /// Proposed pipe and service routes drawn during planning.
    public var routeMarkups: [RouteMarkupV1]

    /// Access constraint notes added during planning.
    public var accessNotes: [PlanningNoteV1]

    /// Per-room planning notes.
    public var roomPlanNotes: [PlanningNoteV1]

    /// Specification and material notes.
    public var specNotes: [PlanningNoteV1]

    // MARK: Convenience

    /// An overlay with no content.
    public static var empty: PlanningOverlayV1 {
        PlanningOverlayV1()
    }

    /// True when the overlay carries no planning data.
    public var isEmpty: Bool {
        proposedEmitters.isEmpty
            && routeMarkups.isEmpty
            && accessNotes.isEmpty
            && roomPlanNotes.isEmpty
            && specNotes.isEmpty
    }

    // MARK: Init

    public init(
        proposedEmitters: [ProposedEmitterV1] = [],
        routeMarkups: [RouteMarkupV1] = [],
        accessNotes: [PlanningNoteV1] = [],
        roomPlanNotes: [PlanningNoteV1] = [],
        specNotes: [PlanningNoteV1] = []
    ) {
        self.proposedEmitters = proposedEmitters
        self.routeMarkups = routeMarkups
        self.accessNotes = accessNotes
        self.roomPlanNotes = roomPlanNotes
        self.specNotes = specNotes
    }
}

// MARK: - PlanningReadinessV1

/// Counts of planning-overlay items, used to show planning coverage on the review screen.
public struct PlanningReadinessV1: Codable, Sendable {

    /// Number of proposed emitters placed.
    public let proposedEmittersCount: Int

    /// Number of proposed pipe/service routes drawn.
    public let routesCount: Int

    /// Number of access constraint notes.
    public let accessNotesCount: Int

    /// Number of per-room plan notes.
    public let roomPlansCount: Int

    /// Number of specification/material notes.
    public let specNotesCount: Int

    // MARK: Init

    public init(
        proposedEmittersCount: Int,
        routesCount: Int,
        accessNotesCount: Int,
        roomPlansCount: Int,
        specNotesCount: Int
    ) {
        self.proposedEmittersCount = proposedEmittersCount
        self.routesCount = routesCount
        self.accessNotesCount = accessNotesCount
        self.roomPlansCount = roomPlansCount
        self.specNotesCount = specNotesCount
    }
}

// MARK: - derivePlanningReadiness

/// Derives `PlanningReadinessV1` from the given `PlanningOverlayV1`.
///
/// Pure and crash-safe.  An empty overlay returns all-zero counts.
public func derivePlanningReadiness(_ overlay: PlanningOverlayV1) -> PlanningReadinessV1 {
    PlanningReadinessV1(
        proposedEmittersCount: overlay.proposedEmitters.count,
        routesCount: overlay.routeMarkups.count,
        accessNotesCount: overlay.accessNotes.count,
        roomPlansCount: overlay.roomPlanNotes.count,
        specNotesCount: overlay.specNotes.count
    )
}
