import SwiftUI
import AVFoundation
import ARKit

// MARK: - ARCameraFeedView
//
// UIViewRepresentable that exposes the ARSCNView from an ARPlacementSession as a
// full-screen camera preview.  Used when ARWorldTracking is available so that the
// same ARSession that handles raycasting also drives the camera feed — preventing
// two sessions from competing for the camera hardware.
//
// The view itself adds no SceneKit content; it is purely a pass-through preview.

struct ARCameraFeedView: UIViewRepresentable {

    let session: ARPlacementSession

    func makeUIView(context: Context) -> UIView { session.arView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - CameraFeedView
//
// Thin UIViewRepresentable wrapper around an AVFoundation camera preview layer.
//
// On a real device the rear wide-angle camera feed is shown.
// On the simulator (no camera hardware) a dark grey placeholder is displayed instead.
// The view does not capture photos itself — it is purely a preview surface.
// Photo capture is handled via the existing AddPhotoSheet / ImagePickerView flow.
//
// Note: Used as the fallback camera background when ARPlacementSession.isSupported
// returns false (e.g. Simulator, devices without A9 chip).

struct CameraFeedView: UIViewRepresentable {

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView()
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

// MARK: - CameraPreviewUIView

final class CameraPreviewUIView: UIView {

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: Setup

    private func setup() {
        backgroundColor = .black

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input  = try? AVCaptureDeviceInput(device: device)
        else {
            // Simulator or device without rear camera — show a placeholder label.
            addPlaceholderLabel()
            return
        }

        captureSession.sessionPreset = .high
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        previewLayer = layer

        // Start running on a background thread — UIKit layout callbacks are on main.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    private func addPlaceholderLabel() {
        let label = UILabel()
        label.text = "Camera preview unavailable"
        label.textColor = UIColor.white.withAlphaComponent(0.45)
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
