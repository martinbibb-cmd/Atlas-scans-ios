import SwiftUI
import CoreGraphics

// MARK: - ClearanceOverlayView
//
// Renders the three-layer clearance geometry for a selected object in
// normalised (0…1) room coordinates, as produced by ClearanceEngine.
//
// Visual layers (outermost → innermost):
//   • serviceAccessRect   — full service working space   (dashed border, lightest fill)
//   • installMinimumRect  — tightest installation space  (dotted border, medium fill)
//   • footprintRect       — physical installed envelope  (solid border, strongest fill)
//
// Colour follows ClearanceStatus: .clear → green / .warning → orange / .conflict → red.
// A legend at the bottom-left identifies each layer.
// An issue badge at the top-right shows the count of detected clearance issues.
//
// Used by SessionCaptureView to provide the primary visual signal for the
// selected object's clearance state, with the text summary as secondary support.

struct ClearanceOverlayView: View {

    let result: ClearanceResult
    let object: TaggedObject

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { ctx, size in
                draw(ctx: ctx, size: size)
            }

            if !result.issues.isEmpty {
                issueBadge
                    .padding(8)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
            legendView
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Aspect ratio

    /// Aspect ratio derived from the service-access zone, clamped to a sensible display range.
    private var aspectRatio: CGFloat {
        let w = result.serviceAccessRect.width
        let h = result.serviceAccessRect.height
        guard w > 0, h > 0 else { return 1.5 }
        return max(0.5, min(3.0, CGFloat(w / h)))
    }

    // MARK: - Status colour

    private var statusColor: Color {
        switch result.status {
        case .clear:    return .green
        case .warning:  return .orange
        case .conflict: return .red
        }
    }

    // MARK: - Canvas drawing

    private func draw(ctx: GraphicsContext, size: CGSize) {
        // Build a padded source rect so all three layers have breathing room.
        let padding = 0.12
        let src = result.serviceAccessRect.insetBy(
            dx: -result.serviceAccessRect.width  * padding,
            dy: -result.serviceAccessRect.height * padding
        )

        let scaleX = src.width  > 0 ? Double(size.width)  / src.width  : 1.0
        let scaleY = src.height > 0 ? Double(size.height) / src.height : 1.0

        func toScreen(_ r: CGRect) -> CGRect {
            CGRect(
                x: (r.minX - src.minX) * scaleX,
                y: (r.minY - src.minY) * scaleY,
                width:  r.width  * scaleX,
                height: r.height * scaleY
            )
        }

        // Background fill
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(.secondary.opacity(0.04))
        )

        // Layer 3 — service access zone (dashed border, very light fill)
        let svcScreen = toScreen(result.serviceAccessRect)
        ctx.fill(Path(svcScreen), with: .color(statusColor.opacity(0.07)))
        ctx.stroke(
            Path(svcScreen),
            with: .color(statusColor.opacity(0.40)),
            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
        )

        // Layer 2 — install minimum zone (dotted border, medium fill)
        let instScreen = toScreen(result.installMinimumRect)
        ctx.fill(Path(instScreen), with: .color(statusColor.opacity(0.12)))
        ctx.stroke(
            Path(instScreen),
            with: .color(statusColor.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])
        )

        // Layer 1 — physical footprint (solid border, strongest fill)
        let fpScreen = toScreen(result.footprintRect)
        ctx.fill(Path(fpScreen), with: .color(statusColor.opacity(0.20)))
        ctx.stroke(
            Path(fpScreen),
            with: .color(statusColor.opacity(0.85)),
            lineWidth: 2
        )

        // Object category icon centred on the footprint
        ctx.draw(
            Text(Image(systemName: object.category.symbolName))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor.opacity(0.9)),
            at: CGPoint(x: fpScreen.midX, y: fpScreen.midY)
        )
    }

    // MARK: - Issue badge

    private var issueBadge: some View {
        let count = result.issues.count
        let hasConflict = result.issues.contains {
            switch $0.severity {
            case .conflict: return true
            case .warning:  return false
            }
        }
        let badgeColor: Color = hasConflict ? .red : .orange
        return Label("\(count) issue\(count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12), in: Capsule())
    }

    // MARK: - Legend

    private var legendView: some View {
        VStack(alignment: .leading, spacing: 3) {
            legendRow(dash: [],       lineWidth: 2.0, label: "Footprint")
            legendRow(dash: [2, 2],   lineWidth: 1.5, label: "Install min.")
            legendRow(dash: [5, 3],   lineWidth: 1.5, label: "Service zone")
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func legendRow(dash: [CGFloat], lineWidth: CGFloat, label: String) -> some View {
        HStack(spacing: 5) {
            Canvas { ctx, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(
                    path,
                    with: .color(statusColor),
                    style: StrokeStyle(lineWidth: lineWidth, dash: dash)
                )
            }
            .frame(width: 22, height: 10)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    let obj = TaggedObject(
        roomID: UUID(),
        category: .boiler,
        normalizedPosition: NormalizedPoint2D(x: 0.5, y: 0.1)
    )
    let room = ScannedRoom(
        jobID: UUID(),
        name: "Kitchen",
        areaSquareMetres: 16
    )
    if let result = ClearanceEngine.evaluate(object: obj, in: room) {
        ClearanceOverlayView(result: result, object: obj)
            .padding()
    }
}
#endif
