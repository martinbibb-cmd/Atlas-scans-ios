import SwiftUI

// MARK: - StartVisitView
//
// Sheet presented when the engineer taps "Start Local Capture Visit".
//
// Collects:
//   • Visit reference / number (required)
//   • Property address (optional)
//   • Brand / client ID (optional, shown under Advanced)
//
// On confirm:
//   • Creates a visit via AtlasScanVisitStore (status = capturing).
//   • Also creates the linked CaptureSessionDraft.
//   • Calls onStart() to dismiss and navigate to VisitHomeView.

struct StartVisitView: View {

    let onStart: () -> Void

    @EnvironmentObject private var visitStore: AtlasScanVisitStore
    @Environment(\.dismiss) private var dismiss

    @State private var visitNumber    = ""
    @State private var propertyAddress = ""
    @State private var brandId        = ""
    @State private var showAdvanced   = false
    @FocusState private var numberFocused: Bool

    private var canStart: Bool {
        !visitNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. JOB-2025-001", text: $visitNumber)
                        .focused($numberFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Visit Number")
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

                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        TextField("Brand / client ID", text: $brandId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } footer: {
                    Text("Brand or client identifier — not required for most visits.")
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
            .onAppear { numberFocused = true }
        }
    }

    // MARK: - Actions

    private func startVisit() {
        let ref     = visitNumber.trimmingCharacters(in: .whitespaces)
        let address = propertyAddress.trimmingCharacters(in: .whitespaces)
        let brand   = brandId.trimmingCharacters(in: .whitespaces)

        // Create the visit lifecycle via the store (also creates CaptureSessionDraft).
        var visit = visitStore.createVisit(
            visitNumber: ref.isEmpty ? nil : ref,
            brandId: brand.isEmpty ? nil : brand
        )

        // Backfill the property address into the linked capture session draft.
        if !address.isEmpty,
           let sessionId = visit.captureSessionId,
           var draft = CaptureSessionPersistence.shared.load(id: sessionId) {
            draft.propertyAddress = address
            CaptureSessionPersistence.shared.save(draft)
        }

        onStart()
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = AtlasScanVisitStore.makeTestInstance()
    StartVisitView(onStart: {})
        .environmentObject(store)
}
#endif

