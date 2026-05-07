/// V2RoomLoopView — Orchestrates repeated room captures until the user finishes.

import SwiftUI
import AtlasScanCore

struct V2RoomLoopView: View {
    @ObservedObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var capturedRoom: RoomCaptureV2?
    @State private var showCapture = true
    @State private var roomName = ""
    @State private var showNamePrompt = false

    var body: some View {
        Group {
            if showCapture {
                LiveSpatialCaptureView(
                    capturedRoom: $capturedRoom,
                    rooms: coordinator.session.rooms,
                    onExit: { dismiss() }
                )
                .ignoresSafeArea()
                .onChange(of: capturedRoom?.id) { _, newId in
                    if newId != nil {
                        showCapture = false
                        showNamePrompt = true
                    }
                }
            } else {
                // Brief pause between rooms.
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Room captured!")
                        .font(.title2.bold())
                    HStack(spacing: 16) {
                        Button("Add Another Room") {
                            capturedRoom = nil
                            showCapture = true
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Finish") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Name this room", isPresented: $showNamePrompt, actions: {
            TextField("e.g. Kitchen", text: $roomName)
            Button("Save") { saveRoom() }
            Button("Cancel", role: .cancel) { showCapture = true }
        })
    }

    private func saveRoom() {
        guard var room = capturedRoom else { return }
        room.displayName = roomName.isEmpty ? "Room \(coordinator.session.rooms.count + 1)" : roomName
        coordinator.addRoom(room)
        Task { await coordinator.saveSession() }
        roomName = ""
        capturedRoom = nil
    }
}

private struct LiveSpatialCaptureView: View {
    private let hudOverlayZIndex: Double = 999

    @Binding var capturedRoom: RoomCaptureV2?
    let rooms: [RoomCaptureV2]
    let onExit: () -> Void
    @State private var activeDockTool: DockTool?

    var body: some View {
        ZStack {
            V2RoomPlanCaptureView(capturedRoom: $capturedRoom)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("LIVE SPATIAL CAPTURE")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                    .fontWeight(.black)
                    .padding(.top, 18)
                    .zIndex(hudOverlayZIndex)

                HStack(alignment: .top) {
                    MiniMapHUD(rooms: rooms)
                        .debugOverlayBorder(.red)
                        .zIndex(hudOverlayZIndex)
                    Spacer()
                    ObjectRadarPointersHUD()
                        .zIndex(hudOverlayZIndex)
                }
                .padding(.horizontal, 16)

                Spacer()

                CenterCaptureReticleButton()
                    .zIndex(hudOverlayZIndex)

                BottomActionDock(
                    onObject: { activeDockTool = .object },
                    onPhoto: { activeDockTool = .photo },
                    onVoice: { activeDockTool = .voice },
                    onExit: onExit
                )
                    .debugOverlayBorder(.green)
                    .zIndex(hudOverlayZIndex)
            }
            .padding(.bottom, 20)
        }
        .alert(item: $activeDockTool) { tool in
            Alert(
                title: Text("\(tool.rawValue) workflow"),
                message: Text("This control is now wired into LiveSpatialCaptureView and ready for workflow integration."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct CenterCaptureReticleButton: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: 72, height: 72)
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 44, height: 44)
            Image(systemName: "scope")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

private struct BottomActionDock: View {
    let onObject: () -> Void
    let onPhoto: () -> Void
    let onVoice: () -> Void
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            dockButton(symbol: "mappin.circle", title: "Object", action: onObject)
            dockButton(symbol: "camera.circle", title: "Photo", action: onPhoto)
            dockButton(symbol: "waveform.circle", title: "Voice", action: onVoice)
            Button(action: onExit) {
                Label("Finish", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.green.opacity(0.92), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 14)
    }

    private func dockButton(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title3)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct ObjectRadarPointersHUD: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Label("Object Radar", systemImage: "location.north.line")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                Image(systemName: "arrow.up.right")
                Image(systemName: "arrow.right")
            }
            .font(.caption.bold())
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private enum DockTool: String, Identifiable {
    case object = "Object"
    case photo = "Photo"
    case voice = "Voice"

    var id: String { rawValue }
}

private extension View {
    @ViewBuilder
    func debugOverlayBorder(_ color: Color) -> some View {
#if DEBUG
        self.border(color)
#else
        self
#endif
    }
}
