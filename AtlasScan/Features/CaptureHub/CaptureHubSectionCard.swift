import SwiftUI

// MARK: - CaptureHubSectionStatus

/// The status of a capture hub section.
enum CaptureHubSectionStatus {
    case notStarted
    case inProgress(count: Int)
    case ready(count: Int)
    case needsAttention(message: String)

    var displayText: String {
        switch self {
        case .notStarted:              return "Not started"
        case .inProgress(let count):   return "\(count) captured"
        case .ready(let count):        return "\(count) ready"
        case .needsAttention(let msg): return msg
        }
    }

    var symbolName: String {
        switch self {
        case .notStarted:      return "circle"
        case .inProgress:      return "clock.fill"
        case .ready:           return "checkmark.circle.fill"
        case .needsAttention:  return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notStarted:      return .secondary
        case .inProgress:      return .orange
        case .ready:           return .green
        case .needsAttention:  return .red
        }
    }
}

// MARK: - CaptureHubSectionCard

/// A single section card on the Capture Hub screen.
///
/// Each card represents one capture area and shows:
///   • title
///   • item count / status
///   • primary action button
struct CaptureHubSectionCard: View {

    let title: String
    let subtitle: String
    let symbolName: String
    let status: CaptureHubSectionStatus
    let actionLabel: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                iconBox
                contentStack
                Spacer()
                chevron
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Icon box

    private var iconBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(status.color.opacity(0.15))
                .frame(width: 48, height: 48)
            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(status.color)
        }
    }

    // MARK: - Content

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.bold())
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                Image(systemName: status.symbolName)
                    .font(.caption2)
                    .foregroundStyle(status.color)
                Text(status.displayText)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Chevron

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        CaptureHubSectionCard(
            title: "Room Scans",
            subtitle: "LiDAR capture of each room",
            symbolName: "lidar.scanner",
            status: .notStarted,
            actionLabel: "Start Scan"
        ) {}

        CaptureHubSectionCard(
            title: "Photos",
            subtitle: "Evidence photos for rooms and objects",
            symbolName: "camera",
            status: .inProgress(count: 3),
            actionLabel: "Add Photo"
        ) {}

        CaptureHubSectionCard(
            title: "Review & Export",
            subtitle: "Check completeness and export",
            symbolName: "checklist",
            status: .ready(count: 8),
            actionLabel: "Review"
        ) {}
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
#endif
