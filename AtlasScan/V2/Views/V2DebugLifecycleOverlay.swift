/// V2DebugLifecycleOverlay — Debug-only HUD showing V2 visit lifecycle state.
///
/// Compiled and visible only in DEBUG builds. Attach via the
/// `.v2DebugLifecycleOverlay()` view modifier on any view that has
/// `ScanSessionCoordinator` in the environment.
///
/// The overlay can be hidden by tapping the "Hide" button inside the HUD;
/// a small wrench button appears in its place so it can be restored.

#if DEBUG

import SwiftUI

// MARK: - Overlay view

struct V2DebugLifecycleOverlay: View {
    @ObservedObject var coordinator: ScanSessionCoordinator
    /// Persisted across launches so engineers don't have to hide the HUD every session.
    @AppStorage("show_v2_debug_hud") private var showHUD = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        if showHUD {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        label("🔄 State", value: coordinator.lifecycleState.rawValue)
                        label("🆔 visitId", value: shortId(coordinator.session.visitId))
                        label("🏷 ref", value: coordinator.session.visitReference ?? "—")
                    }
                    Spacer(minLength: 8)
                    Button {
                        showHUD = false
                    } label: {
                        Text("Hide")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                Divider().overlay(Color.white.opacity(0.4))
                label("🏠 rooms", value: "\(coordinator.session.rooms.count)")
                label("📌 pins", value: "\(totalPins)")
                label("👻 ghosts", value: "\(totalGhosts)")
                label("📐 measures", value: "\(totalMeasurements)")
                label("📷 photos", value: "\(coordinator.session.photos.count)")
                label("🎙 voice", value: "\(coordinator.session.voiceNotes.count)")
                Divider().overlay(Color.white.opacity(0.4))
                label("💾 saved", value: saveLabel)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.72))
            )
            .padding(10)
        } else {
            // Compact restore button so engineers can bring the HUD back.
            Button {
                showHUD = true
            } label: {
                Image(systemName: "wrench.adjustable.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    // MARK: - Computed helpers

    private var totalPins: Int {
        coordinator.session.rooms.reduce(0) { $0 + $1.pinnedObjects.count }
    }

    private var totalGhosts: Int {
        coordinator.session.rooms.reduce(0) { $0 + $1.ghostAppliancePlacements.count }
    }

    private var totalMeasurements: Int {
        coordinator.session.rooms.reduce(0) { $0 + $1.measurements.count }
    }

    private var saveLabel: String {
        guard let date = coordinator.lastSaveDate else { return "—" }
        return Self.timeFormatter.string(from: date)
    }

    private func shortId(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }

    @ViewBuilder
    private func label(_ key: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .opacity(0.7)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - View modifier

struct V2DebugLifecycleOverlayModifier: ViewModifier {
    @EnvironmentObject var coordinator: ScanSessionCoordinator

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomLeading) {
            V2DebugLifecycleOverlay(coordinator: coordinator)
        }
    }
}

extension View {
    /// Pins the debug lifecycle HUD to the bottom-leading corner.
    /// Compiled and active only in DEBUG builds; no-ops in release.
    func v2DebugLifecycleOverlay() -> some View {
        modifier(V2DebugLifecycleOverlayModifier())
    }
}

#else

extension View {
    @_transparent
    func v2DebugLifecycleOverlay() -> some View { self }
}

#endif
