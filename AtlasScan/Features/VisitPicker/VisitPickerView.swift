import SwiftUI

// MARK: - VisitPickerView
//
// Second screen in the Scan flow.
//
// The engineer can:
//   • Resume a locally-saved draft that was not yet exported.
//   • Start a new visit (leads to StartJobView).
//   • Pick a scheduled visit fetched from the Cloudflare database — which
//     pre-fills the appointmentId and visit reference so the resulting
//     SessionCaptureV1 export can be matched back by Atlas Recommendations.
//
// Local sessions are always shown first; remote appointments are loaded
// asynchronously and merged below.

struct VisitPickerView: View {

    // Called when the engineer is ready to begin / resume capturing.
    let onStart: (CaptureSessionDraft) -> Void

    // MARK: - State

    @State private var localDrafts: [CaptureSessionDraft] = []
    @State private var remoteVisits: [RemoteVisit] = []
    @State private var isLoadingRemote = false
    @State private var remoteLoadError: String?
    @State private var showingNewVisit = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: In-progress local sessions
                if !localDrafts.isEmpty {
                    Section {
                        ForEach(localDrafts) { draft in
                            LocalDraftRow(draft: draft) {
                                resume(draft: draft)
                            }
                        }
                    } header: {
                        Text("In Progress")
                    }
                }

                // MARK: Scheduled visits from Cloudflare
                Section {
                    if isLoadingRemote {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Loading scheduled visits…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = remoteLoadError {
                        Label(error, systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if remoteVisits.isEmpty {
                        Text("No scheduled visits found.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(remoteVisits) { visit in
                            RemoteVisitRow(visit: visit) {
                                startFromRemote(visit: visit)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Scheduled")
                        Spacer()
                        Button {
                            Task { await loadRemoteVisits() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Visits")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewVisit = true
                    } label: {
                        Label("New Visit", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewVisit) {
                NavigationStack {
                    StartJobView { draft in
                        showingNewVisit = false
                        onStart(draft)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingNewVisit = false }
                        }
                    }
                    .navigationTitle("New Visit")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onAppear {
            localDrafts = CaptureSessionPersistence.shared.loadAll()
                .filter { $0.exportState != .exported }
            Task { await loadRemoteVisits() }
        }
    }

    // MARK: - Actions

    private func resume(draft: CaptureSessionDraft) {
        let store = CaptureSessionStore(draft: draft, persistence: .shared)
        onStart(store.draft)
    }

    private func startFromRemote(visit: RemoteVisit) {
        var draft = CaptureSessionStore.newSession(
            visitReference: visit.visitReference,
            appointmentId: visit.id
        )
        if let addr = visit.propertyAddress {
            draft.propertyAddress = addr
        }
        let store = CaptureSessionStore(draft: draft, persistence: .shared)
        store.saveNow()
        onStart(store.draft)
    }

    private func loadRemoteVisits() async {
        isLoadingRemote = true
        remoteLoadError = nil
        do {
            remoteVisits = try await CloudflareVisitClient.shared.fetchUpcomingVisits()
        } catch {
            remoteLoadError = error.localizedDescription
        }
        isLoadingRemote = false
    }
}

// MARK: - LocalDraftRow

private struct LocalDraftRow: View {

    let draft: CaptureSessionDraft
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: draft.exportState.symbolName)
                    .foregroundStyle(exportStateColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.visitReference.isEmpty ? "No reference" : draft.visitReference)
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

                artefactBadge
            }
        }
        .foregroundStyle(.primary)
    }

    private var exportStateColor: Color {
        switch draft.exportState {
        case .draft:          return .orange
        case .readyForExport: return .green
        case .exported:       return .secondary
        case .exportFailed:   return .red
        }
    }

    private var artefactBadge: some View {
        let count = draft.totalArtefactCount
        return Group {
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
}

// MARK: - RemoteVisitRow

private struct RemoteVisitRow: View {

    let visit: RemoteVisit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.visitReference)
                        .font(.headline)
                    if let addr = visit.propertyAddress {
                        Text(addr)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let scheduled = visit.scheduledAt,
                       let date = ISO8601DateFormatter().date(from: scheduled) {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                statusPill
            }
        }
        .foregroundStyle(.primary)
    }

    private var statusPill: some View {
        Text(visit.status.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch visit.status.lowercased() {
        case "confirmed":    return .green
        case "in_progress":  return .orange
        case "scheduled":    return .blue
        default:             return .secondary
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VisitPickerView { _ in }
}
#endif
