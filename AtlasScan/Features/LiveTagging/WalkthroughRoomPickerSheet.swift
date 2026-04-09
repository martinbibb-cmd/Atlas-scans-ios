import SwiftUI

// MARK: - WalkthroughRoomPickerSheet
//
// Lightweight sheet presented from the Walkthrough action bar when the engineer
// taps "Assign Room".  Lets them select an existing room from the session or
// clear the current assignment.
//
// The sheet is intentionally minimal — the full room-scan flow is still available
// from the Session Home via "Add / Scan Room".  The walkthrough only needs a quick
// room pick so new objects and photos inherit the correct context.

struct WalkthroughRoomPickerSheet: View {

    let rooms: [ScannedRoom]

    /// Currently active room (highlighted in the list).
    let selectedRoomID: UUID?

    /// Called when the engineer picks a room (nil = clear assignment).
    let onSelect: (ScannedRoom?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = rooms.first(where: { $0.id == selectedRoomID }) {
                    Section {
                        HStack {
                            Label(current.name, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                            Spacer()
                            Text("Current")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Active Room")
                    }
                }

                Section {
                    ForEach(rooms) { room in
                        Button {
                            onSelect(room)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(room.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(room.displayFloor)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if room.id == selectedRoomID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("All Rooms")
                } footer: {
                    Text("Objects and photos captured after assignment will be linked to the selected room.")
                        .font(.caption2)
                }

                if selectedRoomID != nil {
                    Section {
                        Button(role: .destructive) {
                            onSelect(nil)
                        } label: {
                            Label("Clear Room Assignment", systemImage: "xmark.circle")
                        }
                    }
                }

                if rooms.isEmpty {
                    ContentUnavailableView(
                        "No Rooms Yet",
                        systemImage: "square.split.2x1",
                        description: Text("Return to the session and add a room before assigning one here.")
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Assign Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    WalkthroughRoomPickerSheet(
        rooms: [
            ScannedRoom(jobID: UUID(), name: "Lounge", floor: 0),
            ScannedRoom(jobID: UUID(), name: "Kitchen", floor: 0),
            ScannedRoom(jobID: UUID(), name: "Bedroom 1", floor: 1)
        ],
        selectedRoomID: nil
    ) { _ in }
}
#endif
