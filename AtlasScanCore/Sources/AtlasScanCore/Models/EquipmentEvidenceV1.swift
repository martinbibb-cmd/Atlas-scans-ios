/// EquipmentEvidenceV1 — Maps SpatialPinV1 records from a session into
/// structured equipment evidence groups for the Atlas Mind handoff.

import Foundation

// MARK: - EquipmentPinEvidenceV1

/// Evidence record for a single ``SpatialPinV1``, mapped into Mind-consumable form.
///
/// Carries identity resolution, anchor confidence assessment, and review state
/// for each equipment pin captured during a V2 scan session.
public struct EquipmentPinEvidenceV1: Codable, Sendable {

    // MARK: Identity

    /// Stable UUID of the originating ``SpatialPinV1``.
    public let pinId: String

    /// Object type raw value (e.g. `"boiler"`, `"hotWaterCylinder"`).
    public let type: String

    /// Service object category raw value (e.g. `"heat_source"`, `"emitters"`).
    public let objectCategory: String

    /// Engineer-assigned label for this pin.
    public let label: String?

    // MARK: Location

    /// UUID of the room this pin is associated with.
    public let roomId: String

    /// Location context within the room (e.g. `"wall"`, `"floor"`).
    public let locationContext: String

    // MARK: Identity resolution

    /// How the identity of this equipment item was established.
    ///
    /// One of:
    ///   - `"catalogue_template"` — resolved from a catalogue template.
    ///   - `"engineer_entered"` — manually entered by the engineer.
    ///   - `"unknown"` — no useful identity; shown as "needs identification".
    public let identitySource: String

    /// Catalogue template ID when `identitySource == "catalogue_template"`.
    ///
    /// Atlas Mind resolves the full label from its catalogue.
    /// This field carries the raw template ID as a placeholder until Mind resolves it.
    public let catalogueLabel: String?

    /// The selected catalogue template ID.
    public let selectedTemplateId: String?

    /// Engineer-entered appliance details when `identitySource == "engineer_entered"`.
    ///
    /// All manual fields (manufacturer, model, dimensions, flue orientation, notes)
    /// survive the Scan → Mind handoff intact.
    public let manualEntry: SpatialPinManualEntryV1?

    // MARK: Anchor confidence

    /// Human-readable anchor confidence summary.
    ///
    /// One of:
    ///   - `"room note only — not spatially anchored"` (`screen_only`)
    ///   - `"estimated position"` (`raycast_estimated` / `estimated` / `low`)
    ///   - `"spatially anchored"` (`world_locked` / `high` / `medium`)
    public let anchorSummary: String

    /// Raw anchor confidence string from the originating pin.
    public let anchorConfidenceRaw: String

    /// `true` when the pin has a confirmed strong spatial placement.
    ///
    /// Rules:
    ///   - Confidence must be `world_locked` or `high`.
    ///   - Review status must be `confirmed`.
    public let isSpatiallyAnchored: Bool

    // MARK: Review state

    /// Raw review status string from the originating pin.
    public let reviewStatusRaw: String

    /// `true` when the pin qualifies as customer-proof evidence.
    ///
    /// Customer proof requires:
    ///   - `reviewStatus == "confirmed"`
    ///   - `anchorConfidence != "screen_only"`
    public let isConfirmedEvidence: Bool

    // MARK: Provenance

    /// Capture provenance raw value.
    public let provenance: String

    /// UUID of the associated capture point.
    public let capturePointId: String?

    /// UUID of a linked evidence photo.
    public let linkedPhotoId: String?

    public init(
        pinId: String,
        type: String,
        objectCategory: String,
        label: String?,
        roomId: String,
        locationContext: String,
        identitySource: String,
        catalogueLabel: String?,
        selectedTemplateId: String?,
        manualEntry: SpatialPinManualEntryV1?,
        anchorSummary: String,
        anchorConfidenceRaw: String,
        isSpatiallyAnchored: Bool,
        reviewStatusRaw: String,
        isConfirmedEvidence: Bool,
        provenance: String,
        capturePointId: String?,
        linkedPhotoId: String?
    ) {
        self.pinId = pinId
        self.type = type
        self.objectCategory = objectCategory
        self.label = label
        self.roomId = roomId
        self.locationContext = locationContext
        self.identitySource = identitySource
        self.catalogueLabel = catalogueLabel
        self.selectedTemplateId = selectedTemplateId
        self.manualEntry = manualEntry
        self.anchorSummary = anchorSummary
        self.anchorConfidenceRaw = anchorConfidenceRaw
        self.isSpatiallyAnchored = isSpatiallyAnchored
        self.reviewStatusRaw = reviewStatusRaw
        self.isConfirmedEvidence = isConfirmedEvidence
        self.provenance = provenance
        self.capturePointId = capturePointId
        self.linkedPhotoId = linkedPhotoId
    }
}

