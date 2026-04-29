import SwiftUI

// MARK: - AtlasHandoffView
//
// Invisible handoff: submits the canonical AtlasPropertyV1 payload directly
// to the Atlas Mind database as soon as the view appears.  No JSON is ever
// shown to the engineer.
//
// States:
//   .submitting  — upload in progress; shows a spinner
//   .success     — payload accepted by Atlas Mind; auto-dismisses after a beat
//   .failed      — upload failed; shows the error with a retry option

struct AtlasHandoffView: View {

    let session: PropertyScanSession
    var onHandoffComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var state: HandoffState = .submitting

    private enum HandoffState {
        case submitting
        case success(visitId: String)
        case failed(message: String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                stateContent
                Spacer()
            }
            .padding()
            .navigationTitle("Atlas Mind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .failed = state {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task { await submit() }
        }
    }

    // MARK: - State content

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .submitting:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Sending to Atlas Mind…")
                    .font(.headline)
                Text("The session data is being submitted directly to the Atlas database.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .success:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Sent to Atlas Mind")
                    .font(.title2.bold())
                Text("The session has been delivered to the Atlas database.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text("Submission Failed")
                    .font(.title2.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    state = .submitting
                    Task { await submit() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Submit

    private func submit() async {
        state = .submitting
        do {
            let response = try await AtlasMindClient.submitHandoff(session: session)
            state = .success(visitId: response.propertyId)
            onHandoffComplete?()
            // Brief pause so the engineer sees the confirmation tick, then close.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Submitting") {
    AtlasHandoffView(session: MockData.sampleSession)
}

#Preview("Success") {
    // Reach the success state immediately via a local wrapper
    NavigationStack {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Sent to Atlas Mind")
                    .font(.title2.bold())
                Text("The session has been delivered to the Atlas database.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Atlas Mind")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Failed") {
    NavigationStack {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text("Submission Failed")
                    .font(.title2.bold())
                Text("No Atlas auth token stored. Sign in from Settings to enable sync.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {} label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Atlas Mind")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {}
            }
        }
    }
}
#endif
