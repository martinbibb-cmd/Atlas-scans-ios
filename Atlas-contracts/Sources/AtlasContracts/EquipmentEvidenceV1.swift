import Foundation

// MARK: - EquipmentEvidenceV1 (Atlas-contracts)
//
// Maps CapturedObjectPinV2 records into structured equipment evidence groups
// for consumption by Atlas Mind.
//
// Design rules:
//   • Pins are grouped by objectCategory (heat source, hot water storage,
//     flue/external, emitters, heating components).
//   • Identity is resolved as catalogue template, engineer-entered, or unknown.
//   • screen_only anchor confidence → room note only (not spatial proof).
//   • Only confirmed + non-screen-only pins qualify as customer-proof evidence.
//   • Manual entry fields survive the Scan → Mind boundary intact.
//   • The mapper is pure (no side effects) and testable without a running app.

// MARK: - EquipmentPinEvidenceV1

/// Evidence record for a single CapturedObjectPinV2, mapped into Mind-consumable form.
///
/// Carries identity resolution, anchor confidence assessment, and review state
/// for each equipment pin captured during a Scan visit.
public struct EquipmentPinEvidenceV1: Codable, Sendable {

    // MARK: Identity

    /// Stable UUID of the originating `CapturedObjectPinV2`.
    public let pinId: String

    /// Object type raw value (e.g. `"boiler"`, `"radiator"`, `"cylinder"`).
    public let type: String

    /// Service object category raw value (e.g. `"boiler"`, `"radiator_drop"`).
    public let objectCategory: String?

    /// Engineer-assigned label for this pin.
    public let label: String?

    // MARK: Location

    /// UUID of the room this pin is associated with.
    public let roomId: String?

    /// UUID of an external area when the pin was captured outside a room.
    public let externalAreaId: String?

    /// Location context within the room/area (e.g. `"wall"`, `"floor"`).
    public let locationContext: String?

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
    /// Atlas Mind resolves the full label from its own catalogue.
    /// This field carries the raw template ID as a placeholder.
    public let catalogueLabel: String?

    /// Catalogue item category when `identitySource == "catalogue_template"`.
    public let catalogueCategory: String?

    /// The selected catalogue template ID.
    public let selectedTemplateId: String?

    /// Engineer-entered appliance details when `identitySource == "engineer_entered"`.
    ///
    /// All manual fields survive the Scan → Mind handoff intact.
    public let manualEntry: CapturedObjectManualEntryV2?

    // MARK: Anchor confidence

    /// Human-readable anchor confidence summary.
    ///
    /// One of:
    ///   - `"room note only — not spatially anchored"` (screen_only)
    ///   - `"estimated position"` (raycast_estimated / inferred)
    ///   - `"spatially anchored"` (world_locked / manual with confirmation)
    ///   - `"position needs review"` (needs_review)
    ///   - `"position unknown"` (nil or unrecognised)
    public let anchorSummary: String

    /// Raw anchor confidence string from the originating pin.
    public let anchorConfidenceRaw: String?

    /// `true` when the pin has a confirmed world-locked or manual spatial placement.
    ///
    /// Rules:
    ///   - Confidence must be `world_locked`, `manual`, or `photo_linked`.
    ///   - `reviewStatus` must be `confirmed`.
    public let isSpatiallyAnchored: Bool

    // MARK: Review state

    /// Raw review status string from the originating pin (`"confirmed"`, `"pending"`, `"rejected"`).
    public let reviewStatusRaw: String?

    /// `true` when the pin can be used as customer-proof evidence.
    ///
    /// Customer proof requires:
    ///   - `reviewStatus == "confirmed"`
    ///   - `anchorConfidence != "screen_only"`
    public let isConfirmedEvidence: Bool

    // MARK: Provenance

    /// Capture provenance (`"manual_capture"`, `"room_scan_inference"`, etc.).
    public let provenance: String?

    /// UUID of the associated capture point.
    public let capturePointId: String?

    /// UUID of a linked evidence photo.
    public let linkedPhotoId: String?

