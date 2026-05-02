import SwiftUI

// MARK: - VisitCompleteView
//
// Shown when the engineer marks a visit as complete.
//
// Handoff options (export, ScanToMind, etc.) are reserved for later PRs.
// This screen provides a clear completion state and a route back to home.

struct VisitCompleteView: View {

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

                    Text("All required evidence has been captured.\nYou can return home or export the data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    Button {
                        onDone()
                    } label: {
                        Label("Return to Home", systemImage: "house")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Text("Export and handoff options will be available in a future release.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
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
    VisitCompleteView(onDone: {})
}
#endif
