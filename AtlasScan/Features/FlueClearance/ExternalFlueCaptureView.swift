import SwiftUI
import ARKit
import UIKit

// MARK: - ExternalFlueCaptureView
//
// Full-screen outdoor flue-clearance capture view.
//
// Workflow:
//   Phase 1 – Initialising: wait for AR world tracking.
//   Phase 2 – Placing Terminal: tap front face of flue terminal.
//   Phase 3 – Placing Features: tap to tag nearby windows, doors, air bricks, etc.
//   Phase 4 – Reviewing: show structured measurements and compliance summary.
//   Phase 5 – Saved: scene saved to session and view dismissed.
//
// The view produces an ExternalClearanceScene via onSceneCaptured callback
// when the engineer taps "Save to Session".

struct ExternalFlueCaptureView: View {

    let propertySessionID: UUID
    let onSceneCaptured: (ExternalClearanceScene) -> Void

    @StateObject private var session = ExternalFlueCaptureSession()
    @Environment(\.dismiss) private var dismiss
    @State private var showingFeaturePicker = false
    @State private var captureSessionID = UUID()

    var body: some View {
        ZStack {
            arBackground
            overlay
        }
        .navigationTitle("Flue Clearance Capture")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isCapturing)
        .onAppear  { session.start() }
        .onDisappear { session.pause() }
        .sheet(isPresented: $showingFeaturePicker) {
            featureKindPickerSheet
        }
    }

    private var isCapturing: Bool {
        switch session.phase {
        case .placingTerminal, .placingFeatures: return true
        default: return false
        }
    }

    // MARK: - AR background

    @ViewBuilder
    private var arBackground: some View {
        switch session.phase {
        case .unavailable:
            unavailableBackground
        case .permissionDenied:
            permissionDeniedBackground
        default:
            FlueCaptureARViewRepresentable(arView: session.arView) { point in
                session.handleTap(at: point)
            }
            .ignoresSafeArea()
        }
    }

    private var unavailableBackground: some View {
        Color.black.ignoresSafeArea()
            .overlay {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)
                    Text("AR Not Available")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("This feature requires an ARKit-capable device.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.subheadline)
                        .padding(.horizontal)
                    Button("Dismiss") { dismiss() }
                        .buttonStyle(FluePrimaryButtonStyle())
                }
            }
    }

    private var permissionDeniedBackground: some View {
        Color.black.ignoresSafeArea()
            .overlay {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)
                    Text("Camera Access Required")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Grant camera permission in Settings to use flue clearance capture.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.subheadline)
                        .padding(.horizontal)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(FluePrimaryButtonStyle())
                }
            }
    }

    // MARK: - HUD overlay

    private var overlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            switch session.phase {
            case .unavailable, .permissionDenied:
                EmptyView()
            case .initialising:
                initialisingPanel
            case .placingTerminal:
                placingTerminalPanel
            case .placingFeatures:
                placingFeaturesPanel
            case .reviewing:
                reviewPanel
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                session.pause()
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            Spacer()

            phaseLabel
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var phaseLabel: some View {
        Text(phaseTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private var phaseTitle: String {
        switch session.phase {
        case .initialising:     return "Initialising AR…"
        case .placingTerminal:  return "Step 1: Place Terminal"
        case .placingFeatures:  return "Step 2: Tag Features"
        case .reviewing:        return "Step 3: Review"
        case .unavailable:      return "Unavailable"
        case .permissionDenied: return "Permission Denied"
        }
    }

    // MARK: - Panels

    private var initialisingPanel: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Move the camera slowly to initialise AR tracking…")
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private var placingTerminalPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "smoke")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Place Flue Terminal")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("Tap the centre of the flue terminal opening")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private var placingFeaturesPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: session.pendingFeatureKind.symbolName)
                    .foregroundStyle(.white)
                    .font(.title3)
                Button {
                    showingFeaturePicker = true
                } label: {
                    Text("Tap to tag: \(session.pendingFeatureKind.displayName)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }

            if !session.nearbyFeatures.isEmpty {
                Divider()
                ForEach(session.nearbyFeatures) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: feature.kind.symbolName)
                            .frame(width: 20)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(feature.kind.displayName)
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                        if let d = feature.distanceToTerminalM {
                            Text(String(format: "%.2f m", d))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(distanceColor(d, kind: feature.kind))
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Button {
                            session.removeFeature(id: feature.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.6))
                                .font(.caption)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                if !session.nearbyFeatures.isEmpty {
                    Button("Review") {
                        session.finishPlacingFeatures()
                    }
                    .buttonStyle(FluePrimaryButtonStyle())
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private var reviewPanel: some View {
        let builtScene = session.buildScene(
            propertySessionID: propertySessionID,
            captureSessionID: captureSessionID
        )

        return VStack(alignment: .leading, spacing: 12) {
            // Compliance header
            if let comp = builtScene.compliance {
                HStack(spacing: 8) {
                    Image(systemName: comp.pass == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(comp.pass == true ? .green : .orange)
                    Text(comp.pass == true ? "Measurements look clear" : "Potential clearance issue")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    if let ref = comp.standardRef {
                        Text(ref)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !comp.warnings.isEmpty {
                    ForEach(comp.warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }

                Divider()
            }

            // Nearby features
            if !session.nearbyFeatures.isEmpty {
                Text("Tagged features (\(session.nearbyFeatures.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                ForEach(session.nearbyFeatures) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: feature.kind.symbolName)
                            .frame(width: 20)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(feature.kind.displayName)
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                        if let d = feature.distanceToTerminalM {
                            Text(String(format: "%.2f m", d))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(distanceColor(d, kind: feature.kind))
                        }
                    }
                }
                Divider()
            }

            Text("Guidance only — verify with manufacturer specification and Gas Safe guidelines.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .italic()

            HStack(spacing: 10) {
                Button("Retag") {
                    session.beginPlacingFeatures()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white.opacity(0.18))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button("Save to Session") {
                    saveScene()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    // MARK: - Feature kind picker sheet

    private var featureKindPickerSheet: some View {
        NavigationStack {
            List(ClearanceFeatureKind.allCases, id: \.rawValue) { kind in
                Button {
                    session.pendingFeatureKind = kind
                    showingFeaturePicker = false
                } label: {
                    HStack {
                        Label(kind.displayName, systemImage: kind.symbolName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if session.pendingFeatureKind == kind {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Feature Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingFeaturePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func saveScene() {
        // Take AR snapshot for preview
        let snapshot = _arViewSnapshot()
        let scene = session.buildScene(
            propertySessionID: propertySessionID,
            captureSessionID: captureSessionID,
            previewImage: snapshot
        )
        onSceneCaptured(scene)
        dismiss()
    }

    private func _arViewSnapshot() -> UIImage? {
        guard let view = session.arView as? ARSCNView else { return nil }
        return view.snapshot()
    }

    private func distanceColor(_ d: Double, kind: ClearanceFeatureKind) -> Color {
        let minRequired: Double
        switch kind {
        case .window, .door, .airBrick, .opening, .adjacentFlue:
            minRequired = 0.30
        case .boundary:
            minRequired = 0.60
        case .eaves, .gutter:
            minRequired = 0.30
        default:
            minRequired = 0.30
        }
        if d < minRequired         { return .red }
        if d < minRequired * 1.30  { return .orange }
        return .green
    }
}

// MARK: - FlueCaptureARViewRepresentable

private struct FlueCaptureARViewRepresentable: UIViewRepresentable {
    let arView: UIView
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)
        return arView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        let onTap: (CGPoint) -> Void
        init(onTap: @escaping (CGPoint) -> Void) { self.onTap = onTap }
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onTap(gesture.location(in: gesture.view))
        }
    }
}

// MARK: - FluePrimaryButtonStyle

private struct FluePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.white)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NavigationStack {
        ExternalFlueCaptureView(propertySessionID: UUID()) { _ in }
    }
}
#endif
