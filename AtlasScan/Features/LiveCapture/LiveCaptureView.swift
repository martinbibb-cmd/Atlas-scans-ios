import SwiftUI

// MARK: - CaptureMode
//
// The swipeable capture modes available during a live session.
// The engineer swipes left/right between modes; the active mode
// changes the bottom HUD tools and AR overlay hints.

enum CaptureMode: Int, CaseIterable, Identifiable {
    case roomScan      = 0
    case tagObject     = 1
    case photo         = 2
    case pointCloud    = 3
    case measure       = 4
    case floorPlan     = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .roomScan:   return "Room Scan"
        case .tagObject:  return "Tag Object"
        case .photo:      return "Photo"
        case .pointCloud: return "3D Scan"
        case .measure:    return "Measure"
        case .floorPlan:  return "Floor Plan"
        }
    }

    var symbolName: String {
        switch self {
        case .roomScan:   return "lidar.scanner"
        case .tagObject:  return "mappin.and.ellipse"
        case .photo:      return "camera"
        case .pointCloud: return "cube.transparent"
        case .measure:    return "ruler"
        case .floorPlan:  return "map"
        }
    }

    /// True for modes that are available now; false for stubs pending hardware / API integration.
    var isAvailable: Bool {
        switch self {
        case .roomScan, .tagObject, .photo, .floorPlan: return true
        case .pointCloud, .measure: return false
        }
    }
}

