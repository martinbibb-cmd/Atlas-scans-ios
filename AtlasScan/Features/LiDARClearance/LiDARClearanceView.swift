import SwiftUI
import UIKit

// MARK: - LiDARClearanceView
//
// Fullscreen AR view that uses the device LiDAR sensor to measure real-world
// clearance distances around a selected appliance — the equivalent of the
// Clearance Wizard (ArUco-based) but without printed markers.
//
// Workflow:
//   1. Select an appliance category and optional profile using the top bar.
//   2. Point the camera at the appliance and tap its front face.
//   3. Review the measured distances and pass/fail status in the results card.
//   4. Tap "Remeasure" to reposition; "Done" to dismiss.

struct LiDARClearanceView: View {

    @StateObject private var session = LiDARClearanceSession()
    @Environment(\.dismiss) private var dismiss

    @State private var showingCategoryPicker = false
    @State private var showingProfilePicker  = false

    var body: some View {
        ZStack {
            arBackground
            overlay
        }
        .navigationTitle("LiDAR Clearance Check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear  { session.start() }
        .onDisappear { session.pause() }
        .sheet(isPresented: $showingCategoryPicker) {
            LiDARCategoryPickerSheet(selected: $session.selectedCategory)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingProfilePicker) {
            LiDARProfilePickerSheet(
                category: session.selectedCategory,
                selectedID: Binding(
                    get: { session.selectedProfileID },
                    set: { session.selectedProfileID = $0 }
                )
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - AR background

    @ViewBuilder
    private var arBackground: some View {
        switch session.sessionState {
        case .unavailable:
            unavailableBackground
        case .permissionDenied:
            permissionDeniedBackground
        default:
            LiDARARViewRepresentable(arView: session.arView) { point in
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
                    Text("LiDAR Not Available")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("This feature requires a LiDAR-equipped device\n(iPhone 12 Pro or later, iPad Pro 2020 or later).")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.subheadline)
                        .padding(.horizontal)
                    Button("Dismiss") { dismiss() }
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    Text("Grant camera permission in Settings to use LiDAR clearance checking.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.subheadline)
                        .padding(.horizontal)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
    }

    // MARK: - HUD overlay

    private var overlay: some View {
        VStack(spacing: 0) {
            configBar
            Spacer()
            switch session.sessionState {
            case .unavailable, .permissionDenied:
                EmptyView()
            default:
                bottomPanel
            }
        }
    }

    private var configBar: some View {
        HStack(spacing: 12) {
            Button {
                showingCategoryPicker = true
            } label: {
                Label(session.selectedCategory.displayName, systemImage: session.selectedCategory.symbolName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }

            Button {
                showingProfilePicker = true
            } label: {
                let name = session.selectedProfileID
                    .flatMap { ApplianceProfileLibrary.profile(id: $0) }?.displayName ?? "Generic"
                Label(name, systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            switch session.sessionState {
            case .waitingForPlacement:
                placementPrompt
            case .measuring:
                measuringCard
            case .completed:
                if let m = session.latestMeasurement {
                    measurementCard(m)
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private var placementPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.85))
            Text("Tap the front face of the appliance")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Text("Point the camera at the appliance and tap its front surface.\nThe LiDAR sensor will measure clearances in all directions.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var measuringCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("Measuring clearances…")
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func measurementCard(_ m: LiDARClearanceMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: m.overallStatus.symbolName)
                    .foregroundStyle(statusColor(m.overallStatus))
                Text(m.overallStatus.displayMessage)
                    .font(.subheadline.bold())
                    .foregroundStyle(statusColor(m.overallStatus))
                Spacer()
                Text(m.profileName ?? m.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(m.axes, id: \.axis.rawValue) { axis in
                HStack(spacing: 10) {
                    Image(systemName: axis.axis.symbolName)
                        .frame(width: 22)
                        .foregroundStyle(statusColor(axis.status))
                    Text(axis.axis.displayName)
                        .font(.caption.weight(.semibold))
                        .frame(width: 58, alignment: .leading)
                    Text(axis.displayMeasured)
                        .font(.caption.monospacedDigit())
                        .frame(width: 72, alignment: .trailing)
                    Text(axis.displayRequired)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Divider()

            Text("Guidance only — not a compliance approval. Verify with manufacturer specification.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .italic()

            HStack(spacing: 10) {
                Button("Remeasure") { session.reset() }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.18))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statusColor(_ status: ClearanceStatus) -> Color {
        switch status {
        case .clear:    return .green
        case .warning:  return .orange
        case .conflict: return .red
        }
    }
}

// MARK: - LiDARARViewRepresentable

private struct LiDARARViewRepresentable: UIViewRepresentable {
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

// MARK: - LiDARCategoryPickerSheet

struct LiDARCategoryPickerSheet: View {
    @Binding var selected: ServiceObjectCategory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ServiceObjectCategory.allCases, id: \.rawValue) { cat in
                Button {
                    selected = cat
                    dismiss()
                } label: {
                    HStack {
                        Label(cat.displayName, systemImage: cat.symbolName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selected == cat {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Appliance Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - LiDARProfilePickerSheet

struct LiDARProfilePickerSheet: View {
    let category: ServiceObjectCategory
    @Binding var selectedID: String?
    @Environment(\.dismiss) private var dismiss

    private var profiles: [ApplianceProfile] {
        ApplianceProfileLibrary.profiles(for: category)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("Generic (category default)")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedID == nil {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                }

                if !profiles.isEmpty {
                    Section("Profiles") {
                        ForEach(profiles) { profile in
                            Button {
                                selectedID = profile.id
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.displayName).foregroundStyle(.primary)
                                        Text(profile.family)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedID == profile.id {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NavigationStack {
        LiDARClearanceView()
    }
}
#endif
