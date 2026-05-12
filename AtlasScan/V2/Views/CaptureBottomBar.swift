/// CaptureBottomBar — Bottom action bar shown over the camera feed in
/// `ContinuousSurveyView`. Six actions per the brief:
///
///   Photo · Tag · Note · Measure · Room · Finish
///
/// The `Room` button opens the room-suggestion / picker sheet; `Finish`
/// is *always* enabled — incomplete drafts are valid handoffs.

import SwiftUI

public struct CaptureBottomBar: View {
    public let onPhoto: () -> Void
    public let onTag: () -> Void
    public let onNote: () -> Void
    public let onMeasure: () -> Void
    public let onRoom: () -> Void
    public let onFinish: () -> Void

    public init(
        onPhoto: @escaping () -> Void,
        onTag: @escaping () -> Void,
        onNote: @escaping () -> Void,
        onMeasure: @escaping () -> Void,
        onRoom: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.onPhoto = onPhoto
        self.onTag = onTag
        self.onNote = onNote
        self.onMeasure = onMeasure
        self.onRoom = onRoom
        self.onFinish = onFinish
    }

    public var body: some View {
        HStack(spacing: 0) {
            actionButton("Photo", system: "camera.fill", action: onPhoto)
            actionButton("Tag", system: "mappin.circle.fill", action: onTag)
            actionButton("Note", system: "mic.fill", action: onNote)
            actionButton("Measure", system: "ruler.fill", action: onMeasure)
            actionButton("Room", system: "square.split.bottomrightquarter.fill", action: onRoom)
            actionButton("Finish", system: "checkmark.seal.fill", action: onFinish, prominent: true)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func actionButton(
        _ title: String,
        system: String,
        action: @escaping () -> Void,
        prominent: Bool = false
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: system)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(prominent ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
