import Foundation

// MARK: - VisitHandoffPack
//
// The canonical output of a completed field visit.
//
// Built once from a completed PropertyScanSession by VisitHandoffPackBuilder.
// Owns two stable output lenses — one customer-safe, one engineer-detailed —
// and is the single source of truth for the post-completion review surface.
//
// This struct is intentionally immutable so the review flow cannot mutate
// visit data after completion.

struct VisitHandoffPack {

    /// The session UUID this pack was built from.
    let visitID: UUID

    /// Job reference string (e.g. "JOB-2025-001").
    let jobReference: String

    /// Property address as entered at session creation.
    let propertyAddress: String

    /// Engineer name, if set.
    let engineerName: String

    /// When the visit was explicitly completed.  Nil for sessions completed
    /// before the completedAt field was introduced (backward-compat guard).
    let completedAt: Date?

    /// Customer-safe summary for presentation to the customer or portal.
    let customerSummary: CustomerVisitSummary

    /// Engineer-facing detail pack for technical sense-check before handoff.
    let engineerSummary: EngineerVisitSummary
}

// MARK: - CustomerVisitSummary

/// A customer-safe, jargon-free summary of what was found and what is planned.
///
/// Design rule: contains no engineering jargon, no raw note lists,
/// no recommendation scores.  Safe to present directly to a customer.
struct CustomerVisitSummary {

    /// Short human-readable title (property address or visit reference).
    let title: String

    /// Number of rooms included in the survey.
    let roomCount: Int

    /// High-level findings lines (e.g. "Boiler identified", "Flue recorded").
    let findings: [String]

    /// High-level planned-work lines (e.g. "Proposed radiator changes recorded").
    let planSummary: [String]

    /// What happens next / what to expect lines.
    let whatToExpectNext: [String]

    /// Number of survey photos captured (used for summary display only).
    let photoCount: Int
}

// MARK: - EngineerVisitSummary

/// A denser, engineer-facing technical summary of the completed visit.
///
/// Covers rooms, key objects, proposed emitters, planning notes, and
/// consolidated field notes.  Intended for sense-checking before handoff
/// to the portal or Atlas Mind.
struct EngineerVisitSummary {

    // MARK: Rooms

    struct RoomEntry {
        let name: String
        let objectCount: Int
        let photoCount: Int
        let voiceNoteCount: Int
    }

    let rooms: [RoomEntry]

    // MARK: Key objects

    struct KeyObjectEntry {
        let displayLabel: String
        let category: String
        let roomName: String?
        let notes: String
    }

    let keyObjects: [KeyObjectEntry]

    // MARK: Proposed emitters

    struct ProposedEmitterEntry {
        let displayLabel: String
        let type: String
        let roomName: String?
        let note: String
    }

    let proposedEmitters: [ProposedEmitterEntry]

    // MARK: Planning notes

    let accessNotes: [String]
    let roomPlanNotes: [String]
    let specNotes: [String]

    // MARK: Field notes

    /// Consolidated voice + text notes from the whole session.
    let consolidatedFieldNotes: [String]

    // MARK: Completion metadata

    let completedAt: Date?
    let completionMethod: String?
    let completedByUserId: String?

    // MARK: Counts (convenience for summary display)

    var roomCount: Int { rooms.count }
    var keyObjectCount: Int { keyObjects.count }
    var proposedEmitterCount: Int { proposedEmitters.count }
    var accessNoteCount: Int { accessNotes.count }
    var fieldNoteCount: Int { consolidatedFieldNotes.count }
}
