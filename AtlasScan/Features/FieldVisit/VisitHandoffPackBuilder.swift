import Foundation

// MARK: - VisitHandoffPackBuilder
//
// Pure builder: converts a completed PropertyScanSession into a VisitHandoffPack.
//
// Rules:
//   • All derivation is deterministic — same input always produces same output.
//   • No side effects; no mutation of the session.
//   • Missing optional fields do not crash the builder.
//   • Customer and engineer summaries are derived separately from the same
//     canonical session data.

struct VisitHandoffPackBuilder {

    // MARK: - Public entry point

    /// Builds a handoff pack from a completed visit session.
    ///
    /// The session does not need to be in `.complete` lifecycle state to build
    /// a pack — the builder is defensive and produces a valid pack from any
    /// session state.  Callers should validate lifecycle before deciding
    /// whether to show the review surface.
    func buildHandoffPack(for session: PropertyScanSession) -> VisitHandoffPack {
        VisitHandoffPack(
            visitID: session.id,
            jobReference: session.jobReference,
            propertyAddress: session.propertyAddress,
            engineerName: session.engineerName,
            completedAt: session.completedAt,
            customerSummary: buildCustomerSummary(for: session),
            engineerSummary: buildEngineerSummary(for: session)
        )
    }

    // MARK: - Customer summary

    func buildCustomerSummary(for session: PropertyScanSession) -> CustomerVisitSummary {
        CustomerVisitSummary(
            title: session.propertyAddress.isEmpty ? session.jobReference : session.propertyAddress,
            roomCount: session.rooms.count,
            findings: deriveCustomerFindingsSummary(from: session),
            planSummary: deriveCustomerPlanSummary(from: session),
            whatToExpectNext: deriveCustomerWhatToExpect(),
            photoCount: session.totalPhotos
        )
    }

    // MARK: - Engineer summary

    func buildEngineerSummary(for session: PropertyScanSession) -> EngineerVisitSummary {
        let roomEntries = session.rooms.map { room in
            EngineerVisitSummary.RoomEntry(
                name: room.name,
                objectCount: room.taggedObjects.count,
                photoCount: room.photos.count,
                voiceNoteCount: room.voiceNotes.count
            )
        }

        let keyObjectEntries = buildKeyObjectEntries(session: session)
        let proposedEmitterEntries = buildProposedEmitterEntries(session: session)

        let accessNotes = session.planningAnnotations(ofKind: .accessNote).map(\.text)
        let roomPlanNotes = session.planningAnnotations(ofKind: .roomPlanNote).map(\.text)
        let specNotes = session.planningAnnotations(ofKind: .specNote).map(\.text)

        let allNotes = consolidateVisitNotes(
            voiceNotes: session.allVoiceNotes
        )

        return EngineerVisitSummary(
            rooms: roomEntries,
            keyObjects: keyObjectEntries,
            proposedEmitters: proposedEmitterEntries,
            accessNotes: accessNotes,
            roomPlanNotes: roomPlanNotes,
            specNotes: specNotes,
            consolidatedFieldNotes: allNotes.lines,
            completedAt: session.completedAt,
            completionMethod: session.completionMethod?.displayName,
            completedByUserId: session.completedByUserId
        )
    }

    // MARK: - Derivation helpers (customer)

    /// Derives customer-safe high-level finding lines from session data.
    ///
    /// Factual, not salesy.  No engineering jargon.
    func deriveCustomerFindingsSummary(from session: PropertyScanSession) -> [String] {
        var lines: [String] = []

        let allObjects = session.allTaggedObjects

        if allObjects.contains(where: { $0.category == .boiler }) {
            lines.append("Boiler identified and recorded")
        }
        if allObjects.contains(where: { $0.category == .heatPump }) {
            lines.append("Heat pump identified and recorded")
        }
        if allObjects.contains(where: { $0.category == .flue }) {
            lines.append("Flue location recorded")
        }
        if allObjects.contains(where: { $0.category == .cylinder || $0.category == .thermalStore }) {
            lines.append("Hot water cylinder recorded")
        }

        let emitterCategories: Set<ServiceObjectCategory> = [
            .radiator, .radiatorDrop, .towelRail, .ufhZone, .fanConvector
        ]
        let emitterCount = allObjects.filter { emitterCategories.contains($0.category) }.count
        if emitterCount > 0 {
            lines.append("\(emitterCount) existing emitter\(emitterCount == 1 ? "" : "s") recorded")
        }

        if !session.rooms.isEmpty {
            lines.append("\(session.rooms.count) room\(session.rooms.count == 1 ? "" : "s") surveyed")
        }

        if session.totalPhotos > 0 {
            lines.append("Survey photos captured")
        }

        if lines.isEmpty {
            lines.append("Survey complete")
        }

        return lines
    }

