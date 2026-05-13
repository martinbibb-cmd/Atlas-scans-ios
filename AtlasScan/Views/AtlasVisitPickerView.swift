import SwiftUI

struct AtlasVisitPickerView: View {
    let workspace: AtlasWorkspaceV1
    let visits: [AtlasVisitIdentityV1]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void
    let onCreateMindVisit: () -> Void
    let onSelectVisit: (AtlasVisitIdentityV1) -> Void
    let onBack: () -> Void
    let onSignOut: () -> Void

    private var remoteVisits: [AtlasVisitIdentityV1] {
        visits.filter { $0.source == .mind }
    }

    private var orphanVisits: [AtlasVisitIdentityV1] {
        visits.filter { $0.source == .localOrphanDebug }
    }

    var body: some View {
        List {
            Section {
                Text(workspace.name)
                    .font(.subheadline.weight(.semibold))
            } header: {
                Text("Workspace")
            }

            Section {
                Button(action: onCreateMindVisit) {
                    Label("Start New Mind Visit", systemImage: "plus.circle")
                }
                .disabled(isLoading)
            }

            Section {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading visits…")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if remoteVisits.isEmpty {
                    Text("No Mind visits found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(remoteVisits) { visit in
                        Button {
                            onSelectVisit(visit)
                        } label: {
                            VisitIdentityRow(visit: visit)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } header: {
                HStack {
                    Text("Mind Visits")
                    Spacer()
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .disabled(isLoading)
                }
            }

            #if DEBUG
            if !orphanVisits.isEmpty {
                Section("Local Orphan Visits (Debug Fallback)") {
                    ForEach(orphanVisits) { visit in
                        Button {
                            onSelectVisit(visit)
                        } label: {
                            VisitIdentityRow(visit: visit)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            #endif
        }
        .navigationTitle("Choose Visit")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Workspaces", action: onBack)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sign Out", role: .destructive, action: onSignOut)
            }
        }
    }
}

private struct VisitIdentityRow: View {
    let visit: AtlasVisitIdentityV1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(visit.visitReference)
                .font(.headline)
            if let address = visit.propertyAddress, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(visit.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let scheduledAtISO8601 = visit.scheduledAtISO8601,
                   let date = ISO8601DateFormatter().date(from: scheduledAtISO8601) {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AtlasVisitPickerView(
            workspace: AtlasWorkspaceV1(id: "w1", name: "Primary Workspace"),
            visits: [
                AtlasVisitIdentityV1(
                    id: "v1",
                    visitReference: "JOB-2026-001",
                    propertyAddress: "1 Example Street",
                    status: "scheduled",
                    scheduledAtISO8601: ISO8601DateFormatter().string(from: .now),
                    source: .mind
                ),
                AtlasVisitIdentityV1(
                    id: "draft",
                    visitReference: "LOCAL-123456",
                    propertyAddress: nil,
                    status: "draft",
                    scheduledAtISO8601: nil,
                    source: .localOrphanDebug
                )
            ],
            isLoading: false,
            errorMessage: nil,
            onRefresh: {},
            onCreateMindVisit: {},
            onSelectVisit: { _ in },
            onBack: {},
            onSignOut: {}
        )
    }
}
#endif
