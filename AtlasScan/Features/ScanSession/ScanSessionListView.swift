import SwiftUI

// MARK: - ScanSessionListView
//
// Home screen: shows all scan jobs (drafts + complete), lets the engineer
// create a new job or continue an existing one.

struct ScanSessionListView: View {

    @EnvironmentObject private var jobStore: ScanJobStore
    @State private var showingNewJobSheet = false
    @State private var jobToDelete: ScanJob?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if jobStore.jobs.isEmpty {
                    emptyState
                } else {
                    jobList
                }
            }
            .navigationTitle("Atlas Scan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewJobSheet = true
                    } label: {
                        Label("New Scan", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewJobSheet) {
                NewScanJobView { newJob in
                    jobStore.save(newJob)
                    showingNewJobSheet = false
                }
            }
            .confirmationDialog(
                "Delete Scan?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let job = jobToDelete {
                        jobStore.delete(job)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let job = jobToDelete {
                    Text("'\(job.propertyAddress)' will be permanently deleted.")
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Scans Yet")
                .font(.title2.bold())

            Text("Tap + to start a new scan job.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("New Scan Job") {
                showingNewJobSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Job list

    private var jobList: some View {
        List {
            ForEach(jobStore.jobs) { job in
                NavigationLink {
                    ScanJobDetailView(job: job)
                } label: {
                    ScanJobRowView(job: job)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        jobToDelete = job
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - ScanJobRowView

struct ScanJobRowView: View {

    let job: ScanJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.propertyAddress)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: job.status)
            }

            HStack(spacing: 12) {
                Label(job.jobReference, systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(job.rooms.count) room(s)", systemImage: "square.split.2x1")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(job.totalTaggedObjects) object(s)", systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(job.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - StatusBadge

struct StatusBadge: View {
    let status: ScanJobStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .draft:        return .gray
        case .inProgress:   return .orange
        case .reviewing:    return .blue
        case .exported:     return .green
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("With Jobs") {
    ScanSessionListView()
        .environmentObject({
            let store = ScanJobStore()
            // Preview: inject mock jobs directly
            return store
        }())
}

#Preview("Empty") {
    ScanSessionListView()
        .environmentObject(ScanJobStore())
}
#endif