    /// Derives customer-safe planned-work summary lines from session data.
    func deriveCustomerPlanSummary(from session: PropertyScanSession) -> [String] {
        var lines: [String] = []

        let emitterCategories: Set<String> = [
            "radiator", "radiator_drop", "towel_rail", "ufh_zone", "fan_convector"
        ]

        let proposedEmitters = session.installMarkupObjects.filter {
            $0.layer == .proposed && emitterCategories.contains($0.categoryRawValue)
        }
        if !proposedEmitters.isEmpty {
            lines.append("Proposed radiator changes recorded")
        }

        let proposedOtherObjects = session.installMarkupObjects.filter {
            $0.layer == .proposed && !emitterCategories.contains($0.categoryRawValue)
        }
        if !proposedOtherObjects.isEmpty {
            lines.append("Proposed installation changes recorded")
        }

        let accessNotes = session.planningAnnotations(ofKind: .accessNote)
        if !accessNotes.isEmpty {
            lines.append("Access considerations noted")
        }

        if lines.isEmpty && !session.installMarkupObjects.isEmpty {
            lines.append("Installation plan captured")
        }

        return lines
    }

    /// Returns the standard "what to expect next" lines.
    ///
    /// These are fixed copy — independent of session content.
    func deriveCustomerWhatToExpect() -> [String] {
        [
            "Your survey has been saved and is ready for review",
            "Your engineer will follow up with a detailed proposal",
            "A copy of the survey summary will be available on request"
        ]
    }

    // MARK: - Derivation helpers (engineer)

    /// Derives engineer-facing technical summary lines (for display headers).
    func deriveEngineerTechnicalSummary(from session: PropertyScanSession) -> [String] {
        var lines: [String] = []

        let allObjects = session.allTaggedObjects

        let boilers = allObjects.filter { $0.category == .boiler || $0.category == .heatPump }
        for b in boilers {
            let roomName = roomName(for: b.roomID, in: session)
            if let rn = roomName, rn != session.propertyAddress {
                lines.append("\(b.displayLabel) in \(rn)")
            } else {
                lines.append(b.displayLabel)
            }
        }

        let flues = allObjects.filter { $0.category == .flue }
        if flues.isEmpty {
            lines.append("Flue unassigned")
        } else {
            for f in flues {
                let direction = f.quickFieldValues["direction"] ?? "unassigned"
                lines.append("Flue direction: \(direction)")
            }
        }

        let emitterCategories: Set<String> = [
            "radiator", "radiator_drop", "towel_rail", "ufh_zone", "fan_convector"
        ]
        let proposedEmitters = session.installMarkupObjects.filter {
            $0.layer == .proposed && emitterCategories.contains($0.categoryRawValue)
        }
        let proposedRoomIDs = Set(proposedEmitters.compactMap(\.roomID))
        if !proposedEmitters.isEmpty {
            lines.append(
                "\(proposedEmitters.count) proposed emitter\(proposedEmitters.count == 1 ? "" : "s") across \(proposedRoomIDs.count) room\(proposedRoomIDs.count == 1 ? "" : "s")"
            )
        }

        let accessNotes = session.planningAnnotations(ofKind: .accessNote)
        if !accessNotes.isEmpty {
            lines.append("\(accessNotes.count) access note\(accessNotes.count == 1 ? "" : "s")")
        }

        let fieldNotes = consolidateVisitNotes(voiceNotes: session.allVoiceNotes)
        if !fieldNotes.lines.isEmpty {
            lines.append("\(fieldNotes.lines.count) consolidated field note\(fieldNotes.lines.count == 1 ? "" : "s")")
        }

        return lines
    }

    // MARK: - Private helpers

    private func buildKeyObjectEntries(session: PropertyScanSession) -> [EngineerVisitSummary.KeyObjectEntry] {
        let keyCategories: Set<ServiceObjectCategory> = [
            .boiler, .heatPump, .cylinder, .thermalStore, .bufferVessel,
            .flue, .gasMeter, .stopTap
        ]

        return session.allTaggedObjects
            .filter { keyCategories.contains($0.category) }
            .map { obj in
                EngineerVisitSummary.KeyObjectEntry(
                    displayLabel: obj.displayLabel,
                    category: obj.category.displayName,
                    roomName: roomName(for: obj.roomID, in: session),
                    notes: obj.notes
                )
            }
    }

    private func buildProposedEmitterEntries(session: PropertyScanSession) -> [EngineerVisitSummary.ProposedEmitterEntry] {
        let emitterCategories: Set<String> = [
            "radiator", "radiator_drop", "towel_rail", "ufh_zone", "fan_convector"
        ]

        return session.installMarkupObjects
            .filter { $0.layer == .proposed && emitterCategories.contains($0.categoryRawValue) }
            .map { obj in
                let resolvedRoomName: String?
                if let rid = obj.roomID {
                    resolvedRoomName = session.rooms.first(where: { $0.id == rid })?.name
                } else {
                    resolvedRoomName = nil
                }
                return EngineerVisitSummary.ProposedEmitterEntry(
                    displayLabel: obj.displayLabel,
                    type: ServiceObjectCategory(rawValue: obj.categoryRawValue)?.displayName ?? obj.categoryRawValue,
                    roomName: resolvedRoomName,
                    note: obj.note
                )
            }
    }

    private func roomName(for roomID: UUID?, in session: PropertyScanSession) -> String? {
        guard let rid = roomID else { return nil }
        return session.rooms.first(where: { $0.id == rid })?.name
    }
}