// MARK: - LiveCaptureView
//
// The unified full-screen capture surface for one visit session.
//
// Layout:
//   • Full-screen LiDAR / camera background (or placeholder when no scans yet)
//   • Top HUD   — visit reference + recording indicator + "Finish" button
//   • Bottom HUD — swipeable CaptureMode selector + mode-specific action bar
//   • AR overlay — placed object pin labels floating over the live feed
//
// Voice recording starts automatically when this view appears.
// All capture actions are accessible without leaving this screen.

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
    @State private var showingTranscripts    = false

    // MARK: - Swipe mode state

    @State private var activeMode: CaptureMode = .roomScan

    // MARK: - Pin placement state

    @State private var pendingPinType: ObjectPinType? = nil

    // MARK: - Active room context

    @State private var activeRoomId: UUID? = nil

    // MARK: - Voice recorder (continuous, auto-started)

    @StateObject private var voiceRecorder = VoiceNoteRecorderViewModel()

    var body: some View {
        ZStack {
            cameraBackground
            arPinOverlay
            VStack(spacing: 0) {
                topHUD
                Spacer()
                captureModeStrip
                bottomHUD
            }
        }
        .ignoresSafeArea(edges: .all)
        .sheet(isPresented: $showingVoiceSheet) { voiceSheet }
        .sheet(isPresented: $showingPhotoSheet) { photoSheet }
        .sheet(isPresented: $showingObjectSheet) { objectSheet }
        .sheet(isPresented: $showingRoomsSheet) { roomsSheet }
        .sheet(isPresented: $showingTranscripts) { transcriptsSheet }
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
            Button("Finish & Review") { finishAndSave() }
            Button("Keep Capturing", role: .cancel) {}
        } message: {
            Text("Voice recording will be saved. You can review and export on the next screen.")
        }
        .onAppear { autoStartVoice() }
        .onDisappear { voiceRecorder.discard() }
    }

    // MARK: - Auto-start voice

    private func autoStartVoice() {
        guard voiceRecorder.state == .idle else { return }
        voiceRecorder.start(roomId: activeRoomId)
    }

    // MARK: - Finish and save

    private func finishAndSave() {
        // Stop continuous voice recording and save whatever was captured.
        if voiceRecorder.canStop {
            voiceRecorder.stop()
        }
        if voiceRecorder.canCommit, let note = voiceRecorder.commit() {
            store.addVoiceNote(note)
        }
        // Flush any pending debounced autosave so no data is lost when the view transitions.
        store.saveNow()
        onFinish()
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

            // Transcript shortcut (only when voice notes exist)
            if !store.draft.voiceNotes.isEmpty {
                Button {
                    showingTranscripts = true
                } label: {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

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

    // MARK: - Capture mode strip (swipeable)
    //
    // A horizontally-scrolling selector that lets the engineer swipe between
    // the six capture modes.  The active mode controls which tools appear
    // in the bottom action bar below.

    private var captureModeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeMode = mode
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 18, weight: .semibold))
                            Text(mode.title)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(activeMode == mode ? .white : .white.opacity(0.45))
                        .frame(minWidth: 72)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if activeMode == mode {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(height: 3)
                                    .padding(.horizontal, 12)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!mode.isAvailable)
                    .opacity(mode.isAvailable ? 1 : 0.35)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color.black.opacity(0.55))
    }

    // MARK: - Bottom HUD (mode-specific action bar)

    private var bottomHUD: some View {
        Group {
            switch activeMode {
            case .roomScan:
                roomScanActions
            case .tagObject:
                tagObjectActions
            case .photo:
                photoActions
            case .pointCloud:
                stubModeActions(title: "3D Point Cloud coming soon", symbol: "cube.transparent")
            case .measure:
                stubModeActions(title: "Measurement overlay coming soon", symbol: "ruler")
            case .floorPlan:
                floorPlanActions
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

    // Room Scan mode actions
    private var roomScanActions: some View {
        HStack(spacing: 0) {
            hudButton(
                symbol: voiceRecorder.state == .recording ? "mic.fill" : "mic",
                label: hudVoiceLabel,
                color: voiceRecorder.state == .recording ? .red : .white
            ) { handleVoiceTap() }

            hudButton(symbol: "lidar.scanner", label: "Scan Room", color: .white) {
                showingRoomCapture = true
            }

            hudButton(symbol: "map", label: roomsHUDLabel, color: .white) {
                showingRoomsSheet = true
            }
        }
    }

    // Tag Object mode actions
    private var tagObjectActions: some View {
        HStack(spacing: 0) {
            hudButton(
                symbol: pendingPinType != nil ? "mappin.circle.fill" : "mappin.and.ellipse",
                label: pendingPinType != nil ? "Cancel" : "Place Pin",
                color: pendingPinType != nil ? .yellow : .white
            ) {
                if pendingPinType != nil {
                    pendingPinType = nil
                } else {
                    showingObjectSheet = true
                }
            }

            hudButton(symbol: "camera", label: "Photo", color: .white) {
                showingPhotoSheet = true
            }

            hudButton(
                symbol: voiceRecorder.state == .recording ? "mic.fill" : "mic",
                label: hudVoiceLabel,
                color: voiceRecorder.state == .recording ? .red : .white
            ) { handleVoiceTap() }
        }
    }

    // Photo mode actions
    private var photoActions: some View {
        HStack(spacing: 0) {
            hudButton(symbol: "camera.fill", label: "Take Photo", color: .white) {
                showingPhotoSheet = true
            }

            hudButton(
                symbol: voiceRecorder.state == .recording ? "mic.fill" : "mic",
                label: hudVoiceLabel,
                color: voiceRecorder.state == .recording ? .red : .white
            ) { handleVoiceTap() }
        }
    }

    // Floor Plan mode actions
    private var floorPlanActions: some View {
        HStack(spacing: 0) {
            if let latestScan = store.draft.roomScans.last {
                hudButton(symbol: "pencil.and.ruler", label: "Edit Floor Plan", color: .white) {
                    showingFloorPlanEditor = latestScan
                }
            }

            hudButton(symbol: "lidar.scanner", label: "Scan Room", color: .white) {
                showingRoomCapture = true
            }
        }
    }

    // Stub placeholder for modes not yet fully implemented
    private func stubModeActions(title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .thin))
                .foregroundStyle(.white.opacity(0.5))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
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
    //
    // Tap to pause/resume or create a manual note marker.
    // The continuous session-level recording starts automatically on view appear.

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
            // Restart continuous recording for the rest of the session.
            voiceRecorder.start(roomId: activeRoomId)
        } onDiscard: {
            voiceRecorder.discard()
            showingVoiceSheet = false
            // Restart continuous recording even after discard.
            voiceRecorder.start(roomId: activeRoomId)
        }
    }

    private var transcriptsSheet: some View {
        NavigationStack {
            TranscriptView(draft: store.draft)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingTranscripts = false }
                    }
                }
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
                Section {
                    if recorder.isTranscribing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Transcribing…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextEditor(text: $recorder.transcript)
                        .frame(minHeight: 100)
                } header: {
                    Text("Transcript")
                } footer: {
                    if recorder.isTranscribing {
                        Text("Auto-transcribing your recording. You can edit the text when it appears.")
                            .font(.caption2)
                    }
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
                            .foregroundStyle(Color.accentColor)
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

        // Derive the floor-plan outline from the room's wall geometry so the
        // FloorPlanEditorView shows the scanned perimeter instead of a blank canvas.
        let polygon = PlacementService.layoutPolygon(for: room)
        if polygon.count >= 2 {
            var plan = FloorPlanDraft()
            plan.outlinePoints = polygon.map { NormalisedPoint(x: $0.x, y: $0.y) }
            self.floorPlan = plan
        }
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
