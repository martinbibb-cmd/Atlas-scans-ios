import SwiftUI

// MARK: - SessionCaptureView
//
// The session home surface for one PropertyScanSession.
//
// Exposes three top-level actions:
//   • Resume Walkthrough — primary live capture mode (room scan, add objects, evidence photos)
//   • Review Session     — read-only review surface (rooms, objects, photos, transcript)
//   • Sync to Atlas      — package and upload the session bundle
//
// Secondary surfaces available from the same screen:
//   • Session HUD (status, autosave indicator, stats)
//   • Selected-object panel with inline clearance summary
//   • Room list with scan / manual add
//   • Session-level floating objects
//   • Atlas sync queue status
//
// Engineers never need to leave this screen during a survey pass.

struct SessionCaptureView: View {

    @StateObject private var viewModel: SessionCaptureViewModel

    // Sheet presentation state
    @State private var showingAddObject = false
    @State private var showingAddPhoto = false
    @State private var showingAddVoiceNote = false
    @State private var showingAddRoom = false
    @State private var showingSyncConfirm = false
    @State private var showingLiveView = false
    @State private var showingReview = false
    @State private var newRoomName = ""
    @State private var newRoomFloor = 0

    init(session: PropertyScanSession, store: ScanSessionStore, atlasSync: AtlasSync) {
        _viewModel = StateObject(wrappedValue: SessionCaptureViewModel(
            session: session,
            store: store,
            atlasSync: atlasSync
        ))
    }

    var body: some View {
        List {
            sessionHeaderSection
            if viewModel.selectedObject != nil {
                selectedObjectSection
            }
            roomsSection
            if let focusedRoom = viewModel.selectedRoom {
                if !focusedRoom.taggedObjects.isEmpty {
                    focusedRoomObjectsSection(focusedRoom)
                }
                if !focusedRoom.voiceNotes.isEmpty {
                    focusedRoomVoiceNotesSection(focusedRoom)
                }
            }
            if !viewModel.sessionLevelObjects.isEmpty {
                sessionObjectsSection
            }
            if !viewModel.sessionLevelVoiceNotes.isEmpty {
                sessionVoiceNotesSection
            }
            quickActionsSection
            atlasSyncSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(viewModel.session.propertyAddress)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAddObject) {
            AddObjectSheet(room: viewModel.makePlaceholderRoom()) { obj in
                viewModel.addObject(obj)
            }
        }
        .sheet(isPresented: $showingAddPhoto) {
            AddPhotoSheet(
                roomID: photoContextRoomID,
                taggedObjectID: photoContextObjectID
            ) { photo in
                viewModel.addPhoto(photo)
            }
        }
        .sheet(isPresented: $showingAddVoiceNote) {
            VoiceNoteRecorderSheet(attachContext: voiceNoteAttachContext) { note in
                viewModel.addVoiceNote(note)
            }
        }
        .sheet(isPresented: $showingAddRoom) {
            addRoomSheet
        }
        .fullScreenCover(isPresented: $showingLiveView) {
            liveViewTaggingCover
        }
        .navigationDestination(isPresented: $showingReview) {
            SessionReviewView(
                session: viewModel.session,
                store: viewModel.store
            )
        }
        .onDisappear {
            viewModel.saveNow()
        }
    }

    // MARK: - Photo context helpers

    /// Room to pre-fill on the photo sheet, derived from current attachment target.
    private var photoContextRoomID: UUID? {
        switch viewModel.pendingPhotoTarget {
        case .session:        return nil
        case .room(let id):   return id
        case .object:         return viewModel.selectedObject?.roomID
        }
    }

    /// Object to pre-fill on the photo sheet, derived from current attachment target.
    private var photoContextObjectID: UUID? {
        switch viewModel.pendingPhotoTarget {
        case .object(let id): return id
        default:              return nil
        }
    }

    /// Human-readable label describing where a voice note will attach.
    private var voiceNoteAttachContext: String {
        if let obj = viewModel.selectedObject {
            return obj.displayLabel
        } else if let room = viewModel.selectedRoom {
            return room.name
        } else {
            return "Session"
        }
    }

