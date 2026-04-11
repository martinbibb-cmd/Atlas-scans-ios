import Foundation

// MARK: - SessionKnowledgeExtractor
//
// Conservative keyword-based extraction from VoiceNote captions and transcripts.
//
// Design rules:
//   • Voice evidence is always preserved in the originating VoiceNote.
//   • Extraction is conservative: prefer "review needed" over confidently wrong structure.
//   • Explicit categorisation (extractionHint on VoiceNote) produces high confidence.
//   • Keyword matches in caption/transcript produce medium confidence.
//   • Facts are always attributed to their source note.

struct SessionKnowledgeExtractor {

    // MARK: - Public API

    /// Extracts structured facts from a collection of voice notes.
    ///
    /// Facts are deduplicated by category × source note — one note cannot
    /// produce two facts of the same category.
    static func extractFacts(from notes: [VoiceNote]) -> [ExtractedSessionFact] {
        notes.flatMap { extractFacts(from: $0) }
    }

    /// Extracts structured facts from a single voice note.
    ///
    /// If the note has an explicit `extractionHint`, a high-confidence fact is
    /// produced regardless of keyword matching.  Otherwise the full text
    /// (caption + transcript) is scanned for known patterns.
    static func extractFacts(from note: VoiceNote) -> [ExtractedSessionFact] {
        var facts: [ExtractedSessionFact] = []

        // Explicit engineer categorisation → high confidence, no pattern needed.
        if let hint = note.extractionHint {
            let value = effectiveText(for: note)
            guard !value.isEmpty else { return [] }
            let fact = ExtractedSessionFact(
                category: hint,
                value: value,
                confidence: .high,
                sourceNoteID: note.id,
                roomID: note.linkedRoomID,
                objectID: note.linkedObjectID
            )
            return [fact]
        }

        // Keyword / VoiceNoteKind-based extraction → medium confidence.
        let text = effectiveText(for: note).lowercased()
        guard !text.isEmpty else { return [] }

        // Household composition
        if let fact = extractHousehold(text: text, note: note) { facts.append(fact) }

        // Occupancy patterns
        if let fact = extractOccupancy(text: text, note: note) { facts.append(fact) }

        // Bathroom / hot water
        if let fact = extractBathrooms(text: text, note: note) { facts.append(fact) }

        // Hot water usage patterns (separate from bathroom count)
        if let fact = extractHotWaterUsage(text: text, note: note) { facts.append(fact) }

        // Customer priority
        if let fact = extractPriority(text: text, note: note) { facts.append(fact) }

        // Customer constraint — also triggered by .constraint kind
        if let fact = extractConstraint(text: text, note: note) { facts.append(fact) }

        // Current system type
        if let fact = extractSystemType(text: text, note: note) { facts.append(fact) }

        // Current system issue
        if let fact = extractSystemIssue(text: text, note: note) { facts.append(fact) }

        // Water quality
        if let fact = extractWaterQuality(text: text, note: note) { facts.append(fact) }

        return facts
    }

    // MARK: - Knowledge summary

    /// Computes a `SessionKnowledgeSummary` from a list of extracted facts.
    static func knowledgeSummary(from facts: [ExtractedSessionFact]) -> SessionKnowledgeSummary {
        let householdFacts    = facts.filter { $0.category == .householdComposition }
        let systemFacts       = facts.filter { $0.category == .currentSystemType || $0.category == .currentSystemIssue }
        let bathroomFacts     = facts.filter { $0.category == .bathroomCount || $0.category == .hotWaterUsage }
        let priorityFacts     = facts.filter { $0.category == .customerPriority }
        let constraintFacts   = facts.filter { $0.category == .customerConstraint }

        let householdKnown  = householdFacts.contains { $0.confidence >= .medium }
        let systemKnown     = systemFacts.contains    { $0.confidence >= .medium }
        let bathroomsKnown  = bathroomFacts.contains  { $0.confidence >= .medium }
        let prioritiesKnown = priorityFacts.contains  { $0.confidence >= .medium }
        let constraintsKnown = constraintFacts.contains { $0.confidence >= .medium }

        var missing: [String] = []
        var warnings: [String] = []

        // Missing: no facts at all for an area
        if householdFacts.isEmpty  { missing.append("Household composition not captured") }
        if systemFacts.isEmpty     { missing.append("Current system not documented") }

        // Review: only low-confidence facts captured
        if !householdFacts.isEmpty && !householdKnown {
            warnings.append("Household composition needs review")
        }
        if !bathroomFacts.isEmpty && !bathroomsKnown {
            warnings.append("Bathroom / hot water usage needs review")
        }

        return SessionKnowledgeSummary(
            householdKnown: householdKnown,
            systemKnown: systemKnown,
            bathroomsKnown: bathroomsKnown,
            prioritiesKnown: prioritiesKnown,
            constraintsKnown: constraintsKnown,
            missingEssentials: missing,
            reviewWarnings: warnings
        )
    }

    // MARK: - Private extraction helpers

