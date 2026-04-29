import SwiftUI

// MARK: - SavedVisitsView
//
// Full-screen list of all locally persisted visit drafts.
//
// The engineer can:
//   • Tap a visit to reopen it in VisitDetailView
//   • Swipe-to-delete a visit
//   • See the export state and evidence count at a glance

struct SavedVisitsView: View {

    let onOpen: (CaptureSessionDraft) -> Void
    let onClose: () -> Void

    @State private var drafts: [CaptureSessionDraft] = []

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    emptyState
                } else {
                    visitList
                }
            }
            .navigationTitle("Saved Visits")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onClose()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Home")
                        }
                    }
                }
            }
            .onAppear { reload() }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Saved Visits")
                .font(.title3.bold())
            Text("Start a local capture visit from the home screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Visit list

    private var visitList: some View {
        List {
            ForEach(drafts) { draft in
                Button {
                    onOpen(draft)
                } label: {
                    SavedVisitRow(draft: draft)
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteDraft(id: draft.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func reload() {
        drafts = CaptureSessionPersistence.shared.loadAll()
    }

    private func deleteDraft(id: UUID) {
        CaptureSessionPersistence.shared.delete(id: id)
        withAnimation { drafts.removeAll { $0.id == id } }
    }
}

// MARK: - SavedVisitRow

private struct SavedVisitRow: View {

    let draft: CaptureSessionDraft

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stateSymbol)
                .foregroundStyle(stateColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.visitReference.isEmpty ? "No Reference" : draft.visitReference)
                    .font(.headline)
                if !draft.propertyAddress.isEmpty {
                    Text(draft.propertyAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(draft.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            evidenceBadge
        }
        .padding(.vertical, 2)
    }

    private var stateSymbol: String {
        switch draft.exportState {
        case .draft:          return "pencil.circle"
        case .readyForExport: return "checkmark.circle"
        case .exported:       return "checkmark.seal.fill"
        case .exportFailed:   return "xmark.circle"
        }
    }

    private var stateColor: Color {
        switch draft.exportState {
        case .draft:          return .orange
        case .readyForExport: return .green
        case .exported:       return .secondary
        case .exportFailed:   return .red
        }
    }

    @ViewBuilder
    private var evidenceBadge: some View {
        let count = draft.photos.count + draft.voiceNotes.count
        if count > 0 {
            Text("\(count)")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SavedVisitsView(onOpen: { _ in }, onClose: {})
}
#endif
