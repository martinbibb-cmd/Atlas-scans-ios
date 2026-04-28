import SwiftUI

// MARK: - LiveCaptureView
//
// The unified full-screen capture surface for one visit session.
//
// Layout:
//   • Full-screen LiDAR / camera background (or placeholder when no scans yet)
//   • Top HUD   — visit reference + recording indicator + "Finish" button
//   • Bottom HUD — Voice / Photo / Object / Rooms action buttons
//   • AR overlay — placed object pin labels floating over the live feed
//
// All capture actions (voice, photo, object, room) are accessible as overlay
// sheets without leaving this screen.  "One screen, one visit."

struct LiveCaptureView: View {

    @ObservedObject var store: CaptureSessionStore
    let onFinish: () -> Void

    // MARK: - Sheet state

    @State private var showingVoiceSheet     = false
    @State private var showingPhotoSheet     = false
    @State private var showingObjectSheet    = false
    @State private var showingRoomsSheet     = false
    @State private var showingRoomCapture    = false
    @State private var showingFloorPlanEditor: CapturedRoomScanDraft? = nil
    @State private var showingFinishConfirm  = false

    // MARK: - Pin placement state

    /// When non-nil, the next tap on the canvas places a pin of this type.
    @State private var pendingPinType: ObjectPinType? = nil

    // MARK: - Active room context

    /// The room currently in focus; voice notes and photos auto-attach here.
    @State private var activeRoomId: UUID? = nil

    // MARK: - Voice recorder (inline, not a sheet ViewModel)

    @StateObject private var voiceRecorder = VoiceNoteRecorderViewModel()

    var body: some View {
        ZStack {
            cameraBackground
            arPinOverlay
            VStack(spacing: 0) {
                topHUD
                Spacer()
                bottomHUD
            }
        }
        .ignoresSafeArea(edges: .all)
        .sheet(isPresented: $showingVoiceSheet) { voiceSheet }
        .sheet(isPresented: $showingPhotoSheet) { photoSheet }
        .sheet(isPresented: $showingObjectSheet) { objectSheet }
        .sheet(isPresented: $showingRoomsSheet) { roomsSheet }
        .fullScreenCover(isPresented: $showingRoomCapture) { roomCaptureModal }
        .sheet(item: $showingFloorPlanEditor) { scan in
            FloorPlanEditorView(scan: scan) { updatedScan in
                store.updateRoomScan(updatedScan)
            }
        }
        .confirmationDialog(
            "Finish Capture?",
            isPresented: $showingFinishConfirm,
            titleVisibility: .visible
        ) {
            Button("Finish & Review") { onFinish() }
            Button("Keep Capturing", role: .cancel) {}
        } message: {
            Text("You can review and export the session on the next screen.")
        }
        .onDisappear { voiceRecorder.discard() }
    }

    // MARK: - Camera background

