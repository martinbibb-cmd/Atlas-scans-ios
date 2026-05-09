/// V2RoomLoopView — Orchestrates repeated room captures until the user finishes.

import SwiftUI
import simd
import AtlasScanCore
import AtlasContracts

struct V2DraftRoomRecoveryTransition {
    let draftRoom: RoomCaptureV2
    let remainingPendingPins: [SpatialPinV1]
    let remainingGhostPlacements: [GhostAppliancePlacementV1]
    let remainingPendingMeasurements: [SpatialMeasurementV1]
    let nextProspectiveRoomId: UUID
}

enum V2RoomLoopLifecycle {
    static func makeDraftRoomRecoveryTransition(
        prospectiveRoomId: UUID,
        pendingPins: [SpatialPinV1],
        pendingGhostPlacements: [GhostAppliancePlacementV1],
        pendingMeasurements: [SpatialMeasurementV1] = [],
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
        draftRoom.ghostAppliancePlacements = pendingGhostPlacements.filter { $0.roomId == prospectiveRoomId }
        draftRoom.measurements = pendingMeasurements.filter { $0.roomId == prospectiveRoomId }
        let remainingPins = pendingPins.filter { $0.roomId != prospectiveRoomId }
        let remainingGhostPlacements = pendingGhostPlacements.filter { $0.roomId != prospectiveRoomId }
        let remainingMeasurements = pendingMeasurements.filter { $0.roomId != prospectiveRoomId }
        return V2DraftRoomRecoveryTransition(
            draftRoom: draftRoom,
            remainingPendingPins: remainingPins,
            remainingGhostPlacements: remainingGhostPlacements,
            remainingPendingMeasurements: remainingMeasurements,
            nextProspectiveRoomId: nextProspectiveRoomId
        )
    }
}

struct V2RoomLoopView: View {
    @ObservedObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var capturedRoom: RoomCaptureV2?
    @State private var showCapture = true
    @State private var showPostScanReview = false
    @State private var showUnfinishedRoomRecovery = false
    @State private var captureViewRefreshToken = UUID()
    /// Pre-generated UUID shared with the live-capture view so photos, voice
    /// notes, and pins recorded during scanning already reference this room.
    @State private var prospectiveRoomId = UUID()
    /// Object pins placed during the scan; attached to the room on save.
    @State private var pendingPins: [SpatialPinV1] = []
    @State private var pendingGhostPlacements: [GhostAppliancePlacementV1] = []
    @State private var pendingCustomApplianceDefinitions: [CustomApplianceDefinitionV1] = []
    @State private var pendingMeasurements: [SpatialMeasurementV1] = []
    @State private var postCaptureReview: V2PostCaptureReviewCardModel?
    @State private var renameRoomName = ""
    @State private var showRenamePrompt = false
    @State private var showRoomReview = false
    @State private var showVisitReview = false
    @State private var showFinishVisit = false