    public init(
        pinId: String,
        type: String,
        objectCategory: String?,
        label: String?,
        roomId: String?,
        externalAreaId: String?,
        locationContext: String?,
        identitySource: String,
        catalogueLabel: String?,
        catalogueCategory: String?,
        selectedTemplateId: String?,
        manualEntry: CapturedObjectManualEntryV2?,
        anchorSummary: String,
        anchorConfidenceRaw: String?,
        isSpatiallyAnchored: Bool,
        reviewStatusRaw: String?,
        isConfirmedEvidence: Bool,
        provenance: String?,
        capturePointId: String?,
        linkedPhotoId: String?
    ) {
        self.pinId = pinId
        self.type = type
        self.objectCategory = objectCategory
        self.label = label
        self.roomId = roomId
        self.externalAreaId = externalAreaId
        self.locationContext = locationContext
        self.identitySource = identitySource
        self.catalogueLabel = catalogueLabel
        self.catalogueCategory = catalogueCategory
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
public struct EquipmentEvidenceGroupV1: Codable, Sendable {

    /// Group identifier key, matching the objectCategory values used for classification.
    ///
    /// One of: `"heat_source"`, `"hot_water_storage"`, `"flue_external"`,
    /// `"emitters"`, `"heating_system_components"`.
    public let group: String

    /// Human-readable display name for this group.
    public let displayName: String

    /// All pins classified into this group.
    public let pins: [EquipmentPinEvidenceV1]

    /// Count of customer-proof confirmed pins in this group.
    public let confirmedCount: Int

    /// Count of pins awaiting engineer review in this group.
    public let pendingCount: Int

    /// Count of pins where no useful identity could be established.
    public let needsIdentificationCount: Int

    public init(group: String, displayName: String, pins: [EquipmentPinEvidenceV1]) {
        self.group = group
        self.displayName = displayName
        self.pins = pins
        self.confirmedCount = pins.filter(\.isConfirmedEvidence).count
        self.pendingCount = pins.filter { $0.reviewStatusRaw == "pending" }.count
        self.needsIdentificationCount = pins.filter { $0.identitySource == "unknown" }.count
    }
}

// MARK: - EquipmentEvidenceGroupsV1

/// The five equipment evidence groups derived from a session's object pins.
///
/// Built by ``EquipmentEvidenceMapper/buildGroups(from:visitId:)`` and
/// carried in ``ScanToMindHandoffV1``.
///
/// Atlas Mind consumes this to replace the generic flat object-pin list with
/// structured equipment evidence cards.
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

    /// IDs of pins with `screen_only` anchor confidence.
    ///
    /// These pins must not appear as spatial proof in customer reports.
    public var screenOnlyPinIds: [String] {
        allGroups.flatMap(\.pins)
            .filter { $0.anchorConfidenceRaw == "screen_only" }
            .map(\.pinId)
    }

    /// Returns an empty groups object for the given visitId.
    public static func empty(visitId: String) -> EquipmentEvidenceGroupsV1 {
        EquipmentEvidenceGroupsV1(
            visitId: visitId,
            heatSourceEvidence:      EquipmentEvidenceGroupV1(group: "heat_source",               displayName: "Boiler / Heat Source",           pins: []),
            hotWaterStorageEvidence: EquipmentEvidenceGroupV1(group: "hot_water_storage",          displayName: "Cylinder / Hot Water Storage",    pins: []),
            flueExternalEvidence:    EquipmentEvidenceGroupV1(group: "flue_external",              displayName: "Flue / External",                 pins: []),
            emitterEvidence:         EquipmentEvidenceGroupV1(group: "emitters",                   displayName: "Emitters",                        pins: []),
            heatingComponentEvidence: EquipmentEvidenceGroupV1(group: "heating_system_components", displayName: "Heating Components",              pins: [])
        )
    }
}

// MARK: - EquipmentEvidenceMapper

/// Maps ``CapturedObjectPinV2`` records into structured equipment evidence groups.
///
/// Implements the Scan → Mind classification rules:
///   - Pins are grouped by `objectCategory` (with `type` as fallback).
///   - Identity is resolved as catalogue template, engineer-entered, or unknown.
///   - `screen_only` anchor confidence → non-spatial; cannot become customer proof.
///   - `world_locked` with `confirmed` review → spatially anchored.
///   - Only `confirmed` + non-`screen_only` pins qualify as customer-proof evidence.
///   - All manual-entry fields survive the Scan → Mind boundary.
public enum EquipmentEvidenceMapper {

