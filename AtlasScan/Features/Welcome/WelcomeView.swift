import SwiftUI

// MARK: - WelcomeView
//
// Atlas landing screen.
//
// The engineer chooses between:
//   • Scan  — the native capture flow (RoomPlan + AR + voice)
//   • Mind  — the Atlas Recommendations PWA (WKWebView)
//
// Design intent: "Choose your tool before you begin."

enum AtlasMode {
    case scan
    case mind
}

struct WelcomeView: View {

    let onSelect: (AtlasMode) -> Void

    var body: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Header
                VStack(spacing: 8) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(.tint)
                        .padding(.top, 60)

                    Text("Atlas")
                        .font(.system(size: 48, weight: .bold, design: .rounded))

                    Text("Choose how you'd like to work today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 48)

                // MARK: Mode tiles
                VStack(spacing: 20) {
                    ModeCard(
                        title: "Scan",
                        subtitle: "Capture rooms, objects & voice notes on site.",
                        symbolName: "camera.viewfinder",
                        accentColor: .blue
                    ) { onSelect(.scan) }

                    ModeCard(
                        title: "Mind",
                        subtitle: "View recommendations, reports & visit history.",
                        symbolName: "brain.head.profile",
                        accentColor: .purple
                    ) { onSelect(.mind) }
                }
                .padding(.horizontal, 24)

                Spacer()

                // MARK: Version tag
                Text("Atlas Scan")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - ModeCard

private struct ModeCard: View {

    let title: String
    let subtitle: String
    let symbolName: String
    let accentColor: Color
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: symbolName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(accentColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeIn(duration: 0.05)) { isPressed = true } }
                .onEnded   { _ in withAnimation(.easeOut(duration: 0.15)) { isPressed = false } }
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    WelcomeView { _ in }
}
#endif
