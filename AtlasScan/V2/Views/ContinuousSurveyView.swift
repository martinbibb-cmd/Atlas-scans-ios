/// ContinuousSurveyView — Single, camera-first capture surface that replaces
/// the old room-wizard flow. The user remains in this view while walking the
/// property; room breaks come through suggestion sheets, never automatic
/// creations.
///
/// Layout:
///   ┌─────────────────────────────────────────┐
///   │ CaptureStatusBar (top)                  │
///   ├─────────────────────────────────────────┤
///   │                                         │
///   │ Camera feed (V2RoomPlanCaptureView)     │
///   │       + CaptureReticleView (centre)     │
///   │       + DEBUG-only ghost overlay        │
///   │                                         │
///   ├─────────────────────────────────────────┤
///   │ CaptureBottomBar (bottom)               │
///   └─────────────────────────────────────────┘
///
/// The ghost overlay (`V2GhostAROverlayView`) is wrapped in `#if DEBUG` so
/// it never appears in production builds (PR-6 cutover).
///
/// Camera-unavailable case shows an explicit error state with a `Back to
/// Visit` button — never a black screen.

import SwiftUI

public struct ContinuousSurveyView: View {

    @ObservedObject public var viewModel: ContinuousSurveyViewModel

    public let onPhoto: () -> Void
    public let onTag: () -> Void
    public let onNote: () -> Void
    public let onMeasure: () -> Void
    public let onRoom: () -> Void
    public let onFinish: () -> Void
    public let onBackToVisit: () -> Void
    public let onSaveAndExit: () -> Void

    public init(
        viewModel: ContinuousSurveyViewModel,
        onPhoto: @escaping () -> Void,
        onTag: @escaping () -> Void,
        onNote: @escaping () -> Void,
        onMeasure: @escaping () -> Void,
        onRoom: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onBackToVisit: @escaping () -> Void,
        onSaveAndExit: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onPhoto = onPhoto
        self.onTag = onTag
        self.onNote = onNote
        self.onMeasure = onMeasure
        self.onRoom = onRoom
        self.onFinish = onFinish
        self.onBackToVisit = onBackToVisit
        self.onSaveAndExit = onSaveAndExit
    }

    public var body: some View {
        VStack(spacing: 0) {
            CaptureStatusBar(
                roomLabel: viewModel.currentRoomLabel,
                onBackToVisit: onBackToVisit,
                onSaveAndExit: onSaveAndExit
            )

            ZStack {
                if viewModel.cameraUnavailable {
                    cameraUnavailableState
                } else {
                    cameraCanvas
                    CaptureReticleView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CaptureBottomBar(
                onPhoto: onPhoto,
                onTag: onTag,
                onNote: onNote,
                onMeasure: onMeasure,
                onRoom: onRoom,
                onFinish: onFinish
            )
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Camera

    /// Camera canvas placeholder. The production wiring uses the existing
    /// `V2RoomPlanCaptureView` (in `AtlasScan/V2/AR/`) — the parent injects
    /// it via `cameraCanvasOverride` in a future revision so this view
    /// stays free of AR imports while the shell is still being shaped.
    private var cameraCanvas: some View {
        Color.black
            // PR-6: ghost overlay is DEBUG-only on the production camera path.
            .overlay(alignment: .topTrailing) {
                #if DEBUG
                Text("DEBUG: ghost overlay slot")
                    .font(.caption2)
                    .padding(4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
                #endif
            }
    }

    private var cameraUnavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
            Text("Camera unavailable")
                .font(.headline)
                .foregroundStyle(.white)
            if let last = viewModel.lastError, !last.isEmpty {
                Text(last)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Button("Back to Visit", action: onBackToVisit)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85).ignoresSafeArea())
    }
}