// MARK: - EquipmentEvidenceGroupV1

/// A group of equipment pins classified by functional role.
public struct EquipmentEvidenceGroupV1: Codable, Sendable, Identifiable {

    /// Group identifier; matches ``PinObjectCategoryV1/rawValue``.
    public let category: PinObjectCategoryV1

    /// All pins classified into this group.
    public let pins: [EquipmentPinEvidenceV1]

    /// Count of customer-proof confirmed pins.
    public let confirmedCount: Int

    /// Count of pins awaiting engineer review.
    public let pendingCount: Int

    /// Count of pins with no useful identity.
    public let needsIdentificationCount: Int

    public var id: String { category.rawValue }

    public var displayName: String {
        switch category {
        case .heatSource:               return "Boiler / Heat Source"
        case .hotWaterStorage:          return "Cylinder / Hot Water Storage"
        case .flueExternal:             return "Flue / External"
        case .emitters:                 return "Emitters"
        case .heatingSystemComponents:  return "Heating Components"
        }
    }

    public var systemImage: String {
        switch category {
        case .heatSource:               return "flame.fill"
        case .hotWaterStorage:          return "cylinder.split.1x2.fill"
        case .flueExternal:             return "arrow.up.to.line"
        case .emitters:                 return "thermometer.medium"
        case .heatingSystemComponents:  return "gearshape.2.fill"
        }
    }

    public init(category: PinObjectCategoryV1, pins: [EquipmentPinEvidenceV1]) {
        self.category = category
        self.pins = pins
        self.confirmedCount = pins.filter(\.isConfirmedEvidence).count
        self.pendingCount = pins.filter {
            $0.reviewStatusRaw == SpatialPinReviewStatus.needsReview.rawValue
        }.count
        self.needsIdentificationCount = pins.filter { $0.identitySource == "unknown" }.count
    }
}

// MARK: - EquipmentEvidenceGroupsV1

/// The five equipment evidence groups derived from a session's spatial pins.
///
/// Built by ``EquipmentEvidenceMapper`` and carried in ``ScanToMindHandoffV1``.
/// Atlas Mind uses this to display structured equipment evidence cards.
public struct EquipmentEvidenceGroupsV1: Codable, Sendable {

    public let visitId: String
    public let heatSourceEvidence: EquipmentEvidenceGroupV1
    public let hotWaterStorageEvidence: EquipmentEvidenceGroupV1
    public let flueExternalEvidence: EquipmentEvidenceGroupV1
    public let emitterEvidence: EquipmentEvidenceGroupV1
    public let heatingComponentEvidence: EquipmentEvidenceGroupV1

    public init(
        visitId: String,
        heatSourceEvidence: EquipmentEvidenceGroupV1,
        hotWaterStorageEvidence: EquipmentEvidenceGroupV1,
        flueExternalEvidence: EquipmentEvidenceGroupV1,
        emitterEvidence: EquipmentEvidenceGroupV1,
        heatingComponentEvidence: EquipmentEvidenceGroupV1
    ) {
        self.visitId = visitId
        self.heatSourceEvidence = heatSourceEvidence
        self.hotWaterStorageEvidence = hotWaterStorageEvidence
        self.flueExternalEvidence = flueExternalEvidence
        self.emitterEvidence = emitterEvidence
        self.heatingComponentEvidence = heatingComponentEvidence
    }

    /// All five groups in display order.
    public var allGroups: [EquipmentEvidenceGroupV1] {
        [heatSourceEvidence, hotWaterStorageEvidence, flueExternalEvidence,
         emitterEvidence, heatingComponentEvidence]
    }

