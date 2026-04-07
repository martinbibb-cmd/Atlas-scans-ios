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
// Intrusion regions (where clearance zones are blocked by a wall) are shown with
// a strong red fill and diagonal hatch, making it immediately clear which side fails.
//
// A thin room-boundary outline anchors the geometry so intrusion areas are
// visually legible even when the clearance zone extends only slightly outside.
//
// Colour follows ClearanceStatus: .clear → green / .warning → orange / .conflict → red.
// A legend at the bottom-left identifies each layer.
// An issue badge at the top-right shows the count of detected clearance issues.
// Tapping the badge opens a detail sheet listing every issue with its direction and severity.
//
// Accessibility: colour is never the sole signal — stroke patterns differ per layer,
// the badge icon changes with severity, and status text always states pass / tight / blocked.
//
// Used by SessionCaptureView to provide the primary visual signal for the
// selected object's clearance state, with the text summary as secondary support.

struct ClearanceOverlayView: View {

    let result: ClearanceResult
    let object: TaggedObject
    /// Other tagged objects in the same room; used by the issue sheet to resolve
    /// `.object(UUID)` source references to human-readable names.
    var otherObjects: [TaggedObject] = []

    @State private var showingIssueSheet = false

    // MARK: - Layout constants

    /// Aspect ratio used when the service-access zone has zero area.
    private static let defaultAspectRatio: CGFloat = 1.5

    /// Lower bound for the displayed aspect ratio (prevents very tall narrow panels).
    private static let minAspectRatio: CGFloat = 0.5

    /// Upper bound for the displayed aspect ratio (prevents very wide shallow panels).
    private static let maxAspectRatio: CGFloat = 3.0

    /// Fractional padding added around the service-access zone on each side,
    /// so the outermost layer has breathing room and doesn't touch the panel edge.
    private static let canvasPaddingRatio: Double = 0.12

    /// Spacing between diagonal hatch lines in the intrusion / conflict zone (points).
    private static let hatchSpacing: CGFloat = 6

    /// Stroke width for individual hatch lines in the intrusion / conflict zone.
    private static let hatchLineWidth: CGFloat = 0.8

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { ctx, size in
                draw(ctx: ctx, size: size)
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)

