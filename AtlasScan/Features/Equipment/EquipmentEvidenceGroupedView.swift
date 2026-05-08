/// EquipmentEvidenceGroupedView — Displays the five equipment evidence groups
/// as structured cards for the engineer before handing off to Atlas Mind.
///
/// Shows:
///   - Identity source: catalogue template / manual entry / needs identification
///   - Anchor confidence: spatially anchored / estimated / room note only
///   - Review status: confirmed / pending
///   - Manual entry details where available
///   - Linked photo indicator
///
/// Customer proof rules are enforced at display:
///   - screen_only pins are labelled as room notes and excluded from spatial proof.
///   - Only confirmed + non-screen-only pins are marked as customer-proof evidence.

import SwiftUI
import AtlasScanCore

// MARK: - EquipmentEvidenceGroupedView

struct EquipmentEvidenceGroupedView: View {
    let groups: EquipmentEvidenceGroupsV1

    var body: some View {
        List {
            summarySection
            ForEach(groups.allGroups) { group in
                groupSection(group)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Equipment Evidence")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary section

    private var summarySection: some View {
        Section {
            HStack(spacing: 0) {
                summaryBadge(
                    value: groups.totalConfirmedCount,
                    label: "Confirmed",
                    color: .green,
                    symbol: "checkmark.circle.fill"
                )
                summaryBadge(
                    value: groups.screenOnlyPinIds.count,
                    label: "Room note only",
                    color: .orange,
                    symbol: "mappin.slash"
                )
                summaryBadge(
                    value: groups.allGroups.reduce(0) { $0 + $1.needsIdentificationCount },
                    label: "Needs ID",
                    color: .secondary,
                    symbol: "questionmark.circle"
                )
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Only confirmed, non-screen-only pins appear as customer-proof evidence. Screen-only pins are room notes.")
                .font(.caption2)
        }
    }

    private func summaryBadge(value: Int, label: String, color: Color, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.title2)
            Text("\(value)")
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Group sections

    private func groupSection(_ group: EquipmentEvidenceGroupV1) -> some View {
        Section {
            if group.pins.isEmpty {
                Label {
                    Text("No \(group.displayName.lowercased()) pins captured")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: group.systemImage)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 2)
            } else {
                ForEach(group.pins, id: \.pinId) { pin in
                    EquipmentEvidencePinRow(pin: pin)
                }
            }
        } header: {
            Label(group.displayName, systemImage: group.systemImage)
        } footer: {
            if !group.pins.isEmpty {
                let pending = group.pins.count - group.confirmedCount
                Text(pending > 0
                     ? "\(group.confirmedCount) confirmed · \(pending) pending"
                     : "\(group.confirmedCount) confirmed")
                    .font(.caption2)
            }
        }
    }
}

// MARK: - EquipmentEvidencePinRow

private struct EquipmentEvidencePinRow: View {
    let pin: EquipmentPinEvidenceV1

    var body: some View {
        HStack(spacing: 12) {
            confidenceIndicator
            VStack(alignment: .leading, spacing: 4) {
                Text(pinTitle)
                    .font(.subheadline)
                HStack(spacing: 4) {
                    identityBadge
                    anchorBadge
                    reviewBadge
                }
                if let entry = pin.manualEntry {
                    manualEntryDetails(entry)
                }
            }
            Spacer(minLength: 0)
            if pin.linkedPhotoId != nil {
                Image(systemName: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Confidence indicator

    private var confidenceIndicator: some View {
        ZStack {
            Circle()
                .fill(anchorColor.opacity(0.15))
                .frame(width: 34, height: 34)
            Image(systemName: anchorSymbol)
                .font(.caption.bold())
                .foregroundStyle(anchorColor)
        }
    }

    // MARK: Title

    private var pinTitle: String {
        if let label = pin.label, !label.isEmpty { return label }
        return pin.type
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    // MARK: Badges

    @ViewBuilder
    private var identityBadge: some View {
        switch pin.identitySource {
        case "catalogue_template":
            pillBadge("Catalogue", color: .blue, symbol: "list.bullet.clipboard")
        case "engineer_entered":
            pillBadge("Manual", color: .indigo, symbol: "pencil")
        default:
            pillBadge("Needs ID", color: .secondary, symbol: "questionmark.circle")
        }
    }

    @ViewBuilder
    private var anchorBadge: some View {
        if pin.anchorConfidenceRaw == SpatialPinAnchorConfidence.screenOnly.rawValue {
            pillBadge("Room note", color: .orange, symbol: "mappin.slash")
        } else if pin.isSpatiallyAnchored {
            pillBadge("Anchored", color: .green, symbol: "location.fill")
        } else {
            pillBadge("Estimated", color: .secondary, symbol: "location")
        }
    }

    @ViewBuilder
    private var reviewBadge: some View {
        if pin.reviewStatusRaw == SpatialPinReviewStatus.confirmed.rawValue {
            pillBadge("Confirmed", color: .green, symbol: "checkmark.circle.fill")
        } else {
            pillBadge("Pending", color: .orange, symbol: "clock.fill")
        }
    }

    @ViewBuilder
    private func manualEntryDetails(_ entry: SpatialPinManualEntryV1) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let make = entry.manufacturer {
                Text(make).font(.caption).foregroundStyle(.secondary)
            }
            if let model = entry.model {
                Text(model).font(.caption).foregroundStyle(.secondary)
            }
            if let w = entry.widthMm, let h = entry.heightMm {
                Text("\(w) mm × \(h) mm")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let orientation = entry.flueOrientation {
                Text("Flue: \(orientation)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: Helpers

    private func pillBadge(_ label: String, color: Color, symbol: String) -> some View {
        Label(label, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var anchorColor: Color {
        switch pin.anchorConfidenceRaw {
        case SpatialPinAnchorConfidence.screenOnly.rawValue:
            return .orange
        case SpatialPinAnchorConfidence.worldLocked.rawValue,
             SpatialPinAnchorConfidence.high.rawValue,
             SpatialPinAnchorConfidence.medium.rawValue:
            return .green
        default:
            return .secondary
        }
    }

    private var anchorSymbol: String {
        switch pin.anchorConfidenceRaw {
        case SpatialPinAnchorConfidence.screenOnly.rawValue:
            return "mappin.slash"
        case SpatialPinAnchorConfidence.worldLocked.rawValue:
            return "location.fill"
        default:
            return "location"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        EquipmentEvidenceGroupedView(groups: {
            let roomId = UUID()
            let boilerPin = SpatialPinV1(
                roomId: roomId,
                positionX: 1.5, positionY: 0.8, positionZ: -2.0,
                objectType: .boiler,
                label: "Combi boiler",
                objectCategory: .heatSource,
                manualEntry: SpatialPinManualEntryV1(
                    manufacturer: "Worcester Bosch",
                    model: "Greenstar 30i",
                    widthMm: 440, heightMm: 700, depthMm: 330,
                    flueOrientation: "rear"
                ),
                anchorConfidence: .worldLocked,
                reviewStatus: .confirmed,
                provenance: .manualCapture
            )
            let cylinderPin = SpatialPinV1(
                roomId: roomId,
                positionX: 0.5, positionY: 0.5, positionZ: -1.0,
                objectType: .hotWaterCylinder,
                objectCategory: .hotWaterStorage,
                anchorConfidence: .screenOnly,
                reviewStatus: .needsReview,
                provenance: .manualCapture
            )
            let fluePin = SpatialPinV1(
                roomId: roomId,
                positionX: 2.0, positionY: 2.0, positionZ: 0.0,
                objectType: .flueTerminal,
                objectCategory: .flueExternal,
                selectedTemplateId: "template-flue-horizontal-100mm",
                anchorConfidence: .raycastEstimated,
                reviewStatus: .needsReview,
                provenance: .manualCapture
            )
            var room = RoomCaptureV2(id: roomId, displayName: "Kitchen")
            room.pinnedObjects = [boilerPin, cylinderPin, fluePin]
            return EquipmentEvidenceMapper.buildGroups(
                from: [room],
                visitId: UUID().uuidString
            )
        }())
    }
}
#endif
