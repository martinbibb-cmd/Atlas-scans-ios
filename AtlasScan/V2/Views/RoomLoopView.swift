/// RoomLoopView — Orchestrates repeated room captures until the user finishes.

import SwiftUI
import AtlasScanCore

struct RoomLoopView: View {
    @ObservedObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var capturedRoom: RoomCaptureV2?
    @State private var showCapture = true
    @State private var roomName = ""
    @State private var showNamePrompt = false

    var body: some View {
        Group {
            if showCapture {
                ZStack(alignment: .bottom) {
                    RoomPlanCaptureView(capturedRoom: $capturedRoom)
                        .ignoresSafeArea()
                    MiniMapHUD(rooms: coordinator.session.rooms)
                        .padding()
                }
                .onChange(of: capturedRoom) { _, newRoom in
                    if newRoom != nil {
                        showCapture = false
                        showNamePrompt = true
                    }
                }
                .overlay(alignment: .topLeading) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .padding()
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
    }
}