    var body: some View {
        Group {
            if showCapture {
                LiveSpatialCaptureView(
                    capturedRoom: $capturedRoom,
                    rooms: coordinator.session.rooms,
                    photos: coordinator.session.photos,
                    voiceNotes: coordinator.session.voiceNotes,
                    visitId: coordinator.session.visitId,
                    visitReference: coordinator.session.visitReference,
                    visitLabel: coordinator.session.visitLabel,
                    prospectiveRoomId: prospectiveRoomId,
                    refreshToken: captureViewRefreshToken,
                    onExit: { dismiss() },
                    onReview: { showVisitReview = true },
                    onPinAdded: { pin in pendingPins.append(pin) },
                    customApplianceDefinitions: allCustomApplianceDefinitions,
                    onCustomApplianceDefinitionAdded: { definition in
                        pendingCustomApplianceDefinitions.append(definition)
                    },
                    onMeasurementAdded: { measurement in pendingMeasurements.append(measurement) },
                    onPhotoAdded: { coordinator.addPhoto($0) },
                    onVoiceNoteAdded: { coordinator.addVoiceNote($0) },
                    onCaptureEndedWithoutRoom: { showUnfinishedRoomRecovery = true },
                    onFinishVisit: { showFinishVisit = true },
                    onEvidenceDeleted: { item in
                        switch item.evidenceType {
                        case .objectPin:
                            pendingPins.removeAll { $0.id == item.sourceEvidenceId }
                            coordinator.deleteEvidenceItem(item)
                        case .ghostAppliance:
                            pendingGhostPlacements.removeAll { $0.id == item.sourceEvidenceId }
                            coordinator.deleteEvidenceItem(item)
                        case .measurement:
                            pendingMeasurements.removeAll { $0.id == item.sourceEvidenceId }
                            coordinator.deleteEvidenceItem(item)
                        case .photo, .voiceNote, .note:
                            coordinator.deleteEvidenceItem(item)
                        }
                    }
                )
                .ignoresSafeArea()
                .onChange(of: capturedRoom?.id) { _, newId in
                    if newId != nil {
                        showCapture = false
                        showPostScanReview = true
                        coordinator.transition(to: .reviewingRoom)
                    }
                }
            } else {
                if let review = postCaptureReview, let reviewRoom = currentReviewRoom {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("\(reviewRoom.displayName) saved to visit", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(reviewRoom.displayName)
                                    .font(.title3.bold())
                                Text(review.status.badgeText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(review.status.badgeColor)
                                Text("Rooms in visit: \(coordinator.session.rooms.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                                    coordinator.transition(to: .choosingNextStep)
                                    beginNextCapture()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Review Room") {
                                    showRoomReview = true
                                }
                                .buttonStyle(.bordered)
                            }

                            HStack(spacing: 12) {
                                Button("Finish Visit") {
                                    showFinishVisit = true
                                }
                                .buttonStyle(.bordered)

                                Button("Back to Map") {
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                            }

                            Button("Rename Room") {
                                renameRoomName = reviewRoom.displayName
                                showRenamePrompt = true
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                }
            }
        }
        .fullScreenCover(isPresented: $showPostScanReview) {
            if let room = capturedRoom {
                V2PostScanRoomReviewView(
                    capturedRoom: room,
                    suggestedName: nextRoomSuggestedName,
                    pendingPinCount: pendingPins.count,
                    photoCount: coordinator.session.photos.filter { $0.roomId == room.id }.count,
                    voiceNoteCount: coordinator.session.voiceNotes.filter { $0.roomId == room.id }.count,
                    onSave: { name in
                        showPostScanReview = false
                        saveRoom(name: name)
                    },
                    onContinueToNextRoom: { name in
                        showPostScanReview = false
                        saveRoomAndContinue(name: name)
                    },
                    onFinishVisit: { name in
                        showPostScanReview = false
                        saveRoom(name: name)
                        showFinishVisit = true
                    },
                    onDiscard: {
                        showPostScanReview = false
                        showUnfinishedRoomRecovery = true
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showFinishVisit) {
            V2FinishVisitView(coordinator: coordinator) {
                showFinishVisit = false
            }
        }
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
                            coordinator.transition(to: .choosingNextStep)
                            beginNextCapture()
                        },
                        onPropertyMap: {
                            showRoomReview = false
                            dismiss()
                        },
                        onFinishVisit: {
                            showRoomReview = false
                            showFinishVisit = true
                        }
                    )
                }
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showVisitReview) {
            NavigationStack {
                V2VisitReviewView(
                    coordinator: coordinator,
                    rooms: coordinator.session.rooms,
                    photos: coordinator.session.photos,
                    voiceNotes: coordinator.session.voiceNotes,
                    transcripts: coordinator.session.transcripts,
                    visitReference: coordinator.session.visitReference,
                    visitLabel: coordinator.session.visitLabel
                )
            }
        }
    }

    private func saveRoom(name: String) {
        guard var room = capturedRoom else { return }
        room.displayName = name.isEmpty ? nextRoomSuggestedName : name
        room.pinnedObjects = pendingPins
        room.ghostAppliancePlacements = pendingGhostPlacements
        room.customApplianceDefinitions = pendingCustomApplianceDefinitions
        room.measurements = pendingMeasurements
        coordinator.addRoom(room)
        coordinator.transition(to: .roomSaved)
        Task { await coordinator.saveSession() }
        let nextProspectiveRoomId = UUID()
        postCaptureReview = V2PostCaptureReviewCardModel(
            roomId: room.id,
            status: .captured,
            nextProspectiveRoomId: nextProspectiveRoomId
        )
        capturedRoom = nil
        pendingPins = []
        pendingGhostPlacements = []
        pendingCustomApplianceDefinitions = []
        pendingMeasurements = []
        prospectiveRoomId = nextProspectiveRoomId
        showCapture = false
    }

    /// Saves the current room, then immediately begins scanning the next room.
    private func saveRoomAndContinue(name: String) {
        saveRoom(name: name)
        beginNextCapture()
    }

    private func refreshCaptureView() {
        captureViewRefreshToken = UUID()
    }

    private func saveDraftRoomEvidence() {
        let transition = V2RoomLoopLifecycle.makeDraftRoomRecoveryTransition(
            prospectiveRoomId: prospectiveRoomId,
            pendingPins: pendingPins,
            pendingGhostPlacements: pendingGhostPlacements,
            pendingMeasurements: pendingMeasurements
        )
        var draftRoom = transition.draftRoom
        draftRoom.customApplianceDefinitions = pendingCustomApplianceDefinitions
        coordinator.addRoom(draftRoom)
        coordinator.transition(to: .roomSaved)
        Task { await coordinator.saveSession() }
        postCaptureReview = V2PostCaptureReviewCardModel(
            roomId: draftRoom.id,
            status: .draft,
            nextProspectiveRoomId: transition.nextProspectiveRoomId
        )
        capturedRoom = nil
        pendingPins = transition.remainingPendingPins
        pendingGhostPlacements = transition.remainingGhostPlacements
        pendingMeasurements = transition.remainingPendingMeasurements
        pendingCustomApplianceDefinitions.removeAll()
        prospectiveRoomId = transition.nextProspectiveRoomId
        showCapture = false
    }

    private func discardUnfinishedRoomEvidence() {
        let discardedRoomId = prospectiveRoomId
        coordinator.discardUnfinishedRoomEvidence(for: discardedRoomId)
        capturedRoom = nil
        pendingPins.removeAll { $0.roomId == discardedRoomId }
        pendingGhostPlacements.removeAll { $0.roomId == discardedRoomId }
        pendingMeasurements.removeAll { $0.roomId == discardedRoomId }
        pendingCustomApplianceDefinitions.removeAll()
        prospectiveRoomId = UUID()
        refreshCaptureView()
    }

    private var currentReviewRoom: RoomCaptureV2? {
        guard let roomId = postCaptureReview?.roomId else { return nil }
        return coordinator.room(withId: roomId)
    }

    /// Default name for the room currently being scanned, based on how many rooms
    /// are already saved. Users can rename it from the post-scan review screen.
    private var nextRoomSuggestedName: String {
        "Room \(coordinator.session.rooms.count + 1)"
    }

    private var pinCountForReviewRoom: Int {
        currentReviewRoom?.pinnedObjects.count ?? 0
    }

    private var allCustomApplianceDefinitions: [CustomApplianceDefinitionV1] {
        let roomDefinitions = coordinator.session.rooms.flatMap(\.customApplianceDefinitions)
        return dedupeCustomDefinitions(roomDefinitions + pendingCustomApplianceDefinitions)
    }

    private func dedupeCustomDefinitions(_ definitions: [CustomApplianceDefinitionV1]) -> [CustomApplianceDefinitionV1] {
        var seen: Set<String> = []
        return definitions.filter { seen.insert($0.id).inserted }
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
        pendingMeasurements = []
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

private struct V2VisitReviewView: View {
    @ObservedObject var coordinator: ScanSessionCoordinator
    let rooms: [RoomCaptureV2]
    let photos: [PhotoEvidenceV1]
    let voiceNotes: [VoiceNoteV1]
    let transcripts: [ProcessedTranscriptV1]
    let visitReference: String?
    let visitLabel: String?

    @Environment(\.dismiss) private var dismiss
    @State private var includeInCustomerReport: [String: Bool] = [:]
    @State private var showFinishVisit = false

    var body: some View {
        List {
            Section("Visit") {
                LabeledContent("Reference", value: cleanedReference ?? "—")
                if let cleanedLabel {
                    LabeledContent("Label", value: cleanedLabel)
                }
            }

            Section("Summary") {
                LabeledContent("Rooms", value: "\(rooms.count)")
                LabeledContent("Photos", value: "\(photos.count)")
                LabeledContent("Voice notes", value: "\(voiceNotes.count)")
                LabeledContent("Transcripts", value: "\(transcripts.count)")
                LabeledContent("Object pins", value: "\(allPins.count)")
                LabeledContent("Measurements", value: "\(allMeasurements.count)")
            }

            Section("Rooms") {
                ForEach(rooms) { room in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(room.displayName).font(.subheadline.weight(.semibold))
                        Text("Pins \(room.pinnedObjects.count) · Photos \(photoCountByRoomId[room.id, default: 0]) · Voice \(voiceNoteCountByRoomId[room.id, default: 0])")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    showFinishVisit = true
                } label: {
                    Label("Finish Visit / Export", systemImage: "flag.checkered")
                }
            }

            Section("Object pins") {
                ForEach(allPins) { pin in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pin.label ?? pin.objectType.rawValue.capitalized)
                            .font(.subheadline.weight(.semibold))
                        Text("Anchor: \(pin.anchorConfidence.rawValue) · Review: \(pin.reviewStatus.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("Include in customer report", isOn: binding(for: "pin-\(pin.id.uuidString)"))
                            .font(.caption)
                    }
                }
            }

            Section("Measurements") {
                ForEach(allMeasurements) { measurement in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%.2f m", measurement.distanceMeters))
                            .font(.subheadline.weight(.semibold))
                        Text("Anchor: \(measurement.anchorConfidence.rawValue) · Review: \(measurement.needsReview ? "needs_review" : "confirmed")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("Include in customer report", isOn: binding(for: "measurement-\(measurement.id.uuidString)"))
                            .font(.caption)
                    }
                }
            }

            Section("Photos") {
                ForEach(photos) { photo in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(photo.relativeFilePath)
                            .font(.caption.weight(.semibold))
                        Toggle("Include in customer report", isOn: binding(for: "photo-\(photo.id.uuidString)"))
                            .font(.caption)
                    }
                }
            }

            Section("Voice notes / transcripts") {
                ForEach(voiceNotes) { note in
                    let trimmedTranscript = note.processedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trimmedTranscript.isEmpty ? "Voice note (no transcript)" : trimmedTranscript)
                            .font(.caption)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .accessibilityHint("Transcript preview. Open item details for full text.")
                        Toggle("Include in customer report", isOn: binding(for: "voice-\(note.id.uuidString)"))
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Visit Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showFinishVisit) {
            V2FinishVisitView(coordinator: coordinator) {
                showFinishVisit = false
            }
        }
    }

    private var allPins: [SpatialPinV1] {
        rooms.flatMap(\.pinnedObjects)
    }

    private var allMeasurements: [SpatialMeasurementV1] {
        rooms.flatMap(\.measurements)
    }

    private var photoCountByRoomId: [UUID: Int] {
        Dictionary(grouping: photos, by: \.roomId).mapValues(\.count)
    }

    private var voiceNoteCountByRoomId: [UUID: Int] {
        Dictionary(grouping: voiceNotes, by: \.roomId).mapValues(\.count)
    }

    private var cleanedReference: String? {
        let trimmed = visitReference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var cleanedLabel: String? {
        let trimmed = visitLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { includeInCustomerReport[key] ?? true },
            set: { includeInCustomerReport[key] = $0 }
        )
    }
}

// MARK: - LiveSpatialCaptureView

private struct LiveSpatialCaptureView: View {
    /// Z-index layer that keeps Atlas HUD controls consistently above the
    /// RoomPlan base surface.
    private let hudOverlayLayer: Double = 10
    private let maxRecentModelCount = 6
    private let maxVisibleOffscreenPointers = 5
    private let normalizedScreenCenter = 0.5
    private let noisyMeasurementThresholdMeters = 0.03
    private let ghostSurfaceConflictThresholdMeters = 0.05
    /// Classifies a measurement as axis-dominant when one component exceeds
    /// the other by this ratio (e.g. vertical vs horizontal).
    private let axisDominanceRatio = 1.2
    private let accurateMeasurementQualityMessage = "Accurate (2 anchored points)"
    private let estimatedMeasurementQualityMessage = "Estimated (room-note estimate)"
    private static let pointerDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let pointerDateFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @Binding var capturedRoom: RoomCaptureV2?
    let rooms: [RoomCaptureV2]
    let photos: [PhotoEvidenceV1]
    let voiceNotes: [VoiceNoteV1]
    let visitId: UUID
    let visitReference: String?
    let visitLabel: String?
    let prospectiveRoomId: UUID
    let refreshToken: UUID
    /// Called when the user dismisses the scan without saving (e.g. back gesture).
    let onExit: () -> Void
    let onReview: () -> Void
    let onPinAdded: (SpatialPinV1) -> Void
    let customApplianceDefinitions: [CustomApplianceDefinitionV1]
    let onCustomApplianceDefinitionAdded: (CustomApplianceDefinitionV1) -> Void
    let onMeasurementAdded: (SpatialMeasurementV1) -> Void
    let onPhotoAdded: (PhotoEvidenceV1) -> Void
    let onVoiceNoteAdded: (VoiceNoteV1) -> Void
    let onCaptureEndedWithoutRoom: () -> Void
    /// Called when the engineer taps "Finish Visit" from the capture action menu.
    /// The parent should present V2FinishVisitView.
    let onFinishVisit: () -> Void
    /// Called when the engineer deletes an item from the evidence strip.
    /// The parent should remove pending pins/ghosts from its own state and
    /// route photo / voice-note deletions to the session coordinator.
    let onEvidenceDeleted: (RecentCaptureItemV1) -> Void

    @State private var shouldStopCapture = false
    @State private var liveMapVertices: [Vertex2D] = []
    @State private var pendingPinsLocal: [SpatialPinV1] = []
    @State private var ghostPreview: GhostAppliancePreview?
    @State private var pendingMeasurementsLocal: [SpatialMeasurementV1] = []
    @State private var capturePointProbe: (() -> LiveCapturePointProbeResultV1)?
    @State private var worldPointProjector: ((SIMD3<Double>) -> CGPointCodable?)?
    @State private var anchorTransformResolver: ((UUID) -> WorldTransformV1?)?
    @State private var capturePointsById: [UUID: LiveCapturePointV1] = [:]
    @State private var pendingCapturePoint: LiveCapturePointV1?
    @State private var measurementStartPoint: LiveCapturePointV1?
    @State private var measurementFeedback = ""
    @State private var showCapturePointMenu = false
    @State private var showRoomNoteOnlyPrompt = false
    @State private var lastCaptureProbeDiagnostics: CaptureProbeDiagnosticsV1?
    @State private var lastMeasurement: SpatialMeasurementV1?
    @State private var showMeasurementFeedback = false
    @State private var showObjectPicker = false
    @State private var showGhostAppliancePicker = false
    @State private var showPlacementPlanePicker = false
    @State private var selectedGhostPlacementPlane: GhostPlacementPlaneV1 = .wall
    @State private var selectedGhostApplianceDefinition: GhostApplianceCandidate?
    @State private var showPhotoPicker = false
    @State private var showVoiceRecorder = false
    @State private var showObservationNote = false
    @State private var recentGhostModelIds: [String] = []
    /// All evidence items captured during this room session, kept in insertion order.
    /// Filtered by `prospectiveRoomId` before display so switching rooms clears the strip.
    @State private var recentCaptures: [RecentCaptureItemV1] = []
    /// The item currently shown in the detail sheet (tapped from the strip).
    @State private var selectedRecentItem: RecentCaptureItemV1?

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
                        DispatchQueue.main.async {
                            capturePointProbe = probe
                        }
                    },
                    onWorldPointProjectionReady: { projector in
                        DispatchQueue.main.async {
                            worldPointProjector = projector
                        }
                    },
                    onAnchorTransformResolverReady: { resolver in
                        DispatchQueue.main.async {
                            anchorTransformResolver = resolver
                        }
                    }
                )
                .id(refreshToken)
                .ignoresSafeArea()

                VStack(spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            VisitCaptureHeaderBadge(
                                visitReference: visitReference,
                                visitLabel: visitLabel
                            )
                            MiniMapHUD(
                                rooms: rooms,
                                livePolygonVertices: liveMapVertices,
                                activeRoomId: prospectiveRoomId,
                                pins: pendingPinsLocal,
                                ghostPlacements: []
                            )
                        }
                        .zIndex(hudOverlayLayer)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 8) {
                            if let pendingCapturePoint {
                                CapturePointStatusBadge(
                                    point: pendingCapturePoint,
                                    isAnchorLost: isAnchorLost(for: pendingCapturePoint)
                                )
                            }
                            if let diagnostics = lastCaptureProbeDiagnostics {
                                ProbeCaptureStatusBadge(
                                    diagnostics: diagnostics,
                                    pendingPoint: pendingCapturePoint
                                )
                            }
                            if measurementStartPoint != nil {
                                MeasurementInProgressBadge()
                            }
                            if let lastMeasurement {
                                MeasurementResultBadge(
                                    summary: measurementSummary(for: lastMeasurement)
                                )
                            }
                            if !pendingPinsLocal.isEmpty {
                                PinsCountBadge(count: pendingPinsLocal.count)
                            }
                            if !pendingMeasurementsLocal.isEmpty {
                                MeasurementsCountBadge(count: pendingMeasurementsLocal.count)
                            }
                            #if DEBUG
                            if let lastCaptureProbeDiagnostics {
                                CaptureProbeDiagnosticsBadge(diagnostics: lastCaptureProbeDiagnostics)
                            }
                            #endif
                        }
                        .zIndex(hudOverlayLayer)
                    }
                    .padding(.horizontal, 16)

                    Spacer()

                    let stripItems = recentItemsForCurrentRoom
                    if !stripItems.isEmpty {
                        V2RecentCaptureStripView(
                            items: stripItems,
                            onTap: { item in selectedRecentItem = item },
                            onDelete: { item in handleDeleteRecentItem(item) }
                        )
                        .zIndex(hudOverlayLayer)
                    }

                    BottomActionDock(
                        onCapturePoint: captureCenterPoint,
                        onMore: { shouldStopCapture = true },
                        onReview: onReview,
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

                if let ghostPreview {
                    GhostPlacementOverlay(
                        preview: ghostPreview,
                        clearanceState: ghostClearanceState(for: ghostPreview)
                    )
                    .zIndex(hudOverlayLayer + 5)
                }

                if let startPoint = measurementStartPoint,
                   let startScreen = resolvedMeasurementStartScreen(for: startPoint) {
                    MeasurementGuideLineOverlay(
                        startNormalized: startScreen,
                        needsReview: startPoint.anchorConfidence == .screenOnly
                    )
                    .zIndex(hudOverlayLayer + 8)
                    .allowsHitTesting(false)
                }

                if !offscreenPointerItems.isEmpty {
                    OffscreenPointerOverlay(
                        items: offscreenPointerItems,
                        maxVisiblePointers: maxVisibleOffscreenPointers,
                        onTap: handlePointerTap,
                        onLongPressDelete: handlePointerDelete
                    )
                    .zIndex(hudOverlayLayer + 20)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let ghostPreview {
                GhostPreviewActionBar(
                    title: ghostPreview.displayName,
                    selectedPlane: selectedGhostPlacementPlane,
                    onConfirm: confirmGhostPreview,
                    onAdjust: { showPlacementPlanePicker = true },
                    onSelectPlane: { plane in
                        selectedGhostPlacementPlane = plane
                        stageGhostPreview(on: plane)
                    },
                    onChangeAppliance: {
                        self.ghostPreview = nil
                        selectedGhostApplianceDefinition = nil
                        showGhostAppliancePicker = true
                    },
                    onCancel: {
                        self.ghostPreview = nil
                        selectedGhostApplianceDefinition = nil
                    }
                )
                .padding(.bottom, 104)
            } else if showCapturePointMenu, pendingCapturePoint != nil {
                CaptureActionBubbleMenu(
                    onTagObject: {
                        showObjectPicker = true
                        showCapturePointMenu = false
                    },
                    onPhoto: {
                        showPhotoPicker = true
                        showCapturePointMenu = false
                    },
                    onVoiceNote: {
                        showVoiceRecorder = true
                        showCapturePointMenu = false
                    },
                    onMeasure: {
                        measureUsingPendingPoint()
                        showCapturePointMenu = false
                    },
                    onNote: {
                        showObservationNote = true
                        showCapturePointMenu = false
                    },
                    onPreviewAppliance: {
                        showGhostAppliancePicker = true
                        showCapturePointMenu = false
                    },
                    onNextRoom: {
                        stopCaptureAndCloseMenu()
                    },
                    onFinishVisit: {
                        stopCaptureAndCloseMenu()
                        onFinishVisit()
                    },
                    onDismiss: { showCapturePointMenu = false }
                )
                .padding(.bottom, 104)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: showCapturePointMenu)
        .alert("No spatial hit detected", isPresented: $showRoomNoteOnlyPrompt) {
            Button("Save as room note only") {
                showCapturePointMenu = true
            }
            Button("Cancel", role: .cancel) {
                pendingCapturePoint = nil
            }
        } message: {
            Text("Unable to anchor at this location. You can save this as a room note instead.")
        }
        .sheet(isPresented: $showObjectPicker) {
            V2PinPickerSheet(
                roomId: prospectiveRoomId,
                capturePoint: pendingCapturePoint
            ) { pin in
                pendingPinsLocal.append(pin)
                onPinAdded(pin)
                recentCaptures.append(RecentCaptureItemV1.from(pin: pin))
                showObjectPicker = false
            }
        }
        .sheet(isPresented: $showGhostAppliancePicker) {
            V2GhostAppliancePickerSheet(
                customDefinitions: customApplianceDefinitions,
                recentModelIds: recentGhostModelIds
            ) { selected in
                selectedGhostApplianceDefinition = selected
                selectedGhostPlacementPlane = .wall
                showGhostAppliancePicker = false
                showPlacementPlanePicker = true
            } onCustomDefinitionCreated: { definition in
                onCustomApplianceDefinitionAdded(definition)
            }
        }
        .confirmationDialog(
            "Placement plane",
            isPresented: $showPlacementPlanePicker,
            titleVisibility: .visible
        ) {
            Button("Wall mounted") {
                selectedGhostPlacementPlane = .wall
                stageGhostPreview(on: .wall)
            }
            Button("Floor standing") {
                selectedGhostPlacementPlane = .floor
                stageGhostPreview(on: .floor)
            }
            Button("Cancel", role: .cancel) {}
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
                recentCaptures.append(RecentCaptureItemV1.from(voiceNote: note))
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
                recentCaptures.append(RecentCaptureItemV1.fromObservationNote(note))
                showObservationNote = false
            }
        }
        .alert("Measurement", isPresented: $showMeasurementFeedback) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(measurementFeedback)
        }
        .sheet(item: $selectedRecentItem) { item in
            V2RecentItemDetailSheet(item: item) {
                handleDeleteRecentItem(item)
                selectedRecentItem = nil
            }
            .presentationDetents([.height(260)])
        }
        .v2DebugLifecycleOverlay()
    }

    // MARK: - Photo save

    /// Stops the active capture and closes the action menu.
    /// Used by the "Next Room" and "Finish Visit" quick actions.
    private func stopCaptureAndCloseMenu() {
        shouldStopCapture = true
        showCapturePointMenu = false
    }

    private func captureCenterPoint() {
        let probe = capturePointProbe?() ?? LiveCapturePointProbeResultV1(
            screenPoint: CGPointCodable(x: 0.5, y: 0.5),
            worldPosition: nil,
            anchorConfidence: .screenOnly,
            hitNormal: nil,
            anchorId: nil,
            worldTransform: nil,
            debugDiagnostics: CaptureProbeDiagnosticsV1(
                raycastAttempted: false,
                resultType: .failed,
                hitDistanceM: nil,
                planeAlignment: "none",
                trackingState: "unavailable"
            )
        )
        lastCaptureProbeDiagnostics = probe.debugDiagnostics
        let point = LiveCapturePointV1(
            roomId: prospectiveRoomId,
            screenPoint: probe.screenPoint,
            worldPosition: probe.worldPosition,
            anchorConfidence: probe.anchorConfidence,
            hitNormal: probe.hitNormal,
            anchorId: probe.anchorId,
            worldTransform: probe.worldTransform
        )
        pendingCapturePoint = point
        capturePointsById[point.id] = point
        showCapturePointMenu = false
        if point.anchorConfidence == .screenOnly {
            showRoomNoteOnlyPrompt = true
        } else {
            showCapturePointMenu = true
        }
    }

    private func isAnchorLost(for point: LiveCapturePointV1) -> Bool {
        guard
            point.anchorConfidence != .screenOnly,
            let anchorId = point.anchorId
        else {
            return false
        }
        return anchorTransformResolver?(anchorId) == nil
    }

    private func measureUsingPendingPoint() {
        guard let pendingCapturePoint else { return }
        if let start = measurementStartPoint {
            defer { measurementStartPoint = nil }
            let startWorld = start.worldPosition ?? SIMD3<Double>(0, 0, 0)
            let endWorld = pendingCapturePoint.worldPosition ?? SIMD3<Double>(0, 0, 0)
            let bothAnchored = start.worldPosition != nil && pendingCapturePoint.worldPosition != nil
            let confidence: SpatialPinAnchorConfidence = bothAnchored
                ? lowerAnchorConfidence(start.anchorConfidence, pendingCapturePoint.anchorConfidence)
                : .screenOnly
            let measurement = SpatialMeasurementV1(
                roomId: prospectiveRoomId,
                startCapturePointId: start.id,
                endCapturePointId: pendingCapturePoint.id,
                startWorldPosition: startWorld,
                endWorldPosition: endWorld,
                startSurfaceSemantic: start.surfaceSemantic ?? .unknown,
                endSurfaceSemantic: pendingCapturePoint.surfaceSemantic ?? .unknown,
                anchorConfidence: confidence
            )
            if bothAnchored, measurement.distanceMeters < noisyMeasurementThresholdMeters {
                measurementFeedback = "Measurement not saved - distance fell below the stability threshold. Adjust your position and retake."
                showMeasurementFeedback = true
                return
            }
            pendingMeasurementsLocal.append(measurement)
            onMeasurementAdded(measurement)
            recentCaptures.append(RecentCaptureItemV1.from(measurement: measurement))
            lastMeasurement = measurement
            if bothAnchored {
                let vSign = measurement.verticalOffsetMeters >= 0 ? "▲" : "▼"
                let vText = abs(measurement.verticalOffsetMeters) >= 0.01
                    ? " · \(vSign)\(String(format: "%.2f m", abs(measurement.verticalOffsetMeters)))"
                    : ""
                let axis = measurementSummary(for: measurement).axisLabel
                measurementFeedback = String(format: "Measured %.2f m%@ · %@ alignment", measurement.distanceMeters, vText, axis)
            } else {
                measurementFeedback = "Measurement saved as room-note estimate - capture two anchored points for accurate measurement."
            }
            showMeasurementFeedback = true
            return
        }
        measurementStartPoint = pendingCapturePoint
        measurementFeedback = "Measurement start set. Tap centre reticle to capture the end point, then select Measure space again."
        showMeasurementFeedback = true
    }

    private func measurementSummary(for measurement: SpatialMeasurementV1) -> MeasurementResultSummary {
        let horizontal = measurement.horizontalDistanceMeters
        let vertical = abs(measurement.verticalOffsetMeters)
        let axis: MeasurementAxisClassification
        if measurement.distanceMeters < noisyMeasurementThresholdMeters {
            axis = .unclassified
        } else if vertical >= (horizontal * axisDominanceRatio) {
            axis = .vertical
        } else if horizontal >= (vertical * axisDominanceRatio) {
            axis = .horizontal
        } else {
            axis = .depth
        }
        let isAccurate = measurement.anchorConfidence != .screenOnly
        return MeasurementResultSummary(
            distanceText: String(format: "%.2f m", measurement.distanceMeters),
            axisLabel: axis.displayName,
            qualityText: isAccurate ? accurateMeasurementQualityMessage : estimatedMeasurementQualityMessage,
            qualityColor: isAccurate ? .green : .orange
        )
    }

    private func ghostClearanceState(for preview: GhostAppliancePreview) -> GhostPreviewClearanceState {
        if preview.confidence == .screenOnly || preview.placementPlane == .unknown {
            return .warning("Needs stable anchor")
        }
        if let hitDistance = lastCaptureProbeDiagnostics?.hitDistanceM, hitDistance < ghostSurfaceConflictThresholdMeters {
            return .conflict("Too close to surface")
        }
        return .clear("Clearance envelope active")
    }

    private func lowerAnchorConfidence(
        _ a: SpatialPinAnchorConfidence,
        _ b: SpatialPinAnchorConfidence
    ) -> SpatialPinAnchorConfidence {
        // Ordered from weakest to strongest confidence; worldLocked is strongest.
        let order: [SpatialPinAnchorConfidence] = [.screenOnly, .estimated, .raycastEstimated, .low, .medium, .high, .worldLocked]
        let ai = order.firstIndex(of: a) ?? 0
        let bi = order.firstIndex(of: b) ?? 0
        return order[min(ai, bi)]
    }

    private func resolvedMeasurementStartScreen(for point: LiveCapturePointV1) -> CGPointCodable? {
        if let world = point.worldPosition, let projected = worldPointProjector?(world) {
            return projected
        }
        return point.screenPoint
    }

    private func stageGhostPreview(on plane: GhostPlacementPlaneV1) {
        guard let capturePoint = pendingCapturePoint, let definition = selectedGhostApplianceDefinition else { return }
        let resolvedPlane = resolvedPlacementPlane(for: plane, capturePoint: capturePoint)
        selectedGhostPlacementPlane = resolvedPlane
        let planeNormal = resolvedPlaneNormal(for: resolvedPlane, capturePoint: capturePoint)
        let world = resolvedGhostWorldPosition(
            for: definition.dimensionsMm,
            plane: resolvedPlane,
            capturePoint: capturePoint,
            planeNormal: planeNormal
        )
        ghostPreview = GhostAppliancePreview(
            templateId: definition.templateId,
            displayName: definition.displayTitle,
            dimensionsMm: definition.dimensionsMm,
            clearanceOffsetsMm: definition.clearanceOffsetsMm,
            worldPosition: world,
            screenPoint: capturePoint.screenPoint,
            placementPlane: resolvedPlane,
            planeNormal: planeNormal,
            confidence: capturePoint.worldPosition == nil ? .screenOnly : capturePoint.anchorConfidence,
            capturePointId: capturePoint.id,
            anchorId: capturePoint.anchorId,
            worldTransform: capturePoint.worldTransform,
            objectCategory: definition.objectCategory,
            objectType: definition.objectType,
            manufacturer: definition.brand,
            modelName: definition.modelName,
            applianceRole: definition.boilerRole,
            customDefinitionId: definition.customDefinitionId,
            note: definition.note
        )

        if definition.templateId != nil {
            var updatedRecentModelIds = recentGhostModelIds
            updatedRecentModelIds.removeAll { $0 == definition.modelId }
            updatedRecentModelIds.insert(definition.modelId, at: 0)
            if updatedRecentModelIds.count > maxRecentModelCount {
                updatedRecentModelIds.removeSubrange(maxRecentModelCount...)
            }
            recentGhostModelIds = updatedRecentModelIds
        }
    }

    private func confirmGhostPreview() {
        guard let preview = ghostPreview else { return }

        let manualEntry: SpatialPinManualEntryV1? = {
            guard shouldPopulateManualEntry(for: preview) else { return nil }
            return SpatialPinManualEntryV1(
                manufacturer: trimmedPreviewValue(preview.manufacturer),
                model: trimmedPreviewValue(preview.modelName),
                type: trimmedPreviewValue(preview.applianceRole),
                widthMm: preview.dimensionsMm.width,
                heightMm: preview.dimensionsMm.height,
                depthMm: preview.dimensionsMm.depth,
                flueOrientation: nil,
                notes: trimmedPreviewValue(preview.note),
                photoEvidenceRecommended: true
            )
        }()

        let pin = SpatialPinV1(
            roomId: prospectiveRoomId,
            locationContext: locationContext(for: preview.placementPlane),
            capturePointId: preview.capturePointId,
            anchorId: preview.anchorId,
            worldTransform: preview.worldTransform,
            positionX: preview.worldPosition.x,
            positionY: preview.worldPosition.y,
            positionZ: preview.worldPosition.z,
            screenPositionX: preview.screenPoint.x,
            screenPositionY: preview.screenPoint.y,
            objectType: preview.objectType,
            label: preview.displayName,
            objectCategory: preview.objectCategory,
            selectedTemplateId: preview.templateId,
            manualEntry: manualEntry,
            anchorConfidence: preview.confidence,
            reviewStatus: .needsReview,
            provenance: .manualCapture
        )
        pendingPinsLocal.append(pin)
        onPinAdded(pin)
        recentCaptures.append(RecentCaptureItemV1.from(pin: pin))
        ghostPreview = nil
        selectedGhostApplianceDefinition = nil
    }

    private func locationContext(for plane: GhostPlacementPlaneV1) -> PinPlacementLocationContext {
        switch plane {
        case .wall: return .wall
        case .floor: return .floor
        case .ceiling: return .ceiling
        case .worktop: return .cupboard
        case .unknown: return .unknownNeedsReview
        }
    }

    private func trimmedPreviewValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        if GhostPreviewStrings.unknownMarkers.contains(normalized) {
            return nil
        }
        return trimmed
    }

    private func shouldPopulateManualEntry(for preview: GhostAppliancePreview) -> Bool {
        preview.templateId == nil || preview.customDefinitionId != nil
    }

    private func resolvedPlacementPlane(
        for requestedPlane: GhostPlacementPlaneV1,
        capturePoint: LiveCapturePointV1
    ) -> GhostPlacementPlaneV1 {
        guard capturePoint.worldPosition != nil else { return .unknown }
        switch requestedPlane {
        case .wall:
            return capturePoint.hitNormal == nil ? .unknown : .wall
        case .floor:
            return .floor
        case .ceiling, .worktop, .unknown:
            return .unknown
        }
    }

    private func resolvedPlaneNormal(
        for plane: GhostPlacementPlaneV1,
        capturePoint: LiveCapturePointV1
    ) -> SIMD3<Double> {
        switch plane {
        case .wall:
            return capturePoint.hitNormal ?? SIMD3<Double>(0, 0, -1)
        case .floor, .worktop:
            return SIMD3<Double>(0, 1, 0)
        case .ceiling:
            return SIMD3<Double>(0, -1, 0)
        case .unknown:
            return capturePoint.hitNormal ?? SIMD3<Double>(0, 0, 0)
        }
    }

    private func resolvedGhostWorldPosition(
        for dimensions: GhostApplianceDimensionsMmV1,
        plane: GhostPlacementPlaneV1,
        capturePoint: LiveCapturePointV1,
        planeNormal: SIMD3<Double>
    ) -> SIMD3<Double> {
        guard var world = capturePoint.worldPosition else { return SIMD3<Double>(0, 0, 0) }
        let dimensionsM = SIMD3<Double>(
            Double(dimensions.width) / 1_000,
            Double(dimensions.height) / 1_000,
            Double(dimensions.depth) / 1_000
        )

        switch plane {
        case .wall:
            let outward = normalizedVector(
                SIMD3<Double>(planeNormal.x, 0, planeNormal.z),
                fallback: SIMD3<Double>(0, 0, -1)
            )
            world += outward * (dimensionsM.z / 2)
        case .floor:
            world.y += dimensionsM.y / 2
        case .ceiling, .worktop, .unknown:
            break
        }

        return world
    }

    private func normalizedVector(
        _ vector: SIMD3<Double>,
        fallback: SIMD3<Double>
    ) -> SIMD3<Double> {
        let length = simd_length(vector)
        guard length > 0.000_1 else { return fallback }
        return vector / length
    }

    private func ghostLabel(for placement: GhostAppliancePlacementV1) -> String {
        if let customId = placement.customApplianceDefinitionId,
           let custom = customApplianceDefinitions.first(where: { $0.id == customId }) {
            return "\(custom.brand) \(custom.modelName)"
        }
        if let definition = MasterHardwareRegistry.registry.definition(for: placement.applianceModelId) {
            return "\(definition.brand) \(definition.displayName)"
        }
        return placement.applianceModelId
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
            recentCaptures.append(RecentCaptureItemV1.from(photo: photo))
        } catch {
            print("[LiveSpatialCaptureView] Photo save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Recent captures helpers

    /// Evidence items for the current prospective room, sorted newest-first, capped at 7.
    private var recentItemsForCurrentRoom: [RecentCaptureItemV1] {
        recentCaptures
            .filter { $0.roomId == prospectiveRoomId }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(7)
            .map { $0 }
    }

    private var roomPhotos: [PhotoEvidenceV1] {
        photos.filter { $0.roomId == prospectiveRoomId }
    }

    private var roomVoiceNotes: [VoiceNoteV1] {
        voiceNotes.filter { $0.roomId == prospectiveRoomId }
    }

    private var noteSourceIDs: Set<UUID> {
        Set(
            recentCaptures
                .filter { $0.roomId == prospectiveRoomId && $0.evidenceType == .note }
                .map(\.sourceEvidenceId)
        )
    }

    private var offscreenPointerItems: [OffscreenPointerItemV1] {
        let activeSavedRoom = rooms.first(where: { $0.id == prospectiveRoomId })
        let savedPins = activeSavedRoom?.pinnedObjects ?? []
        let allPins = V2IdentifiableDedupe.byUUID(primary: savedPins, secondary: pendingPinsLocal)
        let roomCapturePoints = capturePointsById.values.filter { $0.roomId == prospectiveRoomId }
        let capturePointMap = Dictionary(uniqueKeysWithValues: roomCapturePoints.map { ($0.id, $0) })
        let recentDateByEvidenceId = Dictionary(
            uniqueKeysWithValues: recentCaptures
                .filter { $0.roomId == prospectiveRoomId }
                .map { ($0.sourceEvidenceId, $0.createdAt) }
        )

        var items: [OffscreenPointerItemV1] = []

        for pin in allPins {
            guard let capturePointId = pin.capturePointId else { continue }
            let world = pin.hasResolvedWorldAnchor ? SIMD3(pin.positionX, pin.positionY, pin.positionZ) : nil
            let fallbackScreen = normalizedScreenPoint(x: pin.screenPositionX, y: pin.screenPositionY)
            guard let resolvedScreen = resolvedScreenPoint(
                worldPosition: world,
                fallback: fallbackScreen,
                anchorConfidence: pin.anchorConfidence
            ) else {
                continue
            }

            items.append(
                OffscreenPointerItemV1(
                    id: UUID(),
                    roomId: pin.roomId,
                    capturePointId: capturePointId,
                    evidenceType: .objectPin,
                    title: pin.label ?? pin.objectType.rawValue.capitalized,
                    iconName: iconName(for: pin.objectType),
                    worldPosition: world,
                    screenPoint: resolvedScreen,
                    anchorConfidence: pin.anchorConfidence,
                    needsReview: pin.anchorConfidence == .screenOnly,
                    sourceEvidenceId: pin.id,
                    createdAt: recentDateByEvidenceId[pin.id] ?? .distantPast
                )
            )
        }

        for photo in roomPhotos {
            guard
                let capturePointId = photo.capturePointId,
                let capturePoint = capturePointMap[capturePointId],
                let resolvedScreen = resolvedScreenPoint(
                    worldPosition: capturePoint.worldPosition,
                    fallback: capturePoint.screenPoint,
                    anchorConfidence: capturePoint.anchorConfidence
                )
            else {
                continue
            }
            let createdAt = parseEvidenceTimestamp(photo.capturedAt)
            items.append(
                OffscreenPointerItemV1(
                    id: UUID(),
                    roomId: photo.roomId,
                    capturePointId: capturePointId,
                    evidenceType: .photo,
                    title: "Photo",
                    iconName: "photo.fill",
                    worldPosition: capturePoint.worldPosition,
                    screenPoint: resolvedScreen,
                    anchorConfidence: capturePoint.anchorConfidence,
                    needsReview: capturePoint.anchorConfidence == .screenOnly,
                    sourceEvidenceId: photo.id,
                    createdAt: createdAt
                )
            )
        }

        for note in roomVoiceNotes {
            guard
                let capturePointId = note.capturePointId,
                let capturePoint = capturePointMap[capturePointId],
                let resolvedScreen = resolvedScreenPoint(
                    worldPosition: capturePoint.worldPosition,
                    fallback: capturePoint.screenPoint,
                    anchorConfidence: capturePoint.anchorConfidence
                )
            else {
                continue
            }
            let createdAt = parseEvidenceTimestamp(note.recordedAt)
            let noteType: OffscreenPointerItemV1.EvidenceType = noteSourceIDs.contains(note.id) ? .note : .voiceNote
            items.append(
                OffscreenPointerItemV1(
                    id: UUID(),
                    roomId: note.roomId,
                    capturePointId: capturePointId,
                    evidenceType: noteType,
                    title: noteType == .note ? "Note" : "Voice note",
                    iconName: noteType == .note ? "note.text" : "mic.fill",
                    worldPosition: capturePoint.worldPosition,
                    screenPoint: resolvedScreen,
                    anchorConfidence: capturePoint.anchorConfidence,
                    needsReview: capturePoint.anchorConfidence == .screenOnly,
                    sourceEvidenceId: note.id,
                    createdAt: createdAt
                )
            )
        }

        return items
            .sorted(by: offscreenPrioritySort)
            .prefix(maxVisibleOffscreenPointers)
            .map { $0 }
    }

    private func offscreenPrioritySort(_ lhs: OffscreenPointerItemV1, _ rhs: OffscreenPointerItemV1) -> Bool {
        let lhsRank = evidencePriorityRank(lhs.evidenceType)
        let rhsRank = evidencePriorityRank(rhs.evidenceType)
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        let lhsDistance = distanceFromCenter(for: lhs.screenPoint)
        let rhsDistance = distanceFromCenter(for: rhs.screenPoint)
        if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }

        return lhs.createdAt > rhs.createdAt
    }

    private func evidencePriorityRank(_ type: OffscreenPointerItemV1.EvidenceType) -> Int {
        switch type {
        case .objectPin: return 0
        case .ghostAppliance: return 1
        case .photo: return 2
        case .voiceNote, .note: return 3
        case .measurement: return 4
        }
    }

    private func distanceFromCenter(for point: CGPointCodable?) -> Double {
        guard let point else { return .greatestFiniteMagnitude }
        let dx = point.x - normalizedScreenCenter
        let dy = point.y - normalizedScreenCenter
        return sqrt(dx * dx + dy * dy)
    }

    private func normalizedScreenPoint(x: Double?, y: Double?) -> CGPointCodable? {
        guard let x, let y else { return nil }
        return CGPointCodable(x: x, y: y)
    }

    private func resolvedScreenPoint(
        worldPosition: SIMD3<Double>?,
        fallback: CGPointCodable?,
        anchorConfidence: SpatialPinAnchorConfidence
    ) -> CGPointCodable? {
        if anchorConfidence != .screenOnly {
            guard let worldPosition else { return nil }
            return worldPointProjector?(worldPosition)
        }
        return fallback
    }

    private func parseEvidenceTimestamp(_ timestamp: String) -> Date {
        if let primary = Self.pointerDateFormatter.date(from: timestamp) {
            return primary
        }
        if let fractional = Self.pointerDateFormatterFractional.date(from: timestamp) {
            return fractional
        }
        print("[LiveSpatialCaptureView] Unable to parse evidence timestamp: \(timestamp)")
        return .distantPast
    }

    private func handlePointerTap(_ pointer: OffscreenPointerItemV1) {
        if let existing = recentItemsForCurrentRoom.first(where: {
            $0.sourceEvidenceId == pointer.sourceEvidenceId && matches(pointer.evidenceType, recentType: $0.evidenceType)
        }) {
            selectedRecentItem = existing
            return
        }

        guard let synthetic = syntheticRecentItem(from: pointer) else { return }
        selectedRecentItem = synthetic
    }

    private func handlePointerDelete(_ pointer: OffscreenPointerItemV1) {
        guard let item = syntheticRecentItem(from: pointer) else { return }
        handleDeleteRecentItem(item)
    }

    private func matches(_ pointerType: OffscreenPointerItemV1.EvidenceType, recentType: RecentCaptureItemV1.EvidenceType) -> Bool {
        switch (pointerType, recentType) {
        case (.objectPin, .objectPin),
             (.ghostAppliance, .ghostAppliance),
             (.photo, .photo),
             (.voiceNote, .voiceNote),
             (.note, .note):
            return true
        default:
            return false
        }
    }

    private func syntheticRecentItem(from pointer: OffscreenPointerItemV1) -> RecentCaptureItemV1? {
        switch pointer.evidenceType {
        case .objectPin:
            if let pin = pendingPinsLocal.first(where: { $0.id == pointer.sourceEvidenceId }) ??
                rooms.flatMap(\.pinnedObjects).first(where: { $0.id == pointer.sourceEvidenceId }) {
                return RecentCaptureItemV1.from(pin: pin)
            }
            return nil
        case .ghostAppliance:
            if let ghost = rooms.flatMap(\.ghostAppliancePlacements).first(where: { $0.id == pointer.sourceEvidenceId }) {
                return RecentCaptureItemV1.from(ghost: ghost, displayLabel: ghostLabel(for: ghost))
            }
            return nil
        case .photo:
            guard let photo = photos.first(where: { $0.id == pointer.sourceEvidenceId }) else { return nil }
            return RecentCaptureItemV1.from(photo: photo)
        case .voiceNote:
            guard let note = voiceNotes.first(where: { $0.id == pointer.sourceEvidenceId }) else { return nil }
            return RecentCaptureItemV1.from(voiceNote: note)
        case .note:
            guard let note = voiceNotes.first(where: { $0.id == pointer.sourceEvidenceId }) else { return nil }
            return RecentCaptureItemV1.fromObservationNote(note)
        case .measurement:
            if let m = pendingMeasurementsLocal.first(where: { $0.id == pointer.sourceEvidenceId }) ??
                rooms.flatMap(\.measurements).first(where: { $0.id == pointer.sourceEvidenceId }) {
                return RecentCaptureItemV1.from(measurement: m)
            }
            return nil
        }
    }

    private func handleDeleteRecentItem(_ item: RecentCaptureItemV1) {
        recentCaptures.removeAll { $0.id == item.id }
        switch item.evidenceType {
        case .objectPin:
            pendingPinsLocal.removeAll { $0.id == item.sourceEvidenceId }
        case .ghostAppliance:
            break
        case .measurement:
            pendingMeasurementsLocal.removeAll { $0.id == item.sourceEvidenceId }
        case .photo, .voiceNote, .note:
            break
        }
        onEvidenceDeleted(item)
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
    let onMore: () -> Void
    let onReview: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            dockButton(symbol: "scope", title: "Capture Point", action: onCapturePoint)
            dockButton(symbol: "map", title: "Review", action: onReview)
            Button(action: onFinish) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Finish Capture")
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
            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
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

private struct VisitCaptureHeaderBadge: View {
    let visitReference: String?
    let visitLabel: String?

    var body: some View {
        HStack(spacing: 8) {
            Label(displayReference, systemImage: "number")
                .font(.caption.weight(.semibold))
            if let label = cleanedLabel {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var displayReference: String {
        let trimmed = visitReference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Visit reference required" : trimmed
    }

    private var cleanedLabel: String? {
        let trimmed = visitLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CaptureActionBubbleMenu: View {
    let onTagObject: () -> Void
    let onPhoto: () -> Void
    let onVoiceNote: () -> Void
    let onMeasure: () -> Void
    let onNote: () -> Void
    let onPreviewAppliance: () -> Void
    let onNextRoom: () -> Void
    let onFinishVisit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                bubbleAction(title: "Tag object", systemImage: "mappin.and.ellipse", action: onTagObject)
                bubbleAction(title: "Photo", systemImage: "camera.fill", action: onPhoto)
                bubbleAction(title: "Voice note", systemImage: "mic.fill", action: onVoiceNote)
            }
            HStack(spacing: 8) {
                bubbleAction(title: "Measure", systemImage: "ruler.fill", action: onMeasure)
                bubbleAction(title: "Note", systemImage: "note.text", action: onNote)
                bubbleAction(title: "Preview", systemImage: "cube.transparent.fill", action: onPreviewAppliance)
            }
            HStack(spacing: 8) {
                bubbleAction(title: "Next Room", systemImage: "arrow.right.circle.fill", action: onNextRoom)
                bubbleAction(title: "Finish Visit", systemImage: "flag.checkered", action: onFinishVisit)
            }
            Button("Close", action: onDismiss)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func bubbleAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 6)
            .background(.ultraThinMaterial, in: Capsule())
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

private struct MeasurementsCountBadge: View {
    let count: Int

    var body: some View {
        Label("\(count) measurement\(count == 1 ? "" : "s")", systemImage: "ruler.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Shows an amber pulsing badge while the engineer is aiming the second measurement point.
private struct MeasurementInProgressBadge: View {
    @State private var pulse = false

    var body: some View {
        Label("Measuring — tap centre for end point", systemImage: "ruler")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.orange.opacity(pulse ? 0.95 : 0.70), in: RoundedRectangle(cornerRadius: 12))
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

private enum MeasurementAxisClassification {
    case vertical
    case horizontal
    case depth
    case unclassified

    var displayName: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        case .depth: return "Depth"
        case .unclassified: return "Unclassified"
        }
    }
}

private struct MeasurementResultSummary {
    let distanceText: String
    let axisLabel: String
    let qualityText: String
    let qualityColor: Color
}

private struct MeasurementResultBadge: View {
    let summary: MeasurementResultSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Last: \(summary.distanceText) · \(summary.axisLabel)")
                .font(.caption.weight(.semibold))
            Text(summary.qualityText)
                .font(.caption2)
                .foregroundStyle(summary.qualityColor)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProbeCaptureStatusBadge: View {
    let diagnostics: CaptureProbeDiagnosticsV1
    let pendingPoint: LiveCapturePointV1?

    private var normalizedTrackingState: String {
        diagnostics.trackingState.lowercased()
    }

    private var isTrackingLimited: Bool {
        normalizedTrackingState.hasPrefix("limited") || normalizedTrackingState == "notavailable"
    }

    private var formattedPlaneAlignment: String {
        switch diagnostics.planeAlignment.lowercased() {
        case "vertical": return "Vertical"
        case "horizontal": return "Horizontal"
        case "any": return "Any"
        case "none": return "None"
        default: return diagnostics.planeAlignment
        }
    }

    private var statusColor: Color {
        if pendingPoint?.anchorConfidence == .screenOnly { return .orange }
        if isTrackingLimited { return .orange }
        if diagnostics.resultType == .failed { return .red }
        return .green
    }

    private var statusText: String {
        if pendingPoint?.anchorConfidence == .screenOnly {
            return "Room-note-only hit"
        }
        if diagnostics.resultType == .failed {
            return "No stable hit"
        }
        if isTrackingLimited {
            return "Tracking limited"
        }
        return "Stable hit"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            Text("Alignment: \(formattedPlaneAlignment)")
                .font(.caption2)
                .foregroundStyle(.white)
            Text("Tracking: \(diagnostics.trackingState)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private enum GhostPreviewClearanceState {
    case clear(String)
    case warning(String)
    case conflict(String)

    var message: String {
        switch self {
        case .clear(let message), .warning(let message), .conflict(let message):
            return message
        }
    }

    var color: Color {
        switch self {
        case .clear: return .green
        case .warning: return .orange
        case .conflict: return .red
        }
    }
}

/// Draws a dashed guide line from the start measurement point to the screen centre.
private struct MeasurementGuideLineOverlay: View {
    let startNormalized: CGPointCodable
    let needsReview: Bool

    var body: some View {
        GeometryReader { geometry in
            let start = CGPoint(
                x: startNormalized.x * geometry.size.width,
                y: startNormalized.y * geometry.size.height
            )
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            Canvas { context, _ in
                var path = Path()
                path.move(to: start)
                path.addLine(to: centre)
                context.stroke(
                    path,
                    with: .color(needsReview ? .orange : .green),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                // Start anchor dot
                let dotRect = CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: dotRect), with: .color(needsReview ? .orange : .green))
            }
        }
    }
}

private struct GhostPlacementOverlay: View {
    let preview: GhostAppliancePreview
    let clearanceState: GhostPreviewClearanceState

    private var footprintSize: CGSize {
        let width = max(CGFloat(preview.dimensionsMm.width) / 10, 50)
        let height = max(CGFloat(preview.dimensionsMm.height) / 10, 60)
        return CGSize(width: min(width, 180), height: min(height, 220))
    }

    private var clearanceSize: CGSize {
        let expandedWidthMm = preview.dimensionsMm.width + preview.clearanceOffsetsMm.left + preview.clearanceOffsetsMm.right
        let expandedHeightMm = preview.dimensionsMm.height + preview.clearanceOffsetsMm.top + preview.clearanceOffsetsMm.bottom
        let width = max(CGFloat(expandedWidthMm) / 10, footprintSize.width + 8)
        let height = max(CGFloat(expandedHeightMm) / 10, footprintSize.height + 8)
        return CGSize(width: min(width, 230), height: min(height, 260))
    }

    private var needsReview: Bool {
        preview.confidence == .screenOnly || preview.placementPlane == .unknown
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(clearanceState.color.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(clearanceState.color.opacity(0.9), lineWidth: 2))
                        .frame(width: clearanceSize.width, height: clearanceSize.height)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.cyan.opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.9), lineWidth: 2))
                        .frame(width: footprintSize.width, height: footprintSize.height)
                }
                Text("Preview: \(preview.displayName)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(preview.dimensionsMm.width) × \(preview.dimensionsMm.height) × \(preview.dimensionsMm.depth) mm")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clearance envelope")
                    Text("Left \(preview.clearanceOffsetsMm.left) millimetres · Right \(preview.clearanceOffsetsMm.right) millimetres")
                    Text("Top \(preview.clearanceOffsetsMm.top) millimetres · Bottom \(preview.clearanceOffsetsMm.bottom) millimetres")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.86))
                Text(clearanceState.message)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(clearanceState.color)
                if needsReview {
                    Text("Needs review")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.orange, in: Capsule())
                }
            }
            .padding(8)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .position(screenPosition(in: geometry.size))
        }
        .allowsHitTesting(false)
    }

    private func screenPosition(in size: CGSize) -> CGPoint {
        CGPoint(
            x: preview.screenPoint.x * size.width,
            y: preview.screenPoint.y * size.height
        )
    }
}

private struct GhostPreviewActionBar: View {
    let title: String
    let selectedPlane: GhostPlacementPlaneV1
    let onConfirm: () -> Void
    let onAdjust: () -> Void
    let onSelectPlane: (GhostPlacementPlaneV1) -> Void
    let onChangeAppliance: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Preview: \(title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                planeChip(label: "Wall", plane: .wall)
                planeChip(label: "Floor", plane: .floor)
            }
            HStack(spacing: 8) {
                Button("Confirm placement", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                Button("Adjust", action: onAdjust)
                    .buttonStyle(.bordered)
                Button("Change appliance", action: onChangeAppliance)
                    .buttonStyle(.bordered)
                Button("Cancel", role: .destructive, action: onCancel)
                    .buttonStyle(.bordered)
            }
            .font(.caption2.weight(.semibold))
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
    }

    private func planeChip(label: String, plane: GhostPlacementPlaneV1) -> some View {
        let isActive = selectedPlane == plane
        return Button(label) {
            onSelectPlane(plane)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.green.opacity(0.85) : Color.white.opacity(0.12), in: Capsule())
        .foregroundStyle(isActive ? .black : .white)
        .buttonStyle(.plain)
    }
}

private struct CapturePointStatusBadge: View {
    let point: LiveCapturePointV1
    let isAnchorLost: Bool

    var body: some View {
        Label(statusText, systemImage: "scope")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusText: String {
        if isAnchorLost {
            return "Anchor lost"
        }
        if point.anchorConfidence == .screenOnly {
            return "Room note only"
        }
        if point.anchorConfidence == .worldLocked {
            return "World anchored"
        }
        return "Needs review"
    }
}

#if DEBUG
private struct CaptureProbeDiagnosticsBadge: View {
    let diagnostics: CaptureProbeDiagnosticsV1

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Raycast: \(diagnostics.raycastAttempted ? "yes" : "no")")
            Text("Type: \(diagnostics.resultType.rawValue)")
            Text("Distance: \(distanceText)")
            Text("Alignment: \(diagnostics.planeAlignment)")
            Text("Tracking: \(diagnostics.trackingState)")
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var distanceText: String {
        guard let distance = diagnostics.hitDistanceM else { return "n/a" }
        return String(format: "%.2fm", distance)
    }
}
#endif

struct LiveCapturePointProbeResultV1 {
    let screenPoint: CGPointCodable
    let worldPosition: SIMD3<Double>?
    let anchorConfidence: SpatialPinAnchorConfidence
    let hitNormal: SIMD3<Double>?
    let anchorId: UUID?
    let worldTransform: WorldTransformV1?
    let debugDiagnostics: CaptureProbeDiagnosticsV1?
}

enum CaptureProbeResultTypeV1: String {
    case existingPlaneGeometry
    case existingPlaneInfinite
    case estimatedPlane
    case featurePoint
    case roomMesh
    case failed
}

struct CaptureProbeDiagnosticsV1 {
    let raycastAttempted: Bool
    let resultType: CaptureProbeResultTypeV1
    let hitDistanceM: Double?
    let planeAlignment: String
    let trackingState: String
}

struct LiveCapturePointV1: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let roomId: UUID
    let createdAt: Date
    let screenPoint: CGPointCodable
    let worldPosition: SIMD3<Double>?
    let anchorConfidence: SpatialPinAnchorConfidence
    let hitNormal: SIMD3<Double>?
    let anchorId: UUID?
    let worldTransform: WorldTransformV1?
    let reviewStatus: SpatialPinReviewStatus
    /// Surface semantic at the hit point, derived from the hit normal at
    /// capture time.  Nil when no world-space anchor was available.
    let surfaceSemantic: SurfaceSemanticV1?

    init(
        id: UUID = UUID(),
        roomId: UUID,
        createdAt: Date = .now,
        screenPoint: CGPointCodable,
        worldPosition: SIMD3<Double>?,
        anchorConfidence: SpatialPinAnchorConfidence,
        hitNormal: SIMD3<Double>? = nil,
        anchorId: UUID? = nil,
        worldTransform: WorldTransformV1? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.createdAt = createdAt
        self.screenPoint = screenPoint
        self.worldPosition = worldPosition
        self.anchorConfidence = anchorConfidence
        self.hitNormal = hitNormal
        self.anchorId = anchorId
        self.worldTransform = worldTransform
        self.reviewStatus = .needsReview
        self.surfaceSemantic = worldPosition != nil
            ? SurfaceSemanticV1.derived(fromHitNormal: hitNormal)
            : nil
    }
}

// MARK: - V2PinPickerSheet

private struct V2PinPickerSheet: View {
    let roomId: UUID
    let capturePoint: LiveCapturePointV1?
    let onSave: (SpatialPinV1) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: PinObjectCategoryV1 = .heatSource
    @State private var selectedLocationContext: PinPlacementLocationContext = .unknownNeedsReview
    @State private var selectedBoilerType: BoilerType = .combi
    @State private var selectedCylinderType: CylinderType = .openVented
    @State private var selectedTemplateId: String?
    @State private var selectedComponent: EquipmentOption = defaultEquipmentOption
    @State private var customLabel = ""

    @State private var manualManufacturer = ""
    @State private var manualModel = ""
    @State private var manualType = ""
    @State private var manualWidthMm = ""
    @State private var manualHeightMm = ""
    @State private var manualDepthMm = ""
    @State private var manualFlueOrientation = ""
    @State private var manualNotes = ""

    private var hasLockedLocation: Bool { capturePoint != nil }

    init(
        roomId: UUID,
        capturePoint: LiveCapturePointV1?,
        onSave: @escaping (SpatialPinV1) -> Void
    ) {
        self.roomId = roomId
        self.capturePoint = capturePoint
        self.onSave = onSave
        _selectedLocationContext = State(initialValue: V2PinnedObjectBuilder.defaultLocationContext(for: capturePoint))
    }

    private enum BoilerType: String, CaseIterable, Identifiable {
        case combi
        case system
        case regular
        case manualUnknown = "manual_unknown"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .combi: return "Combi"
            case .system: return "System"
            case .regular: return "Regular"
            case .manualUnknown: return "Manual / unknown"
            }
        }
    }

    private enum CylinderType: String, CaseIterable, Identifiable {
        case openVented = "open_vented"
        case unvented
        case thermalStore = "thermal_store"
        case smart
        case unknownManual = "unknown_manual"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .openVented: return "Open vented cylinder"
            case .unvented: return "Unvented cylinder"
            case .thermalStore: return "Thermal store"
            case .smart: return "Smart cylinder"
            case .unknownManual: return "Unknown / manual cylinder"
            }
        }
    }

    private struct EquipmentOption: Identifiable, Hashable {
        let id: String
        let title: String
        let objectType: PinnedObjectType
        let templateId: String?
    }

    private static let heatingComponents: [EquipmentOption] = [
        .init(id: "pump", title: "Pump", objectType: .other, templateId: nil),
        .init(id: "zone_valve", title: "Zone valve", objectType: .other, templateId: nil),
        .init(id: "motorised_valve", title: "Motorised valve", objectType: .other, templateId: nil),
        .init(id: "filter", title: "Filter", objectType: .other, templateId: nil),
        .init(id: "expansion_vessel", title: "Expansion vessel", objectType: .other, templateId: nil),
        .init(id: "buffer_header", title: "Buffer / low loss header", objectType: .other, templateId: nil),
        .init(id: "controls", title: "Controls", objectType: .other, templateId: nil),
    ]

    private static let flueExternalItems: [EquipmentOption] = [
        .init(id: "flue_terminal", title: "Flue terminal", objectType: .flueTerminal, templateId: nil),
        .init(id: "plume_kit", title: "Plume kit", objectType: .other, templateId: nil),
        .init(id: "condensate_discharge", title: "Condensate discharge", objectType: .other, templateId: nil),
        .init(id: "gas_meter", title: "Gas meter", objectType: .gasmeter, templateId: nil),
        .init(id: "external_clearance_item", title: "External clearance item", objectType: .other, templateId: nil),
    ]

    private static let emitterItems: [EquipmentOption] = [
        .init(id: "radiator", title: "Radiator", objectType: .other, templateId: nil),
        .init(id: "towel_rail", title: "Towel rail", objectType: .other, templateId: nil),
        .init(id: "ufh_manifold", title: "Underfloor heating manifold", objectType: .other, templateId: nil),
        .init(id: "manual_emitter", title: "Manual emitter entry", objectType: .other, templateId: nil),
    ]

    private static let defaultEquipmentOption = EquipmentOption(
        id: "pump",
        title: "Pump",
        objectType: .other,
        templateId: nil
    )

    private static let boilerPlaceholderOption = EquipmentOption(
        id: "boiler_manual_unknown",
        title: "Boiler (manual details required)",
        objectType: .boiler,
        templateId: nil
    )

    private static let cylinderPlaceholderOption = EquipmentOption(
        id: "cylinder_manual_unknown",
        title: "Cylinder (manual details required)",
        objectType: .hotWaterCylinder,
        templateId: nil
    )

    private var boilerTemplates: [EquipmentOption] {
        let defs = MasterHardwareRegistry.registry
            .definitions(forCategory: "boiler")
            .filter { definition in
                switch selectedBoilerType {
                case .combi:
                    return definition.family.localizedCaseInsensitiveContains("Combi")
                case .system:
                    return definition.family.localizedCaseInsensitiveContains("System")
                case .regular:
                    return definition.family.localizedCaseInsensitiveContains("Regular")
                case .manualUnknown:
                    return false
                }
            }
            .sorted { $0.brand == $1.brand ? $0.displayName < $1.displayName : $0.brand < $1.brand }
        return defs.map { def in
            EquipmentOption(
                id: def.modelId,
                title: "\(def.brand) \(def.displayName)",
                objectType: .boiler,
                templateId: def.modelId
            )
        }
    }

    private var cylinderTemplates: [EquipmentOption] {
        let defs = MasterHardwareRegistry.registry
            .definitions(forCategory: "cylinder")
            .filter { definition in
                switch selectedCylinderType {
                case .openVented:
                    return definition.family.localizedCaseInsensitiveContains("Open Vented")
                case .unvented:
                    return definition.family.localizedCaseInsensitiveContains("Unvented")
                case .thermalStore:
                    return definition.family.localizedCaseInsensitiveContains("Thermal Store")
                case .smart:
                    return definition.family.localizedCaseInsensitiveContains("Smart")
                case .unknownManual:
                    return false
                }
            }
            .sorted { $0.brand == $1.brand ? $0.displayName < $1.displayName : $0.brand < $1.brand }
        return defs.map { def in
            EquipmentOption(
                id: def.modelId,
                title: "\(def.brand) \(def.displayName)",
                objectType: .hotWaterCylinder,
                templateId: def.modelId
            )
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Room") {
                    Text("Equipment will be added to the current room.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Location context") {
                    if hasLockedLocation {
                        LabeledContent("Location") {
                            Label(selectedLocationContext.displayName, systemImage: "lock.fill")
                                .foregroundStyle(.primary)
                        }
                        Text("Locked to the tapped location used to open this menu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Location", selection: $selectedLocationContext) {
                            ForEach(PinPlacementLocationContext.allCases, id: \.self) { context in
                                Text(context.displayName).tag(context)
                            }
                        }
                    }
                }
                Section("Object category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Heat source").tag(PinObjectCategoryV1.heatSource)
                        Text("Hot water storage").tag(PinObjectCategoryV1.hotWaterStorage)
                        Text("Heating system components").tag(PinObjectCategoryV1.heatingSystemComponents)
                        Text("Flue / external").tag(PinObjectCategoryV1.flueExternal)
                        Text("Emitters").tag(PinObjectCategoryV1.emitters)
                    }
                }

                switch selectedCategory {
                case .heatSource:
                    boilerSelectionSection
                case .hotWaterStorage:
                    cylinderSelectionSection
                case .heatingSystemComponents:
                    componentSelectionSection("Heating system components", options: Self.heatingComponents)
                case .flueExternal:
                    componentSelectionSection("Flue / external", options: Self.flueExternalItems)
                case .emitters:
                    componentSelectionSection("Emitters", options: Self.emitterItems)
                }
                Section("Review") {
                    Text(reviewSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Label override (optional)") {
                    TextField("Custom label", text: $customLabel)
                }
            }
            .navigationTitle("Add Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePinAndDismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var boilerSelectionSection: some View {
        Section("Boiler type") {
            Picker("Type", selection: $selectedBoilerType) {
                ForEach(BoilerType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
        }
        if selectedBoilerType == .manualUnknown {
            manualEntrySection(title: "Manual boiler entry")
        } else {
            Section("Boiler template") {
                Picker("Template", selection: $selectedTemplateId) {
                    ForEach(boilerTemplates) { option in
                        Text(option.title).tag(Optional(option.id))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cylinderSelectionSection: some View {
        Section("Cylinder category") {
            Picker("Category", selection: $selectedCylinderType) {
                ForEach(CylinderType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
        }
        if selectedCylinderType == .unknownManual {
            manualEntrySection(title: "Manual cylinder entry")
        } else {
            Section("Cylinder template") {
                Picker("Template", selection: $selectedTemplateId) {
                    ForEach(cylinderTemplates) { option in
                        Text(option.title).tag(Optional(option.id))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func componentSelectionSection(_ title: String, options: [EquipmentOption]) -> some View {
        Section(title) {
            Picker("Item", selection: $selectedComponent) {
                ForEach(options) { option in
                    Text(option.title).tag(option)
                }
            }
        }
    }

    @ViewBuilder
    private func manualEntrySection(title: String) -> some View {
        Section(title) {
            TextField("Manufacturer", text: $manualManufacturer)
            TextField("Model", text: $manualModel)
            TextField("Type", text: $manualType)
            TextField("Width (mm)", text: $manualWidthMm).keyboardType(.numberPad)
            TextField("Height (mm)", text: $manualHeightMm).keyboardType(.numberPad)
            TextField("Depth (mm)", text: $manualDepthMm).keyboardType(.numberPad)
            TextField("Flue orientation", text: $manualFlueOrientation)
            TextField("Notes", text: $manualNotes, axis: .vertical)
            Text("Photo evidence recommended")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var reviewSummary: String {
        let roomSummary = "Linked to the current room."
        let locationSummary = "Location: \(selectedLocationContext.displayName)."
        if capturePoint?.anchorConfidence == .screenOnly {
            return "\(roomSummary) \(locationSummary) Room note only — not spatially anchored."
        }
        if hasLockedLocation {
            return "\(roomSummary) \(locationSummary) Spatially locked to the tapped location."
        }
        return "\(roomSummary) \(locationSummary)"
    }

    private func savePinAndDismiss() {
        let option = selectedOption()
        let manualEntry = selectedManualEntry()
        let title = customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? option.title
            : customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = V2PinnedObjectBuilder.makePin(
            roomId: roomId,
            capturePoint: capturePoint,
            locationContext: selectedLocationContext,
            objectType: option.objectType,
            label: title,
            objectCategory: selectedCategory,
            selectedTemplateId: option.templateId,
            manualEntry: manualEntry
        )
        onSave(pin)
        dismiss()
    }

    private func selectedOption() -> EquipmentOption {
        switch selectedCategory {
        case .heatSource:
            if selectedBoilerType == .manualUnknown {
                return Self.boilerPlaceholderOption
            }
            let options = boilerTemplates
            return options.first(where: { $0.id == selectedTemplateId }) ?? options.first ?? Self.boilerPlaceholderOption
        case .hotWaterStorage:
            if selectedCylinderType == .unknownManual {
                return Self.cylinderPlaceholderOption
            }
            let options = cylinderTemplates
            return options.first(where: { $0.id == selectedTemplateId }) ?? options.first ?? Self.cylinderPlaceholderOption
        case .heatingSystemComponents, .flueExternal, .emitters:
            return selectedComponent
        }
    }

    private func selectedManualEntry() -> SpatialPinManualEntryV1? {
        guard selectedBoilerType == .manualUnknown || selectedCylinderType == .unknownManual else {
            return nil
        }
        return SpatialPinManualEntryV1(
            manufacturer: trimmed(manualManufacturer),
            model: trimmed(manualModel),
            type: trimmed(manualType),
            widthMm: intValue(manualWidthMm),
            heightMm: intValue(manualHeightMm),
            depthMm: intValue(manualDepthMm),
            flueOrientation: trimmed(manualFlueOrientation),
            notes: trimmed(manualNotes),
            photoEvidenceRecommended: true
        )
    }

    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func intValue(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum V2PinnedObjectBuilder {
    static func defaultLocationContext(for capturePoint: LiveCapturePointV1?) -> PinPlacementLocationContext {
        PinPlacementLocationContext.derived(from: capturePoint?.surfaceSemantic)
    }

    static func makePin(
        roomId: UUID,
        capturePoint: LiveCapturePointV1?,
        locationContext: PinPlacementLocationContext,
        objectType: PinnedObjectType,
        label: String,
        objectCategory: PinObjectCategoryV1,
        selectedTemplateId: String?,
        manualEntry: SpatialPinManualEntryV1?
    ) -> SpatialPinV1 {
        let worldPosition = capturePoint?.worldPosition
        let confidence: SpatialPinAnchorConfidence = capturePoint?.anchorConfidence ?? .screenOnly
        return SpatialPinV1(
            roomId: roomId,
            locationContext: locationContext,
            capturePointId: capturePoint?.id,
            anchorId: capturePoint?.anchorId,
            worldTransform: capturePoint?.worldTransform,
            positionX: worldPosition?.x ?? 0,
            positionY: worldPosition?.y ?? 0,
            positionZ: worldPosition?.z ?? 0,
            screenPositionX: capturePoint?.screenPoint.x,
            screenPositionY: capturePoint?.screenPoint.y,
            objectType: objectType,
            label: label,
            objectCategory: objectCategory,
            selectedTemplateId: selectedTemplateId,
            manualEntry: manualEntry,
            anchorConfidence: confidence,
            reviewStatus: .needsReview,
            provenance: .manualCapture,
            surfaceSemantic: capturePoint?.surfaceSemantic
        )
    }
}

private struct GhostAppliancePreview {
    let templateId: String?
    let displayName: String
    let dimensionsMm: GhostApplianceDimensionsMmV1
    let clearanceOffsetsMm: GhostApplianceClearanceOffsetsMmV1
    let worldPosition: SIMD3<Double>
    let screenPoint: CGPointCodable
    let placementPlane: GhostPlacementPlaneV1
    let planeNormal: SIMD3<Double>
    let confidence: SpatialPinAnchorConfidence
    let capturePointId: UUID
    let anchorId: UUID?
    let worldTransform: WorldTransformV1?
    let objectCategory: PinObjectCategoryV1
    let objectType: PinnedObjectType
    let manufacturer: String?
    let modelName: String?
    let applianceRole: String?
    let customDefinitionId: String?
    let note: String?
    /// Reserved for future pin-linking once preview-confirm synchronization ships.
    let sourcePinId: UUID? = nil
    /// Preview state is always unconfirmed until converted to a real pin.
    let isConfirmed = false
}

private enum GhostPreviewStrings {
    static let unknown = "unknown"
    static let manufacturerUnknown = "Manufacturer unknown"
    static let modelUnknown = "Model unknown"
    static let modelUnknownLower = "model unknown"
    static let unknownPreviewModelPrefix = "unknown-preview"
    static let unknownManufacturerSentinel = "__unknown_manufacturer__"
    static let unknownModelTemplateNote = "Template dimensions supplied for unknown model."
    static let roleCombi = "combi"
    static let roleSystem = "system"
    static let roleRegularHeatOnly = "regular_heat_only"
    static let unknownMarkers: Set<String> = [
        "unknown",
        "manufacturer unknown",
        "model unknown"
    ]
}

private struct GhostApplianceCandidate: Identifiable {
    let modelId: String
    let templateId: String?
    let brand: String
    let modelName: String
    let applianceType: String
    let boilerRole: String?
    let objectCategory: PinObjectCategoryV1
    let objectType: PinnedObjectType
    let dimensionsMm: GhostApplianceDimensionsMmV1
    let clearanceOffsetsMm: GhostApplianceClearanceOffsetsMmV1
    let customDefinitionId: String?
    let note: String?

    var id: String { modelId }

    var displayTitle: String {
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == GhostPreviewStrings.modelUnknownLower {
            if applianceType.lowercased().contains("boiler") {
                switch boilerRole {
                case GhostPreviewStrings.roleRegularHeatOnly: return "Regular / heat-only boiler"
                case GhostPreviewStrings.roleCombi: return "Combi boiler"
                case GhostPreviewStrings.roleSystem: return "System boiler"
                default: return "Boiler"
                }
            }
            let fallback = applianceType.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? "Appliance preview" : fallback.capitalized
        }
        let composed = "\(brand) \(modelName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return composed.isEmpty ? "Appliance preview" : composed
    }
}

private struct V2GhostAppliancePickerSheet: View {
    let customDefinitions: [CustomApplianceDefinitionV1]
    let recentModelIds: [String]
    let onSelect: (GhostApplianceCandidate) -> Void
    let onCustomDefinitionCreated: (CustomApplianceDefinitionV1) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showCustomCreator = false
    @State private var selectedCategory: ApplianceCategory = .boiler
    @State private var selectedBoilerRole: BoilerRole = .unknown
    @State private var selectedManufacturer = GhostPreviewStrings.unknownManufacturerSentinel
    @State private var selectedModelId: String?
    @State private var useTemplateDimensions = true
    @State private var widthMm = "700"
    @State private var heightMm = "800"
    @State private var depthMm = "550"

    private enum ApplianceCategory: String, CaseIterable, Identifiable {
        case boiler
        case cylinder
        case radiator
        case control
        case pump
        case gasMeter = "gas_meter"
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .boiler: return "Boiler"
            case .cylinder: return "Cylinder"
            case .radiator: return "Radiator"
            case .control: return "Control"
            case .pump: return "Pump"
            case .gasMeter: return "Gas meter"
            case .other: return "Other"
            }
        }
    }

    private enum BoilerRole: String, CaseIterable, Identifiable {
        case combi
        case system
        case regularHeatOnly = "regular_heat_only"
        case unknown

        var id: String { rawValue }

        var title: String {
            switch self {
            case .combi: return "Combi"
            case .system: return "System"
            case .regularHeatOnly: return "Regular heat-only"
            case .unknown: return "Unknown"
            }
        }

        var summaryLabel: String {
            switch self {
            case .regularHeatOnly: return "Regular / heat-only"
            case .combi: return "Combi"
            case .system: return "System"
            case .unknown: return "Boiler"
            }
        }
    }

    private var staticCandidates: [GhostApplianceCandidate] {
        MasterHardwareRegistry.registry.definitions.values
            .sorted { lhs, rhs in
                lhs.brand == rhs.brand ? lhs.displayName < rhs.displayName : lhs.brand < rhs.brand
            }
            .map {
                GhostApplianceCandidate(
                    modelId: $0.modelId,
                    templateId: $0.modelId,
                    brand: $0.brand,
                    modelName: $0.displayName,
                    applianceType: $0.category,
                    boilerRole: boilerRole(for: $0),
                    objectCategory: objectCategory(for: $0.category),
                    objectType: objectType(for: $0.category),
                    dimensionsMm: .init(
                        width: $0.dimensions.widthMm,
                        height: $0.dimensions.heightMm,
                        depth: $0.dimensions.depthMm
                    ),
                    clearanceOffsetsMm: .init(
                        top: $0.clearanceRules.topMm,
                        front: $0.clearanceRules.frontMm,
                        back: $0.clearanceRules.rearMm,
                        left: $0.clearanceRules.sideMm,
                        right: $0.clearanceRules.sideMm
                    ),
                    customDefinitionId: nil,
                    note: $0.guidanceNote
                )
            }
    }

    private var customCandidates: [GhostApplianceCandidate] {
        customDefinitions.map {
            GhostApplianceCandidate(
                modelId: $0.id,
                templateId: $0.id,
                brand: $0.brand,
                modelName: $0.modelName,
                applianceType: $0.applianceType,
                boilerRole: nil,
                objectCategory: objectCategory(for: $0.applianceType),
                objectType: objectType(for: $0.applianceType),
                dimensionsMm: $0.dimensionsMm,
                clearanceOffsetsMm: $0.clearanceOffsetsMm,
                customDefinitionId: $0.id,
                note: "Custom appliance"
            )
        }
    }

    private var allCandidates: [GhostApplianceCandidate] {
        staticCandidates + customCandidates
    }

    private var recentCandidates: [GhostApplianceCandidate] {
        recentModelIds.compactMap { id in allCandidates.first(where: { $0.modelId == id }) }
    }

    private var categoryCandidates: [GhostApplianceCandidate] {
        let filtered = allCandidates.filter { normalizedCategory($0.applianceType) == selectedCategory }
        guard selectedCategory == .boiler else { return filtered }
        switch selectedBoilerRole {
        case .combi:
            return filtered.filter { $0.boilerRole == "combi" }
        case .system:
            return filtered.filter { $0.boilerRole == "system" }
        case .regularHeatOnly:
            return filtered.filter { $0.boilerRole == "regular_heat_only" }
        case .unknown:
            return filtered
        }
    }

    private var manufacturerOptions: [String] {
        let known = Set(categoryCandidates.map(\.brand))
        let sortedKnown = known.sorted()
        return [GhostPreviewStrings.unknownManufacturerSentinel] + sortedKnown
    }

    private var modelOptions: [GhostApplianceCandidate] {
        guard selectedManufacturer != GhostPreviewStrings.unknownManufacturerSentinel else { return [] }
        return categoryCandidates.filter { $0.brand == selectedManufacturer }
    }

    private var selectedModelCandidate: GhostApplianceCandidate? {
        guard let selectedModelId else { return nil }
        return modelOptions.first { $0.modelId == selectedModelId }
    }

    private var fallbackTemplateCandidate: GhostApplianceCandidate? {
        switch selectedCategory {
        case .boiler:
            let fallbackId: String
            switch selectedBoilerRole {
            case .combi: fallbackId = "combi_generic"
            case .system: fallbackId = "system_generic"
            case .regularHeatOnly, .unknown: fallbackId = "regular_generic"
            }
            return allCandidates.first(where: { $0.modelId == fallbackId })
        case .cylinder:
            return allCandidates.first { normalizedCategory($0.applianceType) == .cylinder }
        default:
            return nil
        }
    }

    private var selectedDimensionsMm: GhostApplianceDimensionsMmV1 {
        if let selectedModelCandidate {
            return selectedModelCandidate.dimensionsMm
        }
        if let fallbackTemplateCandidate {
            return fallbackTemplateCandidate.dimensionsMm
        }
        return .init(width: intValue(widthMm, fallback: 700), height: intValue(heightMm, fallback: 800), depth: intValue(depthMm, fallback: 550))
    }

    var body: some View {
        NavigationStack {
            Form {
                if !recentCandidates.isEmpty {
                    Section("Recent") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recentCandidates) { candidate in
                                    Button(candidate.displayTitle) {
                                        selectRecentCandidate(candidate)
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("1. Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ApplianceCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                }

                if selectedCategory == .boiler {
                    Section("2. Boiler role") {
                        Picker("Boiler role", selection: $selectedBoilerRole) {
                            ForEach(BoilerRole.allCases) { role in
                                Text(role.title).tag(role)
                            }
                        }
                    }
                }

                Section("3. Manufacturer") {
                    Picker("Manufacturer", selection: $selectedManufacturer) {
                        ForEach(manufacturerOptions, id: \.self) { manufacturer in
                            Text(manufacturerDisplayName(manufacturer)).tag(manufacturer)
                        }
                    }
                }

                Section("4. Model / range") {
                    if modelOptions.isEmpty {
                        Text(GhostPreviewStrings.modelUnknown)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Model", selection: $selectedModelId) {
                            Text(GhostPreviewStrings.modelUnknown).tag(Optional<String>.none)
                            ForEach(modelOptions) { candidate in
                                Text(candidate.modelName).tag(Optional(candidate.modelId))
                            }
                        }
                    }
                }

                Section("5. Confirm dimensions") {
                    Toggle("Use template dimensions", isOn: $useTemplateDimensions)
                    TextField("Width (mm)", text: $widthMm)
                        .keyboardType(.numberPad)
                        .disabled(useTemplateDimensions)
                    TextField("Height (mm)", text: $heightMm)
                        .keyboardType(.numberPad)
                        .disabled(useTemplateDimensions)
                    TextField("Depth (mm)", text: $depthMm)
                        .keyboardType(.numberPad)
                        .disabled(useTemplateDimensions)
                }

                Section("Selection summary") {
                    Text(summaryLine1)
                    Text(summaryLine2)
                    Text(summaryLine3)
                    Text("Template: \(summaryTemplateLine)")
                        .foregroundStyle(.secondary)
                }

                Section("Manual / custom appliance") {
                    Button {
                        showCustomCreator = true
                    } label: {
                        Label("Custom appliance", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .onAppear(perform: syncDimensionsFromTemplate)
            .onChange(of: selectedCategory) { _, _ in
                selectedManufacturer = GhostPreviewStrings.unknownManufacturerSentinel
                selectedModelId = nil
                syncDimensionsFromTemplate()
            }
            .onChange(of: selectedBoilerRole) { _, _ in
                selectedModelId = nil
                syncDimensionsFromTemplate()
            }
            .onChange(of: selectedManufacturer) { _, _ in
                selectedModelId = nil
                syncDimensionsFromTemplate()
            }
            .onChange(of: selectedModelId) { _, _ in
                syncDimensionsFromTemplate()
            }
            .onChange(of: useTemplateDimensions) { _, _ in
                syncDimensionsFromTemplate()
            }
            .navigationTitle("Select appliance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use preview") {
                        onSelect(selectedCandidateForPreview())
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCustomCreator) {
                V2CustomApplianceDefinitionSheet { definition in
                    onCustomDefinitionCreated(definition)
                    onSelect(
                        GhostApplianceCandidate(
                            modelId: definition.id,
                            templateId: definition.id,
                            brand: definition.brand,
                            modelName: definition.modelName,
                            applianceType: definition.applianceType,
                            boilerRole: nil,
                            objectCategory: objectCategory(for: definition.applianceType),
                            objectType: objectType(for: definition.applianceType),
                            dimensionsMm: definition.dimensionsMm,
                            clearanceOffsetsMm: definition.clearanceOffsetsMm,
                            customDefinitionId: definition.id,
                            note: "Custom appliance"
                        )
                    )
                    dismiss()
                }
            }
        }
    }

    private func selectRecentCandidate(_ candidate: GhostApplianceCandidate) {
        selectedCategory = normalizedCategory(candidate.applianceType)
        selectedManufacturer = candidate.brand
        selectedModelId = candidate.modelId
        switch candidate.boilerRole {
        case GhostPreviewStrings.roleCombi: selectedBoilerRole = .combi
        case GhostPreviewStrings.roleSystem: selectedBoilerRole = .system
        case GhostPreviewStrings.roleRegularHeatOnly: selectedBoilerRole = .regularHeatOnly
        default: selectedBoilerRole = .unknown
        }
        syncDimensionsFromTemplate()
    }

    private func selectedCandidateForPreview() -> GhostApplianceCandidate {
        if let selectedModelCandidate {
            return selectedModelCandidate
        }

        let dims = GhostApplianceDimensionsMmV1(
            width: intValue(widthMm, fallback: selectedDimensionsMm.width),
            height: intValue(heightMm, fallback: selectedDimensionsMm.height),
            depth: intValue(depthMm, fallback: selectedDimensionsMm.depth)
        )
        return GhostApplianceCandidate(
            modelId: "\(GhostPreviewStrings.unknownPreviewModelPrefix)-\(UUID().uuidString)",
            templateId: nil,
            brand: GhostPreviewStrings.manufacturerUnknown,
            modelName: GhostPreviewStrings.modelUnknown,
            applianceType: selectedCategory.rawValue,
            boilerRole: selectedCategory == .boiler ? selectedBoilerRole.rawValue : nil,
            objectCategory: objectCategory(for: selectedCategory.rawValue),
            objectType: objectType(for: selectedCategory.rawValue),
            dimensionsMm: dims,
            clearanceOffsetsMm: fallbackTemplateCandidate?.clearanceOffsetsMm ?? .init(),
            customDefinitionId: nil,
            note: GhostPreviewStrings.unknownModelTemplateNote
        )
    }

    private func syncDimensionsFromTemplate() {
        guard useTemplateDimensions else { return }
        let dims = selectedDimensionsMm
        widthMm = "\(dims.width)"
        heightMm = "\(dims.height)"
        depthMm = "\(dims.depth)"
    }

    private var summaryLine1: String {
        if selectedCategory == .boiler {
            return "\(selectedBoilerRole.summaryLabel) boiler"
        }
        return selectedCategory.title
    }

    private var summaryLine2: String {
        manufacturerDisplayName(selectedManufacturer)
    }

    private var summaryLine3: String {
        selectedModelCandidate?.modelName ?? GhostPreviewStrings.modelUnknown
    }

    private var summaryTemplateLine: String {
        "\(intValue(widthMm, fallback: selectedDimensionsMm.width)) × \(intValue(heightMm, fallback: selectedDimensionsMm.height)) × \(intValue(depthMm, fallback: selectedDimensionsMm.depth)) mm"
    }

    private func normalizedCategory(_ value: String) -> ApplianceCategory {
        let lower = value.lowercased()
        if lower.contains("boiler") { return .boiler }
        if lower.contains("cylinder") { return .cylinder }
        if lower.contains("radiator") { return .radiator }
        if lower.contains("control") { return .control }
        if lower.contains("pump") { return .pump }
        if lower.contains("gas") && lower.contains("meter") { return .gasMeter }
        return .other
    }

    private func manufacturerDisplayName(_ rawValue: String) -> String {
        rawValue == GhostPreviewStrings.unknownManufacturerSentinel
            ? GhostPreviewStrings.manufacturerUnknown
            : rawValue
    }

    private func intValue(_ text: String, fallback: Int) -> Int {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
    }

    private func objectType(for applianceType: String) -> PinnedObjectType {
        let lower = applianceType.lowercased()
        if lower.contains("boiler") || lower.contains("heat") {
            return .boiler
        }
        if lower.contains("cylinder") {
            return .hotWaterCylinder
        }
        if lower.contains("gas") && lower.contains("meter") {
            return .gasmeter
        }
        return .other
    }

    private func objectCategory(for applianceType: String) -> PinObjectCategoryV1 {
        let lower = applianceType.lowercased()
        if lower.contains("boiler") || lower.contains("heat") {
            return .heatSource
        }
        if lower.contains("cylinder") {
            return .hotWaterStorage
        }
        if lower.contains("radiator") {
            return .emitters
        }
        if lower.contains("gas") || lower.contains("flue") {
            return .flueExternal
        }
        return .heatingSystemComponents
    }

    private func boilerRole(for definition: ApplianceDefinitionV1) -> String? {
        let family = definition.family.lowercased()
        if family.contains("combi") { return GhostPreviewStrings.roleCombi }
        if family.contains("system") { return GhostPreviewStrings.roleSystem }
        if family.contains("regular") { return GhostPreviewStrings.roleRegularHeatOnly }
        return nil
    }
}

private struct V2CustomApplianceDefinitionSheet: View {
    let onSave: (CustomApplianceDefinitionV1) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var brand = ""
    @State private var modelName = ""
    @State private var applianceType = "boiler"
    @State private var widthMm = "600"
    @State private var heightMm = "750"
    @State private var depthMm = "500"
    @State private var clearanceTopMm = "200"
    @State private var clearanceBottomMm = "0"
    @State private var clearanceFrontMm = "600"
    @State private var clearanceBackMm = "50"
    @State private var clearanceLeftMm = "100"
    @State private var clearanceRightMm = "100"

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    TextField("Brand", text: $brand)
                    TextField("Model", text: $modelName)
                    TextField("Type (boiler/cylinder/...)", text: $applianceType)
                }
                Section("Dimensions (mm)") {
                    TextField("Width", text: $widthMm).keyboardType(.numberPad)
                    TextField("Height", text: $heightMm).keyboardType(.numberPad)
                    TextField("Depth", text: $depthMm).keyboardType(.numberPad)
                }
                Section("Clearances (mm)") {
                    TextField("Top", text: $clearanceTopMm).keyboardType(.numberPad)
                    TextField("Bottom", text: $clearanceBottomMm).keyboardType(.numberPad)
                    TextField("Front", text: $clearanceFrontMm).keyboardType(.numberPad)
                    TextField("Back", text: $clearanceBackMm).keyboardType(.numberPad)
                    TextField("Left", text: $clearanceLeftMm).keyboardType(.numberPad)
                    TextField("Right", text: $clearanceRightMm).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Custom Appliance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveDefinition() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        intValue(widthMm) > 0 &&
        intValue(heightMm) > 0 &&
        intValue(depthMm) > 0
    }

    private func intValue(_ text: String) -> Int {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func saveDefinition() {
        let id = "custom-\(UUID().uuidString.lowercased())"
        let definition = CustomApplianceDefinitionV1(
            id: id,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            applianceType: applianceType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            dimensionsMm: .init(
                width: intValue(widthMm),
                height: intValue(heightMm),
                depth: intValue(depthMm)
            ),
            clearanceOffsetsMm: .init(
                top: intValue(clearanceTopMm),
                bottom: intValue(clearanceBottomMm),
                front: intValue(clearanceFrontMm),
                back: intValue(clearanceBackMm),
                left: intValue(clearanceLeftMm),
                right: intValue(clearanceRightMm)
            )
        )
        onSave(definition)
        dismiss()
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
