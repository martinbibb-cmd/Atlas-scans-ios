import SwiftUI
import simd
import AtlasScanCore

struct OffscreenPointerItemV1: Identifiable, Equatable {
    enum EvidenceType: String, Equatable {
        case objectPin
        case ghostAppliance
        case photo
        case voiceNote
        case note
        case measurement
    }

    let id: UUID
    let roomId: UUID
    let capturePointId: UUID
    let evidenceType: EvidenceType
    let title: String
    let iconName: String
    let worldPosition: SIMD3<Double>?
    let screenPoint: CGPointCodable?
    let anchorConfidence: SpatialPinAnchorConfidence
    let needsReview: Bool
    let sourceEvidenceId: UUID
    let createdAt: Date
}

struct OffscreenPointerOverlay: View {
    let items: [OffscreenPointerItemV1]
    let maxVisiblePointers: Int
    let onTap: (OffscreenPointerItemV1) -> Void
    let onLongPressDelete: (OffscreenPointerItemV1) -> Void

    private let edgeInset: CGFloat = 18
    /// Keep central overlays uncluttered around the capture reticle.
    private let centerHideRadiusFraction: CGFloat = 0.18
    private let maxLabelLength = 20

    var body: some View {
        GeometryReader { geometry in
            let pointers = positionedPointers(in: geometry.size)
            ForEach(pointers) { pointer in
                pointerChip(for: pointer.item, angle: pointer.angle)
                    .position(pointer.position)
            }
        }
    }

    private func positionedPointers(in size: CGSize) -> [PositionedPointerV1] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let centerRadius = min(size.width, size.height) * centerHideRadiusFraction

        return items.compactMap { item in
            guard let target = normalizedToViewportPoint(item.screenPoint, size: size) else { return nil }

            let inViewport = target.x >= 0 && target.x <= size.width && target.y >= 0 && target.y <= size.height
            let centerDistance = hypot(target.x - center.x, target.y - center.y)
            if inViewport || centerDistance <= centerRadius {
                return nil
            }

            let clamped = clampToEdge(target, size: size, inset: edgeInset)
            let angle = atan2(target.y - center.y, target.x - center.x)
            return PositionedPointerV1(item: item, position: clamped, angle: angle)
        }
        .prefix(maxVisiblePointers)
        .map { $0 }
    }

    private func normalizedToViewportPoint(_ normalized: CGPointCodable?, size: CGSize) -> CGPoint? {
        guard let normalized else { return nil }
        return CGPoint(
            x: normalized.x * size.width,
            y: normalized.y * size.height
        )
    }

    private func clampToEdge(_ point: CGPoint, size: CGSize, inset: CGFloat) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let safeWidth = max(size.width / 2 - inset, 1)
        let safeHeight = max(size.height / 2 - inset, 1)
        let scale = max(abs(dx) / safeWidth, abs(dy) / safeHeight, 1)
        return CGPoint(
            x: center.x + dx / scale,
            y: center.y + dy / scale
        )
    }

    @ViewBuilder
    private func pointerChip(for item: OffscreenPointerItemV1, angle: CGFloat) -> some View {
        Button {
            onTap(item)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.radians(angle))
                Image(systemName: item.iconName)
                    .font(.caption.weight(.semibold))
                Text(shortLabel(item.title))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                if item.needsReview {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                item.needsReview
                ? Color.orange.opacity(0.38)
                : Color.black.opacity(0.45),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            onLongPressDelete(item)
        }
    }

    private func shortLabel(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLabelLength else { return trimmed }
        return String(trimmed.prefix(maxLabelLength)) + "…"
    }
}

private struct PositionedPointerV1: Identifiable {
    let item: OffscreenPointerItemV1
    let position: CGPoint
    let angle: CGFloat

    var id: UUID { item.id }
}
