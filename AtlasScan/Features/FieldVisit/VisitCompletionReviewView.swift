import SwiftUI

// MARK: - VisitCompletionReviewView
//
// Post-completion review screen.
//
// Accessible:
//   • Immediately after successful visit completion (from FieldCompleteView).
//   • From the session list for already-completed visits.
//
// Rules:
//   • Read-only. No mutation actions are exposed.
//   • Built from the canonical session data via VisitHandoffPackBuilder.
//   • Share/export is a placeholder seam for future PDF/portal work.

struct VisitCompletionReviewView: View {

    let session: PropertyScanSession

    // MARK: State

    @State private var activeTab: ReviewTab = .customer
    @State private var showSharePlaceholder = false

    // MARK: Builder (stateless — recomputed on appear)

    private var handoffPack: VisitHandoffPack {
        VisitHandoffPackBuilder().buildHandoffPack(for: session)
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                completionBanner
                tabPicker
                tabContent
                actionRow
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Visit Summary")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Export not yet available", isPresented: $showSharePlaceholder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Full export and portal sharing will be available in a future update.")
        }
    }

    // MARK: - Completion banner

    private var completionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Visit completed")
                    .font(.headline)
                if let completedAt = session.completedAt {
                    Text("Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Your survey has been saved and is ready for review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Tab picker

    private enum ReviewTab: String, CaseIterable {
        case customer = "Customer"
        case engineer = "Engineer"

        var symbolName: String {
            switch self {
            case .customer: return "person"
            case .engineer: return "wrench.adjustable"
            }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbolName)
                            .font(.caption)
                        Text(tab.rawValue)
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(activeTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                    .foregroundStyle(activeTab == tab ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .customer:
            CustomerSummaryView(summary: handoffPack.customerSummary)
        case .engineer:
            EngineerSummaryView(summary: handoffPack.engineerSummary)
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        VStack(spacing: 10) {
            Button {
                showSharePlaceholder = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share summary")
                        .font(.body)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .disabled(false) // placeholder seam — will enable with real export in a later PR
        }
    }
}

// MARK: - CustomerSummaryView

/// Clean, customer-safe summary card.
///
/// Sections:
///   • What we found
///   • What's planned
///   • What happens next
struct CustomerSummaryView: View {

    let summary: CustomerVisitSummary

    var body: some View {
        VStack(spacing: 12) {
            headerCard

            summarySection(
                title: "What we found",
                symbol: "magnifyingglass",
                lines: summary.findings
            )

            if !summary.planSummary.isEmpty {
                summarySection(
                    title: "What's planned",
                    symbol: "pencil.and.ruler",
                    lines: summary.planSummary
                )
            }

            summarySection(
                title: "What happens next",
                symbol: "arrow.right.circle",
                lines: summary.whatToExpectNext
            )
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Customer summary")
                    .font(.headline)
                Text(summary.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func summarySection(title: String, symbol: String, lines: [String]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            VStack(spacing: 1) {
                ForEach(lines, id: \.self) { line in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green.opacity(0.7))
                        Text(line)
                            .font(.body)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemGroupedBackground))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - EngineerSummaryView

/// Denser, engineer-facing detail summary.
///
/// Sections:
///   • Rooms
///   • Key objects
///   • Proposed emitters
///   • Access notes
///   • Room plan notes
///   • Spec notes
///   • Field notes summary
struct EngineerSummaryView: View {

    let summary: EngineerVisitSummary

    var body: some View {
        VStack(spacing: 12) {
            headerCard

            if !summary.rooms.isEmpty {
                roomsSection
            }

            if !summary.keyObjects.isEmpty {
                keyObjectsSection
            }

            if !summary.proposedEmitters.isEmpty {
                proposedEmittersSection
            }

            if !summary.accessNotes.isEmpty {
                notesSection(title: "Access notes", symbol: "door.left.hand.open", lines: summary.accessNotes)
            }

            if !summary.roomPlanNotes.isEmpty {
                notesSection(title: "Room plan notes", symbol: "rectangle.portrait", lines: summary.roomPlanNotes)
            }

            if !summary.specNotes.isEmpty {
                notesSection(title: "Spec notes", symbol: "list.bullet.clipboard", lines: summary.specNotes)
            }

            if !summary.consolidatedFieldNotes.isEmpty {
                fieldNotesSection
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "wrench.adjustable.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(Color.orange.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Engineer handoff")
                    .font(.headline)
                Text("\(summary.roomCount) room\(summary.roomCount == 1 ? "" : "s") · \(summary.keyObjectCount) key object\(summary.keyObjectCount == 1 ? "" : "s") · \(summary.proposedEmitterCount) proposed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Rooms

    private var roomsSection: some View {
        engineerSection(title: "Rooms", symbol: "rectangle.grid.2x2") {
            ForEach(summary.rooms, id: \.name) { room in
                engineerRow {
                    HStack {
                        Text(room.name)
                            .font(.body)
                        Spacer()
                        HStack(spacing: 8) {
                            if room.objectCount > 0 {
                                Label("\(room.objectCount)", systemImage: "tag")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if room.photoCount > 0 {
                                Label("\(room.photoCount)", systemImage: "photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Key objects

    private var keyObjectsSection: some View {
        engineerSection(title: "Key objects", symbol: "tag.fill") {
            ForEach(summary.keyObjects, id: \.displayLabel) { obj in
                engineerRow {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(obj.displayLabel)
                                .font(.body)
                            Spacer()
                            Text(obj.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let rn = obj.roomName {
                            Text(rn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !obj.notes.isEmpty {
                            Text(obj.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: Proposed emitters

    private var proposedEmittersSection: some View {
        engineerSection(title: "Proposed emitters", symbol: "thermometer.medium") {
            ForEach(summary.proposedEmitters, id: \.displayLabel) { emitter in
                engineerRow {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(emitter.displayLabel)
                                .font(.body)
                            if let rn = emitter.roomName {
                                Text(rn)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(emitter.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Generic notes section

    private func notesSection(title: String, symbol: String, lines: [String]) -> some View {
        engineerSection(title: title, symbol: symbol) {
            ForEach(lines, id: \.self) { line in
                engineerRow {
                    Text(line)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Field notes

    private var fieldNotesSection: some View {
        engineerSection(title: "Field notes summary", symbol: "mic") {
            ForEach(summary.consolidatedFieldNotes.prefix(5), id: \.self) { line in
                engineerRow {
                    Text(line)
                        .font(.body)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if summary.fieldNoteCount > 5 {
                engineerRow {
                    Text("… and \(summary.fieldNoteCount - 5) more note\(summary.fieldNoteCount - 5 == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Layout helpers

    private func engineerSection<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            VStack(spacing: 1) {
                content()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func engineerRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Completed Visit Review") {
    var session = PropertyScanSession(
        jobReference: "JOB-2025-001",
        propertyAddress: "12 Coronation Street, Manchester"
    )
    session.visitLifecycle = .complete
    session.completedAt = Date()
    session.completionMethod = .manual
    session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
    session.addRoom(ScannedRoom(jobID: session.id, name: "Living Room"))
    session.addPhoto(TaggedPhoto(filename: "p.jpg"))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .boiler))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .cylinder))
    session.addTaggedObject(TaggedObject(roomID: session.id, category: .radiator))
    session.addVoiceNote(VoiceNote(localFilename: "", caption: "Boiler appears old", kind: .observation))
    return NavigationStack {
        VisitCompletionReviewView(session: session)
    }
}

#Preview("Empty Completed Visit") {
    var session = PropertyScanSession(propertyAddress: "Empty House")
    session.visitLifecycle = .complete
    session.completedAt = Date()
    return NavigationStack {
        VisitCompletionReviewView(session: session)
    }
}
#endif
