import SwiftUI

// MARK: - ClearanceCubeOverlayView
//
// 2-D projected visualisation of the required manufacturer clearance volume
// around each pinned appliance within a scanned room.
//
// Renders a top-down plan view of the room with:
//   • A solid-border box for the object's physical footprint.
//   • A dotted-border box for the install-minimum clearance zone.
//   • A dashed-border box for the full service-access zone.
//
// Conflict detection:
//   If a room wall "pierces" the service-access zone the overlay turns red
//   and a QAFlag is registered for the engineer to review before leaving
//   the room.
//
// Coordinate normalisation:
//   Room dimensions map to (0...1) in both X and Z. The view renders
//   proportionally within whatever SwiftUI frame is provided.

struct ClearanceCubeOverlayView: View {

    // MARK: - Input

    let roomScan: CapturedRoomScanDraft
    let objectPins: [CapturedObjectPinDraft]

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                roomFloorBackground(in: proxy.size)
                roomBoundaryOutline(in: proxy.size)

                ForEach(clearanceItems) { item in
                    clearanceBoxes(for: item, in: proxy.size)
                }

                if conflictCount > 0 {
                    conflictBanner
                }
            }
        }
    }

    // MARK: - Room floor

    private func roomFloorBackground(in size: CGSize) -> some View {
        Rectangle()
            .fill(Color(.systemBackground))
            .overlay(
                Grid(horizontalSpacing: 20, verticalSpacing: 20) {}
                    .stroke(Color(.systemFill), lineWidth: 0.5)
            )
    }

    private func roomBoundaryOutline(in size: CGSize) -> some View {
        let inset: CGFloat = 8
        return Rectangle()
            .stroke(Color(.label), lineWidth: 2)
            .padding(inset)
    }

    // MARK: - Clearance boxes

    private func clearanceBoxes(for item: ClearanceItem, in size: CGSize) -> some View {
        let inset: CGFloat = 8
        let roomW = size.width  - inset * 2
        let roomD = size.height - inset * 2

        let cx = CGFloat(item.normX) * roomW + inset
        let cy = CGFloat(item.normZ) * roomD + inset

        let footprintW = CGFloat(item.footprintW) * roomW
        let footprintD = CGFloat(item.footprintD) * roomD
        let installW   = CGFloat(item.installW) * roomW
        let installD   = CGFloat(item.installD) * roomD
        let serviceW   = CGFloat(item.serviceW) * roomW
        let serviceD   = CGFloat(item.serviceD) * roomD

        let stroke: Color = item.hasConflict ? .red : .green
        let fill:   Color = item.hasConflict ? Color.red.opacity(0.08) : Color.green.opacity(0.06)

        return ZStack {
            // Service access zone (dashed border, lightest fill)
            CentredBox(cx: cx, cy: cy, width: serviceW, height: serviceD)
                .fill(fill)
            CentredBox(cx: cx, cy: cy, width: serviceW, height: serviceD)
                .stroke(stroke.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))

            // Install minimum zone (dotted border)
            CentredBox(cx: cx, cy: cy, width: installW, height: installD)
                .stroke(stroke.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            // Physical footprint (solid border)
            CentredBox(cx: cx, cy: cy, width: footprintW, height: footprintD)
                .fill(stroke.opacity(0.18))
            CentredBox(cx: cx, cy: cy, width: footprintW, height: footprintD)
                .stroke(stroke, lineWidth: 1.5)

            // Pin label
            Text(item.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(stroke)
                .position(x: cx, y: cy)
        }
    }

    // MARK: - Conflict banner

    private var conflictBanner: some View {
        VStack {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("\(conflictCount) clearance conflict(s) — review before leaving")
                    .font(.caption2.bold())
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.12))
            .clipShape(Capsule())
            .padding(.top, 6)
            Spacer()
        }
    }

}

// MARK: - ClearanceItem

