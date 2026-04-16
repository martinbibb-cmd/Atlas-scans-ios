import Foundation

// MARK: - VisitValidationResult

/// Validation result computed before handing off a session to Atlas Mind.
struct VisitValidationResult {

    // MARK: Blocking issues

    /// Issues that prevent handoff (empty visit reference, no rooms, etc.)
    let blockingIssues: [String]

    // MARK: Warnings

    /// Non-blocking issues surfaced to the engineer for awareness.
    let warnings: [String]

    // MARK: Computed

    /// True when there are no blocking issues and handoff is safe.
    var isReadyForHandoff: Bool {
        blockingIssues.isEmpty
    }

    /// True when there are no blocking issues and no warnings.
    var isFullyClean: Bool {
        blockingIssues.isEmpty && warnings.isEmpty
    }

    var allIssues: [String] {
        blockingIssues + warnings
    }
}

// MARK: - VisitSessionValidator

/// Validates a `PropertyScanSession` before handoff to Atlas Mind.
///
/// Design:
///   - Blocking issues prevent handoff.
///   - Warnings are surfaced but do not block.
///   - Validation is pure and stateless; no side effects.
enum VisitSessionValidator {

    static func validate(_ session: PropertyScanSession) -> VisitValidationResult {
        var blocking: [String] = []
        var warnings: [String] = []

        // MARK: Blocking checks

        if session.propertyAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            blocking.append("Property address is required.")
        }

        if session.rooms.isEmpty {
            blocking.append("At least one room must be added.")
        }

        let hasSpatialCapture = session.rooms.contains(\.geometryCaptured)
            || !session.roomScanEvidence.isEmpty
        if !hasSpatialCapture {
            blocking.append("No spatial capture exists (LiDAR scan or room geometry required).")
        }

        // MARK: Transcript / voice checks

        let hasTranscript = session.allVoiceNotes.contains { $0.transcript != nil }
        let hasVoiceNotes = !session.allVoiceNotes.isEmpty
        if !hasTranscript && !hasVoiceNotes {
            warnings.append("No voice notes or transcript captured.")
        } else if hasVoiceNotes && !hasTranscript {
            warnings.append("Voice notes recorded but no transcript available.")
        }

        // MARK: Photo checks

        if session.totalPhotos == 0 {
            warnings.append("No evidence photos captured.")
        }

        // MARK: Photo / object link consistency

        let allObjectIDs = Set(session.allTaggedObjects.map(\.id))
        let orphanedPhotoLinks = session.allPhotos
            .compactMap(\.taggedObjectID)
            .filter { !allObjectIDs.contains($0) }
        if !orphanedPhotoLinks.isEmpty {
            warnings.append("\(orphanedPhotoLinks.count) photo(s) linked to missing objects.")
        }

        // MARK: Per-room checks

        for room in session.rooms where room.name.trimmingCharacters(in: .whitespaces).isEmpty {
            warnings.append("A room has no name.")
        }

        return VisitValidationResult(
            blockingIssues: blocking,
            warnings: warnings
        )
    }
}

// MARK: - Array helper

private extension Array {
    func contains(_ keyPath: KeyPath<Element, Bool>) -> Bool {
        contains { $0[keyPath: keyPath] }
    }
}
