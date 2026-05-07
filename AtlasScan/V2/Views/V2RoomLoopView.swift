/// V2RoomLoopView — Orchestrates repeated room captures until the user finishes.

import SwiftUI
import AtlasScanCore

struct V2RoomLoopView: View {
    @ObservedObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var capturedRoom: RoomCaptureV2?
    @State private var showCapture = true
    @State private var roomName = ""
    @State private var showNamePrompt = false
    @State private var showUnfinishedRoomRecovery = false
    @State private var captureViewRefreshToken = UUID()
    /// Pre-generated UUID shared with the live-capture view so photos, voice
    /// notes, and pins recorded during scanning already reference this room.
    @State private var prospectiveRoomId = UUID()
    /// Object pins placed during the scan; attached to the room on save.
    @State private var pendingPins: [SpatialPinV1] = []

    var body: some View {
        Group {
            if showCapture {
                LiveSpatialCaptureView(
                    capturedRoom: $capturedRoom,
                    rooms: coordinator.session.rooms,
                    visitId: coordinator.session.visitId,
                    prospectiveRoomId: prospectiveRoomId,
                    refreshToken: captureViewRefreshToken,
                    onExit: { dismiss() },
                    onPinAdded: { pin in pendingPins.append(pin) },
                    onPhotoAdded: { coordinator.addPhoto($0) },
                    onVoiceNoteAdded: { coordinator.addVoiceNote($0) },
                    onCaptureEndedWithoutRoom: { showUnfinishedRoomRecovery = true }
                )
                .ignoresSafeArea()
                .onChange(of: capturedRoom?.id) { _, newId in
                    if newId != nil {
                        showCapture = false
                        showNamePrompt = true
                    }
                }
            } else {
                // Brief pause between rooms — confirm and offer to add another.
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Room captured!")
                        .font(.title2.bold())
                    HStack(spacing: 16) {
                        Button("Add Another Room") {
                            capturedRoom = nil
                            pendingPins = []
                            prospectiveRoomId = UUID()
                            showCapture = true
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Finish") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Name this room", isPresented: $showNamePrompt, actions: {
            TextField("e.g. Kitchen", text: $roomName)
            Button("Save") { saveRoom() }
            Button("Cancel", role: .cancel) { showCapture = true }
        })
        .confirmationDialog(
            "Room wasn’t finalized",
            isPresented: $showUnfinishedRoomRecovery,
            titleVisibility: .visible
        ) {
            Button("Retry scan") { restartCurrentCapture() }
            Button("Save evidence as draft room") { saveDraftRoomEvidence() }
            Button("Discard unfinished room evidence", role: .destructive) {
                discardUnfinishedRoomEvidence()
            }
            Button("Continue capturing", role: .cancel) {}
        } message: {
            Text("This scan ended without a completed room. Retry, save current evidence as a draft room, or discard this unfinished room evidence.")
        }
    }

    private func saveRoom() {
        guard var room = capturedRoom else { return }
        room.displayName = roomName.isEmpty ? "Room \(coordinator.session.rooms.count + 1)" : roomName
        room.pinnedObjects = pendingPins
        coordinator.addRoom(room)
        Task { await coordinator.saveSession() }
        roomName = ""
        capturedRoom = nil
        pendingPins = []
        prospectiveRoomId = UUID()
    }

    private func restartCurrentCapture() {
        captureViewRefreshToken = UUID()
    }

    private func saveDraftRoomEvidence() {
        var draftRoom = RoomCaptureV2(
            id: prospectiveRoomId,
            displayName: "Draft Room \(coordinator.session.rooms.count + 1)"
        )
        draftRoom.pinnedObjects = pendingPins
        coordinator.addRoom(draftRoom)
        Task { await coordinator.saveSession() }
        roomName = ""
        capturedRoom = nil
        pendingPins = []
        prospectiveRoomId = UUID()
        showCapture = false
    }

    private func discardUnfinishedRoomEvidence() {
        coordinator.discardUnfinishedRoomEvidence(for: prospectiveRoomId)
        roomName = ""
        capturedRoom = nil
        pendingPins = []
        prospectiveRoomId = UUID()
        restartCurrentCapture()
    }
}

// MARK: - LiveSpatialCaptureView

private struct LiveSpatialCaptureView: View {
    /// Z-index layer that keeps Atlas HUD controls consistently above the
    /// RoomPlan base surface.
    private let hudOverlayLayer: Double = 10

    @Binding var capturedRoom: RoomCaptureV2?
    let rooms: [RoomCaptureV2]
    let visitId: UUID
    let prospectiveRoomId: UUID
    let refreshToken: UUID
    /// Called when the user dismisses the scan without saving (e.g. back gesture).
    let onExit: () -> Void
    let onPinAdded: (SpatialPinV1) -> Void
    let onPhotoAdded: (PhotoEvidenceV1) -> Void
    let onVoiceNoteAdded: (VoiceNoteV1) -> Void
    let onCaptureEndedWithoutRoom: () -> Void

    @State private var shouldStopCapture = false
    @State private var liveMapVertices: [Vertex2D] = []
    @State private var pendingPinsLocal: [SpatialPinV1] = []
    @State private var showObjectPicker = false
    @State private var showPhotoPicker = false
    @State private var showVoiceRecorder = false

    var body: some View {
        ZStack {
            V2RoomPlanCaptureView(
                capturedRoom: $capturedRoom,
                shouldStop: $shouldStopCapture,
                prospectiveRoomId: prospectiveRoomId,
                onLiveVertices: { verts in liveMapVertices = verts },
                onCaptureEndedWithoutRoom: {
                    shouldStopCapture = false
                    onCaptureEndedWithoutRoom()
                }
            )
            .id(refreshToken)
            .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    MiniMapHUD(
                        rooms: rooms,
                        livePolygonVertices: liveMapVertices,
                        pins: pendingPinsLocal
                    )
                    .zIndex(hudOverlayLayer)

                    Spacer()

                    if !pendingPinsLocal.isEmpty {
                        PinsCountBadge(count: pendingPinsLocal.count)
                            .zIndex(hudOverlayLayer)
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                CenterCaptureReticleButton()
                    .zIndex(hudOverlayLayer)

                BottomActionDock(
                    onObject: { showObjectPicker = true },
                    onPhoto:  { showPhotoPicker = true },
                    onVoice:  { showVoiceRecorder = true },
                    onFinish: { shouldStopCapture = true }
                )
                .zIndex(hudOverlayLayer)
            }
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showObjectPicker) {
            V2PinPickerSheet(roomId: prospectiveRoomId) { pin in
                pendingPinsLocal.append(pin)
                onPinAdded(pin)
                showObjectPicker = false
            }
        }
        .fullScreenCover(isPresented: $showPhotoPicker) {
            CameraPickerView { image in
                savePhoto(image)
                showPhotoPicker = false
            } onCancel: {
                showPhotoPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showVoiceRecorder) {
            V2VoiceNoteSheet(visitId: visitId, roomId: prospectiveRoomId) { note in
                onVoiceNoteAdded(note)
                showVoiceRecorder = false
            }
        }
    }

    // MARK: - Photo save

    private func savePhoto(_ image: UIImage) {
        do {
            let (filename, _) = try PhotoStore.shared.save(image)
            let photo = PhotoEvidenceV1(
                visitId: visitId,
                roomId: prospectiveRoomId,
                relativeFilePath: filename
            )
            onPhotoAdded(photo)
        } catch {
            print("[LiveSpatialCaptureView] Photo save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - CenterCaptureReticleButton

private struct CenterCaptureReticleButton: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: 72, height: 72)
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 44, height: 44)
            Image(systemName: "scope")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

// MARK: - BottomActionDock

private struct BottomActionDock: View {
    /// Minimum width of the Finish button so its text never wraps vertically
    /// even on small screen widths.
    fileprivate static let finishButtonMinWidth: CGFloat = 90

    let onObject: () -> Void
    let onPhoto: () -> Void
    let onVoice: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            dockButton(symbol: "mappin.circle", title: "Object", action: onObject)
            dockButton(symbol: "camera.circle", title: "Photo",  action: onPhoto)
            dockButton(symbol: "waveform.circle", title: "Voice", action: onVoice)
            Button(action: onFinish) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Finish")
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minWidth: BottomActionDock.finishButtonMinWidth)
                .background(.green.opacity(0.92), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 14)
    }

    private func dockButton(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title3)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PinsCountBadge

private struct PinsCountBadge: View {
    let count: Int

    var body: some View {
        Label("\(count) pin\(count == 1 ? "" : "s")", systemImage: "mappin.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - V2PinPickerSheet

private struct V2PinPickerSheet: View {
    let roomId: UUID
    let onSave: (SpatialPinV1) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: PinnedObjectType = .boiler
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Object type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(PinnedObjectType.allCases, id: \.self) { type in
                            Label(type.rawValue.capitalized, systemImage: iconName(for: type))
                                .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("Label (optional)") {
                    TextField("e.g. Worcester Combi", text: $label)
                }
                Section {
                    Text("Position will be marked as estimated. Refine in room review after scanning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Pin Object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Pin") { savePinAndDismiss() }
                }
            }
        }
    }

    private func savePinAndDismiss() {
        let pin = SpatialPinV1(
            roomId: roomId,
            positionX: 0, positionY: 0, positionZ: 0,
            objectType: selectedType,
            label: label.isEmpty ? nil : label,
            anchorConfidence: .estimated
        )
        onSave(pin)
    }

    private func iconName(for type: PinnedObjectType) -> String {
        switch type {
        case .boiler, .heatPump:    return "flame.fill"
        case .flueTerminal:         return "arrow.up.circle.fill"
        case .hotWaterCylinder:     return "drop.fill"
        case .electricalPanel:      return "bolt.fill"
        case .gasmeter:             return "gauge"
        case .nearbyOpening:        return "door.left.hand.open"
        case .other:                return "mappin"
        }
    }
}

// MARK: - V2VoiceNoteSheet

private struct V2VoiceNoteSheet: View {
    let visitId: UUID
    let roomId: UUID
    let onSave: (VoiceNoteV1) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceNoteRecorderViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                stateDisplay
                transcriptEditor
                controlBar
                Spacer()
            }
            .padding()
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.discard()
                        dismiss()
                    }
                }
                if recorder.canCommit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { commitNote() }
                    }
                }
            }
        }
    }

    // MARK: State display

    private var stateDisplay: some View {
        VStack(spacing: 8) {
            Image(systemName: recorderIcon)
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(recorderColor)
                .animation(.easeInOut, value: recorder.state)
            Text(recorder.elapsedTimeText)
                .font(.system(.title, design: .monospaced).bold())
            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var recorderIcon: String {
        switch recorder.state {
        case .idle:      return "mic.circle"
        case .recording: return "mic.fill"
        case .paused:    return "pause.circle.fill"
        case .stopped:   return "checkmark.circle.fill"
        }
    }

    private var recorderColor: Color {
        switch recorder.state {
        case .idle:      return .secondary
        case .recording: return .red
        case .paused:    return .orange
        case .stopped:   return .green
        }
    }

    private var stateLabel: String {
        switch recorder.state {
        case .idle:      return "Ready to record"
        case .recording: return "Recording…"
        case .paused:    return "Paused"
        case .stopped:   return "Recording complete — edit transcript below"
        }
    }

    // MARK: Transcript editor

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextEditor(text: $recorder.transcript)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: Control bar

    private var controlBar: some View {
        HStack(spacing: 16) {
            if recorder.canStart {
                controlButton(label: "Start", symbol: "record.circle.fill", color: .red) {
                    recorder.start(roomId: roomId)
                }
            }
            if recorder.canPause {
                controlButton(label: "Pause", symbol: "pause.circle.fill", color: .orange) {
                    recorder.pause()
                }
            }
            if recorder.canResume {
                controlButton(label: "Resume", symbol: "play.circle.fill", color: .blue) {
                    recorder.resume()
                }
            }
            if recorder.canStop {
                controlButton(label: "Stop", symbol: "stop.circle.fill", color: .primary) {
                    recorder.stop()
                }
            }
        }
    }

    private func controlButton(
        label: String,
        symbol: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Save

    private func commitNote() {
        guard let draft = recorder.commit() else { return }
        let note = VoiceNoteV1(
            visitId: visitId,
            roomId: roomId,
            processedTranscript: draft.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(note)
    }
}
