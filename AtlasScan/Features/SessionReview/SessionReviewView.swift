import SwiftUI

// MARK: - SessionReviewView
//
// Read-only (or lightly editable) review surface for an existing PropertyScanSession.
//
// Allows any user with access to open a saved/uploaded session and inspect:
//   • room layout with tagged objects at saved positions
//   • correctly-sized object footprints and clearance zones
//   • linked photos and issue badges
//   • voice notes grouped by room / object
//   • session metadata (captured by, date, address, job reference)
//
// No live AR capture or room scanning is possible from this view.
// This is the "shared session replay" — the session is treated as a portable
// review artifact that any device/user can open from local storage or Atlas sync.
//
// Four review tabs:
//   Layout  — per-room 2D plan with object placements and clearance overlays
//   Objects — grouped object list with size, clearance status, photo/note counts
//   Photos  — evidence photos grouped by room / object
//   Notes   — voice notes grouped by room / object

struct SessionReviewView: View {

    let session: PropertyScanSession

    // Optional store — when provided, light edits (object updates) can be saved.
    var store: ScanSessionStore? = nil

    enum ReviewTab: String, CaseIterable {
        case layout  = "Layout"
        case objects = "Objects"
        case photos  = "Photos"
        case notes   = "Notes"
        case needs   = "Needs"

        var symbolName: String {
            switch self {
            case .layout:  return "map"
            case .objects: return "tag.fill"
            case .photos:  return "photo.stack"
            case .notes:   return "mic.fill"
            case .needs:   return "person.text.rectangle"
            }
        }
    }

    @State private var selectedTab: ReviewTab = .layout
    @State private var selectedRoomID: UUID? = nil
    @State private var selectedObjectID: UUID? = nil
    @State private var showingArtifactInspector = false
    @State private var showingFactReview = false