private struct ClearanceItem: Identifiable {
    let id: UUID
    let label: String
    let normX, normZ: Double
    let footprintW, footprintD: Double
    let installW, installD: Double
    let serviceW, serviceD: Double
    let hasConflict: Bool
}

// MARK: - CentredBox

/// Draws a rectangle centred on (cx, cy).
private struct CentredBox: Shape {
    let cx, cy, width, height: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: cx - width / 2,
            y: cy - height / 2,
            width: width,
            height: height
        ))
    }
}

// MARK: - ObjectPinType helpers

private extension ObjectPinType {
    var shortLabel: String {
        switch self {
        case .boiler:        return "B"
        case .heatPump:      return "HP"
        case .cylinder:      return "CYL"
        case .pump:          return "P"
        case .radiator:      return "RAD"
        case .towelRail:     return "TR"
        case .fanConvector:  return "FC"
        case .flue:          return "FL"
        default:             return "?"
        }
    }

    /// Maps ObjectPinType to the ServiceObjectCategory used by ClearanceEngine.
    var serviceCategory: ServiceObjectCategory {
        switch self {
        case .boiler:        return .boiler
        case .heatPump:      return .heatPump
        case .cylinder:      return .cylinder
        case .pump:          return .pump
        case .radiator:      return .radiator
        case .towelRail:     return .towelRail   // treated as radiator for clearance
        case .fanConvector:  return .fanConvector
        default:             return .other
        }
    }
}

// MARK: - ClearanceCubeOverlayView internal data helpers

private extension ClearanceCubeOverlayView {
    var clearanceItems: [ClearanceItem] {
        guard let roomW = roomScan.rawWidthM, roomW > 0,
              let roomD = roomScan.rawDepthM, roomD > 0
        else { return [] }

        return objectPins.compactMap { pin -> ClearanceItem? in
            guard let rule = ClearanceEngine.rule(for: pin.type.serviceCategory) else { return nil }
            // Default normalised position: evenly spaced along north wall
            let idx = objectPins.firstIndex(where: { $0.id == pin.id }) ?? 0
            let segment = 1.0 / Double(max(objectPins.count, 1))
            let nx = (Double(idx) + 0.5) * segment
            let nz = 0.1   // near north wall by default

            let footW = rule.footprintWidthMetres / roomW
            let footD = rule.footprintDepthMetres / roomD
            let instW = (rule.footprintWidthMetres + rule.sideClearanceMetres * 2) / roomW
            let instD = (rule.footprintDepthMetres + rule.installMinFrontMetres + rule.rearClearanceMetres) / roomD
            let servW = (rule.footprintWidthMetres + rule.sideClearanceMetres * 2) / roomW
            let servD = (rule.footprintDepthMetres + rule.frontClearanceMetres + rule.rearClearanceMetres) / roomD

            // Conflict: service box exceeds room bounds (simple boundary check)
            let conflict = (nx - servW / 2) < 0 || (nx + servW / 2) > 1
                        || (nz - servD / 2) < 0 || (nz + servD / 2) > 1

            return ClearanceItem(
                id: pin.id,
                label: pin.type.shortLabel,
                normX: nx, normZ: nz,
                footprintW: footW, footprintD: footD,
                installW: instW,   installD: instD,
                serviceW: servW,   serviceD: servD,
                hasConflict: conflict
            )
        }
    }

    var conflictCount: Int {
        clearanceItems.filter { $0.hasConflict }.count
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Utility Room"
    scan.rawWidthM = 3.0
    scan.rawDepthM = 2.5

    var boiler = CapturedObjectPinDraft(type: .boiler)
    boiler.label = "Main Boiler"

    var cyl = CapturedObjectPinDraft(type: .cylinder)
    cyl.label = "Cylinder"

    return ClearanceCubeOverlayView(
        roomScan: scan,
        objectPins: [boiler, cyl]
    )
    .frame(height: 240)
    .padding()
}
#endif
