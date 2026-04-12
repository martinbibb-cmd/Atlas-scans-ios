import SwiftUI

// MARK: - FlueClearanceSceneCard
//
// Compact summary card for an ExternalClearanceScene.
//
// Shows:
//   • Preview image (if available) or a placeholder icon
//   • Compliance pass/fail badge
//   • Measurement count and nearby-feature count
//   • Top compliance warnings (up to 2)
//
// Design rules (from problem statement):
//   • Main view shows: preview image, structured annotations, measured distances,
//     compliance outcome.
//   • 3-D scene viewer is secondary, opened on demand.
//   • Raw point cloud is never shown as the primary view.

struct FlueClearanceSceneCard: View {

    let scene: ExternalClearanceScene
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                previewHeader
                measurementsRow
                if let comp = scene.compliance, !comp.warnings.isEmpty {
                    warningsSection(comp.warnings)
                }
                footerRow
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview header

    private var previewHeader: some View {
        HStack(spacing: 12) {
            previewThumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text("Flue Clearance Scene")
                    .font(.subheadline.bold())
                complianceBadge
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var previewThumbnail: some View {
        if let urlString = scene.previewImageURLString,
           let url = URL(string: urlString),
           url.isFileURL,
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                Image(systemName: "smoke")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var complianceBadge: some View {
        if let comp = scene.compliance {
            if let pass = comp.pass {
                Label(
                    pass ? "Clear" : "Issues found",
                    systemImage: pass ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(pass ? .green : .orange)
            } else {
                Label("Not yet evaluated", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("No compliance data", systemImage: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Measurements row

    private var measurementsRow: some View {
        HStack(spacing: 16) {
            Label("\(scene.nearbyFeatures.count) features", systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("\(scene.measurements.count) measurements", systemImage: "ruler")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Warnings section

    private func warningsSection(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(warnings.prefix(2), id: \.self) { warning in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            if warnings.count > 2 {
                Text("+ \(warnings.count - 2) more warning(s)…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer row

    private var footerRow: some View {
        HStack {
            if let ref = scene.compliance?.standardRef {
                Text(ref)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            Spacer()
            Text("Tap to review")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - FlueClearanceDetailView
//
// Full structured measurement review for one ExternalClearanceScene.
// Shown when the engineer taps "Tap to review" in FlueClearanceSceneCard.

struct FlueClearanceDetailView: View {

    let scene: ExternalClearanceScene

    var body: some View {
        List {
            previewSection
            terminalSection
            featuresSection
            measurementsSection
            complianceSection
            legalNoticeSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Flue Clearance Scene")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        if let urlString = scene.previewImageURLString,
           let url = URL(string: urlString),
           url.isFileURL,
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Section("Preview") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Terminal

    @ViewBuilder
    private var terminalSection: some View {
        if let t = scene.flueTerminal {
            Section("Flue Terminal") {
                if let h = t.heightAboveGroundM {
                    LabeledContent("Height above ground", value: String(format: "%.2f m", h))
                }
                LabeledContent(
                    "Position (x, y, z)",
                    value: String(format: "%.2f, %.2f, %.2f m", t.x, t.y, t.z)
                )
                .font(.caption.monospacedDigit())
            }
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        Section("Nearby Features (\(scene.nearbyFeatures.count))") {
            if scene.nearbyFeatures.isEmpty {
                Text("No features tagged")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scene.nearbyFeatures) { feature in
                    HStack(spacing: 10) {
                        Image(systemName: feature.kind.symbolName)
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.kind.displayName)
                                .font(.subheadline)
                            if let notes = feature.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let d = feature.distanceToTerminalM {
                            Text(String(format: "%.2f m", d))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(distanceColor(d, kind: feature.kind))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Measurements

    private var measurementsSection: some View {
        Section("Measurements (\(scene.measurements.count))") {
            if scene.measurements.isEmpty {
                Text("No measurements recorded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scene.measurements) { m in
                    HStack {
                        Text(m.kind.displayName)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.2f m", m.valueM))
                            .font(.subheadline.monospacedDigit())
                        if m.source == .derived {
                            Image(systemName: "function")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Compliance

    private var complianceSection: some View {
        Section("Compliance Summary") {
            if let comp = scene.compliance {
                if let pass = comp.pass {
                    Label(
                        pass ? "All measurements clear" : "Measurements below minimum",
                        systemImage: pass ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(pass ? .green : .orange)
                }
                if let ref = comp.standardRef {
                    LabeledContent("Standard", value: ref)
                }
                ForEach(comp.warnings, id: \.self) { w in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(w)
                            .font(.caption)
                    }
                }
            } else {
                Text("Compliance not yet evaluated")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Legal notice

    private var legalNoticeSection: some View {
        Section {
            Text("Guidance only — not a compliance approval. Verify with manufacturer specification, Gas Safe guidelines, and applicable British Standards.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    // MARK: - Helpers

    private func distanceColor(_ d: Double, kind: ClearanceFeatureKind) -> Color {
        let min: Double
        switch kind {
        case .window, .door, .airBrick, .opening, .adjacentFlue: min = 0.30
        case .boundary:                                           min = 0.60
        case .eaves, .gutter:                                     min = 0.30
        default:                                                  min = 0.30
        }
        if d < min        { return .red }
        if d < min * 1.30 { return .orange }
        return .primary
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Card — no compliance") {
    let scene = ExternalClearanceScene(
        propertySessionID: UUID(),
        captureSessionID: UUID(),
        nearbyFeatures: [
            NearbyFeatureCapture(kind: .window, distanceToTerminalM: 0.25),
            NearbyFeatureCapture(kind: .door,   distanceToTerminalM: 0.45),
        ],
        measurements: [
            ClearanceMeasurementCapture(kind: .terminalToOpening, valueM: 0.25),
            ClearanceMeasurementCapture(kind: .terminalToOpening, valueM: 0.45),
        ]
    )
    return FlueClearanceSceneCard(scene: scene)
        .padding()
}

#Preview("Detail") {
    var scene = ExternalClearanceScene(
        propertySessionID: UUID(),
        captureSessionID: UUID(),
        flueTerminal: FlueTerminalCapture(x: 1, y: 2.5, z: 3, heightAboveGroundM: 2.5),
        nearbyFeatures: [
            NearbyFeatureCapture(kind: .window,   distanceToTerminalM: 0.28),
            NearbyFeatureCapture(kind: .boundary, distanceToTerminalM: 0.72),
        ],
        measurements: [
            ClearanceMeasurementCapture(kind: .terminalToOpening,  valueM: 0.28),
            ClearanceMeasurementCapture(kind: .terminalToBoundary, valueM: 0.72),
        ]
    )
    scene.compliance = scene.evaluateCompliance()
    return NavigationStack {
        FlueClearanceDetailView(scene: scene)
    }
}
#endif
