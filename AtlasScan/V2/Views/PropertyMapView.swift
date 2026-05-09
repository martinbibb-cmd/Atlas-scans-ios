/// PropertyMapView — Root view shown after launch; lists all scanned rooms.

import SwiftUI
import AtlasScanCore

struct PropertyMapView: View {
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @EnvironmentObject var recallClient: MindRecallClient

    @State private var showRoomCapture = false
    @State private var showHandoff = false
    @State private var showOutdoorFlue = false
    @State private var pendingRecall: UUID?
    @State private var showVisitSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.session.rooms.isEmpty {
                    emptyState
                } else {
                    roomList
                }
            }
            .navigationTitle("Property Map")
            .toolbar { toolbarContent }
            .fullScreenCover(isPresented: $showRoomCapture) {
                V2RoomLoopView(coordinator: coordinator)
            }
            .sheet(isPresented: $showVisitSetup) {
                V2VisitSetupSheet(
                    initialReference: coordinator.session.visitReference ?? "",
                    initialLabel: coordinator.session.visitLabel ?? ""
                ) { reference, label in
                    coordinator.session.visitReference = reference
                    coordinator.session.visitLabel = label.isEmpty ? nil : label
                    Task { await coordinator.saveSession() }
                    showVisitSetup = false
                }
            }
            .sheet(isPresented: $coordinator.showHandoff) {
                HandoffView(coordinator: coordinator)
            }
            .sheet(isPresented: $showOutdoorFlue) {
                V2OutdoorFlueModeView(coordinator: coordinator)
            }
            .onAppear {
                if !hasVisitReference {
                    showVisitSetup = true
                }
            }
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "house.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No rooms captured yet")
                .font(.headline)
            Button("Start Scan") {
                guard hasVisitReference else {
                    showVisitSetup = true
                    return
                }
                showRoomCapture = true
            }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var roomList: some View {
        List(coordinator.session.rooms) { room in
            NavigationLink(destination: VanModeView(room: room, coordinator: coordinator)) {
                roomRow(room)
            }
        }
    }

    private func roomRow(_ room: RoomCaptureV2) -> some View {
        HStack {
            V2CustomRoomShapeRenderer(vertices: room.polygonVertices)
                .fill(Color.accentColor.opacity(0.15))
                .overlay(
                    V2CustomRoomShapeRenderer(vertices: room.polygonVertices)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                )
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(room.displayName).font(.headline)
                if room.hasClosedFloorPolygon {
                    Text(String(format: "%.1f m²", room.floorAreaM2))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Room outline incomplete")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { showRoomCapture = true } label: {
                    Label("Add Room", systemImage: "plus.circle")
                }
                .disabled(!hasVisitReference)
                .accessibilityHint("Visit reference required before adding rooms.")
                Button { showOutdoorFlue = true } label: {
                    Label("Outdoor Flue Check", systemImage: "wind")
                }
                Button { coordinator.handOffToMind() } label: {
                    Label("Hand Off to Mind", systemImage: "arrow.up.forward.app")
                }
                Button {
                    showVisitSetup = true
                } label: {
                    Label("Set Visit Reference", systemImage: "number")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var hasVisitReference: Bool {
        !(coordinator.session.visitReference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

private struct V2VisitSetupSheet: View {
    let initialReference: String
    let initialLabel: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reference = ""
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. JOB-2026-001", text: $reference)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Visit / Job reference")
                } footer: {
                    Text("Required before capture begins.")
                }
                Section {
                    TextField("e.g. Smith / SW1A", text: $label)
                        .autocorrectionDisabled()
                } header: {
                    Text("Customer / postcode label (optional)")
                }
            }
            .navigationTitle("Start Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmedReference, trimmedLabel)
                    }
                    .disabled(reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                reference = initialReference
                label = initialLabel
            }
        }
    }
}
