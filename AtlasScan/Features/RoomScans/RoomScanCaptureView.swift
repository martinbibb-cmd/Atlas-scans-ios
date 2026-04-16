import SwiftUI

// MARK: - RoomScanCaptureView
//
// Simulates a room scan capture session.
//
// On real hardware this would launch RoomPlanViewController / ARSession.
// This stub collects the room label and creates a CapturedRoomScanDraft
// with placeholder dimensions, so the rest of the capture flow works
// on simulator or without LiDAR.
//
// The captured draft stores raw observation data only — no derived maths.

struct RoomScanCaptureView: View {

    let onComplete: (CapturedRoomScanDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var roomLabel: String = ""
    @State private var isScanning: Bool = false
    @State private var scanComplete: Bool = false
    @State private var confidence: RoomScanConfidence = .medium

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if scanComplete {
                    scanCompleteView
                } else if isScanning {
                    scanningView
                } else {
                    setupView
                }
            }
            .padding()
            .navigationTitle("Room Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Setup view

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lidar.scanner")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Ready to Scan")
                    .font(.title2.bold())
                Text("Point the device at the room and tap Start Scan.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Room label (optional)", text: $roomLabel)
                .textInputAutocapitalization(.words)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()

            Button {
                startScan()
            } label: {
                Label("Start Scan", systemImage: "lidar.scanner")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Scanning view

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Scanning…")
                .font(.headline)
            Text("Walk around the room slowly to capture all walls.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Finish Scan") {
                finishScan()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Scan complete view

    private var scanCompleteView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Scan Captured")
                    .font(.title2.bold())
                if !roomLabel.isEmpty {
                    Text(roomLabel)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Confidence")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Confidence", selection: $confidence) {
                    ForEach(RoomScanConfidence.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()

            Button("Save Room Scan") {
                saveScan()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Actions

    private func startScan() {
        isScanning = true
    }

    private func finishScan() {
        isScanning = false
        scanComplete = true
    }

    private func saveScan() {
        var scan = CapturedRoomScanDraft()
        scan.roomLabel = roomLabel.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : roomLabel.trimmingCharacters(in: .whitespaces)
        scan.confidence = confidence
        // In production this would be populated from the RoomPlan session output.
        onComplete(scan)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    RoomScanCaptureView { _ in }
}
#endif
