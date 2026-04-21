import SwiftUI

// MARK: - FieldCaptureView

/// Capture tab skeleton for the field visit shell.
///
/// Shows summary counts for what has been captured so far and exposes
/// placeholder actions for adding rooms, photos, objects, and notes.
/// Deeper capture features are wired in later PRs; this view proves the
/// tab is live and that counts update as the session changes.
struct FieldCaptureView: View {

    @ObservedObject var store: FieldVisitStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isCompleted {
                    completedNotice
                }
                summarySection
                if !store.isCompleted {
                    actionsSection
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { store.enterCapturePhase() }
    }

    // MARK: - Completed notice

    private var completedNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text("Visit completed — capture is read-only.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Capture Summary")

            let survey = store.fieldSurvey
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                CaptureSummaryCard(
                    count: survey.roomCount,
                    label: "Rooms",
                    symbol: "square.split.2x1",
                    tint: .blue
                )
                CaptureSummaryCard(
                    count: survey.totalPhotoCount,
                    label: "Photos",
                    symbol: "camera",
                    tint: .orange
                )
                CaptureSummaryCard(
                    count: store.session.allTaggedObjects.count,
                    label: "Key Objects",
                    symbol: "mappin.and.ellipse",
                    tint: .purple
                )
                CaptureSummaryCard(
                    count: survey.totalVoiceNoteCount,
                    label: "Notes",
                    symbol: "mic",
                    tint: .green
                )
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Add Capture Data")

            CaptureActionRow(
                label: "Add Room",
                symbol: "square.split.2x1",
                tint: .blue
            )
            CaptureActionRow(
                label: "Add Photo",
                symbol: "camera",
                tint: .orange
            )
            CaptureActionRow(
                label: "Add Boiler",
                symbol: "flame",
                tint: .red
            )
            CaptureActionRow(
                label: "Add Flue",
                symbol: "arrow.up.to.line",
                tint: .gray
            )
            CaptureActionRow(
                label: "Add Note",
                symbol: "mic",
                tint: .green
            )
        }
    }
}

// MARK: - CaptureSummaryCard

private struct CaptureSummaryCard: View {
    let count: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(count > 0 ? tint : .secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption)
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - CaptureActionRow

private struct CaptureActionRow: View {
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        // Placeholder: wire to the real capture screen in a subsequent PR.
        Button {} label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    let session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldCaptureView(store: visitStore)
}
#endif
