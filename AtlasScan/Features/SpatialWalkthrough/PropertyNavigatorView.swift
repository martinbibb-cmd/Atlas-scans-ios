import SwiftUI
import AtlasContracts

// MARK: - PropertyNavigatorView
//
// The "Spatial-First" property navigator — the primary home screen for a
// visit capture session.
//
// Design:
//   • Replaces the fragmented "card-based" CaptureHubView with a room-by-room
//     spatial walkthrough that treats the property as a continuous 3-D canvas.
//   • Rooms are added incrementally; each follows the 3-step Room Loop
//     (Geometry → Pinning → Clearance).
//   • A global readiness gate blocks the "Export" button until all key
//     evidence requirements are met (VisitReadinessV1).
//   • Outdoor Flue Mode and Van Mode are accessible from the navigator.
//
// "One visit, one property, one spatial session."

struct PropertyNavigatorView: View {

    // MARK: - Dependencies

    @ObservedObject var store: CaptureSessionStore

    // MARK: - Navigation state

    @State private var activeRoom: CapturedRoomScanDraft?
    @State private var showingNewRoomOptions   = false
    @State private var showingLiDARCapture     = false
    @State private var showingManualEntry      = false
    @State private var showingOutdoorFlue      = false
    @State private var showingVanMode          = false
    @State private var showingExportReadiness  = false
    @State private var destination: NavigatorDestination?
    @State private var openFloorPlanForScan: CapturedRoomScanDraft?

    // MARK: - Body

