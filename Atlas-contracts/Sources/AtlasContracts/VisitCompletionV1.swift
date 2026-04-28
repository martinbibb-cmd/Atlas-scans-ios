import Foundation

// MARK: - VisitCompletionV1
//
// Contract types for the explicit visit completion flow.
//
// Design rules:
//   • Completion is an explicit, user-initiated action — never a side effect.
//   • VisitCompletionValidationResult is pure and derived from VisitReadinessV1.
//   • validateVisitForCompletion is crash-safe and has no side effects.
//   • CompletionMethod is the single enumeration of how a visit can be closed.
//   • All seven readiness flags must pass before a visit can be completed.

// MARK: - CompletionMethod

/// How a visit was explicitly completed.
///
/// Additional methods (e.g. `remote`, `batchApproval`) may be added in later PRs.
public enum CompletionMethod: String, Codable, Sendable, CaseIterable {

    /// Surveyor pressed "Complete Visit" manually in the app.
    case manual = "manual"

    // MARK: Display

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        }
    }
}

// MARK: - VisitCompletionMissingItem

/// A specific required survey item that is absent when validating for completion.
///
/// Each case maps to one of the seven mandatory readiness flags checked by
/// `validateVisitForCompletion`.
public enum VisitCompletionMissingItem: String, Codable, Sendable, CaseIterable {

    /// No rooms have been captured.
    case rooms = "rooms"

    /// No photos have been taken.
    case photos = "photos"

    /// No heating system component has been tagged.
    case heatingSystem = "heatingSystem"

    /// No hot water system component has been tagged.
    case hotWaterSystem = "hotWaterSystem"

    /// No boiler or heat pump has been tagged.
    case boiler = "boiler"

    /// No flue has been tagged.
    case flue = "flue"

    /// No voice notes or transcript notes have been recorded.
    case notes = "notes"

    // MARK: Human-readable description

    /// Plain-English instruction shown to the surveyor when this item is missing.
    public var humanReadableDescription: String {
        switch self {
        case .rooms:         return "Add at least one room"
        case .photos:        return "Add at least one photo"
        case .heatingSystem: return "Confirm heating system"
        case .hotWaterSystem: return "Confirm hot water system"
        case .boiler:        return "Tag the boiler"
        case .flue:          return "Tag the flue"
        case .notes:         return "Add notes or transcript"
        }
    }
}

// MARK: - VisitCompletionValidationResult

/// The result of running completion validation against a visit's readiness flags.
///
/// Produced by `validateVisitForCompletion(readiness:)`.
/// All seven required flags must pass for `isCompletable` to be `true`.
public struct VisitCompletionValidationResult: Sendable {

    /// Whether the visit meets all required criteria for explicit completion.
    public let isCompletable: Bool

    /// The specific items that are preventing completion.
    ///
    /// Empty when `isCompletable` is `true`.
    public let missingItems: [VisitCompletionMissingItem]

    public init(isCompletable: Bool, missingItems: [VisitCompletionMissingItem]) {
        self.isCompletable = isCompletable
        self.missingItems = missingItems
    }
}

// MARK: - validateVisitForCompletion

/// Validates whether a visit is ready for explicit completion.
///
/// All seven readiness flags must be true for completion to be allowed.
/// Planning overlay content is not required for completion at this stage.
///
/// This function is pure and side-effect free.  It never mutates state and
/// never throws; an empty or partially-populated readiness input will produce
/// an appropriate result with the relevant missing items listed.
public func validateVisitForCompletion(
    readiness: VisitReadinessV1
) -> VisitCompletionValidationResult {
    var missing: [VisitCompletionMissingItem] = []

    if !readiness.hasRooms          { missing.append(.rooms) }
    if !readiness.hasPhotos         { missing.append(.photos) }
    if !readiness.hasHeatingSystem  { missing.append(.heatingSystem) }
    if !readiness.hasHotWaterSystem { missing.append(.hotWaterSystem) }
    if !readiness.hasBoiler         { missing.append(.boiler) }
    if !readiness.hasFlue           { missing.append(.flue) }
    if !readiness.hasNotes          { missing.append(.notes) }

    return VisitCompletionValidationResult(
        isCompletable: missing.isEmpty,
        missingItems: missing
    )
}
