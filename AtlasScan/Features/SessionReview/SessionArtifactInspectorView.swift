import SwiftUI

// MARK: - SessionArtifactInspectorView
//
// Debug / export inspection surface for a captured PropertyScanSession artifact.
//
// Shows:
//   • A counts summary (rooms, objects, photos, voice notes, issues)
//   • A link integrity report — detects orphaned or broken cross-references between
//     objects, photos, voice notes, and rooms so engineers can trust the artifact
//     before it feeds Atlas
//   • The raw session JSON for deep inspection
//   • Share / copy actions for the session JSON
//
// Intended use: launched from the SessionReviewView toolbar ("Inspect Artifact").
// Provides confidence that the session can be saved, reopened, and queued cleanly.

struct SessionArtifactInspectorView: View {

    let session: PropertyScanSession

    @Environment(\.dismiss) private var dismiss

    @State private var sessionJSON: String = ""
    @State private var linkReport: ArtifactLinkReport = .empty
    @State private var showingJSONView = false
    @State private var shareItem: ArtifactShareItem?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                summarySection
                linkIntegritySection
                jsonActionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Artifact Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { buildReport() }
            .sheet(isPresented: $showingJSONView) {
                ArtifactJSONView(json: sessionJSON)
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.text])
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section("Artifact Summary") {
            LabeledContent("Session ID", value: String(session.id.uuidString.prefix(8)) + "…")
            LabeledContent("Job reference", value: session.jobReference)
            LabeledContent("Address", value: session.propertyAddress)
            LabeledContent("Engineer", value: session.engineerName.isEmpty ? "—" : session.engineerName)
            LabeledContent("Scan state", value: session.scanState.displayName)
            LabeledContent("Sync state", value: session.syncState.displayName)
            LabeledContent("Rooms", value: "\(session.rooms.count)")
            LabeledContent("Tagged objects", value: "\(session.totalTaggedObjects)")
            LabeledContent("Photos", value: "\(session.totalPhotos)")
            LabeledContent("Voice notes", value: "\(session.totalVoiceNotes)")
            LabeledContent("Issues", value: "\(session.issues.count)")
        }
    }

    @ViewBuilder
    private var linkIntegritySection: some View {
        Section {
            if linkReport.issues.isEmpty {
                Label("All cross-links verified", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(linkReport.issues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .frame(width: 20)
                        Text(issue.description)
                            .font(.subheadline)
                    }
                }
            }
        } header: {
            HStack {
                Text("Link Integrity")
                Spacer()
                if !linkReport.issues.isEmpty {
                    Text("\(linkReport.issues.count) issue\(linkReport.issues.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(linkReport.hasErrors ? .red : .orange)
                }
            }
        } footer: {
            if linkReport.issues.isEmpty {
                Text("Object→photo, object→voice-note, photo→room, and note→room references are all resolvable.")
                    .font(.caption2)
            }
        }
    }

    private var jsonActionsSection: some View {
        Section("JSON Payload") {
            if sessionJSON.isEmpty {
                Label("Building payload…", systemImage: "arrow.circlepath")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    showingJSONView = true
                } label: {
                    Label("Inspect JSON", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    shareItem = ArtifactShareItem(text: sessionJSON)
                } label: {
                    Label("Share JSON", systemImage: "square.and.arrow.up")
                }

                Button {
                    copyJSONToClipboard()
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.clipboard")
                }

                LabeledContent("Payload size", value: formattedJSONSize)
            }
        }
    }

    // MARK: - Build report

    private func buildReport() {
        // Encode the session to JSON for inspection
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(session) {
            sessionJSON = String(decoding: data, as: UTF8.self)
        }

        // Run link integrity checks
        linkReport = ArtifactLinkReport.build(from: session)
    }

    // MARK: - Helpers

    private var formattedJSONSize: String {
        let bytes = sessionJSON.utf8.count
        if bytes < 1024 {
            return "\(bytes) B"
        } else {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
    }

    private func copyJSONToClipboard() {
        guard !sessionJSON.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = sessionJSON
        #endif
    }
}

// MARK: - ArtifactLinkReport

/// The result of a cross-reference integrity check on a captured session artifact.
struct ArtifactLinkReport {

    struct LinkIssue: Identifiable {
        let id = UUID()
        let description: String
        let severity: Severity

        enum Severity {
            case error    // broken reference — data loss risk
            case warning  // inconsistency — worth investigating
        }
    }

    var issues: [LinkIssue] = []

    var hasErrors: Bool { issues.contains { $0.severity == .error } }

    static var empty: ArtifactLinkReport { ArtifactLinkReport() }

    /// Checks all cross-references in the session and returns a populated report.
    static func build(from session: PropertyScanSession) -> ArtifactLinkReport {
        var report = ArtifactLinkReport()

        let allObjectIDs = Set(session.allTaggedObjects.map(\.id))
        let allPhotoIDs  = Set(session.allPhotos.map(\.id))
        let allNoteIDs   = Set(session.allVoiceNotes.map(\.id))
        let allRoomIDs   = Set(session.rooms.map(\.id))

        // 1. Each object's linkedPhotoIDs should all exist in allPhotos
        for obj in session.allTaggedObjects {
            for photoID in obj.linkedPhotoIDs {
                if !allPhotoIDs.contains(photoID) {
                    report.issues.append(LinkIssue(
                        description: "Object '\(obj.displayLabel)' references photo \(photoID.uuidString.prefix(8))… which does not exist.",
                        severity: .error
                    ))
                }
            }
        }

        // 2. Each object's linkedVoiceNoteIDs should all exist in allVoiceNotes
        for obj in session.allTaggedObjects {
            for noteID in obj.linkedVoiceNoteIDs {
                if !allNoteIDs.contains(noteID) {
                    report.issues.append(LinkIssue(
                        description: "Object '\(obj.displayLabel)' references voice note \(noteID.uuidString.prefix(8))… which does not exist.",
                        severity: .error
                    ))
                }
            }
        }

        // 3. Each photo's taggedObjectID (when set) should resolve to a known object
        for photo in session.allPhotos {
            if let objID = photo.taggedObjectID, !allObjectIDs.contains(objID) {
                report.issues.append(LinkIssue(
                    description: "Photo '\(photo.filename)' links to object \(objID.uuidString.prefix(8))… which does not exist.",
                    severity: .error
                ))
            }
        }

        // 4. Each photo's roomID (when set) should resolve to a known room
        for photo in session.allPhotos {
            if let roomID = photo.roomID, !allRoomIDs.contains(roomID) {
                report.issues.append(LinkIssue(
                    description: "Photo '\(photo.filename)' links to room \(roomID.uuidString.prefix(8))… which does not exist.",
                    severity: .warning
                ))
            }
        }

        // 5. Each voice note's linkedObjectID (when set) should resolve to a known object
        for note in session.allVoiceNotes {
            if let objID = note.linkedObjectID, !allObjectIDs.contains(objID) {
                report.issues.append(LinkIssue(
                    description: "Voice note '\(note.localFilename)' links to object \(objID.uuidString.prefix(8))… which does not exist.",
                    severity: .error
                ))
            }
        }

        // 6. Each voice note's linkedRoomID (when set) should resolve to a known room
        for note in session.allVoiceNotes {
            if let roomID = note.linkedRoomID, !allRoomIDs.contains(roomID) {
                report.issues.append(LinkIssue(
                    description: "Voice note '\(note.localFilename)' links to room \(roomID.uuidString.prefix(8))… which does not exist.",
                    severity: .warning
                ))
            }
        }

        // 7. Consistency check: object carries a photo cross-link but the photo
        //    doesn't point back to that object (forward link present, back link absent)
        let photosByID = Dictionary(uniqueKeysWithValues: session.allPhotos.map { ($0.id, $0) })
        for obj in session.allTaggedObjects {
            for photoID in obj.linkedPhotoIDs {
                if let photo = photosByID[photoID], photo.taggedObjectID != obj.id {
                    report.issues.append(LinkIssue(
                        description: "Object '\(obj.displayLabel)' links photo '\(photo.filename)' but the photo does not point back to this object.",
                        severity: .warning
                    ))
                }
            }
        }

        // 8. Consistency check: voice note carries a back-link to an object but
        //    the object doesn't carry a forward cross-link to the note
        let objectsByID = Dictionary(
            uniqueKeysWithValues: session.allTaggedObjects.map { ($0.id, $0) }
        )
        for note in session.allVoiceNotes {
            if let objID = note.linkedObjectID {
                if let obj = objectsByID[objID],
                   !obj.linkedVoiceNoteIDs.contains(note.id) {
                    report.issues.append(LinkIssue(
                        description: "Voice note '\(note.localFilename)' links to object '\(obj.displayLabel)' but the object does not carry a forward cross-link.",
                        severity: .warning
                    ))
                }
            }
        }

        return report
    }
}

// MARK: - ArtifactJSONView

private struct ArtifactJSONView: View {
    let json: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(json)
                    .font(.system(.caption2, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Session JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ArtifactShareItem (Identifiable wrapper)

private struct ArtifactShareItem: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Previews

#if DEBUG
#Preview("Artifact Inspector — clean session") {
    let session = PropertyScanSession(
        propertyAddress: "14 Maple Street, Anytown, AN1 2BT",
        engineerName: "Sam Taylor",
        scanState: .completed,
        rooms: [MockData.livingRoom, MockData.utilityRoom]
    )
    SessionArtifactInspectorView(session: session)
}

#Preview("Artifact Inspector — empty session") {
    SessionArtifactInspectorView(
        session: PropertyScanSession(propertyAddress: "7 Elm Close, Othertown")
    )
}
#endif
