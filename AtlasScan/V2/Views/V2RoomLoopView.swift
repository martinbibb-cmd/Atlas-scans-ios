/// V2RoomLoopView — Orchestrates repeated room captures until the user finishes.

import SwiftUI
import simd
import AtlasScanCore

struct V2DraftRoomRecoveryTransition {
    let draftRoom: RoomCaptureV2
    let remainingPendingPins: [SpatialPinV1]
    let nextProspectiveRoomId: UUID
}

enum V2RoomLoopLifecycle {
    static func makeDraftRoomRecoveryTransition(
        prospectiveRoomId: UUID,
        pendingPins: [SpatialPinV1],
        now: Date = .now,
        nextProspectiveRoomId: UUID = UUID()
    ) -> V2DraftRoomRecoveryTransition {
        let formattedDate = now.formatted(date: .abbreviated, time: .shortened)
        let roomPins = pendingPins.filter { $0.roomId == prospectiveRoomId }
        var draftRoom = RoomCaptureV2(
            id: prospectiveRoomId,
            displayName: "Draft Room \(formattedDate)"
        )
        draftRoom.pinnedObjects = roomPins
        let remainingPins = pendingPins.filter { $0.roomId != prospectiveRoomId }
        return V2DraftRoomRecoveryTransition(
            draftRoom: draftRoom,
            remainingPendingPins: remainingPins,
            nextProspectiveRoomId: nextProspectiveRoomId
        )
    }
}

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
    @State private var postCaptureReview: V2PostCaptureReviewCardModel?
    @State private var renameRoomName = ""
    @State private var showRenamePrompt = false
    @State private var showRoomReview = false

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
                if let review = postCaptureReview, let reviewRoom = currentReviewRoom {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Room Captured", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(reviewRoom.displayName)
                                .font(.title3.bold())
                            Text(review.status.badgeText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(review.status.badgeColor)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            summaryLine("Pins", value: pinCountForReviewRoom)
                            summaryLine("Photos", value: photoCountForReviewRoom)
                            summaryLine("Voice notes", value: voiceNoteCountForReviewRoom)
                            summaryLine("Transcripts", value: transcriptCountForReviewRoom)
                        }

                        if review.status == .draft && reviewRoomMissingGeometry {
                            Label("Draft room is missing captured room structure.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        HStack(spacing: 12) {
                            Button("Scan Next Room") {
                                beginNextCapture()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Review Room") {
                                showRoomReview = true
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 12) {
                            Button("Rename Room") {
                                renameRoomName = reviewRoom.displayName
                                showRenamePrompt = true
                            }
                            .buttonStyle(.bordered)

                            Button("Back to Map") {
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                }
            }
        }
        .alert("Name this room", isPresented: $showNamePrompt, actions: {
            TextField("e.g. Kitchen", text: $roomName)
            Button("Save") { saveRoom() }
            Button("Cancel", role: .cancel) { showCapture = true }
        })
        .alert(
            "Couldn’t save room",
            isPresented: Binding(
                get: { coordinator.saveError != nil },
                set: { if !$0 { coordinator.saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.saveError?.localizedDescription ?? "Please try again.")
        }
        .alert("Rename room", isPresented: $showRenamePrompt, actions: {
            TextField("Room name", text: $renameRoomName)
            Button("Save") { renameReviewRoom() }
            Button("Cancel", role: .cancel) {}
        })
        .confirmationDialog(
            "Room wasn’t finalized",
            isPresented: $showUnfinishedRoomRecovery,
            titleVisibility: .visible
        ) {
            Button("Retry scan") { refreshCaptureView() }
            Button("Save evidence as draft room") { saveDraftRoomEvidence() }
            Button("Discard unfinished room evidence", role: .destructive) {
                discardUnfinishedRoomEvidence()
            }
            Button("Continue capturing", role: .cancel) {}
        } message: {
            Text("This scan ended without a completed room. Retry, save current evidence as a draft room, or discard this unfinished room evidence.")
        }
        .fullScreenCover(isPresented: $showRoomReview) {
            if let room = currentReviewRoom {
                NavigationStack {
                    VanModeView(
                        room: room,
                        coordinator: coordinator,
                        onContinueScanning: {
                            showRoomReview = false
                            beginNextCapture()
                        },
                        onPropertyMap: {
                            showRoomReview = false
                            dismiss()
                        },
                        onFinishVisit: {
                            showRoomReview = false
                            coordinator.handOffToMind()
                            dismiss()
                        }
                    )
                }
            } else {
                EmptyView()
            }
        }
    }

    private func saveRoom() {
        guard var room = capturedRoom else { return }
        room.displayName = roomName.isEmpty ? "Room \(coordinator.session.rooms.count + 1)" : roomName
        room.pinnedObjects = pendingPins
        coordinator.addRoom(room)
        Task { await coordinator.saveSession() }
        let nextProspectiveRoomId = UUID()
        postCaptureReview = V2PostCaptureReviewCardModel(
            roomId: room.id,
            status: .captured,
            nextProspectiveRoomId: nextProspectiveRoomId
        )
        roomName = ""
        capturedRoom = nil
        pendingPins = []
        prospectiveRoomId = nextProspectiveRoomId
        showCapture = false
    }

    private func refreshCaptureView() {
        captureViewRefreshToken = UUID()
    }

    private func saveDraftRoomEvidence() {
        let transition = V2RoomLoopLifecycle.makeDraftRoomRecoveryTransition(
            prospectiveRoomId: prospectiveRoomId,
            pendingPins: pendingPins
        )
        coordinator.addRoom(transition.draftRoom)
        Task { await coordinator.saveSession() }
        postCaptureReview = V2PostCaptureReviewCardModel(
            roomId: transition.draftRoom.id,
            status: .draft,
            nextProspectiveRoomId: transition.nextProspectiveRoomId
        )
        roomName = ""
        capturedRoom = nil
        pendingPins = transition.remainingPendingPins
        prospectiveRoomId = transition.nextProspectiveRoomId
        showCapture = false
    }

    private func discardUnfinishedRoomEvidence() {
        let discardedRoomId = prospectiveRoomId
        coordinator.discardUnfinishedRoomEvidence(for: discardedRoomId)
        roomName = ""
        capturedRoom = nil
        pendingPins.removeAll { $0.roomId == discardedRoomId }
        prospectiveRoomId = UUID()
        refreshCaptureView()
    }

    private var currentReviewRoom: RoomCaptureV2? {
        guard let roomId = postCaptureReview?.roomId else { return nil }
        return coordinator.room(withId: roomId)
    }

    private var pinCountForReviewRoom: Int {
        currentReviewRoom?.pinnedObjects.count ?? 0
    }

    private var photoCountForReviewRoom: Int {
        guard let roomId = postCaptureReview?.roomId else { return 0 }
        return coordinator.session.photos.filter { $0.roomId == roomId }.count
    }

    private var voiceNoteCountForReviewRoom: Int {
        guard let roomId = postCaptureReview?.roomId else { return 0 }
        return coordinator.session.voiceNotes.filter { $0.roomId == roomId }.count
    }

    private var transcriptCountForReviewRoom: Int {
        guard let roomId = postCaptureReview?.roomId else { return 0 }
        return coordinator.session.transcripts.filter { $0.roomId == roomId }.count
    }

    private var reviewRoomMissingGeometry: Bool {
        currentReviewRoom?.polygonVertices.isEmpty ?? true
    }

    private func summaryLine(_ title: String, value: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value)")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func beginNextCapture() {
        let nextRoomId = postCaptureReview?.nextProspectiveRoomId ?? UUID()
        postCaptureReview = nil
        showRoomReview = false
        capturedRoom = nil
        pendingPins = []
        prospectiveRoomId = nextRoomId
        refreshCaptureView()
        showCapture = true
    }

    private func renameReviewRoom() {
        guard
            let room = currentReviewRoom,
            !renameRoomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        var renamedRoom = room
        renamedRoom.displayName = renameRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
        coordinator.upsertRoom(renamedRoom)
        Task { await coordinator.saveSession() }
    }
}

private struct V2PostCaptureReviewCardModel {
    let roomId: UUID
    let status: V2PostCaptureRoomStatus
    let nextProspectiveRoomId: UUID
}

private enum V2PostCaptureRoomStatus {
    case captured
    case draft

    var badgeText: String {
        switch self {
        case .captured: return "Captured"
        case .draft: return "Draft"
        }
    }

    var badgeColor: Color {
        switch self {
        case .captured: return .green
        case .draft: return .orange
        }
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
    @State private var capturePointProbe: (() -> LiveCapturePointProbeResultV1)?
    @State private var pendingCapturePoint: LiveCapturePointV1?
    @State private var measurementStartPoint: LiveCapturePointV1?
    @State private var measurementFeedback = ""
    @State private var showCapturePointMenu = false
    @State private var showMeasurementFeedback = false
    @State private var showObjectPicker = false
    @State private var showPhotoPicker = false
    @State private var showVoiceRecorder = false
    @State private var showObservationNote = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                V2RoomPlanCaptureView(
                    capturedRoom: $capturedRoom,
                    shouldStop: $shouldStopCapture,
                    prospectiveRoomId: prospectiveRoomId,
                    onLiveVertices: { verts in liveMapVertices = verts },
                    onCaptureEndedWithoutRoom: {
                        shouldStopCapture = false
                        onCaptureEndedWithoutRoom()
                    },
                    onCapturePointProbeReady: { probe in
                        capturePointProbe = probe
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

                        VStack(alignment: .trailing, spacing: 8) {
                            if let pendingCapturePoint {
                                CapturePointStatusBadge(point: pendingCapturePoint)
                            }
                            if !pendingPinsLocal.isEmpty {
                                PinsCountBadge(count: pendingPinsLocal.count)
                            }
                        }
                        .zIndex(hudOverlayLayer)
                    }
                    .padding(.horizontal, 16)

                    Spacer()

                    BottomActionDock(
                        onCapturePoint: captureCenterPoint,
                        onRoom: { shouldStopCapture = true },
                        onReview: onExit,
                        onFinish: onExit
                    )
                    .zIndex(hudOverlayLayer)
                }
                .padding(.bottom, 20)

                CenterCaptureReticleButton(action: captureCenterPoint)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    .zIndex(hudOverlayLayer + 10)
            }
        }
        .confirmationDialog(
            "Capture Point Actions",
            isPresented: $showCapturePointMenu,
            titleVisibility: .visible
        ) {
            Button("Tag object") { showObjectPicker = true }
            Button("Take photo") { showPhotoPicker = true }
            Button("Add voice note") { showVoiceRecorder = true }
            Button("Measure space") { measureUsingPendingPoint() }
            Button("Add note") { showObservationNote = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(capturePointMessage)
        }
        .sheet(isPresented: $showObjectPicker) {
            V2PinPickerSheet(
                roomId: prospectiveRoomId,
                capturePoint: pendingCapturePoint
            ) { pin in
                pendingPinsLocal.append(pin)
                onPinAdded(pin)
                showObjectPicker = false
            }
        }
        .fullScreenCover(isPresented: $showPhotoPicker) {
            CameraPickerView { image in
                savePhoto(image, capturePoint: pendingCapturePoint)
                showPhotoPicker = false
            } onCancel: {
                showPhotoPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showVoiceRecorder) {
            V2VoiceNoteSheet(
                visitId: visitId,
                roomId: prospectiveRoomId,
                capturePointId: pendingCapturePoint?.id
            ) { note in
                onVoiceNoteAdded(note)
                showVoiceRecorder = false
            }
        }
        .sheet(isPresented: $showObservationNote) {
            V2ObservationNoteSheet(
                visitId: visitId,
                roomId: prospectiveRoomId,
                capturePointId: pendingCapturePoint?.id
            ) { note in
                onVoiceNoteAdded(note)
                showObservationNote = false
            }
        }
        .alert("Measurement", isPresented: $showMeasurementFeedback) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(measurementFeedback)
        }
    }

    // MARK: - Photo save

    private var capturePointMessage: String {
        guard let point = pendingCapturePoint else {
            return "No capture point selected."
        }
        if point.anchorConfidence == .screenOnly {
            return "Screen only — needs review."
        }
        return "Point anchored and ready."
    }

    private func captureCenterPoint() {
        let probe = capturePointProbe?() ?? LiveCapturePointProbeResultV1(
            screenPoint: CGPointCodable(x: 0.5, y: 0.5),
            worldPosition: nil,
            anchorConfidence: .screenOnly
        )
        pendingCapturePoint = LiveCapturePointV1(
            roomId: prospectiveRoomId,
            screenPoint: probe.screenPoint,
            worldPosition: probe.worldPosition,
            anchorConfidence: probe.anchorConfidence
        )
        showCapturePointMenu = true
    }

    private func measureUsingPendingPoint() {
        guard let pendingCapturePoint else { return }
        if let start = measurementStartPoint {
            defer { measurementStartPoint = nil }
            guard
                let startWorld = start.worldPosition,
                let endWorld = pendingCapturePoint.worldPosition
            else {
                measurementFeedback = "Measurement points set, but one or both points are screen only — needs review."
                showMeasurementFeedback = true
                return
            }
            let distance = simd_distance(startWorld, endWorld)
            measurementFeedback = String(format: "Measured %.2f m between selected capture points.", distance)
            showMeasurementFeedback = true
            return
        }
        measurementStartPoint = pendingCapturePoint
        measurementFeedback = "Measurement start point set. Capture another point and choose Measure space again."
        showMeasurementFeedback = true
    }

    private func savePhoto(_ image: UIImage, capturePoint: LiveCapturePointV1?) {
        do {
            let (filename, _) = try PhotoStore.shared.save(image)
            let photo = PhotoEvidenceV1(
                visitId: visitId,
                roomId: prospectiveRoomId,
                capturePointId: capturePoint?.id,
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

// MARK: - BottomActionDock

private struct BottomActionDock: View {
    /// Minimum width of the Finish button so its text never wraps vertically
    /// even on small screen widths.
    fileprivate static let finishButtonMinWidth: CGFloat = 90

    let onCapturePoint: () -> Void
    let onRoom: () -> Void
    let onReview: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            dockButton(symbol: "scope", title: "Capture Point", action: onCapturePoint)
            dockButton(symbol: "square.and.pencil", title: "Room", action: onRoom)
            dockButton(symbol: "map", title: "Review", action: onReview)
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

private struct CapturePointStatusBadge: View {
    let point: LiveCapturePointV1

    var body: some View {
        Label(statusText, systemImage: "scope")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusText: String {
        point.anchorConfidence == .screenOnly
            ? "Screen only — needs review"
            : "Point captured"
    }
}

struct CGPointCodable: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

struct LiveCapturePointProbeResultV1 {
    let screenPoint: CGPointCodable
    let worldPosition: SIMD3<Double>?
    let anchorConfidence: SpatialPinAnchorConfidence
}

struct LiveCapturePointV1: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let roomId: UUID
    let createdAt: Date
    let screenPoint: CGPointCodable
    let worldPosition: SIMD3<Double>?
    let anchorConfidence: SpatialPinAnchorConfidence

    init(
        id: UUID = UUID(),
        roomId: UUID,
        createdAt: Date = .now,
        screenPoint: CGPointCodable,
        worldPosition: SIMD3<Double>?,
        anchorConfidence: SpatialPinAnchorConfidence
    ) {
        self.id = id
        self.roomId = roomId
        self.createdAt = createdAt
        self.screenPoint = screenPoint
        self.worldPosition = worldPosition
        self.anchorConfidence = anchorConfidence
    }
}

// MARK: - V2PinPickerSheet

private struct V2PinPickerSheet: View {
    let roomId: UUID
    let capturePoint: LiveCapturePointV1?
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
                    Text("Pin will be saved as screen-only until anchored in AR review.")
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
        let worldPosition = capturePoint?.worldPosition
        let pin = SpatialPinV1(
            roomId: roomId,
            capturePointId: capturePoint?.id,
            positionX: worldPosition?.x ?? 0,
            positionY: worldPosition?.y ?? 0,
            positionZ: worldPosition?.z ?? 0,
            screenPositionX: capturePoint?.screenPoint.x ?? 0.5,
            screenPositionY: capturePoint?.screenPoint.y ?? 0.5,
            objectType: selectedType,
            label: label.isEmpty ? nil : label,
            anchorConfidence: capturePoint?.anchorConfidence ?? .screenOnly
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
    let capturePointId: UUID?
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
            capturePointId: capturePointId,
            processedTranscript: draft.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(note)
    }
}

private struct V2ObservationNoteSheet: View {
    let visitId: UUID
    let roomId: UUID
    let capturePointId: UUID?
    let onSave: (VoiceNoteV1) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Observation") {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveAndDismiss() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = VoiceNoteV1(
            visitId: visitId,
            roomId: roomId,
            capturePointId: capturePointId,
            processedTranscript: trimmed
        )
        onSave(note)
        dismiss()
    }
}