    /// Total confirmed-evidence count across all groups.
    public var totalConfirmedCount: Int {
        allGroups.reduce(0) { $0 + $1.confirmedCount }
    }

    /// `true` when at least one heat-source pin has been confirmed.
    public var hasAnyConfirmedHeatSource: Bool {
        heatSourceEvidence.confirmedCount > 0
    }

    /// IDs of all `screen_only` pins — must not appear as spatial proof.
    public var screenOnlyPinIds: [String] {
        allGroups.flatMap(\.pins)
            .filter { $0.anchorConfidenceRaw == SpatialPinAnchorConfidence.screenOnly.rawValue }
            .map(\.pinId)
    }

    /// Returns an empty groups object for the given visitId.
    public static func empty(visitId: String) -> EquipmentEvidenceGroupsV1 {
        EquipmentEvidenceGroupsV1(
            visitId: visitId,
            heatSourceEvidence:       EquipmentEvidenceGroupV1(category: .heatSource,              pins: []),
            hotWaterStorageEvidence:  EquipmentEvidenceGroupV1(category: .hotWaterStorage,          pins: []),
            flueExternalEvidence:     EquipmentEvidenceGroupV1(category: .flueExternal,             pins: []),
            emitterEvidence:          EquipmentEvidenceGroupV1(category: .emitters,                 pins: []),
            heatingComponentEvidence: EquipmentEvidenceGroupV1(category: .heatingSystemComponents,  pins: [])
        )
    }
}

// MARK: - EquipmentEvidenceMapper

/// Maps ``SpatialPinV1`` records from a session into structured equipment evidence groups.
///
/// Classification rules:
///   - Pins are grouped by ``PinObjectCategoryV1`` (already encodes the 5-group taxonomy).
///   - Identity resolves to catalogue template, engineer-entered, or unknown.
///   - ``SpatialPinAnchorConfidence/screenOnly`` pins are room notes — not spatial proof.
///   - ``SpatialPinAnchorConfidence/worldLocked`` or `high` + `confirmed` → spatially anchored.
///   - Only `confirmed` + non-`screenOnly` pins are customer-proof evidence.
///   - All ``SpatialPinManualEntryV1`` fields survive the Scan → Mind boundary.
public enum EquipmentEvidenceMapper {

    // MARK: - Public API

    /// Builds ``EquipmentEvidenceGroupsV1`` from a session's room list.
    ///
    /// Extracts all pinned objects from every room, classifies them by
    /// ``PinObjectCategoryV1``, and applies identity and anchor-confidence rules.
    public static func buildGroups(
        from rooms: [RoomCaptureV2],
        photos: [PhotoEvidenceV1] = [],
        visitId: String
    ) -> EquipmentEvidenceGroupsV1 {
        var heatSource:      [EquipmentPinEvidenceV1] = []
        var hotWaterStorage: [EquipmentPinEvidenceV1] = []
        var flueExternal:    [EquipmentPinEvidenceV1] = []
        var emitter:         [EquipmentPinEvidenceV1] = []
        var component:       [EquipmentPinEvidenceV1] = []

        for room in rooms {
            for pin in room.pinnedObjects {
                let linkedPhotoId = photos
                    .first(where: { $0.linkedObjectId == pin.id })?
                    .id.uuidString
                let evidence = makeEvidence(from: pin, linkedPhotoId: linkedPhotoId)
                switch pin.objectCategory {
                case .heatSource:               heatSource.append(evidence)
                case .hotWaterStorage:          hotWaterStorage.append(evidence)
                case .flueExternal:             flueExternal.append(evidence)
                case .emitters:                 emitter.append(evidence)
                case .heatingSystemComponents:  component.append(evidence)
                }
            }
        }

        return EquipmentEvidenceGroupsV1(
            visitId: visitId,
            heatSourceEvidence:       EquipmentEvidenceGroupV1(category: .heatSource,              pins: heatSource),
            hotWaterStorageEvidence:  EquipmentEvidenceGroupV1(category: .hotWaterStorage,          pins: hotWaterStorage),
            flueExternalEvidence:     EquipmentEvidenceGroupV1(category: .flueExternal,             pins: flueExternal),
            emitterEvidence:          EquipmentEvidenceGroupV1(category: .emitters,                 pins: emitter),
            heatingComponentEvidence: EquipmentEvidenceGroupV1(category: .heatingSystemComponents,  pins: component)
        )
    }