    private static func effectiveText(for note: VoiceNote) -> String {
        [note.caption, note.transcript ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func extractHousehold(text: String, note: VoiceNote) -> ExtractedSessionFact? {
        let keywords = ["family of", "household of", "two adults", "three adults",
                        "single adult", "couple", "occupants", "residents",
                        "adults and", "children", "kids"]
        guard keywords.contains(where: { text.contains($0) }) else { return nil }
        return makeFact(category: .householdComposition, note: note, confidence: .medium)
    }

    private static func extractOccupancy(text: String, note: VoiceNote) -> ExtractedSessionFact? {
        let keywords = ["at home during", "works from home", "school hours", "mostly empty",
                        "occupied all day", "shift work", "commute", "home all day",
                        "away during"]
        guard keywords.contains(where: { text.contains($0) }) else { return nil }
        return makeFact(category: .occupancyPattern, note: note, confidence: .medium)
    }

    private static func extractBathrooms(text: String, note: VoiceNote) -> ExtractedSessionFact? {
        let keywords = ["bathroom", "bathrooms", "shower", "bath", "en suite", "en-suite",
                        "wet room", "cloakroom"]
        guard keywords.contains(where: { text.contains($0) }) else { return nil }
        // If it reads more like a usage observation than a count, let extractHotWaterUsage handle it.
        let countKeywords = ["one bathroom", "two bathroom", "three bathroom",
                             "1 bathroom", "2 bathroom", "3 bathroom",
                             "single bathroom", "double bathroom"]
        let confidence: ConfidenceLevel = countKeywords.contains(where: { text.contains($0) }) ? .high : .medium
        return makeFact(category: .bathroomCount, note: note, confidence: confidence)
    }

    private static func extractHotWaterUsage(text: String, note: VoiceNote) -> ExtractedSessionFact? {
        let keywords = ["hot water", "shower mostly", "bath mostly", "both showers",
                        "simultaneous", "peak demand", "morning demand", "evening demand",
                        "hot water usage", "only use shower"]
        guard keywords.contains(where: { text.contains($0) }) else { return nil }
        return makeFact(category: .hotWaterUsage, note: note, confidence: .medium)
    }

    private static func extractPriority(text: String, note: VoiceNote) -> ExtractedSessionFact? {
        let kindMatch = note.kind == .recommendation
        let keywords = ["important to", "wants to", "would like", "priority is",
                        "customer wants", "prefers", "keen on", "really wants",
                        "must have", "critical for", "value", "quick hot water",
                        "lower bills", "quieter", "reliability"]
        let keywordMatch = keywords.contains(where: { text.contains($0) })
        guard kindMatch || keywordMatch else { return nil }
        return makeFact(category: .customerPriority, note: note, confidence: kindMatch ? .high : .medium)
    }

    private static func extractConstraint(text: String, note: VoiceNote) -> ExtractedSessionFact? {
        let kindMatch = note.kind == .constraint
        let keywords = ["must not", "cannot", "constraint", "keep", "airing cupboard",
                        "no access", "low disruption", "minimal disruption",
                        "not allowed", "restricted", "listed building",
                        "conservation area", "tenant", "landlord", "permission needed"]
        let keywordMatch = keywords.contains(where: { text.contains($0) })
        guard kindMatch || keywordMatch else { return nil }
        return makeFact(category: .customerConstraint, note: note, confidence: kindMatch ? .high : .medium)
    }

    private static func extractSystemType(text: String, note: VoiceNote) -> ExtractedSessionFact? {
        let keywords = ["combi", "system boiler", "regular boiler", "heat only",
                        "open vent", "sealed system", "heat pump", "solar thermal",
                        "back boiler", "combination boiler", "cylinder", "unvented",
                        "vented cylinder", "this is the boiler", "this is the cylinder"]
        guard keywords.contains(where: { text.contains($0) }) else { return nil }
        return makeFact(category: .currentSystemType, note: note, confidence: .medium)
    }

    private static func extractSystemIssue(text: String, note: VoiceNote) -> ExtractedSessionFact? {
        let kindMatch = note.kind == .issue
        let keywords = ["struggles", "slow", "noisy", "banging", "dripping",
                        "leaking", "corrosion", "pressure dropping", "losing pressure",
                        "cutting out", "not heating", "cold spots", "intermittent",
                        "old boiler", "failing", "inefficient", "frequent breakdowns"]
        let keywordMatch = keywords.contains(where: { text.contains($0) })
        guard kindMatch || keywordMatch else { return nil }
        return makeFact(category: .currentSystemIssue, note: note, confidence: kindMatch ? .high : .medium)
    }

    private static func extractWaterQuality(text: String, note: VoiceNote) -> ExtractedSessionFact? {
        let keywords = ["hard water", "soft water", "scaling", "limescale", "scale",
                        "calcium", "water quality", "filter needed", "softener",
                        "chalky", "kettle scaling", "furring up"]
        guard keywords.contains(where: { text.contains($0) }) else { return nil }
        return makeFact(category: .waterQuality, note: note, confidence: .medium)
    }

    private static func makeFact(
        category: SessionFactCategory,
        note: VoiceNote,
        confidence: ConfidenceLevel
    ) -> ExtractedSessionFact {
        let value = effectiveText(for: note)
        return ExtractedSessionFact(
            category: category,
            value: value.isEmpty ? "(no caption)" : value,
            confidence: confidence,
            sourceNoteID: note.id,
            roomID: note.linkedRoomID,
            objectID: note.linkedObjectID,
            createdAt: note.createdAt
        )
    }
}
