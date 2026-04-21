import SwiftUI
import AtlasContracts

// MARK: - FieldCompleteView

/// Complete tab skeleton for the field visit shell.
///
/// For this PR the Complete tab:
///   - Explains whether the visit appears ready based on readiness checks.
///   - Shows missing requirements so the engineer knows what to fix.
///   - Shows a disabled "Complete Visit" button as a placeholder.
///   - Does NOT complete the visit.
///
/// Actual completion (writing visitStatus = .complete, completion metadata,
/// and enforcing all validation rules) is implemented in PR 5.
struct FieldCompleteView: View {

    @ObservedObject var store: FieldVisitStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                readinessStatusCard
                if !store.visitReadiness.isReady {
                    missingItemsSection
                }
                completeButtonSection
                pr5Notice
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Readiness status card

    private var readinessStatusCard: some View {
        let readiness = store.visitReadiness
        let isReady = readiness.isReady

        return HStack(spacing: 14) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(isReady ? .green : .orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(isReady ? "Visit Appears Ready" : "Visit Not Yet Ready")
                    .font(.headline)
                Text(isReady
                     ? "All required survey items are present."
                     : "Some required items are missing.")
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
            SectionHeader(title: "Missing Requirements")
                .padding(.bottom, 8)

            VStack(spacing: 1) {
                ForEach(store.visitReadiness.missingItems, id: \.self) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.7))
                            .frame(width: 24)
                        Text(item)
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

    // MARK: - Complete button (disabled placeholder)

    private var completeButtonSection: some View {
        Button {} label: {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                Text("Complete Visit")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(true)
        .opacity(0.45)
    }

    // MARK: - PR5 notice

    private var pr5Notice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Visit completion will be implemented in the next PR. This button is a placeholder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldCompleteView(store: visitStore)
}

#Preview("Not Ready") {
    let store = ScanSessionStore()
    let session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldCompleteView(store: visitStore)
}
#endif
