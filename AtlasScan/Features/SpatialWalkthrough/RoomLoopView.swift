import SwiftUI
import AtlasContracts

// MARK: - RoomCaptureStep
//
// The three-step cycle every room must complete before the engineer
// can move to the next space.

enum RoomCaptureStep: Int, CaseIterable {
    case geometry    = 0    // Step A: LiDAR scan
    case pinning     = 1    // Step B: spatial object pins
    case clearance   = 2    // Step C: clearance verification

    var displayName: String {
        switch self {
        case .geometry:  return "Geometry"
        case .pinning:   return "Pinning"
        case .clearance: return "Clearance"
        }
    }

    var symbolName: String {
        switch self {
        case .geometry:  return "lidar.scanner"
        case .pinning:   return "mappin.and.ellipse"
        case .clearance: return "checkmark.shield"
        }
    }
}

// MARK: - RoomLoopStepStatus

enum RoomLoopStepStatus {
    case pending
    case inProgress
    case complete
    case flagged        // has QA flags needing review

    var color: Color {
        switch self {
        case .pending:    return .secondary
        case .inProgress: return .blue
        case .complete:   return .green
        case .flagged:    return .orange
        }
    }

    var symbolName: String {
        switch self {
        case .pending:    return "circle"
        case .inProgress: return "circle.dotted"
        case .complete:   return "checkmark.circle.fill"
        case .flagged:    return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - RoomLoopView
//
// Guides the engineer through the three-step capture loop for a single room.
// Each step must be marked complete before the "Done — Add Next Room" action
// becomes available.

struct RoomLoopView: View {

    // MARK: - Dependencies

    @ObservedObject var store: CaptureSessionStore

    /// The room scan draft this loop is managing.
    let roomScan: CapturedRoomScanDraft

    /// Called when all three steps are complete and the engineer taps "Add Next Room".
    let onNextRoom: () -> Void

    /// Called when the engineer taps "Finish Walkthrough".
    let onFinish: () -> Void

    // MARK: - State

    @State private var currentStep: RoomCaptureStep = .geometry
    @State private var showingLiDARCapture = false
    @State private var showingPinList      = false
    @State private var showingClearance    = false
    @State private var showingPinDial      = false
    @State private var selectedPin: CapturedObjectPinDraft?

    @State private var geometryDone  = false
    @State private var pinningDone   = false
    @State private var clearanceDone = false

    @State private var openFloorPlanForScan: CapturedRoomScanDraft?

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                roomHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                stepProgress
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                currentStepCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                if allStepsComplete {
                    nextRoomActions
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(roomScan.roomLabel ?? "Room")
        .navigationBarTitleDisplayMode(.inline)
        // LiDAR room capture
        .fullScreenCover(isPresented: $showingLiDARCapture) {
            RoomPlanCaptureView(
                roomIndex: store.draft.roomScans.count
            ) { scan, pins, snapshot in
                store.updateRoomScan(scan)
                pins.forEach { store.addObjectPin($0) }
                store.addFloorPlanSnapshot(snapshot)
                showingLiDARCapture = false
                openFloorPlanForScan = scan
                geometryDone = true
                currentStep = .pinning
            } onCancel: {
                showingLiDARCapture = false
            }
        }
        // Floor-plan editor after scan
        .sheet(item: $openFloorPlanForScan) { scan in
            FloorPlanEditorView(
                scan: scan,
                onSnapshot: { snapshot in store.addFloorPlanSnapshot(snapshot) },
                onSave: { updated in
                    store.updateRoomScan(updated)
                    openFloorPlanForScan = nil
                }
            )
        }
        // Object pin list (Step B)
        .sheet(isPresented: $showingPinList) {
            NavigationStack {
                ObjectPinListView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingPinList = false
                                pinningDone = !pinsForRoom.isEmpty
                                if pinningDone { currentStep = .clearance }
                            }
                        }
                    }
            }
        }
        // LiDAR clearance check (Step C)
        .sheet(isPresented: $showingClearance) {
            NavigationStack {
                LiDARClearanceView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingClearance = false
                                clearanceDone = true
                            }
                        }
                    }
            }
        }
        // Spatial pin dial (pin contextual menu)
        .sheet(item: $selectedPin) { pin in
            SpatialPinDialView(
                pin: pin,
                roomId: roomScan.id,
                store: store
            ) {
                selectedPin = nil
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Room header

    private var roomHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(roomScan.roomLabel ?? "Unnamed Room")
                    .font(.title3.bold())
                if let w = roomScan.rawWidthM, let d = roomScan.rawDepthM {
                    Text(String(format: "%.1f × %.1f m", w, d))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Geometry not yet captured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            completionBadge
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var completionBadge: some View {
        let count = [geometryDone, pinningDone, clearanceDone].filter { $0 }.count
        let color: Color = count == 3 ? .green : .orange
        return Text("\(count)/3")
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Step progress strip

    private var stepProgress: some View {
        HStack(spacing: 0) {
            ForEach(RoomCaptureStep.allCases, id: \.rawValue) { step in
                stepPill(step)
                if step.rawValue < RoomCaptureStep.allCases.count - 1 {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func stepPill(_ step: RoomCaptureStep) -> some View {
        let isDone = stepDone(step)
        let isActive = step == currentStep
        let color: Color = isDone ? .green : (isActive ? .blue : .secondary)

        return VStack(spacing: 4) {
            Image(systemName: isDone ? "checkmark.circle.fill" : step.symbolName)
                .foregroundStyle(color)
                .font(isActive ? .title3 : .body)
            Text(step.displayName)
                .font(.caption2.bold())
                .foregroundStyle(color)
        }
        .frame(minWidth: 64)
        .animation(.easeInOut(duration: 0.2), value: currentStep)
    }

    private func stepDone(_ step: RoomCaptureStep) -> Bool {
        switch step {
        case .geometry:  return geometryDone
        case .pinning:   return pinningDone
        case .clearance: return clearanceDone
        }
    }

    // MARK: - Current step card

    @ViewBuilder
    private var currentStepCard: some View {
        switch currentStep {
        case .geometry:
            geometryCard
        case .pinning:
            pinningCard
        case .clearance:
            clearanceCard
        }
    }

    // MARK: Step A – Geometry

    private var geometryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepCardHeader(
                title: "Step A — Geometry Capture",
                subtitle: "Scan the room with LiDAR to capture raw dimensions and mesh for heat-loss calculations.",
                symbol: "lidar.scanner"
            )
            Divider()

            if geometryDone {
                if let w = roomScan.rawWidthM, let d = roomScan.rawDepthM, let h = roomScan.rawHeightM {
                    dimensionRow("Width",   value: String(format: "%.2f m", w))
                    dimensionRow("Depth",   value: String(format: "%.2f m", d))
                    dimensionRow("Height",  value: String(format: "%.2f m", h))
                }
                HStack(spacing: 10) {
                    Button("Rescan") {
                        geometryDone = false
                        showingLiDARCapture = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button("Continue to Pinning →") {
                        currentStep = .pinning
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    showingLiDARCapture = true
                } label: {
                    Label("Start LiDAR Scan", systemImage: "lidar.scanner")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Step B – Pinning

    private var pinningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepCardHeader(
                title: "Step B — Spatial Pinning",
                subtitle: "Tag the boiler, cylinder, flue, and any other key objects. Tap a pin to snap a photo, dictate a note, or measure clearance.",
                symbol: "mappin.and.ellipse"
            )
            Divider()

            if pinsForRoom.isEmpty {
                Text("No pins placed yet for this room.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pinsForRoom) { pin in
                    pinRow(pin)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showingPinList = true
                } label: {
                    Label(pinsForRoom.isEmpty ? "Add Pins" : "Edit Pins", systemImage: "mappin.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !pinsForRoom.isEmpty {
                    Button("Continue to Clearance →") {
                        pinningDone = true
                        currentStep = .clearance
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var pinsForRoom: [CapturedObjectPinDraft] {
        store.draft.objectPins.filter { $0.roomId == roomScan.id }
    }

    private func pinRow(_ pin: CapturedObjectPinDraft) -> some View {
        Button {
            selectedPin = pin
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pin.type.symbolName)
                    .frame(width: 24)
                    .foregroundStyle(.blue)
                Text(pin.displayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Step C – Clearance

    private var clearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepCardHeader(
                title: "Step C — Clearance Verification",
                subtitle: "Verify manufacturer clearances around the boiler and any other pinned appliances using the LiDAR sensor.",
                symbol: "checkmark.shield"
            )
            Divider()

            ClearanceCubeOverlayView(
                roomScan: roomScan,
                objectPins: pinsForRoom
            )
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if clearanceDone {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Clearance checked")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showingClearance = true
                } label: {
                    Label(clearanceDone ? "Re-check Clearances" : "Measure Clearances", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(clearanceDone ? .bordered : .borderedProminent)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Next-room / finish actions

    private var nextRoomActions: some View {
        VStack(spacing: 10) {
            Button {
                onNextRoom()
            } label: {
                Label("Add Next Room", systemImage: "plus.square.on.square")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Button {
                onFinish()
            } label: {
                Label("Finish Walkthrough", systemImage: "checkmark.seal")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    // MARK: - Helpers

    private var allStepsComplete: Bool {
        geometryDone && pinningDone && clearanceDone
    }

    private func stepCardHeader(title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dimensionRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
        .font(.subheadline)
    }
}

// MARK: - CapturedObjectPinDraft display helpers

private extension CapturedObjectPinDraft {
    var displayLabel: String {
        if let l = label, !l.isEmpty { return l }
        return type.displayName
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = CaptureSessionStore(
        draft: CaptureSessionStore.newSession(visitReference: "PREVIEW-001"),
        persistence: .shared
    )
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Kitchen"
    scan.rawWidthM = 4.2
    scan.rawDepthM = 3.8
    scan.rawHeightM = 2.4
    store.addRoomScan(scan)

    return NavigationStack {
        RoomLoopView(store: store, roomScan: scan, onNextRoom: {}, onFinish: {})
    }
}
#endif
