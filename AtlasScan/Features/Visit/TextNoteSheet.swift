import SwiftUI

// MARK: - TextNoteSheet
//
// Sheet for entering a free-text note during a capture visit.
//
// Notes are persisted as CapturedVoiceNoteDraft with the text in the
// `transcript` field. Since there is no audio recording, startedAt and
// endedAt are set to the same instant, indicating a typed (not spoken) note.

struct TextNoteSheet: View {

    @ObservedObject var store: CaptureSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var noteText = ""
    @FocusState private var textFocused: Bool

    private var canSave: Bool {
        !noteText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $noteText)
                        .focused($textFocused)
                        .frame(minHeight: 120)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Text notes are attached to this visit and included in exports.")
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNote() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { textFocused = true }
        }
    }

    // MARK: - Save

    private func saveNote() {
        let now = Date()
        var note = CapturedVoiceNoteDraft()
        note.transcript = noteText.trimmingCharacters(in: .whitespaces)
        note.startedAt = now
        note.endedAt = now
        store.addVoiceNote(note)
        dismiss()
    }
}
