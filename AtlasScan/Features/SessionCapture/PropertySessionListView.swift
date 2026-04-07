import SwiftUI

// MARK: - PropertySessionListView
//
// Lists all PropertyScanSession records and provides navigation to SessionCaptureView.
// This is the entry point for the session-based capture workflow.

struct PropertySessionListView: View {

    @EnvironmentObject private var sessionStore: ScanSessionStore
    @EnvironmentObject private var atlasSync: AtlasSync

    @State private var showingNewSession = false
    @State private var sessionToDelete: PropertyScanSession?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if sessionStore.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewSession = true
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewSession) {
                NewPropertySessionView { newSession in
                    sessionStore.save(newSession)
                    showingNewSession = false
                }
            }
            .confirmationDialog(
                "Delete Session?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let s = sessionToDelete {
                        sessionStore.delete(s)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let s = sessionToDelete {
                    Text("'\(s.propertyAddress)' will be permanently deleted.")
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

            Text("No Sessions Yet")
                .font(.title2.bold())

            Text("Tap + to start a new property scan session.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("New Session") {
                showingNewSession = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Session list

    private var sessionList: some View {
        List {
            ForEach(sessionStore.sessions) { session in
                NavigationLink {
                    SessionCaptureView(
                        session: session,
                        store: sessionStore,
                        atlasSync: atlasSync
                    )
                } label: {
                    PropertySessionRowView(session: session)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sessionToDelete = session
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

// MARK: - PropertySessionRowView

struct PropertySessionRowView: View {
    let session: PropertyScanSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.propertyAddress)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                scanStateBadge
            }

            HStack(spacing: 12) {
                Label(session.jobReference, systemImage: "number")
                    .font(.caption).foregroundStyle(.secondary)
                Label("\(session.rooms.count) room(s)", systemImage: "square.split.2x1")
                    .font(.caption).foregroundStyle(.secondary)
                Label("\(session.totalTaggedObjects) object(s)", systemImage: "tag")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var scanStateBadge: some View {
        Text(session.scanState.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(stateColor.opacity(0.15))
            .foregroundStyle(stateColor)
            .clipShape(Capsule())
    }

    private var stateColor: Color {
        switch session.scanState {
        case .notStarted:  return .gray
        case .inProgress:  return .orange
        case .paused:      return .yellow
        case .completed:   return .green
        case .incomplete:  return .red
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("With Sessions") {
    PropertySessionListView()
        .environmentObject(ScanSessionStore())
        .environmentObject(AtlasSync())
}

#Preview("Empty") {
    PropertySessionListView()
        .environmentObject(ScanSessionStore())
        .environmentObject(AtlasSync())
}
#endif
