import SwiftUI

// MARK: - VisitOverviewView

/// Session overview screen — the first stop when entering a visit.
///
/// Shows session identity, capture state, and quick stats.
/// Provides shortcuts to each capture surface.
struct VisitOverviewView: View {

    @ObservedObject var viewModel: VisitCaptureViewModel

    var body: some View {
        List {
            visitHeaderSection
            captureStatsSection
            captureShortcutsSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Visit header

    private var visitHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.session.propertyAddress)
                            .font(.headline)
                        Text(viewModel.session.jobReference)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    stateBadge
                }

                if !viewModel.session.engineerName.isEmpty {
                    Label(viewModel.session.engineerName, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Visit")
        } footer: {
            Text("Updated \(viewModel.session.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
        }
    }

    private var stateBadge: some View {
        Text(viewModel.session.scanState.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(stateColor.opacity(0.15))
            .foregroundStyle(stateColor)
            .clipShape(Capsule())
    }

    private var stateColor: Color {
        switch viewModel.session.scanState {
        case .notStarted: return .gray
        case .inProgress: return .orange
        case .paused:     return .yellow
        case .completed:  return .green
        case .incomplete: return .red
        }
    }

    // MARK: - Stats

    private var captureStatsSection: some View {
        Section("Capture Progress") {
            statRow(
                title: "Rooms",
                value: "\(viewModel.session.rooms.count)",
                detail: "\(viewModel.session.rooms.filter(\.geometryCaptured).count) scanned",
                symbol: "square.split.2x1"
            )
            statRow(
                title: "Objects",
                value: "\(viewModel.session.totalTaggedObjects)",
                symbol: "tag"
            )
            statRow(
                title: "Photos",
                value: "\(viewModel.session.totalPhotos)",
                symbol: "camera"
            )
            statRow(
                title: "Voice Notes",
                value: "\(viewModel.session.totalVoiceNotes)",
                symbol: "mic"
            )
            let transcriptCount = viewModel.session.allVoiceNotes.filter { $0.transcript != nil }.count
            statRow(
                title: "Transcripts",
                value: "\(transcriptCount) / \(viewModel.session.totalVoiceNotes)",
                symbol: "text.bubble"
            )
        }
    }

    private func statRow(title: String, value: String, detail: String? = nil, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.body.monospacedDigit())
                    .bold()
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Shortcuts

    private var captureShortcutsSection: some View {
        Section("Capture Screens") {
            ForEach(VisitCaptureScreen.allCases.filter { $0 != .overview }, id: \.self) { screen in
                Button {
                    viewModel.navigate(to: screen)
                } label: {
                    Label(screen.title, systemImage: screen.symbolName)
                }
                .tint(.primary)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    let session = PropertyScanSession(
        jobReference: "JOB-001",
        propertyAddress: "12 Test Lane"
    )
    let vm = VisitCaptureViewModel(session: session, sessionStore: store, atlasSync: AtlasSync())
    return VisitOverviewView(viewModel: vm)
}
#endif