    // MARK: - Session header section

    private var sessionHeaderSection: some View {
        Section {
            LabeledContent("Reference", value: viewModel.session.jobReference)
            if !viewModel.session.engineerName.isEmpty {
                LabeledContent("Engineer", value: viewModel.session.engineerName)
            }
            HStack {
                Label(
                    viewModel.session.scanState.displayName,
                    systemImage: viewModel.session.scanState.symbolName
                )
                .font(.subheadline)
                Spacer()
                saveStateBadge
            }
            HStack(spacing: 16) {
                Label("\(viewModel.session.rooms.count) room(s)", systemImage: "square.split.2x1")
                    .font(.caption).foregroundStyle(.secondary)
                Label("\(viewModel.session.totalTaggedObjects) object(s)", systemImage: "tag.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Label("\(viewModel.session.totalPhotos) photo(s)", systemImage: "photo.fill")
                    .font(.caption).foregroundStyle(.secondary)
                if viewModel.session.totalVoiceNotes > 0 {
                    Label("\(viewModel.session.totalVoiceNotes) note(s)", systemImage: "mic.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Session")
        }
    }

    @ViewBuilder
    private var saveStateBadge: some View {
        switch viewModel.saveState {
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .saving:
            Label("Saving…", systemImage: "arrow.circlepath")
                .font(.caption2).foregroundStyle(.secondary)
        case .unsaved:
            Label("Unsaved", systemImage: "circle.dashed")
                .font(.caption2).foregroundStyle(.orange)
        }
    }

    // MARK: - Selected object section

    /// Shown when an object is selected. Provides the primary clearance overlay and photo shortcut.
    @ViewBuilder
    private var selectedObjectSection: some View {
        if let obj = viewModel.selectedObject {
            Section {
                // Object identity row
                HStack {
                    Image(systemName: obj.category.symbolName)
                        .foregroundStyle(.orange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(obj.displayLabel)
                            .font(.headline)
                        Text(obj.category.groupName)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.selectObject(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Primary visual: three-layer clearance overlay
                clearanceOverlayRow(for: obj)

                // Secondary support: compact text clearance summary
                clearanceSummaryRow(for: obj)

                // Quick photo attach
                Button {
                    showingAddPhoto = true
                } label: {
                    Label("Attach Photo to Object", systemImage: "camera.badge.plus")
                        .font(.subheadline)
                }

                // Voice note attach
                Button {
                    showingAddVoiceNote = true
                } label: {
                    let count = obj.linkedVoiceNoteIDs.count
                    Label(
                        count > 0
                            ? "Add Voice Note (\(count) linked)"
                            : "Add Voice Note",
                        systemImage: "mic.badge.plus"
                    )
                    .font(.subheadline)
                }

                // Linked voice notes list
                let linkedNotes = viewModel.voiceNotes(forObject: obj.id)
                if !linkedNotes.isEmpty {
                    objectVoiceNotesList(linkedNotes)
                }
            } header: {
                Text("Selected Object")
            } footer: {
                Text("Photos taken now will be linked to this object. Tap × to deselect.")
                    .font(.caption2)
            }
        }
    }

    /// Primary clearance visual for the selected object.
    /// Renders footprintRect, installMinimumRect, and serviceAccessRect as layered halos.
    /// Colour follows ClearanceStatus: green / orange / red.
    @ViewBuilder
    private func clearanceOverlayRow(for obj: TaggedObject) -> some View {
        let room = viewModel.selectedRoom
            ?? viewModel.session.rooms.first(where: { $0.id == obj.roomID })
        if let room {
            let otherObjects = room.taggedObjects.filter { $0.id != obj.id }
            if let result = ClearanceEngine.evaluate(object: obj, in: room, otherObjects: otherObjects) {
                ClearanceOverlayView(result: result, object: obj, otherObjects: otherObjects)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        }
    }

    /// Secondary text summary row for the selected object.
    /// Shows explicit pass / tight fit / blocked outcome text so the status
    /// is clear without relying on colour alone.
    @ViewBuilder
    private func clearanceSummaryRow(for obj: TaggedObject) -> some View {
        let room = viewModel.selectedRoom
            ?? viewModel.session.rooms.first(where: { $0.id == obj.roomID })
        if let room,
           let result = ClearanceEngine.evaluate(
               object: obj, in: room,
               otherObjects: room.taggedObjects.filter { $0.id != obj.id }
           ) {
            HStack(spacing: 8) {
                Image(systemName: result.status.symbolName)
                    .foregroundStyle(clearanceStatusColor(result.status))
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.status.shortLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(clearanceStatusColor(result.status))
                    Text(result.status.displayMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !result.issues.isEmpty {
                    let allLabels = result.issues.compactMap(\.sideLabel)
                    let directions = allLabels.reduce(into: [String]()) { acc, label in
                        if !acc.contains(label) { acc.append(label) }
                    }
                    if directions.isEmpty {
                        Text("\(result.issues.count) issue\(result.issues.count == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(directions.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        } else {
            Text("Scan a room to see clearance zones.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func clearanceStatusColor(_ status: ClearanceStatus) -> Color {
        switch status {
        case .clear:    return .green
        case .warning:  return .orange
        case .conflict: return .red
        }
    }

    // MARK: - Rooms section

    private var roomsSection: some View {
        Section {
            if viewModel.session.rooms.isEmpty {
                Text("No rooms yet. Tap 'Add / Scan Room' to start.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.session.rooms) { room in
                    SessionRoomRow(
                        room: room,
                        isSelected: viewModel.selectedRoomID == room.id
                    ) {
                        if viewModel.selectedRoomID == room.id {
                            viewModel.selectRoom(nil)
                        } else {
                            viewModel.selectRoom(room.id)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets {
                        viewModel.removeRoom(id: viewModel.session.rooms[i].id)
                    }
                }
            }
            Button {
                showingAddRoom = true
            } label: {
                Label("Add / Scan Room", systemImage: "plus.square")
            }
        } header: {
            Text("Rooms")
        } footer: {
            if let room = viewModel.selectedRoom {
                Text("Focus: \(room.name). New objects and photos attach to this room.")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Focused room objects section

    /// Shows all tagged objects belonging to the currently focused room.
    /// Each row is tappable to select/deselect the object, triggering the
    /// clearance overlay in `selectedObjectSection`.
    private func focusedRoomObjectsSection(_ room: ScannedRoom) -> some View {
        Section {
            ForEach(room.taggedObjects) { obj in
                SessionObjectRow(
                    object: obj,
                    isSelected: viewModel.selectedObjectID == obj.id
                ) {
                    if viewModel.selectedObjectID == obj.id {
                        viewModel.selectObject(nil)
                    } else {
                        viewModel.selectObject(obj.id)
                    }
                }
            }
        } header: {
            Text("Objects — \(room.name)")
        } footer: {
            Text("Tap an object to select it and view its clearance zones.")
                .font(.caption2)
        }
    }

    // MARK: - Focused room voice notes section

    /// Shows voice notes belonging to the currently focused room.
    private func focusedRoomVoiceNotesSection(_ room: ScannedRoom) -> some View {
        Section {
            ForEach(room.voiceNotes) { note in
                VoiceNoteRowView(
                    note: note,
                    onDelete: {
                        VoiceNotePlaybackManager.shared.stop()
                        viewModel.removeVoiceNote(id: note.id)
                        VoiceNoteStore.shared.deleteFile(for: note)
                    },
                    onUpdateCaption: { newCaption in
                        var updated = note
                        updated.caption = newCaption
                        viewModel.updateVoiceNote(updated)
                    }
                )
            }
        } header: {
            Text("Voice Notes — \(room.name)")
        }
    }

    // MARK: - Object linked voice notes list

    /// Inline list of voice notes linked to the selected object.
    @ViewBuilder
    private func objectVoiceNotesList(_ notes: [VoiceNote]) -> some View {
        ForEach(notes) { note in
            VoiceNoteRowView(
                note: note,
                onDelete: {
                    VoiceNotePlaybackManager.shared.stop()
                    viewModel.removeVoiceNote(id: note.id)
                    VoiceNoteStore.shared.deleteFile(for: note)
                },
                onUpdateCaption: { newCaption in
                    var updated = note
                    updated.caption = newCaption
                    viewModel.updateVoiceNote(updated)
                }
            )
        }
    }

    // MARK: - Session-level objects section

    private var sessionObjectsSection: some View {
        Section {
            ForEach(viewModel.sessionLevelObjects) { obj in
                SessionObjectRow(
                    object: obj,
                    isSelected: viewModel.selectedObjectID == obj.id
                ) {
                    if viewModel.selectedObjectID == obj.id {
                        viewModel.selectObject(nil)
                    } else {
                        viewModel.selectObject(obj.id)
                    }
                }
            }
        } header: {
            Text("Session Objects")
        } footer: {
            Text("Objects not yet assigned to a specific room.")
                .font(.caption2)
        }
    }

    // MARK: - Session-level voice notes section

    private var sessionVoiceNotesSection: some View {
        Section {
            ForEach(viewModel.sessionLevelVoiceNotes) { note in
                VoiceNoteRowView(
                    note: note,
                    onDelete: {
                        VoiceNotePlaybackManager.shared.stop()
                        viewModel.removeVoiceNote(id: note.id)
                        VoiceNoteStore.shared.deleteFile(for: note)
                    },
                    onUpdateCaption: { newCaption in
                        var updated = note
                        updated.caption = newCaption
                        viewModel.updateVoiceNote(updated)
                    }
                )
            }
        } header: {
            Text("Session Voice Notes")
        } footer: {
            Text("Notes not linked to a specific room or object.")
                .font(.caption2)
        }
    }

    // MARK: - Quick actions section

    private var quickActionsSection: some View {
        Section {
            // Primary: Resume Walkthrough — the main capture mode
            Button {
                showingLiveView = true
            } label: {
                HStack {
                    Image(systemName: "camera.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Resume Walkthrough")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Scan rooms, add objects, capture evidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            // Secondary: Add Object (convenience shortcut outside walkthrough)
            Button {
                showingAddObject = true
            } label: {
                Label("Add Object", systemImage: "plus.circle.fill")
            }

            // Evidence photo
            Button {
                showingAddPhoto = true
            } label: {
                Label(evidencePhotoButtonLabel, systemImage: "camera.fill")
            }

            // Note marker
            Button {
                showingAddVoiceNote = true
            } label: {
                Label(noteMarkerButtonLabel, systemImage: "mic.badge.plus")
            }
        } header: {
            Text("Capture")
        } footer: {
            Text("Resume Walkthrough to place objects in the live camera feed. Attaching to: \(viewModel.pendingPhotoTarget.displayName).")
                .font(.caption2)
        }
    }

    private var evidencePhotoButtonLabel: String {
        switch viewModel.pendingPhotoTarget {
        case .session: return "Evidence Photo"
        case .room:    return "Evidence Photo (Room)"
        case .object:  return "Evidence Photo (Object)"
        }
    }

    private var noteMarkerButtonLabel: String {
        if viewModel.selectedObject != nil {
            return "Note Marker (Object)"
        } else if viewModel.selectedRoom != nil {
            return "Note Marker (Room)"
        } else {
            return "Note Marker"
        }
    }

    // MARK: - Atlas sync section

    private var atlasSyncSection: some View {
        Section {
            if viewModel.syncQueueCount > 0 {
                Label(
                    "\(viewModel.syncQueueCount) item(s) queued for Atlas",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Button {
                showingSyncConfirm = true
            } label: {
                Label("Queue for Atlas Sync", systemImage: "icloud.and.arrow.up")
            }
            .confirmationDialog(
                "Queue for Atlas Sync?",
                isPresented: $showingSyncConfirm,
                titleVisibility: .visible
            ) {
                Button("Queue Session + Photos") {
                    viewModel.queueForAtlasSync()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The session and all unsynced photos will be queued for upload when a connection is available.")
            }
        } header: {
            Text("Atlas Sync")
        } footer: {
            Text("Local data is always saved first. Upload begins only when you tap Queue.")
                .font(.caption2)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    showingLiveView = true
                } label: {
                    Label("Walkthrough", systemImage: "camera.viewfinder")
                }
                Button {
                    showingAddObject = true
                } label: {
                    Label("Add Object", systemImage: "plus.circle.fill")
                }
                Button {
                    showingAddPhoto = true
                } label: {
                    Label("Evidence Photo", systemImage: "camera.fill")
                }
                Button {
                    showingAddVoiceNote = true
                } label: {
                    Label("Note Marker", systemImage: "mic.badge.plus")
                }
                Button {
                    showingAddRoom = true
                } label: {
                    Label("Add / Scan Room", systemImage: "plus.square")
                }
                Divider()
                Button {
                    viewModel.saveNow()
                    showingReview = true
                } label: {
                    Label("Review Session", systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    viewModel.saveNow()
                } label: {
                    Label("Save Now", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - Live view cover

    private var liveViewTaggingCover: some View {
        LiveViewTaggingView(
            viewModel: LiveViewTaggingViewModel(sessionViewModel: viewModel)
        )
    }

    // MARK: - Add room sheet

    private var addRoomSheet: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room name", text: $newRoomName)
                        .autocorrectionDisabled()
                    Picker("Floor", selection: $newRoomFloor) {
                        Text("Basement").tag(-1)
                        Text("Ground Floor").tag(0)
                        Text("First Floor").tag(1)
                        Text("Second Floor").tag(2)
                    }
                }

                Section {
                    NavigationLink("Scan Room") {
                        RoomCaptureContainerView(
                            jobID: viewModel.session.id,
                            roomName: newRoomName.isEmpty ? "New Room" : newRoomName,
                            floor: newRoomFloor
                        ) { capturedRoom in
                            viewModel.addRoom(capturedRoom)
                            showingAddRoom = false
                            newRoomName = ""
                            newRoomFloor = 0
                        }
                    }
                    .disabled(newRoomName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Add Room (Manual / No Scan)") {
                        let room = ScannedRoom(
                            jobID: viewModel.session.id,
                            name: newRoomName.isEmpty ? "New Room" : newRoomName,
                            floor: newRoomFloor
                        )
                        viewModel.addRoom(room)
                        showingAddRoom = false
                        newRoomName = ""
                        newRoomFloor = 0
                    }
                    .disabled(newRoomName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Add Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddRoom = false
                        newRoomName = ""
                        newRoomFloor = 0
                    }
                }
            }
        }
    }
}

// MARK: - SessionRoomRow

struct SessionRoomRow: View {
    let room: ScannedRoom
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(room.displayFloor)
                            .font(.caption).foregroundStyle(.secondary)
                        if !room.taggedObjects.isEmpty {
                            Label("\(room.taggedObjects.count)", systemImage: "tag.fill")
                                .font(.caption).foregroundStyle(.blue)
                        }
                        if !room.photos.isEmpty {
                            Label("\(room.photos.count)", systemImage: "photo.fill")
                                .font(.caption).foregroundStyle(.indigo)
                        }
                        if !room.voiceNotes.isEmpty {
                            Label("\(room.voiceNotes.count)", systemImage: "mic.fill")
                                .font(.caption).foregroundStyle(.purple)
                        }
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
                if room.geometryCaptured {
                    Image(systemName: "camera.viewfinder")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SessionObjectRow

struct SessionObjectRow: View {
    let object: TaggedObject
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: object.category.symbolName)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(object.displayLabel)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(object.category.groupName)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
                if !object.linkedPhotoIDs.isEmpty {
                    Label("\(object.linkedPhotoIDs.count)", systemImage: "photo.fill")
                        .font(.caption2).foregroundStyle(.indigo)
                }
                if !object.linkedVoiceNoteIDs.isEmpty {
                    Label("\(object.linkedVoiceNoteIDs.count)", systemImage: "mic.fill")
                        .font(.caption2).foregroundStyle(.purple)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NavigationStack {
        SessionCaptureView(
            session: PropertyScanSession(
                jobReference: "JOB-DEMO",
                propertyAddress: "12 Survey Street",
                engineerName: "Jane Engineer"
            ),
            store: ScanSessionStore(),
            atlasSync: AtlasSync()
        )
    }
}
#endif
