/// CaptureReticleView — Centred AR reticle drawn over the camera feed.
/// Shows a small target indicator that hints at where a tap-to-tag raycast
/// will land. Reusable across `ContinuousSurveyView` and `TagObjectSheet`.

import SwiftUI

public struct CaptureReticleView: View {
    public let isActive: Bool

    public init(isActive: Bool = true) {
        self.isActive = isActive
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(isActive ? 0.9 : 0.4), lineWidth: 1.5)
                .frame(width: 28, height: 28)
            Circle()
                .fill(Color.white.opacity(isActive ? 0.9 : 0.4))
                .frame(width: 4, height: 4)
        }
        .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 0)
        .accessibilityHidden(true)
    }
}
