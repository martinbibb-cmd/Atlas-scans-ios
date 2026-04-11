import Foundation

// MARK: - SessionFactCategory
//
// Categories for structured knowledge extracted from engineer voice notes
// during a property survey session.

enum SessionFactCategory: String, Codable, CaseIterable {
    case householdComposition = "household_composition"
    case occupancyPattern     = "occupancy_pattern"
    case bathroomCount        = "bathroom_count"
    case hotWaterUsage        = "hot_water_usage"
    case heatingPattern       = "heating_pattern"
    case customerPriority     = "customer_priority"
    case customerConstraint   = "customer_constraint"
    case currentSystemType    = "current_system_type"
    case currentSystemIssue   = "current_system_issue"
    case waterQuality         = "water_quality"
    case installerNote        = "installer_note"

    var displayName: String {
        switch self {
        case .householdComposition: return "Household"
        case .occupancyPattern:     return "Occupancy"
        case .bathroomCount:        return "Bathrooms"
        case .hotWaterUsage:        return "Hot Water"
        case .heatingPattern:       return "Heating"
        case .customerPriority:     return "Priority"
        case .customerConstraint:   return "Constraint"
        case .currentSystemType:    return "System Type"
        case .currentSystemIssue:   return "System Issue"
        case .waterQuality:         return "Water Quality"
        case .installerNote:        return "Installer Note"
        }
    }

    var symbolName: String {
        switch self {
        case .householdComposition: return "person.3.fill"
        case .occupancyPattern:     return "clock.fill"
        case .bathroomCount:        return "drop.fill"
        case .hotWaterUsage:        return "flame.fill"
        case .heatingPattern:       return "thermometer.sun.fill"
        case .customerPriority:     return "star.fill"
        case .customerConstraint:   return "exclamationmark.triangle.fill"
        case .currentSystemType:    return "boiler.fill"
        case .currentSystemIssue:   return "xmark.circle.fill"
        case .waterQuality:         return "drop.triangle.fill"
        case .installerNote:        return "note.text"
        }
    }

    /// Coarse group used for knowledge summary display.
    var group: SessionFactGroup {
        switch self {
        case .householdComposition, .occupancyPattern:
            return .household
        case .bathroomCount, .hotWaterUsage, .heatingPattern:
            return .usage
        case .customerPriority:
            return .priorities
        case .customerConstraint:
            return .constraints
        case .currentSystemType, .currentSystemIssue, .waterQuality, .installerNote:
            return .system
        }
    }
}

// MARK: - SessionFactGroup

/// Coarse grouping for display in knowledge summary panels.
enum SessionFactGroup: String, CaseIterable {
    case household  = "household"
    case usage      = "usage"
    case priorities = "priorities"
    case constraints = "constraints"
    case system     = "system"

    var displayName: String {
        switch self {
        case .household:   return "Household"
        case .usage:       return "Usage"
        case .priorities:  return "Priorities"
        case .constraints: return "Constraints"
        case .system:      return "System"
        }
    }

    var symbolName: String {
        switch self {
        case .household:   return "person.3.fill"
        case .usage:       return "drop.fill"
        case .priorities:  return "star.fill"
        case .constraints: return "exclamationmark.triangle.fill"
        case .system:      return "boiler.fill"
        }
    }
}

// MARK: - ConfidenceLevel

/// Confidence of an extracted structured fact.
enum ConfidenceLevel: String, Codable, CaseIterable, Comparable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var displayName: String {
        switch self {
        case .low:    return "Review"
        case .medium: return "Inferred"
        case .high:   return "Confirmed"
        }
    }

    var symbolName: String {
        switch self {
        case .low:    return "questionmark.circle"
        case .medium: return "checkmark.circle"
        case .high:   return "checkmark.circle.fill"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .low:    return 0
        case .medium: return 1
        case .high:   return 2
        }
    }

    static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - ExtractedSessionFact

/// A structured knowledge fact extracted from voice notes during a session.
///
/// Facts carry full provenance: source note id, scope (room/object), confidence,
/// and creation timestamp. Voice evidence is always preserved separately in the
/// originating `VoiceNote`; this model is an extraction layer only.
struct ExtractedSessionFact: Identifiable, Codable, Equatable {

    var id: UUID

    /// The structured category this fact belongs to.
    var category: SessionFactCategory

    /// Human-readable extracted value (e.g. "Family of five").
    var value: String

    /// Confidence level of the extraction.
    var confidence: ConfidenceLevel

    /// UUID of the originating `VoiceNote`; nil for manually entered facts.
    var sourceNoteID: UUID?

    /// Room scope of the fact; nil for session-level facts.
    var roomID: UUID?

    /// Object scope of the fact; nil when not tied to a specific object.
    var objectID: UUID?

    var createdAt: Date

    // MARK: Init

    init(
        id: UUID = UUID(),
        category: SessionFactCategory,
        value: String,
        confidence: ConfidenceLevel,
        sourceNoteID: UUID? = nil,
        roomID: UUID? = nil,
        objectID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.value = value
        self.confidence = confidence
        self.sourceNoteID = sourceNoteID
        self.roomID = roomID
        self.objectID = objectID
        self.createdAt = createdAt
    }

    // MARK: Decodable — backward-compatible

    private enum CodingKeys: String, CodingKey {
        case id, category, value, confidence
        case sourceNoteID, roomID, objectID
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,                         forKey: .id)
        category     = try c.decode(SessionFactCategory.self,          forKey: .category)
        value        = try c.decode(String.self,                       forKey: .value)
        confidence   = try c.decodeIfPresent(ConfidenceLevel.self,     forKey: .confidence) ?? .medium
        sourceNoteID = try c.decodeIfPresent(UUID.self,                forKey: .sourceNoteID)
        roomID       = try c.decodeIfPresent(UUID.self,                forKey: .roomID)
        objectID     = try c.decodeIfPresent(UUID.self,                forKey: .objectID)
        createdAt    = try c.decodeIfPresent(Date.self,                forKey: .createdAt) ?? Date()
    }
}

// MARK: - SessionKnowledgeSummary

/// Computed knowledge coverage summary for a session.
///
/// Indicates which areas of non-spatial truth have been captured,
/// which are inferred or need review, and which are missing.
struct SessionKnowledgeSummary {

    /// True when at least one high-confidence household composition fact is present.
    let householdKnown: Bool

    /// True when at least one system type or system issue fact is present.
    let systemKnown: Bool

    /// True when bathroom count or hot water usage facts are present.
    let bathroomsKnown: Bool

    /// True when at least one customer priority fact is present.
    let prioritiesKnown: Bool

    /// True when at least one customer constraint fact is present.
    let constraintsKnown: Bool

    /// Human-readable labels for areas with no facts captured at all.
    let missingEssentials: [String]

    /// Human-readable labels for areas where only low-confidence facts were extracted.
    let reviewWarnings: [String]

    /// True when all key knowledge areas have at least medium-confidence coverage.
    var allSatisfied: Bool {
        missingEssentials.isEmpty && reviewWarnings.isEmpty
    }

    /// True when at least one structured fact has been captured.
    var hasAnyFacts: Bool {
        householdKnown || systemKnown || bathroomsKnown || prioritiesKnown || constraintsKnown
    }
}