    var body: some View {
        VStack(spacing: 0) {
            // Provenance header
            provenanceHeader
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()

            // Tab picker
            Picker("Review Mode", selection: $selectedTab) {
                ForEach(ReviewTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            TabView(selection: $selectedTab) {
                layoutTab
                    .tag(ReviewTab.layout)

                objectsTab
                    .tag(ReviewTab.objects)

                photosTab
                    .tag(ReviewTab.photos)

                notesTab
                    .tag(ReviewTab.notes)

                needsTab
                    .tag(ReviewTab.needs)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(session.propertyAddress)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    reviewStateBadgeItem
                    Divider()
                    Button {
                        showingArtifactInspector = true
                    } label: {
                        Label("Inspect Artifact", systemImage: "doc.text.magnifyingglass")
                    }
                } label: {
                    Image(systemName: session.reviewState.symbolName)
                }
            }
        }
        .sheet(isPresented: $showingArtifactInspector) {
            SessionArtifactInspectorView(session: session)
        }
        .sheet(isPresented: $showingFactReview) {
            SessionFactReviewView(session: session)
        }
    }

    // MARK: - Provenance header

    private var provenanceHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.propertyAddress)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !session.engineerName.isEmpty {
                        Label("Captured by \(session.engineerName)", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Label(
                        session.createdAt.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(session.jobReference)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(session.reviewState.displayName)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(reviewStateColor.opacity(0.15))
                        .foregroundStyle(reviewStateColor)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            statsChip
        }
    }

    private var statsChip: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Label("\(session.rooms.count)", systemImage: "square.split.2x1")
                .font(.caption2).foregroundStyle(.secondary)
            Label("\(session.totalTaggedObjects)", systemImage: "tag.fill")
                .font(.caption2).foregroundStyle(.secondary)
            Label("\(session.totalPhotos)", systemImage: "photo.fill")
                .font(.caption2).foregroundStyle(.secondary)
            Label("\(session.totalVoiceNotes)", systemImage: "mic.fill")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var reviewStateColor: Color {
        switch session.reviewState {
        case .pending:        return .gray
        case .inReview:       return .orange
        case .reviewed:       return .green
        case .needsAttention: return .orange
        case .blocked:        return .red
        }
    }

    @ViewBuilder
    private var reviewStateBadgeItem: some View {
        Label(session.reviewState.displayName,
              systemImage: session.reviewState.symbolName)
        Label(session.syncState.displayName,
              systemImage: session.syncState.symbolName)
    }

    // MARK: - Layout tab

    private var layoutTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if session.rooms.isEmpty {
                    emptyRoomsPlaceholder
                        .padding()
                } else {
                    ForEach(session.rooms) { room in
                        ReviewRoomLayoutSection(
                            room: room,
                            session: session,
                            selectedObjectID: $selectedObjectID,
                            selectedRoomID: $selectedRoomID
                        )
                    }
                }

                if !session.taggedObjects.isEmpty {
                    ReviewSessionObjectsSection(
                        objects: session.taggedObjects,
                        photos: session.allPhotos,
                        selectedObjectID: $selectedObjectID
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var emptyRoomsPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No rooms captured")
                .font(.title3.bold())
            Text("This session has no scanned rooms. Rooms appear here once captured in the field.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Objects tab

    private var objectsTab: some View {
        List {
            ForEach(session.rooms) { room in
                let objects = room.taggedObjects
                if !objects.isEmpty {
                    Section {
                        ForEach(objects) { obj in
                            ReviewObjectRow(
                                object: obj,
                                room: room,
                                photos: photosForObject(obj.id, in: room),
                                isSelected: selectedObjectID == obj.id,
                                onTap: {
                                    selectedObjectID = selectedObjectID == obj.id ? nil : obj.id
                                    selectedTab = .layout
                                }
                            )
                        }
                    } header: {
                        HStack {
                            Text(room.name)
                            Spacer()
                            Text(room.displayFloor)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if !session.taggedObjects.isEmpty {
                Section("Unassigned Objects") {
                    ForEach(session.taggedObjects) { obj in
                        ReviewObjectRow(
                            object: obj,
                            room: nil,
                            photos: photosForObject(obj.id, in: nil),
                            isSelected: selectedObjectID == obj.id,
                            onTap: {
                                selectedObjectID = selectedObjectID == obj.id ? nil : obj.id
                            }
                        )
                    }
                }
            }

            if session.allTaggedObjects.isEmpty {
                Section {
                    Text("No tagged objects in this session.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Photos tab

    private var photosTab: some View {
        List {
            ForEach(session.rooms) { room in
                let roomPhotos = room.photos
                if !roomPhotos.isEmpty {
                    Section {
                        ForEach(roomPhotos) { photo in
                            ReviewPhotoRow(photo: photo, objects: room.taggedObjects)
                        }
                    } header: {
                        Text(room.name)
                    }
                }
            }

            let sessionPhotos = session.photos
            if !sessionPhotos.isEmpty {
                Section("Session-Level Photos") {
                    ForEach(sessionPhotos) { photo in
                        ReviewPhotoRow(photo: photo, objects: session.allTaggedObjects)
                    }
                }
            }

            if session.allPhotos.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No photos captured")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Notes tab

    private var notesTab: some View {
        List {
            ForEach(session.rooms) { room in
                let roomNotes = room.voiceNotes
                if !roomNotes.isEmpty {
                    Section {
                        ForEach(roomNotes) { note in
                            ReviewVoiceNoteRow(note: note, objects: room.taggedObjects)
                        }
                    } header: {
                        Text(room.name)
                    }
                }
            }

            let sessionNotes = session.voiceNotes
            if !sessionNotes.isEmpty {
                Section("Session-Level Notes") {
                    ForEach(sessionNotes) { note in
                        ReviewVoiceNoteRow(note: note, objects: session.allTaggedObjects)
                    }
                }
            }

            if session.allVoiceNotes.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "mic.slash")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No voice notes recorded")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Needs tab

    private var needsTab: some View {
        List {
            Section {
                SessionKnowledgeSection(session: session)
            } header: {
                Text("Captured Needs")
            } footer: {
                needsTabFooter
            }

            if !session.extractedFacts.isEmpty {
                Section {
                    Button {
                        showingFactReview = true
                    } label: {
                        Label("View All Extracted Facts", systemImage: "list.bullet.rectangle")
                    }
                }
            }

            knowledgeGapsSection
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var needsTabFooter: some View {
        let summary = session.knowledgeSummary
        if summary.hasAnyFacts {
            Text("Facts are extracted conservatively from voice notes. Capture more notes to improve coverage.")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private var knowledgeGapsSection: some View {
        let summary = session.knowledgeSummary
        if !summary.missingEssentials.isEmpty || !summary.reviewWarnings.isEmpty {
            Section("Knowledge Gaps") {
                ForEach(summary.missingEssentials, id: \.self) { msg in
                    Label(msg, systemImage: "circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(summary.reviewWarnings, id: \.self) { msg in
                    Label(msg, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Helpers

    private func photosForObject(_ objectID: UUID, in room: ScannedRoom?) -> [TaggedPhoto] {
        let allPhotos: [TaggedPhoto]
        if let room {
            allPhotos = room.photos + session.photos
        } else {
            allPhotos = session.allPhotos
        }
        return allPhotos.filter { $0.taggedObjectID == objectID }
    }
}

// MARK: - ReviewRoomLayoutSection

/// One room's layout panel inside the review layout tab.
/// Shows the 2D room plan, clearance overlays, and an object summary strip.
private struct ReviewRoomLayoutSection: View {

    let room: ScannedRoom
    let session: PropertyScanSession
    @Binding var selectedObjectID: UUID?
    @Binding var selectedRoomID: UUID?

    private var isExpanded: Bool { selectedRoomID == room.id }

    private var clearanceResults: [UUID: ClearanceResult] {
        let others = room.taggedObjects
        return room.taggedObjects.reduce(into: [:]) { dict, obj in
            if let result = ClearanceEngine.evaluate(
                object: obj, in: room,
                otherObjects: others.filter { $0.id != obj.id }
            ) {
                dict[obj.id] = result
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room header — tap to expand / collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedRoomID = isExpanded ? nil : room.id
                }
            } label: {
                roomHeader
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Layout canvas
                RoomLayoutView(
                    room: room,
                    selectedObjectID: selectedObjectID,
                    clearanceResults: clearanceResults,
                    onTapObject: { id in
                        selectedObjectID = selectedObjectID == id ? nil : id
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Object summary strip below the canvas
                if !room.taggedObjects.isEmpty {
                    objectStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }

            Divider()
        }
    }

    private var roomHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(room.displayFloor)
                        .font(.caption).foregroundStyle(.secondary)
                    if room.geometryCaptured {
                        Label("Scanned", systemImage: "camera.viewfinder")
                            .font(.caption2).foregroundStyle(.blue)
                    }
                    if !room.taggedObjects.isEmpty {
                        Label("\(room.taggedObjects.count)", systemImage: "tag.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if !room.photos.isEmpty {
                        Label("\(room.photos.count)", systemImage: "photo.fill")
                            .font(.caption2).foregroundStyle(.indigo)
                    }
                }
            }

            Spacer()

            if room.isReviewed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var objectStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(room.taggedObjects) { obj in
                    let isSelected = selectedObjectID == obj.id
                    let result = clearanceResults[obj.id]
                    Button {
                        selectedObjectID = isSelected ? nil : obj.id
                    } label: {
                        ReviewObjectChip(
                            object: obj,
                            clearanceStatus: result?.status,
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - ReviewSessionObjectsSection

/// Session-level floating objects shown in the layout tab.
private struct ReviewSessionObjectsSection: View {
    let objects: [TaggedObject]
    let photos: [TaggedPhoto]
    @Binding var selectedObjectID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unassigned Objects")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ForEach(objects) { obj in
                ReviewObjectRow(
                    object: obj,
                    room: nil,
                    photos: photos.filter { $0.taggedObjectID == obj.id },
                    isSelected: selectedObjectID == obj.id,
                    onTap: {
                        selectedObjectID = selectedObjectID == obj.id ? nil : obj.id
                    }
                )
            }
        }
    }
}

// MARK: - ReviewObjectRow

struct ReviewObjectRow: View {
    let object: TaggedObject
    let room: ScannedRoom?
    let photos: [TaggedPhoto]
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Category icon
                Image(systemName: object.category.symbolName)
                    .font(.body)
                    .foregroundStyle(isSelected ? .white : categoryColor)
                    .frame(width: 36, height: 36)
                    .background(isSelected ? categoryColor : categoryColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(object.displayLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if !object.isConfirmed {
                            Text("Unconfirmed")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    Text(object.category.groupName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Dimensions if set
                    if let size = object.boundingSize {
                        Text(String(format: "%.0f cm × %.0f cm",
                                    size.widthMetres * 100,
                                    size.depthMetres * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    // Clearance status
                    if let result = clearanceResult {
                        Image(systemName: result.status.symbolName)
                            .font(.caption)
                            .foregroundStyle(clearanceStatusColor(result.status))
                    }

                    // Photo count
                    if !photos.isEmpty {
                        Label("\(photos.count)", systemImage: "photo.fill")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                    }

                    // Voice note count
                    let noteCount = object.linkedVoiceNoteIDs.count
                    if noteCount > 0 {
                        Label("\(noteCount)", systemImage: "mic.fill")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                    }

                    // Notes indicator
                    if !object.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var clearanceResult: ClearanceResult? {
        guard let room else { return nil }
        let others = room.taggedObjects.filter { $0.id != object.id }
        return ClearanceEngine.evaluate(object: object, in: room, otherObjects: others)
    }

    private var categoryColor: Color {
        switch object.category.groupName {
        case "Heat Source / Plant":  return .orange
        case "Emitters":             return .red
        case "Services / Utilities": return .blue
        case "Controls":             return .purple
        case "Structural / Siting":  return .gray
        default:                     return Color(.systemGray3)
        }
    }

    private func clearanceStatusColor(_ status: ClearanceStatus) -> Color {
        switch status {
        case .clear:    return .green
        case .warning:  return .orange
        case .conflict: return .red
        }
    }
}

// MARK: - ReviewObjectChip

/// A compact chip used in the horizontal object strip below the room layout canvas.
struct ReviewObjectChip: View {
    let object: TaggedObject
    var clearanceStatus: ClearanceStatus? = nil
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: object.category.symbolName)
                .font(.caption2)
                .foregroundStyle(isSelected ? .white : .secondary)
            Text(object.displayLabel)
                .font(.caption2)
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)

            if let status = clearanceStatus {
                Circle()
                    .fill(statusColor(status))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.accentColor : Color(.separator), lineWidth: 0.5)
        )
    }

    private func statusColor(_ status: ClearanceStatus) -> Color {
        switch status {
        case .clear:    return .green
        case .warning:  return .orange
        case .conflict: return .red
        }
    }
}

// MARK: - ReviewPhotoRow

struct ReviewPhotoRow: View {
    let photo: TaggedPhoto
    let objects: [TaggedObject]

    var body: some View {
        HStack(spacing: 12) {
            // Photo icon / thumbnail placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 44, height: 44)
                Image(systemName: photo.kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                if !photo.caption.isEmpty {
                    Text(photo.caption)
                        .font(.subheadline)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(photo.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let objID = photo.taggedObjectID,
                       let obj = objects.first(where: { $0.id == objID }) {
                        Text("→ \(obj.displayLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(photo.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Sync state indicator
            Image(systemName: photo.syncState.symbolName)
                .font(.caption)
                .foregroundStyle(photo.syncState == .uploaded ? Color.green : Color.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ReviewVoiceNoteRow

struct ReviewVoiceNoteRow: View {
    let note: VoiceNote
    let objects: [TaggedObject]

    var body: some View {
        HStack(spacing: 12) {
            // Kind icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 44, height: 44)
                Image(systemName: note.kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(note.kind.displayName)
                    .font(.subheadline)

                if !note.caption.isEmpty {
                    Text(note.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(formatDuration(note.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let objID = note.linkedObjectID,
                       let obj = objects.first(where: { $0.id == objID }) {
                        Text("→ \(obj.displayLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Sync state indicator
            Image(systemName: note.syncState.symbolName)
                .font(.caption)
                .foregroundStyle(note.syncState == .uploaded ? Color.green : Color.secondary)
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Session Review — full session") {
    let session: PropertyScanSession = {
        let s = PropertyScanSession(
            propertyAddress: "14 Maple Street, Anytown, AN1 2BT",
            engineerName: "Sam Taylor",
            scanState: .completed,
            reviewState: .inReview,
            rooms: [MockData.livingRoom, MockData.utilityRoom]
        )
        return s
    }()

    NavigationStack {
        SessionReviewView(session: session)
    }
}

#Preview("Session Review — empty") {
    let session = PropertyScanSession(
        propertyAddress: "7 Elm Close, Othertown",
        engineerName: "Alex Hughes"
    )
    NavigationStack {
        SessionReviewView(session: session)
    }
}
#endif