    // MARK: - Public API

    /// Builds ``EquipmentEvidenceGroupsV1`` from a flat list of ``CapturedObjectPinV2``.
    public static func buildGroups(
        from pins: [CapturedObjectPinV2],
        visitId: String
    ) -> EquipmentEvidenceGroupsV1 {
        var heatSource:      [EquipmentPinEvidenceV1] = []
        var hotWaterStorage: [EquipmentPinEvidenceV1] = []
        var flueExternal:    [EquipmentPinEvidenceV1] = []
        var emitter:         [EquipmentPinEvidenceV1] = []
        var component:       [EquipmentPinEvidenceV1] = []

        for pin in pins {
            let evidence = makeEvidence(from: pin)
            switch classifyGroup(pin) {
            case "heat_source":               heatSource.append(evidence)
            case "hot_water_storage":         hotWaterStorage.append(evidence)
            case "flue_external":             flueExternal.append(evidence)
            case "emitters":                  emitter.append(evidence)
            case "heating_system_components": component.append(evidence)
            default:                          break
            }
        }

        return EquipmentEvidenceGroupsV1(
            visitId: visitId,
            heatSourceEvidence:      EquipmentEvidenceGroupV1(group: "heat_source",               displayName: "Boiler / Heat Source",           pins: heatSource),
            hotWaterStorageEvidence: EquipmentEvidenceGroupV1(group: "hot_water_storage",          displayName: "Cylinder / Hot Water Storage",    pins: hotWaterStorage),
            flueExternalEvidence:    EquipmentEvidenceGroupV1(group: "flue_external",              displayName: "Flue / External",                 pins: flueExternal),
            emitterEvidence:         EquipmentEvidenceGroupV1(group: "emitters",                   displayName: "Emitters",                        pins: emitter),
            heatingComponentEvidence: EquipmentEvidenceGroupV1(group: "heating_system_components", displayName: "Heating Components",              pins: component)
        )
    }

    // MARK: - Group classification

    /// Returns the evidence group key for a pin, or `nil` for uncategorised pins.
    ///
    /// Prefers `objectCategory` over `type` for classification, since
    /// `objectCategory` reflects the engineer's intentional grouping choice.
    static func classifyGroup(_ pin: CapturedObjectPinV2) -> String? {
        groupForKey(pin.objectCategory ?? pin.type)
    }

    private static func groupForKey(_ key: String) -> String? {
        switch key {
        case "boiler", "heat_pump":
            return "heat_source"
        case "cylinder", "thermal_store", "buffer_vessel", "hot_water_cylinder":
            return "hot_water_storage"
        case "flue", "likely_flue_route", "flue_terminal":
            return "flue_external"
        case "radiator", "radiator_drop", "towel_rail", "ufh_zone", "fan_convector":
            return "emitters"
        case "pump", "low_loss_header", "expansion_vessel", "manifold", "zone_valve",
             "thermostat", "programmer", "smart_controller", "thermostat_receiver":
            return "heating_system_components"
        // Mapped from PinObjectCategoryV1 raw values (used by V2 flow pins).
        case "heat_source":               return "heat_source"
        case "hot_water_storage":         return "hot_water_storage"
        case "flue_external":             return "flue_external"
        case "emitters":                  return "emitters"
        case "heating_system_components": return "heating_system_components"
        default:
            return nil
        }
    }

    // MARK: - Evidence builder

