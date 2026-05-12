/// CaptureStatusBar — Top status bar shown above `ContinuousSurveyView`.
///
/// Three slots: Back to Visit · current room chip · Save & Exit.
/// Deliberately *no* debug walls of text — debug overlays live behind a
/// dedicated DEBUG-only toggle in `SurveyHomeView`.

import SwiftUI

public struct CaptureStatusBar: View {
    public let roomLabel: String?
    public let onBackToVisit: () -> Void
    public let onSaveAndExit: () -> Void

    public init(
        roomLabel: String?,
        onBackToVisit: @escaping () -> Void,
        onSaveAndExit: @escaping () -> Void
    ) {
        self.roomLabel = roomLabel
        self.onBackToVisit = onBackToVisit
        self.onSaveAndExit = onSaveAndExit
    }

    public var body: some View {
        HStack {
            Button(action: onBackToVisit) {
                Label("Visit", systemImage: "chevron.backward")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)

            Spacer()

            if let roomLabel, !roomLabel.isEmpty {
                Text(roomLabel)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            } else {
                Text("No room")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onSaveAndExit) {
                Text("Save & Exit").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
