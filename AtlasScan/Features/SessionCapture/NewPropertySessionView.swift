import SwiftUI

// MARK: - NewPropertySessionView
//
// Sheet for creating a new PropertyScanSession before any rooms are added.
// Mirrors the existing NewScanJobView pattern for consistency.

struct NewPropertySessionView: View {

    let onCreate: (PropertyScanSession) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var propertyAddress = ""
    @State private var engineerName = ""
    @State private var jobReference = ""
    @State private var atlasJobID = ""

    private var isValid: Bool {
        !propertyAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Property") {
                    TextField("Address *", text: $propertyAddress, axis: .vertical)
                        .lineLimit(2...4)
                        .autocorrectionDisabled()
                }

                Section("Job Details") {
                    TextField("Job reference (optional)", text: $jobReference)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)

                    TextField("Engineer name (optional)", text: $engineerName)
                        .autocorrectionDisabled()

                    TextField("Atlas Job ID (optional)", text: $atlasJobID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section {
                    Text("You can scan rooms and tag objects after creating the session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createSession() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func createSession() {
        let session = PropertyScanSession(
            jobReference: jobReference.trimmingCharacters(in: .whitespaces),
            propertyAddress: propertyAddress.trimmingCharacters(in: .whitespaces),
            engineerName: engineerName.trimmingCharacters(in: .whitespaces),
            atlasJobID: atlasJobID.trimmingCharacters(in: .whitespaces).nilIfEmpty
        )
        onCreate(session)
        dismiss()
    }
}

// MARK: - String helper

private extension String {
    /// Returns `nil` when the string is empty, otherwise `self`.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NewPropertySessionView { _ in }
}
#endif
