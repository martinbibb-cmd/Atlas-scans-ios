import SwiftUI

struct LoginView: View {
    let isLoading: Bool
    let errorMessage: String?
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text("Sign in to Atlas Scan")
                .font(.title3.weight(.semibold))
            Text("Sign in with your Atlas account so Scan and Mind share the same engineer identity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button(action: onSignIn) {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                    }
                    Text("Continue")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
            .padding(.horizontal)

            Spacer()
        }
        .navigationTitle("Login")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LoginView(isLoading: false, errorMessage: nil) {}
    }
}
#endif