    // MARK: - Evidence builder

    static func makeEvidence(
        from pin: SpatialPinV1,
        linkedPhotoId: String?
    ) -> EquipmentPinEvidenceV1 {
        let (source, catLabel) = resolveIdentity(pin)
        let confidence = pin.anchorConfidence
        let anchor = anchorSummary(for: confidence)
        let spatiallyAnchored = isSpatiallyAnchored(confidence: confidence, reviewStatus: pin.reviewStatus)
        let confirmedEvidence = isConfirmedEvidence(reviewStatus: pin.reviewStatus, anchorConfidence: confidence)

        return EquipmentPinEvidenceV1(
            pinId: pin.id.uuidString,
            type: pin.objectType.rawValue,
            objectCategory: pin.objectCategory.rawValue,
            label: pin.label,
            roomId: pin.roomId.uuidString,
            locationContext: pin.locationContext.rawValue,
            identitySource: source,
            catalogueLabel: catLabel,
            selectedTemplateId: pin.selectedTemplateId,
            manualEntry: pin.manualEntry,
            anchorSummary: anchor,
            anchorConfidenceRaw: confidence.rawValue,
            isSpatiallyAnchored: spatiallyAnchored,
            reviewStatusRaw: pin.reviewStatus.rawValue,
            isConfirmedEvidence: confirmedEvidence,
            provenance: pin.provenance.rawValue,
            capturePointId: pin.capturePointId?.uuidString,
            linkedPhotoId: linkedPhotoId
        )
    }

    // MARK: - Identity resolution

    /// Returns `(identitySource, catalogueLabel)` for a pin.
    ///
    /// Rules:
    ///   - `selectedTemplateId` present → catalogue template; ID serves as label placeholder.
    ///   - `manualEntry` with manufacturer or model → engineer-entered.
    ///   - Otherwise → unknown / needs identification.
    static func resolveIdentity(_ pin: SpatialPinV1) -> (String, String?) {
        if let templateId = pin.selectedTemplateId, !templateId.isEmpty {
            return ("catalogue_template", templateId)
        }
        if let entry = pin.manualEntry,
           entry.manufacturer != nil || entry.model != nil {
            return ("engineer_entered", nil)
        }
        return ("unknown", nil)
    }

    // MARK: - Anchor confidence

    /// Returns a human-readable anchor confidence summary.
    ///
    /// Maps:
    ///   - ``SpatialPinAnchorConfidence/screenOnly``
    ///     → `"room note only — not spatially anchored"`
    ///   - ``SpatialPinAnchorConfidence/raycastEstimated``,
    ///     `estimated`, `low`
    ///     → `"estimated position"`
    ///   - ``SpatialPinAnchorConfidence/worldLocked``, `high`, `medium`
    ///     → `"spatially anchored"`
    static func anchorSummary(for confidence: SpatialPinAnchorConfidence) -> String {
        switch confidence {
        case .screenOnly:
            return "room note only — not spatially anchored"
        case .raycastEstimated, .estimated, .low:
            return "estimated position"
        case .worldLocked, .high, .medium:
            return "spatially anchored"
        }
    }

    /// Returns `true` when the pin has a confirmed strong spatial placement.
    ///
    /// Rules:
    ///   - Confidence must be ``SpatialPinAnchorConfidence/worldLocked`` or `high`.
    ///   - Review status must be ``SpatialPinReviewStatus/confirmed``.
    static func isSpatiallyAnchored(
        confidence: SpatialPinAnchorConfidence,
        reviewStatus: SpatialPinReviewStatus
    ) -> Bool {
        let strongAnchor = confidence == .worldLocked || confidence == .high
        return strongAnchor && reviewStatus == .confirmed
    }

    /// Returns `true` when the pin qualifies as customer-proof evidence.
    ///
    /// Customer proof requires:
    ///   - `reviewStatus == .confirmed`
    ///   - `anchorConfidence != .screenOnly`
    static func isConfirmedEvidence(
        reviewStatus: SpatialPinReviewStatus,
        anchorConfidence: SpatialPinAnchorConfidence
    ) -> Bool {
        reviewStatus == .confirmed && anchorConfidence != .screenOnly
    }
}
