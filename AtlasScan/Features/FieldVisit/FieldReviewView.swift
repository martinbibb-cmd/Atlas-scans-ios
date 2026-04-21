import SwiftUI
import AtlasContracts

// MARK: - FieldReviewView

/// Review tab for the field visit shell.
///
/// The most important surface in this PR.
///
/// Shows:
///   - Visit status from the contract lifecycle
///   - Readiness flags from `deriveVisitReadinessFromFieldSurvey`
///   - Planning coverage from `derivePlanningReadiness`
///   - All missing items, clearly labelled
///
/// This view computes readiness from the live session state every time it
/// appears.  No separate readiness snapshot is stored; derivation is pure
/// and crash-safe for partially-populated sessions.
struct FieldReviewView: View {

    @ObservedObject var store: FieldVisitStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusSection
                visitReadinessSection
                planningReadinessSection
                if !store.session.rooms.isEmpty {
                    roomCoverageSection
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Visit status

    private var statusSection: some View {
        let status = store.lifecycleBadgeStatus
        return HStack(spacing: 12) {
            Image(systemName: status.symbolName)
                .font(.title3)
                .foregroundStyle(lifecycleColor(status))
            VStack(alignment: .leading, spacing: 2) {
                Text("Visit Status")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(status.displayName)
                    .font(.headline)
                    .foregroundStyle(lifecycleColor(status))
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Visit readiness

    private var visitReadinessSection: some View {
        let readiness = store.visitReadiness
        return VStack(spacing: 0) {
            SectionHeader(title: "Survey Readiness")
                .padding(.bottom, 8)

            VStack(spacing: 1) {
                ReadinessRow(label: "Rooms",           passed: readiness.hasRooms,          symbol: "square.split.2x1")
                ReadinessRow(label: "Photos",          passed: readiness.hasPhotos,          symbol: "camera")
                ReadinessRow(label: "Heating System",  passed: readiness.hasHeatingSystem,   symbol: "flame")
                ReadinessRow(label: "Hot Water System",passed: readiness.hasHotWaterSystem,  symbol: "drop.fill")
                ReadinessRow(label: "Boiler",          passed: readiness.hasBoiler,          symbol: "flame.fill")
                ReadinessRow(label: "Flue",            passed: readiness.hasFlue,            symbol: "arrow.up.to.line")
                ReadinessRow(label: "Notes",           passed: readiness.hasNotes,           symbol: "mic")
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !readiness.isReady {
                missingItemsBanner(items: readiness.missingItems)
                    .padding(.top, 8)
            }
        }
    }

    private func missingItemsBanner(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Missing Required Items", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Planning readiness

    private var planningReadinessSection: some View {
        let planning = store.planningReadiness
        return VStack(spacing: 0) {
            SectionHeader(title: "Planning Coverage")
                .padding(.bottom, 8)

            VStack(spacing: 1) {
                PlanningCountRow(
                    label: "Proposed Emitters",
                    count: planning.proposedEmittersCount,
                    symbol: "thermometer.medium"
                )
                PlanningCountRow(
                    label: "Routes",
                    count: planning.routesCount,
                    symbol: "line.diagonal"
                )
                PlanningCountRow(
                    label: "Access Notes",
                    count: planning.accessNotesCount,
                    symbol: "door.left.hand.open"
                )
                PlanningCountRow(
                    label: "Room Plans",
                    count: planning.roomPlansCount,
                    symbol: "rectangle.portrait"
                )
                PlanningCountRow(
                    label: "Spec Notes",
                    count: planning.specNotesCount,
                    symbol: "list.bullet.clipboard"
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Room coverage

    private let emitterCategoryRawValues: Set<String> = [
        "radiator", "radiator_drop", "towel_rail", "ufh_zone", "fan_convector"
    ]

    private var roomCoverageSection: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Room Coverage")
                .padding(.bottom, 8)

            VStack(spacing: 1) {
                ForEach(store.session.rooms) { room in
                    RoomCoverageRow(
                        room: room,
                        keyObjectCount: roomKeyObjectCount(room),
                        proposedEmitterCount: roomProposedEmitterCount(room),
                        accessNoteCount: roomAccessNoteCount(room),
                        planNoteCount: roomPlanNoteCount(room)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func roomKeyObjectCount(_ room: ScannedRoom) -> Int {
        store.session.taggedObjects.filter { $0.roomID == room.id }.count
        + room.taggedObjects.count
    }

    private func roomProposedEmitterCount(_ room: ScannedRoom) -> Int {
        store.session.installMarkupObjects.filter {
            $0.layer == .proposed
            && emitterCategoryRawValues.contains($0.categoryRawValue)
            && $0.roomID == room.id
        }.count
    }

    private func roomAccessNoteCount(_ room: ScannedRoom) -> Int {
        store.session.planningAnnotations.filter {
            $0.kind == .accessNote && $0.roomID == room.id
        }.count
    }

    private func roomPlanNoteCount(_ room: ScannedRoom) -> Int {
        store.session.planningAnnotations.filter {
            $0.kind == .roomPlanNote && $0.roomID == room.id
        }.count
    }

    // MARK: - Color helper

    private func lifecycleColor(_ status: VisitLifecycleStatus) -> Color {
        switch status {
        case .draft:           return .gray
        case .capturing:       return .orange
        case .planning:        return .blue
        case .readyToComplete: return .green
        case .complete:        return .green
        }
    }
}

// MARK: - ReadinessRow

private struct ReadinessRow: View {
    let label: String
    let passed: Bool
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .font(.body)
            Spacer()
            if passed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

// MARK: - PlanningCountRow

private struct PlanningCountRow: View {
    let label: String
    let count: Int
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .font(.body)
            Spacer()
            Text("\(count)")
                .font(.body.monospacedDigit())
                .foregroundStyle(count > 0 ? .primary : .tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

// MARK: - RoomCoverageRow

/// A row in the room coverage section showing photo/note/object/planning presence
/// for a single room.
private struct RoomCoverageRow: View {
    let room: ScannedRoom
    let keyObjectCount: Int
    let proposedEmitterCount: Int
    let accessNoteCount: Int
    let planNoteCount: Int

    private var hasPhotos: Bool   { !room.photos.isEmpty }
    private var hasNotes: Bool    { !room.voiceNotes.isEmpty || !room.notes.isEmpty }
    private var hasObjects: Bool  { keyObjectCount > 0 }
    private var hasPlanning: Bool { proposedEmitterCount > 0 || accessNoteCount > 0 || planNoteCount > 0 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.split.2x1")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(room.name)
                .font(.body)
            Spacer()
            HStack(spacing: 8) {
                coverageIndicator(symbol: "camera",           present: hasPhotos)
                coverageIndicator(symbol: "mic",              present: hasNotes)
                coverageIndicator(symbol: "tag",              present: hasObjects)
                coverageIndicator(symbol: "pencil.and.ruler", present: hasPlanning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func coverageIndicator(symbol: String, present: Bool) -> some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(present ? Color.green : Color.secondary.opacity(0.3))
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    var session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldReviewView(store: visitStore)
}
#endif
