/// RoomSuggestionSheet — Bottom-sheet UI shown when
/// `RoomSegmentationService` surfaces a `RoomCandidateV1`. Four actions:
///
///   - Confirm — promote the candidate to a real `RoomCaptureV2`
///   - Rename  — confirm with a user-edited name
///   - Merge   — fold this candidate into an existing room
///   - Ignore  — dismiss the suggestion without creating anything
///
/// The brief is explicit: rooms are never created automatically. This sheet
/// is the only path that calls `RoomSegmentationService.confirm`.

import SwiftUI
import AtlasScanCore

public struct RoomSuggestionSheet: View {

    public let candidate: RoomCandidateV1
    public let mergeableRooms: [RoomCaptureV2]

    public let onConfirm: (String) -> Void   // name (possibly the suggested one)
    public let onMerge: (UUID) -> Void       // target roomId
    public let onIgnore: () -> Void

    @State private var editedName: String

    public init(
        candidate: RoomCandidateV1,
        mergeableRooms: [RoomCaptureV2],
        onConfirm: @escaping (String) -> Void,
        onMerge: @escaping (UUID) -> Void,
        onIgnore: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.mergeableRooms = mergeableRooms
        self.onConfirm = onConfirm
        self.onMerge = onMerge
        self.onIgnore = onIgnore
        _editedName = State(initialValue: candidate.suggestedName ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Suggested room") {
                    TextField("Room name", text: $editedName)
                        .textInputAutocapitalization(.words)
                    Text("Source: \(candidate.source.rawValue.capitalized)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        onConfirm(name)
                    } label: {
                        Label("Confirm as new room", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !mergeableRooms.isEmpty {
                    Section("Merge into existing room") {
                        ForEach(mergeableRooms, id: \.id) { room in
                            Button {
                                onMerge(room.id)
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.triangle.merge")
                                    Text(room.displayName.isEmpty ? "Untitled room" : room.displayName)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(role: .cancel, action: onIgnore) {
                        Label("Ignore suggestion", systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle("New room?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