            if !result.issues.isEmpty {
                Button {
                    showingIssueSheet = true
                } label: {
                    issueBadge
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("\(result.issues.count) clearance issue\(result.issues.count == 1 ? "" : "s") — tap for details")
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
        .sheet(isPresented: $showingIssueSheet) {
            ClearanceIssueSheet(result: result, object: object, otherObjects: otherObjects)
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        "\(object.displayLabel) clearance zones — \(result.status.shortLabel)"
    }

    private var accessibilityValue: String {
        var parts = [result.status.displayMessage]
        if !result.issues.isEmpty {
            let directions = result.issues.compactMap(\.sideLabel).uniqued()
            if directions.isEmpty {
                parts.append("\(result.issues.count) issue\(result.issues.count == 1 ? "" : "s") detected")
            } else {
                parts.append("Issues on: \(directions.joined(separator: ", "))")
            }
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Aspect ratio

    /// Aspect ratio derived from the service-access zone, clamped to a sensible display range.
    private var aspectRatio: CGFloat {
        let w = result.serviceAccessRect.width
        let h = result.serviceAccessRect.height
        guard w > 0, h > 0 else { return Self.defaultAspectRatio }
        return max(Self.minAspectRatio, min(Self.maxAspectRatio, CGFloat(w / h)))
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
        let src = result.serviceAccessRect.insetBy(
            dx: -result.serviceAccessRect.width  * Self.canvasPaddingRatio,
            dy: -result.serviceAccessRect.height * Self.canvasPaddingRatio
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

        // Room boundary — thin outline showing the normalised 0…1 room extents.
        // Areas outside this boundary are where walls block the clearance zone.
        let roomScreen = toScreen(CGRect(x: 0, y: 0, width: 1, height: 1))
        ctx.stroke(
            Path(roomScreen),
            with: .color(.primary.opacity(0.22)),
            style: StrokeStyle(lineWidth: 1)
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

        // Layer 1 — physical footprint (solid border, strongest fill, slightly bolder stroke)
        let fpScreen = toScreen(result.footprintRect)
        ctx.fill(Path(fpScreen), with: .color(statusColor.opacity(0.25)))
        ctx.stroke(
            Path(fpScreen),
            with: .color(statusColor.opacity(0.85)),
            lineWidth: 2.5
        )

        // Intrusion regions — portions of the service-access zone that extend outside
        // the normalised room bounds [0,1]. Each region is where a wall blocks clearance.
        // Rendered above the halos with a strong red fill and diagonal hatch, so the
        // engineer immediately sees which side is the problem.
        let serviceIntrusionRects = intrusionRects(of: result.serviceAccessRect)
        for intrusionNorm in serviceIntrusionRects {
            let screenRect = toScreen(intrusionNorm)
            // Strong red fill — visually dominates the halo fill beneath.
            ctx.fill(Path(screenRect), with: .color(Color.red.opacity(0.40)))
            // Diagonal hatch — provides a non-colour signal for accessibility.
            drawHatch(into: ctx, rect: screenRect, color: Color.red.opacity(0.65))
        }

        // Object category icon centred on the footprint
        ctx.draw(
            Text(Image(systemName: object.category.symbolName))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor.opacity(0.9)),
            at: CGPoint(x: fpScreen.midX, y: fpScreen.midY)
        )
    }

    // MARK: - Intrusion geometry

    /// Returns the sub-rects of `rect` that fall outside the normalised room bounds [0,1].
    /// Each returned rect represents an area where a wall blocks the clearance zone.
    private func intrusionRects(
        of rect: CGRect,
        roomBounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> [CGRect] {
        var rects: [CGRect] = []

        // Left intrusion (extends past the left wall at x = 0)
        if rect.minX < roomBounds.minX {
            rects.append(CGRect(
                x: rect.minX, y: rect.minY,
                width: roomBounds.minX - rect.minX, height: rect.height
            ))
        }
        // Right intrusion (extends past the right wall at x = 1)
        if rect.maxX > roomBounds.maxX {
            rects.append(CGRect(
                x: roomBounds.maxX, y: rect.minY,
                width: rect.maxX - roomBounds.maxX, height: rect.height
            ))
        }
        // Top intrusion (extends past the top wall at y = 0) — x-clamped to avoid overlap
        if rect.minY < roomBounds.minY {
            let x0 = max(rect.minX, roomBounds.minX)
            let x1 = min(rect.maxX, roomBounds.maxX)
            if x1 > x0 {
                rects.append(CGRect(
                    x: x0, y: rect.minY,
                    width: x1 - x0, height: roomBounds.minY - rect.minY
                ))
            }
        }
        // Bottom intrusion (extends past the bottom wall at y = 1) — x-clamped
        if rect.maxY > roomBounds.maxY {
            let x0 = max(rect.minX, roomBounds.minX)
            let x1 = min(rect.maxX, roomBounds.maxX)
            if x1 > x0 {
                rects.append(CGRect(
                    x: x0, y: roomBounds.maxY,
                    width: x1 - x0, height: rect.maxY - roomBounds.maxY
                ))
            }
        }

        return rects
    }

    /// Draws 45° diagonal hatch lines clipped to `rect` on a copy of `ctx`.
    private func drawHatch(into ctx: GraphicsContext, rect: CGRect, color: Color) {
        guard rect.width > 0, rect.height > 0 else { return }
        var clipped = ctx
        clipped.clip(to: Path(rect))
        let reach = rect.width + rect.height   // enough to cover the diagonal
        var offset: CGFloat = -reach
        while offset < reach {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.maxY))
            clipped.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: Self.hatchLineWidth))
            offset += Self.hatchSpacing
        }
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
        let badgeIcon = hasConflict ? "xmark.circle.fill" : "exclamationmark.triangle.fill"
        return Label("\(count) issue\(count == 1 ? "" : "s")", systemImage: badgeIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12), in: Capsule())
    }

    // MARK: - Legend

    private var legendView: some View {
        VStack(alignment: .leading, spacing: 3) {
            legendRow(dash: [],       lineWidth: 2.5, label: "Footprint")
            legendRow(dash: [2, 2],   lineWidth: 1.5, label: "Install min.")
            legendRow(dash: [5, 3],   lineWidth: 1.5, label: "Service zone")
            if !intrusionRects(of: result.serviceAccessRect).isEmpty {
                legendIntrusionRow
            }
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

    /// Legend entry for the intrusion / conflict zone — uses a hatch swatch instead of a line.
    private var legendIntrusionRow: some View {
        HStack(spacing: 5) {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.red.opacity(0.35)))
                drawHatch(into: ctx, rect: CGRect(origin: .zero, size: size), color: Color.red.opacity(0.65))
            }
            .frame(width: 22, height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 2))

            Text("Wall conflict")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Array+uniqued (local helper)

private extension Array where Element: Hashable {
    /// Returns an array with duplicates removed, preserving order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - ClearanceIssueSheet

/// Detail sheet listing all clearance issues for a selected object.
/// Opened when the engineer taps the issue-count badge on ClearanceOverlayView.
struct ClearanceIssueSheet: View {

    let result: ClearanceResult
    let object: TaggedObject
    /// Other tagged objects in the same room, used to resolve `.object(UUID)` source
    /// references to human-readable names in the issue list.
    var otherObjects: [TaggedObject] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: result.status.symbolName)
                            .foregroundStyle(statusColor)
                        Text(result.status.displayMessage)
                            .font(.subheadline)
                            .foregroundStyle(statusColor)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Overall Status")
                }

                if result.issues.isEmpty {
                    Section {
                        Text("No issues detected.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(result.issues.indices, id: \.self) { i in
                            issueRow(result.issues[i])
                        }
                    } header: {
                        Text("\(result.issues.count) Issue\(result.issues.count == 1 ? "" : "s")")
                    }
                }

                if let note = result.confidenceNote {
                    Section {
                        Label(note, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Scan Confidence")
                    }
                }

                if let note = result.profileNote {
                    Section {
                        Label(note, systemImage: "ruler")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Appliance Guidance")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(object.displayLabel) — Clearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func issueRow(_ issue: ClearanceIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .conflict
                  ? "xmark.circle.fill"
                  : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .conflict ? .red : .orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                if let side = issue.sideLabel {
                    Text(side.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(issue.severity == .conflict ? Color.red : .orange)
                }
                Text(issue.message)
                    .font(.subheadline)
                if let sourceText = issue.sourceDescription(objectName: objectName(for: issue)) {
                    Text(sourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [issue.sideLabel.map { "\($0): " }, issue.message,
             issue.sourceDescription(objectName: objectName(for: issue))]
                .compactMap { $0 }
                .joined(separator: " — ")
        )
        .accessibilityValue(issue.severity == .conflict ? "Conflict" : "Warning")
    }

    /// Resolves the display name of the object referenced by an issue's source,
    /// returning `nil` for non-object sources or when the object cannot be found.
    private func objectName(for issue: ClearanceIssue) -> String? {
        guard case .object(let id) = issue.source else { return nil }
        return otherObjects.first(where: { $0.id == id })?.displayLabel
    }

    private var statusColor: Color {
        switch result.status {
        case .clear:    return .green
        case .warning:  return .orange
        case .conflict: return .red
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    // Object placed near the top wall (y = 0.1) so ClearanceEngine produces
    // a front-facing clearance result — good for demonstrating all three overlay layers.
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
