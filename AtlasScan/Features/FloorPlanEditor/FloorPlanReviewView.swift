import SwiftUI

// MARK: - FloorPlanReviewView
//
// Shows all captured room scans and lets the engineer open
// each room's floor plan in the editor.
//
// Floor plan annotation is optional — the engineer can always
// proceed with a photo-only or scan-only session without annotating.

struct FloorPlanReviewView: View {

    @ObservedObject var store: CaptureSessionStore
    @State private var editingScan: CapturedRoomScanDraft?

    var body: some View {
        List {
            if store.draft.roomScans.isEmpty {
                emptyState
            } else {
                scansSection
            }
            snapshotsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Floor Plans")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingScan) { scan in
            FloorPlanEditorView(
                scan: scan,
                onSnapshot: { snapshot in
                    store.addFloorPlanSnapshot(snapshot)
                },
                onSave: { updated in
                    store.updateRoomScan(updated)
                    editingScan = nil
                }
            )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No room scans yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Capture a room scan first, then return here to annotate its floor plan.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Scans list

    private var scansSection: some View {
        Section {
            ForEach(store.draft.roomScans) { scan in
                Button {
                    editingScan = scan
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scan.roomLabel ?? "Unnamed Room")
                                .font(.body)
                                .foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                annotationSummary(for: scan)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
        } header: {
            Text("Rooms (\(store.draft.roomScans.count))")
        } footer: {
            Text("Tap a room to open the floor plan editor. Annotation is optional.")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private func annotationSummary(for scan: CapturedRoomScanDraft) -> some View {
        if let plan = scan.floorPlan {
            if !plan.objectPlacements.isEmpty {
                Label(countLabel(plan.objectPlacements.count, singular: "object"), systemImage: "mappin.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !plan.pipeSegments.isEmpty {
                Label(countLabel(plan.pipeSegments.count, singular: "pipe"), systemImage: "line.diagonal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if plan.objectPlacements.isEmpty && plan.pipeSegments.isEmpty && plan.outlinePoints.isEmpty {
                Text("No annotations yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("No annotations yet")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    // MARK: - Snapshots section

    @ViewBuilder
    private var snapshotsSection: some View {
        if !store.draft.floorPlanSnapshots.isEmpty {
            Section {
                ForEach(store.draft.floorPlanSnapshots) { snapshot in
                    HStack {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.imageRef)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text(snapshot.captureTimestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { i in
                        store.removeFloorPlanSnapshot(id: store.draft.floorPlanSnapshots[i].id)
                    }
                }
            } header: {
                Text("Saved Snapshots (\(store.draft.floorPlanSnapshots.count))")
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var draft = CaptureSessionDraft()
    draft.visitReference = "JOB-001"
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Kitchen"
    scan.rawWidthM = 4.2
    scan.rawDepthM = 3.8
    var plan = FloorPlanDraft()
    plan.outlinePoints = [
        NormalisedPoint(x: 0.1, y: 0.1),
        NormalisedPoint(x: 0.9, y: 0.1),
        NormalisedPoint(x: 0.9, y: 0.9),
        NormalisedPoint(x: 0.1, y: 0.9)
    ]
    plan.objectPlacements = [
        FloorPlanObjectPlacement(type: .boiler, label: "Boiler", position: NormalisedPoint(x: 0.3, y: 0.3))
    ]
    scan.floorPlan = plan
    draft.roomScans = [scan]
    let store = CaptureSessionStore(draft: draft)
    return NavigationStack {
        FloorPlanReviewView(store: store)
    }
}
#endif