    private var cameraBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if store.draft.roomScans.isEmpty {
                placeholderBackground
            }
        }
    }

    private var placeholderBackground: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.25))
            Text("Tap Rooms → Scan New Room to start LiDAR capture")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - AR pin overlay

    private var arPinOverlay: some View {
        GeometryReader { geo in
            ZStack {
                if pendingPinType != nil {
                    // Transparent tap target for placing a pin
                    Color.white.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { location in
                            placePinAt(location: location, in: geo.size)
                        }
                    placePinBanner
                }
                // Floating labels for pins that have screen-space positions
                ForEach(store.draft.objectPins) { pin in
                    if let x = pin.approximatePositionX,
                       let y = pin.approximatePositionY {
                        arPinLabel(pin)
                            .position(
                                x: x * geo.size.width,
                                y: y * geo.size.height
                            )
                    }
                }
            }
        }
    }

    private var placePinBanner: some View {
        Text("Tap to place \(pendingPinType?.displayName ?? "pin")")
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 90)
    }

    private func arPinLabel(_ pin: CapturedObjectPinDraft) -> some View {
        HStack(spacing: 4) {
            Image(systemName: pin.type.symbolName)
                .font(.caption2.bold())
            Text(pin.label ?? pin.type.displayName)
                .font(.caption2.bold())
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.85))
        .clipShape(Capsule())
    }

    // MARK: - Top HUD

    private var topHUD: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.draft.visitReference.isEmpty ? "No Reference" : store.draft.visitReference)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !store.draft.propertyAddress.isEmpty {
                    Text(store.draft.propertyAddress)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            if voiceRecorder.state == .recording || voiceRecorder.state == .paused {
                recordingIndicator
            }

            saveStateBadge

            Button {
                showingFinishConfirm = true
            } label: {
                Text("Finish")
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.top, 54)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var recordingIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(voiceRecorder.state == .recording ? Color.red : Color.orange)
                .frame(width: 8, height: 8)
            Text(voiceRecorder.elapsedTimeText)
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var saveStateBadge: some View {
        switch store.saveState {
        case .unsaved:
            Text("●")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .saving:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.7)
        case .saved:
            EmptyView()
        }
    }

    // MARK: - Bottom HUD

    private var bottomHUD: some View {
        HStack(spacing: 0) {
            // Voice — tap to start/stop; opens sheet to save/discard after stop
            hudButton(
                symbol: voiceRecorder.state == .recording ? "mic.fill" : "mic",
                label: hudVoiceLabel,
                color: voiceRecorder.state == .recording ? .red : .white
            ) { handleVoiceTap() }

            // Photo — opens system camera sheet
            hudButton(symbol: "camera", label: "Photo", color: .white) {
                showingPhotoSheet = true
            }

            // Object — tap to pick type (then tap canvas to place), or cancel
            hudButton(
                symbol: pendingPinType != nil ? "mappin.circle.fill" : "mappin.and.ellipse",
                label: pendingPinType != nil ? "Cancel" : "Object",
                color: pendingPinType != nil ? .yellow : .white
            ) {
                if pendingPinType != nil {
                    pendingPinType = nil
                } else {
                    showingObjectSheet = true
                }
            }

            // Rooms — manage / scan rooms
            hudButton(symbol: "map", label: roomsHUDLabel, color: .white) {
                showingRoomsSheet = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .padding(.bottom, 28)
        .background(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var hudVoiceLabel: String {
        switch voiceRecorder.state {
        case .idle:      return "Voice"
        case .recording: return "Stop"
        case .paused:    return "Resume"
        case .stopped:   return "Save"
        }
    }

    private var roomsHUDLabel: String {
        let count = store.draft.roomScans.count
        return count == 0 ? "Rooms" : "Rooms (\(count))"
    }

    private func hudButton(
        symbol: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 50, height: 36)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Voice tap logic

    private func handleVoiceTap() {
        switch voiceRecorder.state {
        case .idle:
            voiceRecorder.start(roomId: activeRoomId)
        case .recording:
            voiceRecorder.stop()
            showingVoiceSheet = true
        case .paused:
            voiceRecorder.resume()
        case .stopped:
            showingVoiceSheet = true
        }
    }

    // MARK: - Sheets

    private var voiceSheet: some View {
        InlineVoiceCommitSheet(recorder: voiceRecorder, roomScans: store.draft.roomScans) { note in
            store.addVoiceNote(note)
            showingVoiceSheet = false
        } onDiscard: {
            voiceRecorder.discard()
            showingVoiceSheet = false
        }
    }

    private var photoSheet: some View {
        PhotoCaptureView(
            roomScans: store.draft.roomScans,
            objectPins: store.draft.objectPins
        ) { photo in
            store.addPhoto(photo)
            showingPhotoSheet = false
        }
    }

    private var objectSheet: some View {
        ObjectTypePickerSheet { selectedType in
            pendingPinType = selectedType
            showingObjectSheet = false
        }
    }

    private var roomsSheet: some View {
        NavigationStack {
            LiveCaptureRoomsSheet(
                store: store,
                activeRoomId: $activeRoomId,
                onScanRoom: {
                    showingRoomsSheet = false
                    showingRoomCapture = true
                },
                onEditFloorPlan: { scan in
                    showingFloorPlanEditor = scan
                    showingRoomsSheet = false
                }
            )
        }
    }

    private var roomCaptureModal: some View {
        NavigationStack {
            RoomCaptureContainerView(
                jobID: store.draft.id,
                roomName: "New Room",
                floor: 0
            ) { scannedRoom in
                let draft = CapturedRoomScanDraft(from: scannedRoom)
                store.addRoomScan(draft)
                showingRoomCapture = false
            }
            .navigationTitle("Room Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRoomCapture = false }
                }
            }
        }
    }

    // MARK: - Pin placement

    private func placePinAt(location: CGPoint, in canvasSize: CGSize) {
        guard let type = pendingPinType else { return }
        var pin = CapturedObjectPinDraft(type: type)
        pin.roomId = activeRoomId
        pin.approximatePositionX = Double(location.x / canvasSize.width)
        pin.approximatePositionY = Double(location.y / canvasSize.height)
        store.addObjectPin(pin)
        pendingPinType = nil
    }
}

// MARK: - InlineVoiceCommitSheet
//
// Shown after the engineer taps Stop so they can review/edit the transcript
// before saving.  The recorder is already in `.stopped` state.

struct InlineVoiceCommitSheet: View {
    @ObservedObject var recorder: VoiceNoteRecorderViewModel
    let roomScans: [CapturedRoomScanDraft]
    let onSave: (CapturedVoiceNoteDraft) -> Void
    let onDiscard: () -> Void

    @State private var selectedRoomId: UUID? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Transcript") {
                    TextEditor(text: $recorder.transcript)
                        .frame(minHeight: 100)
                }
                if !roomScans.isEmpty {
                    Section("Room") {
                        Picker("Room", selection: $selectedRoomId) {
                            Text("Session level").tag(UUID?.none)
                            ForEach(roomScans) { scan in
                                Text(scan.roomLabel ?? "Unnamed Room").tag(Optional(scan.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Save Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { onDiscard() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if var note = recorder.commit() {
                            note.roomId = selectedRoomId
                            onSave(note)
                        }
                    }
                    .disabled(!recorder.canCommit)
                }
            }
        }
    }
}

// MARK: - ObjectTypePickerSheet

struct ObjectTypePickerSheet: View {
    let onSelect: (ObjectPinType) -> Void
    @Environment(\.dismiss) private var dismiss

    private let categories: [(String, [ObjectPinType])] = [
        ("Plant", [.boiler, .heatPump, .cylinder, .pump]),
        ("Emitters", [.radiator, .towelRail]),
        ("Services", [.flue, .gasMeter, .stopTap]),
        ("Controls", [.thermostat, .control, .valve]),
        ("Other", [.airingCupboard, .evidencePoint, .genericNote])
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories, id: \.0) { category, types in
                    Section(category) {
                        ForEach(types) { type in
                            Button {
                                onSelect(type)
                            } label: {
                                Label(type.displayName, systemImage: type.symbolName)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Place Object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - LiveCaptureRoomsSheet

struct LiveCaptureRoomsSheet: View {
    @ObservedObject var store: CaptureSessionStore
    @Binding var activeRoomId: UUID?
    let onScanRoom: () -> Void
    let onEditFloorPlan: (CapturedRoomScanDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingLabel: CapturedRoomScanDraft? = nil
    @State private var labelText = ""

    var body: some View {
        List {
            Section {
                Button {
                    dismiss()
                    onScanRoom()
                } label: {
                    Label("Scan New Room", systemImage: "lidar.scanner")
                        .font(.body.bold())
                }
            }

            if !store.draft.roomScans.isEmpty {
                Section("Captured Rooms (\(store.draft.roomScans.count))") {
                    ForEach(store.draft.roomScans) { scan in
                        roomRow(scan)
                    }
                    .onDelete { indexSet in
                        let sorted = store.draft.roomScans
                        indexSet.forEach { i in store.removeRoomScan(id: sorted[i].id) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Rooms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Room Name", isPresented: Binding(
            get: { editingLabel != nil },
            set: { if !$0 { editingLabel = nil } }
        )) {
            TextField("e.g. Kitchen", text: $labelText)
            Button("Save") {
                if var scan = editingLabel {
                    scan.roomLabel = labelText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : labelText.trimmingCharacters(in: .whitespaces)
                    store.updateRoomScan(scan)
                    editingLabel = nil
                }
            }
            Button("Cancel", role: .cancel) { editingLabel = nil }
        }
    }

    private func roomRow(_ scan: CapturedRoomScanDraft) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if activeRoomId == scan.id {
                        Image(systemName: "scope")
                            .foregroundStyle(.accentColor)
                            .font(.caption.bold())
                    }
                    Text(scan.roomLabel ?? "Unnamed Room")
                        .font(.body)
                }
                HStack(spacing: 8) {
                    if let w = scan.rawWidthM, let d = scan.rawDepthM {
                        Text(String(format: "%.1f × %.1f m", w, d))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if scan.rawScanAssetRef != nil {
                        Label("LiDAR", systemImage: "checkmark.circle.fill")
                            .font(.caption2).foregroundStyle(.green)
                    }
                    if scan.floorPlan != nil {
                        Label("Annotated", systemImage: "pencil.tip.crop.circle.fill")
                            .font(.caption2).foregroundStyle(.blue)
                    }
                }
            }
            Spacer()
            Menu {
                Button("Set as Active Room") {
                    activeRoomId = (activeRoomId == scan.id) ? nil : scan.id
                }
                Button("Rename") {
                    labelText = scan.roomLabel ?? ""
                    editingLabel = scan
                }
                Button("Edit Floor Plan") {
                    onEditFloorPlan(scan)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeRoomId = (activeRoomId == scan.id) ? nil : scan.id
        }
    }
}

// MARK: - CapturedRoomScanDraft convenience init from ScannedRoom

extension CapturedRoomScanDraft {
    init(from room: ScannedRoom) {
        self.init()
        self.roomLabel = room.name.isEmpty ? nil : room.name
        if let area = room.areaSquareMetres {
            let side = area.squareRoot()
            self.rawWidthM = side
            self.rawDepthM = side
        }
        self.rawHeightM = room.ceilingHeightMetres
        self.confidence = room.geometryCaptured ? .high : .medium
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var draft = CaptureSessionDraft()
    draft.visitReference = "JOB-001"
    draft.propertyAddress = "12 Coronation Street"
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Kitchen"
    scan.rawWidthM = 3.2
    scan.rawDepthM = 4.1
    draft.roomScans = [scan]
    var pin = CapturedObjectPinDraft(type: .boiler)
    pin.label = "Worcester Bosch 30i"
    pin.approximatePositionX = 0.3
    pin.approximatePositionY = 0.4
    draft.objectPins = [pin]
    let store = CaptureSessionStore(draft: draft)
    return LiveCaptureView(store: store) {}
}
#endif
