import SwiftUI
import AtlasContracts

// MARK: - FieldCompleteView

/// Complete tab for the field visit shell.
///
/// Shows visit readiness, lists missing required items, and provides the
/// explicit "Complete Visit" action.
///
/// Layout:
///   Section A — Status: ready / not ready banner.
///   Section B — Missing items: human-readable list when visit is not ready.
///   Section C — Complete button: enabled only when all required items are present.
///   Post-completion — Completion summary with timestamp and method.
///
/// Rules:
///   - Only the "Complete Visit" button can advance lifecycle to .complete.
///   - The button is disabled when any required item is absent.
///   - On success the visit becomes read-only and the completed summary is shown.
///   - If the immediate save fails, the visit is NOT marked complete and an
///     error banner is shown instead.
struct FieldCompleteView: View {

    @ObservedObject var store: FieldVisitStore

    @State private var showingHandoffReview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isCompleted {
                    completedSummarySection
                } else {
                    readinessStatusCard
                    if !store.completionValidation.isCompletable {
                        missingItemsSection
                    }
                    completeButtonSection
                    if let error = store.completionError {
                        errorBanner(error)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(isPresented: $showingHandoffReview) {
            VisitCompletionReviewView(session: store.session)
        }
    }

    // MARK: - Readiness status card

    private var readinessStatusCard: some View {
        let isReady = store.completionValidation.isCompletable

        return HStack(spacing: 14) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(isReady ? .green : .orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(isReady ? "Ready to complete" : "Not ready to complete")
                    .font(.headline)
                Text(isReady
                     ? "All required survey items are present."
                     : "This visit still needs a few required items before it can be closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Missing items

    private var missingItemsSection: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Required Items")
                .padding(.bottom, 8)

            VStack(spacing: 1) {
                ForEach(store.completionValidation.missingItems, id: \.self) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.7))
                            .frame(width: 24)
                        Text(item.humanReadableDescription)
                            .font(.body)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemGroupedBackground))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Complete button

    private var completeButtonSection: some View {
        Button {
            store.completeVisit()
        } label: {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                Text("Complete Visit")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!store.canCompleteVisit)
        .opacity(store.canCompleteVisit ? 1 : 0.45)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Could not complete visit")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.clearCompletionError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Completed summary

    private var completedSummarySection: some View {
        VStack(spacing: 16) {
            // Banner
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Visit completed")
                        .font(.headline)
                    Text("This visit has been closed and is now read-only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Metadata
            VStack(spacing: 0) {
                SectionHeader(title: "Completion Details")
                    .padding(.bottom, 8)

                VStack(spacing: 1) {
                    if let completedAt = store.session.completedAt {
                        CompletionMetadataRow(
                            label: "Completed at",
                            value: completedAt.formatted(date: .abbreviated, time: .shortened),
                            symbol: "clock"
                        )
                    }

                    if let method = store.session.completionMethod {
                        CompletionMetadataRow(
                            label: "Method",
                            value: method.displayName,
                            symbol: "hand.tap"
                        )
                    }

                    if let userId = store.session.completedByUserId {
                        CompletionMetadataRow(
                            label: "Completed by",
                            value: userId,
                            symbol: "person"
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Review handoff CTA
            Button {
                showingHandoffReview = true
            } label: {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Review handoff")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - CompletionMetadataRow

private struct CompletionMetadataRow: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Ready") {
    let store = ScanSessionStore()
    var session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
    session.addPhoto(TaggedPhoto(filename: "p.jpg"))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .boiler))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .cylinder))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .radiator))
    session.addVoiceNote(VoiceNote(localFilename: "note.m4a", duration: 30))
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldCompleteView(store: visitStore)
}

#Preview("Not Ready") {
    let store = ScanSessionStore()
    let session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldCompleteView(store: visitStore)
}

#Preview("Completed") {
    let store = ScanSessionStore()
    var session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    session.visitLifecycle = .complete
    session.completedAt = Date()
    session.completionMethod = .manual
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldCompleteView(store: visitStore)
}
#endif
