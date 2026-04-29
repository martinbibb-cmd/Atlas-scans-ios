import SwiftUI

// MARK: - StartVisitView
//
// Sheet presented when the engineer taps "Start Local Capture Visit".
//
// Collects:
//   • Visit reference (required — used as identifier and in export)
//   • Property address (optional)
//
// On confirm, creates a persisted CaptureSessionDraft and calls onStart.

struct StartVisitView: View {

    let onStart: (CaptureSessionDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var visitReference = ""
    @State private var propertyAddress = ""
    @FocusState private var referenceFocused: Bool

    private var canStart: Bool {
        !visitReference.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. JOB-2025-001", text: $visitReference)
                        .focused($referenceFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Visit Reference")
                } footer: {
                    Text("Required. Used to identify this visit in exports.")
                }

                Section {
                    TextField("e.g. 12 Oak Street, London", text: $propertyAddress)
                        .autocorrectionDisabled()
                } header: {
                    Text("Property Address")
                } footer: {
                    Text("Optional.")
                }
            }
            .navigationTitle("New Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Visit") { startVisit() }
                        .disabled(!canStart)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { referenceFocused = true }
        }
    }

    // MARK: - Actions

    private func startVisit() {
        var draft = CaptureSessionStore.newSession(
            visitReference: visitReference.trimmingCharacters(in: .whitespaces)
        )
        draft.propertyAddress = propertyAddress.trimmingCharacters(in: .whitespaces)
        CaptureSessionPersistence.shared.save(draft)
        onStart(draft)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    StartVisitView { _ in }
}
#endif
