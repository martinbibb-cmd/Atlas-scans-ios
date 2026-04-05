import SwiftUI

// MARK: - LinkRoomsSheet
//
// Modal form for manually adding a room-to-room adjacency link.
// The engineer selects the two rooms, optionally picks the specific opening
// that creates the connection, chooses the link kind, and marks it as confirmed.

struct LinkRoomsSheet: View {

    @Binding var job: ScanJob
    let onAdd: (RoomAdjacency) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var fromRoomID: UUID?
    @State private var toRoomID: UUID?
    @State private var selectedOpeningID: UUID?
    @State private var kind: AdjacencyKind = .door
    @State private var isConfirmed: Bool = true
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                roomPickersSection
                openingSection
                kindSection
                confirmationSection
                notesSection
            }
            .navigationTitle("Link Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Link") { addLink() }
                        .disabled(!canAdd)
                }
            }
        }
    }

    // MARK: - Sections

    private var roomPickersSection: some View {
        Section {
            Picker("From Room", selection: $fromRoomID) {
                Text("Select room…").tag(Optional<UUID>.none)
                ForEach(job.rooms) { room in
                    Text(room.name).tag(Optional<UUID>.some(room.id))
                }
            }
            .onChange(of: fromRoomID) { _, _ in
                // Clear the to-room if it now equals the from-room.
                if fromRoomID == toRoomID { toRoomID = nil }
                // Clear the selected opening since it belongs to a specific room.
                selectedOpeningID = nil
            }

            Picker("To Room", selection: $toRoomID) {
                Text("Select room…").tag(Optional<UUID>.none)
                ForEach(availableToRooms) { room in
                    Text(room.name).tag(Optional<UUID>.some(room.id))
                }
            }
        } header: {
            Text("Rooms")
        } footer: {
            if duplicateExists {
                Text("A link between these rooms already exists.")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var openingSection: some View {
        if let fromID = fromRoomID,
           let fromRoom = job.rooms.first(where: { $0.id == fromID }),
           !fromRoom.openings.isEmpty {
            Section {
                Picker("Via Opening", selection: $selectedOpeningID) {
                    Text("Not specified").tag(Optional<UUID>.none)
                    ForEach(fromRoom.openings) { opening in
                        Text(openingLabel(opening, in: fromRoom))
                            .tag(Optional<UUID>.some(opening.id))
                    }
                }
            } header: {
                Text("Opening (Optional)")
            } footer: {
                Text("Choose the door or opening in the from-room that leads to the other room.")
                    .font(.caption)
            }
        }
    }

    private var kindSection: some View {
        Section("Connection Type") {
            Picker("Kind", selection: $kind) {
                ForEach(AdjacencyKind.allCases, id: \.self) { k in
                    Label(k.displayName, systemImage: k.symbolName).tag(k)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var confirmationSection: some View {
        Section {
            Toggle("Mark as Confirmed", isOn: $isConfirmed)
        } footer: {
            Text(
                isConfirmed
                    ? "Confirmed links are shown as solid lines in the property plan overview."
                    : "Tentative links are shown as dashed lines until confirmed."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var notesSection: some View {
        Section("Notes (Optional)") {
            TextField("Add a note…", text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    // MARK: - Helpers

    private var canAdd: Bool {
        guard let fromID = fromRoomID, let toID = toRoomID else { return false }
        return fromID != toID && !duplicateExists
    }

    private var duplicateExists: Bool {
        guard let fromID = fromRoomID, let toID = toRoomID else { return false }
        return job.roomAdjacencies.contains { $0.connects(fromID, to: toID) }
    }

    private var availableToRooms: [ScannedRoom] {
        guard let fromID = fromRoomID else { return job.rooms }
        return job.rooms.filter { $0.id != fromID }
    }

    private func openingLabel(_ opening: ScannedOpening, in room: ScannedRoom) -> String {
        let wallNum = opening.wallIndex + 1
        return "\(opening.kind.displayName) on Wall \(wallNum)"
    }

    private func addLink() {
        guard let fromID = fromRoomID, let toID = toRoomID else { return }
        let adjacency = RoomAdjacency(
            fromRoomID: fromID,
            toRoomID: toID,
            openingID: selectedOpeningID,
            kind: kind,
            isConfirmed: isConfirmed,
            notes: notes
        )
        onAdd(adjacency)
        dismiss()
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    LinkRoomsSheet(job: .constant(MockData.sampleJob)) { _ in }
}
#endif
