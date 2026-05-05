import SwiftUI

// MARK: - ExternalScanView
//
// Entry point for managing external area scans for a visit.
//
// Shows a list of existing ExternalAreaScanDraft records and lets
// the engineer add new exterior evidence captures.
//
// Flow:
//   VisitHomeView → ExternalScanView → ExternalScanCaptureView (new scan)
//                                    → ExternalScanCaptureView (edit existing)
//
// Design rules:
//   • No clearance calculation here — evidence capture only.
//   • Each area scan is a discrete record; engineers may record multiple
//     areas per visit (e.g. rear and side elevations).

struct ExternalScanView: View {

    // MARK: Store

    @ObservedObject var store: CaptureSessionStore

    // MARK: Presentation state

    @State private var showingCapture = false
    @State private var editingIndex: Int?

    // MARK: Body

    var body: some View {
        List {
            if store.draft.externalAreaScans.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No External Scans",
                        systemImage: "binoculars",
                        description: Text("Tap the button below to record the flue terminal location and nearby openings.")
                    )
                }
            } else {
                Section {
                    ForEach(store.draft.externalAreaScans.indices, id: \.self) { index in
                        let area = store.draft.externalAreaScans[index]
                        Button {
                            editingIndex = index
                        } label: {
                            externalScanRow(area)
                        }
                    }
                    .onDelete { indexSet in
                        store.draft.externalAreaScans.remove(atOffsets: indexSet)
                    }
                } header: {
                    Text("Captured Areas")
                } footer: {
                    Text("Swipe to delete an area scan. Tap to edit.")
                        .font(.caption2)
                }
            }

            Section {
                Button {
                    editingIndex = nil
                    showingCapture = true
                } label: {
                    Label("Add External Area Scan", systemImage: "plus.circle")
                        .fontWeight(.semibold)
                }
            } footer: {
                Text("Record evidence for each exterior area around the property — typically the flue exit, nearby windows, doors, and boundaries.")
                    .font(.caption2)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("External / Flue Scan")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingCapture) {
            ExternalScanCaptureView(
                existingDraft: nil,
                visitId: store.draft.id
            ) { newArea in
                store.draft.externalAreaScans.append(newArea)
                showingCapture = false
            }
        }
        .sheet(item: $editingIndex) { index in
            ExternalScanCaptureView(
                existingDraft: store.draft.externalAreaScans[index],
                visitId: store.draft.id
            ) { updated in
                store.draft.externalAreaScans[index] = updated
                editingIndex = nil
            }
        }
    }

    // MARK: - Row

    private func externalScanRow(_ area: ExternalAreaScanDraft) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "binoculars")
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(area.label.isEmpty ? "Unlabelled Area" : area.label)
                    .font(.body)
                Text("\(area.objectPins.count) pin(s) · \(area.photos.count) photo(s) · \(area.measurements.count) measurement(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            reviewStatusBadge(area.reviewStatus)
        }
    }

    private func reviewStatusBadge(_ status: EvidenceReviewStatus) -> some View {
        let (color, label): (Color, String) = {
            switch status {
            case .confirmed: return (.green,  "✓")
            case .pending:   return (.orange, "…")
            case .rejected:  return (.red,    "✗")
            }
        }()
        return Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = CaptureSessionStore(
        draft: CaptureSessionStore.newSession(visitReference: "PREVIEW-EXT"),
        persistence: .shared
    )
    return NavigationStack {
        ExternalScanView(store: store)
    }
}
#endif
