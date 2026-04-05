import SwiftUI

// MARK: - NewScanJobView
//
// Sheet to create a new ScanJob before any rooms are added.

struct NewScanJobView: View {

    let onSave: (ScanJob) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var propertyAddress = ""
    @State private var jobReference = ""
    @State private var engineerName = ""
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
                    Text("You can add rooms and service objects after creating the job.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Scan Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        var job = ScanJob(
                            jobReference: jobReference,
                            propertyAddress: propertyAddress,
                            engineerName: engineerName
                        )
                        if !atlasJobID.isEmpty {
                            job.atlasJobID = atlasJobID
                        }
                        onSave(job)
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NewScanJobView { _ in }
}
#endif