    var body: some View {
        // Split the modifier chain across two properties so Swift's type-checker
        // can resolve each sub-expression independently without timing out.
        navigatorStackWithSheets
            .confirmationDialog("Add Room", isPresented: $showingNewRoomOptions, titleVisibility: .visible) {
                Button("Scan with LiDAR") {
                    showingLiDARCapture = true
                }
                Button("Enter Manually") {
                    showingManualEntry = true
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    /// Layers the floor-plan, manual-entry, and export-readiness sheets onto
    /// the navigator stack. Kept separate from `body` so each modifier chain
    /// stays within Swift's type-checker complexity budget.
    private var navigatorStackWithSheets: some View {
        navigatorStack
            .sheet(item: $openFloorPlanForScan, content: floorPlanEditorSheet)
            .sheet(isPresented: $showingManualEntry) { manualEntrySheet }
            .sheet(isPresented: $showingExportReadiness) { exportReadinessSheet }
    }

    @ViewBuilder
    private func floorPlanEditorSheet(for scan: CapturedRoomScanDraft) -> some View {
        FloorPlanEditorView(
            scan: scan,
            onSnapshot: { snapshot in store.addFloorPlanSnapshot(snapshot) },
            onSave: { updated in
                store.updateRoomScan(updated)
                openFloorPlanForScan = nil
            }
        )
    }

    @ViewBuilder private var manualEntrySheet: some View {
        RoomScanManualEntrySheet { scan in
            store.addRoomScan(scan)
            showingManualEntry = false
            activeRoom = scan
        }
    }

    @ViewBuilder private var exportReadinessSheet: some View {
        NavigationStack {
            ReviewExportView(store: store)
        }
    }

    /// Scroll body split out so the VStack's generic type chain stays within
    /// Swift's type-checker complexity budget.
    @ViewBuilder
    private var scrollBody: some View {
        propertyHeader
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

        readinessBar
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

        roomStack
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

        addRoomButton
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

        specialisedModes
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

        exportFooter
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
    }

    /// Inner navigation stack with scroll content and primary presentation layers.
    /// Kept in a separate computed property so the outer `body` chain stays short
    /// enough for Swift's type-checker.
    private var navigatorStack: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    scrollBody
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Property Navigator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            // Room loop navigation
            .navigationDestination(item: $activeRoom) { room in
                RoomLoopView(
                    store: store,
                    roomScan: room,
                    onNextRoom: {
                        activeRoom = nil
                        showingNewRoomOptions = true
                    },
                    onFinish: {
                        activeRoom = nil
                    }
                )
            }
        }
        // Outdoor flue mode
        .sheet(isPresented: $showingOutdoorFlue) { outdoorFlueSheet }
        // Van mode review
        .sheet(isPresented: $showingVanMode) { vanModeSheet }
        // LiDAR capture for new room
        .fullScreenCover(isPresented: $showingLiDARCapture) { lidarCaptureSheet }
    }

    @ViewBuilder private var outdoorFlueSheet: some View {
        OutdoorFlueModeView(store: store)
    }

    @ViewBuilder private var vanModeSheet: some View {
        NavigationStack {
            VanModeReviewView(store: store)
        }
    }

    @ViewBuilder private var lidarCaptureSheet: some View {
        #if false
        RoomPlanCaptureView(
            visitId: store.draft.id,
            roomIndex: store.draft.roomScans.count + 1
        ) { scan, pins, snapshot in
            store.addRoomScan(scan)
            pins.forEach { store.addObjectPin($0) }
            store.addFloorPlanSnapshot(snapshot)
            showingLiDARCapture = false
            openFloorPlanForScan = scan
            activeRoom = scan
        } onCancel: {
            showingLiDARCapture = false
        }
        #else
        EmptyView()
        #endif
    }

    // MARK: - Property header

    private var propertyHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.draft.visitReference.isEmpty ? "New Visit" : store.draft.visitReference)
                    .font(.title2.bold())
                if !store.draft.propertyAddress.isEmpty {
                    Text(store.draft.propertyAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(store.draft.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            exportStateBadge
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var exportStateBadge: some View {
        Text(store.draft.exportState.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(exportStateBadgeColor.opacity(0.15))
            .foregroundStyle(exportStateBadgeColor)
            .clipShape(Capsule())
    }

    private var exportStateBadgeColor: Color {
        switch store.draft.exportState {
        case .draft:          return .orange
        case .readyForExport: return .blue
        case .exported:       return .green
        case .exportFailed:   return .red
        }
    }

    // MARK: - Readiness bar

    private var currentReadiness: VisitReadinessV1 {
        VisitReadinessBuilder.build(from: store.draft)
    }

    private var currentReadinessFlags: [ReadinessFlag] {
        readinessFlags(from: currentReadiness)
    }

    private var readinessMetCount: Int {
        currentReadinessFlags.filter { $0.met }.count
    }

    private var readinessTotalCount: Int {
        currentReadinessFlags.count
    }

    private var allReadinessMet: Bool {
        readinessMetCount == readinessTotalCount
    }

    @ViewBuilder
    private var readinessBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Readiness")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(readinessMetCount)/\(readinessTotalCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(allReadinessMet ? .green : .orange)
            }

            HStack(spacing: 8) {
                ForEach(currentReadinessFlags, id: \.label) { flag in
                    readinessPill(flag)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private struct ReadinessFlag {
        let label: String
        let symbol: String
        let met: Bool
    }

    private func readinessFlags(from r: VisitReadinessV1) -> [ReadinessFlag] {
        [
            ReadinessFlag(label: "Rooms",   symbol: "cube.transparent",   met: r.hasRooms),
            ReadinessFlag(label: "Photos",  symbol: "camera",             met: r.hasPhotos),
            ReadinessFlag(label: "Boiler",  symbol: "flame",              met: r.hasBoiler),
            ReadinessFlag(label: "Flue",    symbol: "arrow.up.to.line",   met: r.hasFlue),
            ReadinessFlag(label: "Notes",   symbol: "mic",                met: r.hasNotes),
        ]
    }

    private func readinessPill(_ flag: ReadinessFlag) -> some View {
        VStack(spacing: 3) {
            Image(systemName: flag.met ? "checkmark.circle.fill" : flag.symbol)
                .font(.caption2)
                .foregroundStyle(flag.met ? .green : Color(.tertiaryLabel))
            Text(flag.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(flag.met ? Color.primary : Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Room stack

    @ViewBuilder
    private var roomStack: some View {
        if store.draft.roomScans.isEmpty {
            emptyRoomsState
        } else {
            VStack(spacing: 8) {
                ForEach(store.draft.roomScans.indices, id: \.self) { index in
                    roomCard(store.draft.roomScans[index], number: index + 1)
                }
            }
        }
    }

    private var emptyRoomsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No rooms yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tap \"Add Room\" to start the spatial walkthrough.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func roomCard(_ scan: CapturedRoomScanDraft, number: Int) -> some View {
        let pinsCount   = store.draft.objectPins.filter { $0.roomId == scan.id }.count
        let photosCount = store.draft.photos.filter     { $0.roomId == scan.id }.count
        let loopDone    = pinsCount > 0 && scan.rawWidthM != nil

        return Button {
            activeRoom = scan
        } label: {
            HStack(spacing: 12) {
                Color.secondary.opacity(0.1).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .bottomTrailing) {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(scan.roomLabel ?? "Room \(number)")
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if let w = scan.rawWidthM, let d = scan.rawDepthM {
                            Text(String(format: "%.1f×%.1f m", w, d))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if pinsCount > 0 {
                            artefactChip("\(pinsCount) pin(s)", symbol: "mappin.circle", color: .blue)
                        }
                        if photosCount > 0 {
                            artefactChip("\(photosCount) photo(s)", symbol: "camera", color: .purple)
                        }
                    }
                }

                Spacer()

                Image(systemName: loopDone ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(loopDone ? Color.green : Color(.tertiaryLabel))
                    .font(loopDone ? .body : .caption)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func artefactChip(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - Add room button

    private var addRoomButton: some View {
        Button {
            showingNewRoomOptions = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.square.on.square")
                Text(store.draft.roomScans.isEmpty ? "Scan First Room" : "Add Room")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    // MARK: - Specialised modes

    private var specialisedModes: some View {
        VStack(spacing: 8) {
            modeCard(
                title: "Outdoor Flue Mode",
                subtitle: "Pin the flue terminal and nearby windows/doors to measure clearances",
                symbol: "arrow.up.to.line.circle",
                color: .orange
            ) {
                showingOutdoorFlue = true
            }

            modeCard(
                title: "Van Mode — Review",
                subtitle: "Review captured room scans and add retrospective annotations off-site",
                symbol: "car.circle",
                color: .indigo
            ) {
                showingVanMode = true
            }
        }
    }

    private func modeCard(
        title: String,
        subtitle: String,
        symbol: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export footer

    private var exportIsReady: Bool {
        let noConflicts = !store.draft.hasClearanceConflicts
        return currentReadiness.hasRooms && currentReadiness.hasPhotos && currentReadiness.hasBoiler && currentReadiness.hasFlue && noConflicts
    }

    @ViewBuilder
    private var exportFooter: some View {
        VStack(spacing: 8) {
            if !exportIsReady {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Complete rooms, photos, boiler tag, flue tag, and clearance verification to unlock export.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                showingExportReadiness = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: exportIsReady ? "arrow.up.doc.fill" : "lock.fill")
                    Text(exportIsReady ? "Review & Export to Atlas Mind" : "Review Capture")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(exportIsReady ? .green : .gray)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text("Property Navigator")
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
}

// MARK: - NavigatorDestination

private enum NavigatorDestination: Hashable {
    case roomLoop(id: UUID)
}

// MARK: - VisitReadinessBuilder convenience

/// Builds a VisitReadinessV1 from the current CaptureSessionDraft without
/// requiring an AtlasScanVisit.
enum VisitReadinessBuilder {
    static func build(from draft: CaptureSessionDraft) -> VisitReadinessV1 {
        let pins = draft.objectPins
        return VisitReadinessV1(
            hasRooms:         !draft.roomScans.isEmpty,
            hasPhotos:        !draft.photos.isEmpty,
            hasHeatingSystem: pins.contains { $0.type == .boiler || $0.type == .heatPump },
            hasHotWaterSystem: pins.contains { $0.type == .cylinder },
            hasBoiler:        pins.contains { $0.type == .boiler || $0.type == .heatPump },
            hasFlue:          pins.contains { $0.type == .flue },
            hasNotes:         !draft.voiceNotes.isEmpty
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Empty") {
    PropertyNavigatorView(
        store: CaptureSessionStore(
            draft: CaptureSessionStore.newSession(visitReference: "JOB-2025-0001"),
            persistence: .shared
        )
    )
}

#Preview("With Rooms") {
    var draft = CaptureSessionStore.newSession(visitReference: "JOB-2025-0002")
    draft.propertyAddress = "42 Elm Street, Bristol"
    var r1 = CapturedRoomScanDraft(); r1.roomLabel = "Kitchen"; r1.rawWidthM = 4.2; r1.rawDepthM = 3.8
    var r2 = CapturedRoomScanDraft(); r2.roomLabel = "Utility";  r2.rawWidthM = 2.1; r2.rawDepthM = 1.8
    draft.roomScans = [r1, r2]
    var boiler = CapturedObjectPinDraft(type: .boiler); boiler.roomId = r1.id
    var flue   = CapturedObjectPinDraft(type: .flue);   flue.roomId   = r2.id
    draft.objectPins = [boiler, flue]
    let photo = CapturedPhotoDraft(localFilename: "photo1.jpg")
    draft.photos = [photo]
    let store = CaptureSessionStore(draft: draft, persistence: .shared)
    return PropertyNavigatorView(store: store)
}
#endif
