import SwiftUI
import AtlasContracts

// MARK: - FieldVisitSection

/// The four sections of the field visit workflow.
enum FieldVisitSection: String, CaseIterable, Hashable {
    case capture  = "capture"
    case plan     = "plan"
    case review   = "review"
    case complete = "complete"

    var title: String {
        switch self {
        case .capture:  return "Capture"
        case .plan:     return "Plan"
        case .review:   return "Review"
        case .complete: return "Complete"
        }
    }

    var symbolName: String {
        switch self {
        case .capture:  return "camera.viewfinder"
        case .plan:     return "pencil.and.ruler"
        case .review:   return "checklist"
        case .complete: return "checkmark.seal"
        }
    }
}

// MARK: - FieldVisitShellView

/// Top-level container for a single field visit.
///
/// Owns:
///   - The `FieldVisitStore` that holds and persists the visit draft.
///   - Section navigation: Capture / Plan / Review / Complete.
///   - A lifecycle badge showing where the visit currently sits.
///
/// Design:
///   - "One visit, one session, one shell."
///   - Section switching never fragments state; all sections read from
///     and write to the single shared `FieldVisitStore`.
///   - The shell is the entry point; child views are injected with the store.
struct FieldVisitShellView: View {

    @StateObject private var store: FieldVisitStore
    @State private var activeSection: FieldVisitSection = .capture

    // MARK: Init

    init(session: PropertyScanSession, sessionStore: ScanSessionStore) {
        _store = StateObject(
            wrappedValue: FieldVisitStore(session: session, sessionStore: sessionStore)
        )
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            visitHeader
            sectionPicker
            sectionContent
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(store.session.propertyAddress)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    // MARK: - Visit header

    private var visitHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if !store.session.jobReference.isEmpty {
                    Text(store.session.jobReference)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(store.session.propertyAddress)
                    .font(.headline)
                    .lineLimit(2)
            }
            Spacer()
            lifecycleBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Lifecycle badge

    private var lifecycleBadge: some View {
        let status = store.lifecycleBadgeStatus
        return HStack(spacing: 4) {
            Image(systemName: status.symbolName)
                .font(.caption2)
            Text(status.displayName)
                .font(.caption2.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(lifecycleColor(status).opacity(0.15))
        .foregroundStyle(lifecycleColor(status))
        .clipShape(Capsule())
    }

    // MARK: - Section picker

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(FieldVisitSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeSection = section
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: section.symbolName)
                                .font(.caption)
                            Text(section.title)
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundStyle(activeSection == section ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if activeSection == section {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Section content

    @ViewBuilder
    private var sectionContent: some View {
        switch activeSection {
        case .capture:
            FieldCaptureView(store: store)
        case .plan:
            FieldPlanView(store: store)
        case .review:
            FieldReviewView(store: store)
        case .complete:
            FieldCompleteView(store: store)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text("Field Visit")
                    .font(.headline)
                saveStateBadge
            }
        }
    }

    @ViewBuilder
    private var saveStateBadge: some View {
        switch store.saveState {
        case .unsaved:
            Text("Unsaved")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .saving:
            Text("Saving…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .saved:
            EmptyView()
        }
    }

    // MARK: - Color helper

    private func lifecycleColor(_ status: VisitLifecycleStatus) -> Color {
        switch status {
        case .draft:           return .gray
        case .capturing:       return .orange
        case .planning:        return .blue
        case .readyToComplete: return .green
        case .complete:        return .green
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Empty Visit") {
    NavigationStack {
        FieldVisitShellView(
            session: PropertyScanSession(
                jobReference: "JOB-2025-001",
                propertyAddress: "12 Coronation Street, Manchester"
            ),
            sessionStore: ScanSessionStore()
        )
    }
}

#Preview("Populated Visit") {
    var session = PropertyScanSession(
        jobReference: "JOB-2025-002",
        propertyAddress: "47 Baker Street, London"
    )
    session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
    session.addRoom(ScannedRoom(jobID: session.id, name: "Living Room"))
    session.addPhoto(TaggedPhoto(filename: "p1.jpg"))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .boiler))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))
    return NavigationStack {
        FieldVisitShellView(session: session, sessionStore: ScanSessionStore())
    }
}
#endif
