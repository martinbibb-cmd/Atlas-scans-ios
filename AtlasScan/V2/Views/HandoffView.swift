/// HandoffView — Presents the visit-readiness summary and hands off to Atlas Mind.

import SwiftUI
import AtlasScanCore

struct HandoffView: View {
    @ObservedObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var isTransmitting = false
    @State private var transmitError: String?

    private var readiness: VisitReadinessV1 {
        VisitReadinessV1.derive(from: coordinator.session)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Readiness checks") {
                    ReadinessRow(label: "Rooms captured",        passed: readiness.hasRooms)
                    ReadinessRow(label: "Photos attached",       passed: readiness.hasPhotos)
                    ReadinessRow(label: "Boiler/heat-pump",      passed: readiness.hasBoilerDetails)
                    ReadinessRow(label: "Flue terminal",         passed: readiness.hasFlueDetails)
                    ReadinessRow(label: "Clearance check",       passed: readiness.hasClearanceCheck)
                    ReadinessRow(label: "Voice notes",           passed: readiness.hasTranscripts)
                    ReadinessRow(label: "Property address",      passed: readiness.hasPropertyAddress)
                }
                if let error = transmitError {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Hand Off to Mind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await sendHandoff() }
                    } label: {
                        if isTransmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(!readiness.isReady || isTransmitting)
                }
            }
        }
    }

    private func sendHandoff() async {
        isTransmitting = true
        defer { isTransmitting = false }
        do {
            let payload = try ScanToMindPayloadEncoder.encode(session: coordinator.session)
            let url = try payload.buildDeepLinkURL()
            await UIApplication.shared.open(url)
            dismiss()
        } catch {
            transmitError = error.localizedDescription
        }
    }
}

private struct ReadinessRow: View {
    let label: String
    let passed: Bool
    var body: some View {
        Label(label, systemImage: passed ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(passed ? .green : .secondary)
    }
}
