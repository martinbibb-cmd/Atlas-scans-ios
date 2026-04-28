import SwiftUI
import AtlasContracts

// MARK: - SessionCompletionView
//
// PR 6 — session completion panel.
//
// This is the default entry point for ending a capture session and sending
// the canonical payload to Atlas Mind. It replaces the direct sheet
// presentation of AtlasHandoffView as the primary "Send to Atlas Mind" action.
//
// Flow:
//   1. Engineer taps "Send to Atlas Mind" in SessionCaptureView.
//   2. SessionCompletionView opens, showing a readiness summary and
//      a prominent primary CTA.
//   3. Tapping the primary CTA opens AtlasHandoffView for payload
//      export/share, which marks handoffState = .sent on success.
//   4. Secondary utilities (inspect payload, copy JSON, review session)
//      are available but subordinate to the primary action.
//
// The view is intentionally stateless with respect to the session — it
// relies on `session` (read-only) and `onHandoffSent` / `onHandoffExported`
// callbacks to propagate state changes back to SessionCaptureViewModel.

struct SessionCompletionView: View {

    let session: PropertyScanSession
    let onHandoffSent: () -> Void
    let onHandoffExported: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingHandoff = false
    @State private var showingReview = false

    private var readiness: HandoffReadiness { session.handoffReadiness }

    var body: some View {
        NavigationStack {
            List {
                handoffStateBannerSection
                readinessSummarySection
                knowledgeReadinessSection
                primaryCTASection
                secondaryUtilitiesSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Complete Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingHandoff) {
                AtlasHandoffView(
                    session: session,
                    onHandoffComplete: {
                        onHandoffSent()
                    }
                )
            }
            .navigationDestination(isPresented: $showingReview) {
                SessionReviewView(session: session, store: nil)
            }
        }
    }

    // MARK: - Sections

    private var handoffStateBannerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: session.handoffState.symbolName)
                    .font(.title2)
                    .foregroundStyle(handoffStateBannerColor)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.handoffState.displayName)
                        .font(.headline)
                    Text(handoffStateBannerDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var handoffStateBannerColor: Color {
        switch session.handoffState {
        case .notSent:  return readiness.isReady ? .green : .orange
        case .sent:     return .blue
        case .exported: return .purple
        }
    }

    private var handoffStateBannerDetail: String {
        switch session.handoffState {
        case .notSent:
            return readiness.isReady
                ? "Session is ready to send"
                : "Session has incomplete items"
        case .sent:
            return "Payload was sent to Atlas Mind"
        case .exported:
            return "Payload was saved to Files"
        }
    }

    private var readinessSummarySection: some View {
        Section("Spatial Readiness") {
            LabeledContent("Rooms", value: "\(session.rooms.count)")
            LabeledContent(
                "Rooms reviewed",
                value: "\(session.totalReviewedRooms) / \(session.rooms.count)"
            )
            LabeledContent("Tagged objects", value: "\(session.totalTaggedObjects)")
            LabeledContent("Photos", value: "\(session.totalPhotos)")
            if session.totalVoiceNotes > 0 {
                LabeledContent("Voice notes", value: "\(session.totalVoiceNotes)")
            }
            if !readiness.isReady {
                ForEach(readiness.missingEssentials, id: \.self) { reason in
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var knowledgeReadinessSection: some View {
        Section {
            KnowledgeReadinessRow(
                label: "Household",
                symbol: "person.3.fill",
                isKnown: session.knowledgeSummary.householdKnown,
                hasFacts: session.extractedFacts.contains { $0.category.group == .household }
            )
            KnowledgeReadinessRow(
                label: "Bathrooms / Usage",
                symbol: "drop.fill",
                isKnown: session.knowledgeSummary.bathroomsKnown,
                hasFacts: session.extractedFacts.contains { $0.category.group == .usage }
            )
            KnowledgeReadinessRow(
                label: "Current System",
                symbol: "boiler.fill",
                isKnown: session.knowledgeSummary.systemKnown,
                hasFacts: session.extractedFacts.contains { $0.category.group == .system }
            )
            KnowledgeReadinessRow(
                label: "Priorities",
                symbol: "star.fill",
                isKnown: session.knowledgeSummary.prioritiesKnown,
                hasFacts: session.extractedFacts.contains { $0.category.group == .priorities }
            )
            KnowledgeReadinessRow(
                label: "Constraints",
                symbol: "exclamationmark.triangle.fill",
                isKnown: session.knowledgeSummary.constraintsKnown,
                hasFacts: session.extractedFacts.contains { $0.category.group == .constraints }
            )
        } header: {
            Text("Captured Knowledge")
        } footer: {
            Text("Captured knowledge is not required for handoff but improves recommendation quality in Atlas Mind.")
                .font(.caption2)
        }
    }

    private var primaryCTASection: some View {
        Section {
            Button {
                showingHandoff = true
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(primaryCTAColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Send to Atlas Mind")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(primaryCTADetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } footer: {
            Text("Builds and shares the ScanBundle export package for Atlas ingestion.")
                .font(.caption2)
        }
    }

    private var primaryCTAColor: Color {
        readiness.isReady ? .green : .orange
    }

    private var primaryCTADetail: String {
        switch session.handoffState {
        case .notSent:
            return readiness.isReady
                ? "Export and share the ScanBundle package"
                : "Session has gaps — you can still send it"
        case .sent:
            return "Send again to Atlas Mind"
        case .exported:
            return "Send via share sheet"
        }
    }

    private var secondaryUtilitiesSection: some View {
        Section("Utilities") {
            Button {
                showingReview = true
            } label: {
                Label("Review Session", systemImage: "doc.text.magnifyingglass")
            }
        }
    }
}

// MARK: - KnowledgeReadinessRow

/// A single row in the knowledge readiness panel inside SessionCompletionView.
private struct KnowledgeReadinessRow: View {
    let label: String
    let symbol: String
    let isKnown: Bool
    let hasFacts: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
            Spacer()
            statusLabel
        }
    }

    private var iconColor: Color {
        if isKnown { return .green }
        if hasFacts { return .orange }
        return .secondary
    }

    private var statusLabel: some View {
        Group {
            if isKnown {
                Label("Confirmed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if hasFacts {
                Label("Review", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("Missing", systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Not Sent — Ready") {
    SessionCompletionView(
        session: MockData.sampleSession,
        onHandoffSent: {},
        onHandoffExported: {}
    )
}

#Preview("Already Sent") {
    var s = MockData.sampleSession
    s.handoffState = .sent
    return SessionCompletionView(
        session: s,
        onHandoffSent: {},
        onHandoffExported: {}
    )
}

#Preview("Incomplete Session") {
    let s = PropertyScanSession(propertyAddress: "1 Empty Street")
    return SessionCompletionView(
        session: s,
        onHandoffSent: {},
        onHandoffExported: {}
    )
}
#endif
