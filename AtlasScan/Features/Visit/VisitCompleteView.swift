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
// Handoff diagnostics:
//   All users see a success / error indicator for URL formation.
//   Developer Mode additionally shows the encoded payload length (characters).

struct VisitCompleteView: View {

    /// Pre-built handoff to deliver to Atlas Mind.
    ///
    /// Nil when the handoff could not be assembled (e.g. session ID mismatch);
    /// the "Continue in Atlas Mind" button is hidden in that case.
    let handoff: ScanToMindHandoffV1?

    let onDone: () -> Void

    @StateObject private var developerMode = DeveloperModeStore.shared

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

                // Handoff diagnostics
                handoffDiagnosticsView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

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

    // MARK: - Handoff diagnostics

    @ViewBuilder
    private var handoffDiagnosticsView: some View {
        if let handoff {
            VStack(alignment: .leading, spacing: 6) {
                // URL formation success — visible to all testers
                Label("Atlas Mind URL: Ready", systemImage: "link.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                // Encoded payload length — developer only
                if developerMode.isEnabled,
                   let encodedPayload = try? ScanToMindPayloadEncoder.encodeForURL(handoff) {
                    Text("Payload: \(encodedPayload.count) chars")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            // URL formation failed — visible to all testers
            Label("Atlas Mind URL: Not available", systemImage: "link.circle")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VisitCompleteView(handoff: nil, onDone: {})
}
#endif