    static func makeEvidence(from pin: CapturedObjectPinV2) -> EquipmentPinEvidenceV1 {
        let (source, catLabel, catCategory) = resolveIdentity(pin)
        let anchor = anchorSummary(for: pin.anchorConfidence)
        let spatiallyAnchored = isSpatiallyAnchored(
            confidence: pin.anchorConfidence,
            reviewStatus: pin.reviewStatus
        )
        let confirmedEvidence = isConfirmedEvidence(
            reviewStatus: pin.reviewStatus,
            anchorConfidence: pin.anchorConfidence
        )

        return EquipmentPinEvidenceV1(
            pinId: pin.id,
            type: pin.type,
            objectCategory: pin.objectCategory,
            label: pin.label,
            roomId: pin.roomId,
            externalAreaId: pin.externalAreaId,
            locationContext: pin.locationContext,
            identitySource: source,
            catalogueLabel: catLabel,
            catalogueCategory: catCategory,
            selectedTemplateId: pin.selectedTemplateId,
            manualEntry: pin.manualEntry,
            anchorSummary: anchor,
            anchorConfidenceRaw: pin.anchorConfidence,
            isSpatiallyAnchored: spatiallyAnchored,
            reviewStatusRaw: pin.reviewStatus,
            isConfirmedEvidence: confirmedEvidence,
            provenance: pin.provenance,
            capturePointId: pin.capturePointId,
            linkedPhotoId: pin.linkedPhotoId
        )
    }

    // MARK: - Identity resolution

    /// Returns `(identitySource, catalogueLabel, catalogueCategory)` for a pin.
    ///
    /// Rules:
    ///   - `selectedTemplateId` present → catalogue template; ID serves as label placeholder.
    ///   - `manualEntry` with manufacturer or model → engineer-entered.
    ///   - Otherwise → unknown / needs identification.
    static func resolveIdentity(
        _ pin: CapturedObjectPinV2
    ) -> (String, String?, String?) {
        if let templateId = pin.selectedTemplateId, !templateId.isEmpty {
            return ("catalogue_template", templateId, pin.objectCategory)
        }
        if let entry = pin.manualEntry,
           entry.manufacturer != nil || entry.model != nil {
            return ("engineer_entered", nil, nil)
        }
        return ("unknown", nil, nil)
    }

    // MARK: - Anchor confidence

    /// Returns a human-readable anchor confidence summary.
    ///
    /// Maps:
    ///   - `"screen_only"`          → `"room note only — not spatially anchored"`
    ///   - `"raycast_estimated"`,
    ///     `"estimated"`, `"inferred"` → `"estimated position"`
    ///   - `"world_locked"`,
    ///     `"manual"`, `"photo_linked"` → `"spatially anchored"`
    ///   - `"needs_review"`          → `"position needs review"`
    ///   - `nil` or unknown          → `"position unknown"`
    static func anchorSummary(for confidence: String?) -> String {
        switch confidence {
        case "screen_only":
            return "room note only — not spatially anchored"
        case "raycast_estimated", "estimated", "inferred", "low":
            return "estimated position"
        case "world_locked", "manual", "photo_linked", "high", "medium":
            return "spatially anchored"
        case "needs_review":
            return "position needs review"
        default:
            return "position unknown"
        }
    }

    /// Returns `true` when the pin has a confirmed, strong spatial placement.
    ///
    /// Rules:
    ///   - Confidence must be `world_locked`, `manual`, or `photo_linked`.
    ///   - `reviewStatus` must be `"confirmed"`.
    static func isSpatiallyAnchored(confidence: String?, reviewStatus: String?) -> Bool {
        let strongAnchor = ["world_locked", "manual", "photo_linked"].contains(confidence ?? "")
        return strongAnchor && reviewStatus == "confirmed"
    }

    /// Returns `true` when the pin qualifies as customer-proof evidence.
    ///
    /// Customer proof requires:
    ///   - `reviewStatus == "confirmed"`
    ///   - `anchorConfidence != "screen_only"`
    static func isConfirmedEvidence(reviewStatus: String?, anchorConfidence: String?) -> Bool {
        reviewStatus == "confirmed" && anchorConfidence != "screen_only"
    }
}
