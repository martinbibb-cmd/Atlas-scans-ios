import SwiftUI
import AtlasContracts

// MARK: - VisitCompleteView
//
// Shown when the engineer marks a visit as complete.
//
// Primary action:
//   Continue in Atlas Mind — encodes the ScanToMindHandoffV1 and opens
//   the Mind PWA at /receive-scan with the visit preloaded.
//
// Secondary action:
//   Return to Home — clears the active visit and returns to the app home screen.
//
// Developer-only:
//   No JSON inspector or raw payload screen is shown in the normal flow.

struct VisitCompleteView: View {

    /// Pre-built handoff to deliver to Atlas Mind.
    ///
    /// Nil when the handoff could not be assembled (e.g. session ID mismatch);
    /// the "Continue in Atlas Mind" button is hidden in that case.
    let handoff: ScanToMindHandoffV1?

    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Completion graphic
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 80, weight: .thin))
                        .foregroundStyle(.green)

                    Text("Visit Complete")
                        .font(.largeTitle.bold())

                    Text("All required evidence has been captured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    if let handoff {
                        Button {
                            OpenAtlasMind.openMind(with: handoff)
                            onDone()
                        } label: {
                            Label("Continue in Atlas Mind", systemImage: "brain.head.profile")
                                .font(.body.bold())
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onDone()
                    } label: {
                        Label("Return to Home", systemImage: "house")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle("Complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VisitCompleteView(handoff: nil, onDone: {})
}
#endif
