import SwiftUI

// MARK: - StartJobView
//
// Entry point for the capture-only visit workflow.
//
// The engineer enters a visit/job reference and taps Start.
// This creates a new CaptureSessionDraft and navigates to CaptureHubView.
//
// "One visit, one session, one home screen."

struct StartJobView: View {

    let onStart: (CaptureSessionDraft) -> Void

    @State private var visitReference = ""

    private var isValid: Bool {
        !visitReference.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            headerSection
            Spacer()
            inputSection
            Spacer()
            startButton
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.tint)

            Text("Start Job")
                .font(.largeTitle.bold())

            Text("Enter the visit reference to begin capturing.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visit Reference")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            TextField("e.g. JOB-2025-0001", text: $visitReference)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.title3)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .onSubmit {
                    if isValid { startJob() }
                }
        }
    }

    // MARK: - Start button

    private var startButton: some View {
        Button(action: startJob) {
            HStack {
                Image(systemName: "play.fill")
                Text("Start Capture")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isValid ? Color.accentColor : Color.secondary.opacity(0.3))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isValid)
    }

    // MARK: - Actions

    private func startJob() {
        guard isValid else { return }
        let draft = CaptureSessionStore.newSession(
            visitReference: visitReference.trimmingCharacters(in: .whitespaces)
        )
        onStart(draft)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    StartJobView { _ in }
}
#endif
