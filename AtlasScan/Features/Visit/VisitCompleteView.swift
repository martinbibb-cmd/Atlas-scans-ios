import SwiftUI
import AtlasContracts

// MARK: - VisitCompleteView
//
// Shown when the engineer marks a visit as complete.
//
// Primary action:
//   Continue in Atlas Mind — encodes the ScanToMindHandoffV1 and opens
//   the Mind PWA at /receive-scan with the visit preloaded.
//
// Secondary action:
//   Open Quote Planner in Atlas Mind — opens the Mind PWA at /quote-planner
//   with the SessionCaptureV2 (including quotePlannerEvidence) preloaded.
//   A "Copy Link" fallback appears after the button is tapped.
//
// Tertiary action:
//   Return to Home — clears the active visit and returns to the app home screen.
//
// Handoff diagnostics:
//   All users see a success / error indicator for URL formation.
//   Developer Mode additionally shows the encoded payload length (characters).

struct VisitCompleteView: View {

    /// Pre-built handoff to deliver to Atlas Mind.
    ///
    /// Nil when the handoff could not be assembled (e.g. session ID mismatch);
    /// the Mind action buttons are hidden in that case.
    let handoff: ScanToMindHandoffV1?

    let onDone: () -> Void

    @StateObject private var developerMode = DeveloperModeStore.shared

    /// The quote-planner URL for the "copy link" fallback, built on demand.
    @State private var quotePlannerLinkURL: URL?

    private var requiresReview: Bool {
        handoff?.requiresReview ?? false
    }

    private var canOpenFinalOutputs: Bool {
        handoff?.finalOutputsAllowed ?? false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    completionHeader
                    handoffDiagnosticsView
                    if let handoff {
                        reviewSummaryView(handoff: handoff)
                    }
                    actionsView
                }
                .padding(24)
            }
            .navigationTitle("Complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Quote planner fallback

    /// Compact fallback row shown after the user taps "Open Quote Planner".
    ///
    /// Offers a "Copy Link" action so the engineer can paste the URL manually
    /// if the browser or PWA did not open as expected.
    private func quotePlannerFallbackRow(url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Quote planner link ready")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = url.absoluteString
                #endif
            } label: {
                Label("Copy Link", systemImage: "doc.on.clipboard")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Handoff diagnostics

    @ViewBuilder
    private var handoffDiagnosticsView: some View {
        if let handoff {
            VStack(alignment: .leading, spacing: 6) {
                // URL formation success — visible to all testers
                Label("Atlas Mind URL: Ready", systemImage: "link.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                // Encoded payload length — developer only
                if developerMode.isEnabled,
                   let encodedPayload = try? ScanToMindPayloadEncoder.encodeForURL(handoff) {
                    Text("Payload: \(encodedPayload.count) chars")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            // URL formation failed — visible to all testers
            Label("Atlas Mind URL: Not available", systemImage: "link.circle")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var completionHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: requiresReview ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 80, weight: .thin))
                .foregroundStyle(requiresReview ? .orange : .green)
                .accessibilityLabel(requiresReview ? "Review required" : "Visit complete")

            Text(requiresReview ? "Review Required" : "Visit Complete")
                .font(.largeTitle.bold())

            Text(
                requiresReview
                    ? "Incomplete capture — review required before final outputs are available."
                    : "All required evidence has been captured."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func reviewSummaryView(handoff: ScanToMindHandoffV1) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if requiresReview {
                Label("Incomplete capture — review required", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            detailSection("Readiness flags") {
                readinessRow(label: "Rooms captured", passed: handoff.visit.readiness.hasRooms)
                readinessRow(label: "Photos captured", passed: handoff.visit.readiness.hasPhotos)
                readinessRow(label: "Heating system tagged", passed: handoff.visit.readiness.hasHeatingSystem)
                readinessRow(label: "Hot water system tagged", passed: handoff.visit.readiness.hasHotWaterSystem)
                readinessRow(label: "Boiler tagged", passed: handoff.visit.readiness.hasBoiler)
                readinessRow(label: "Flue tagged", passed: handoff.visit.readiness.hasFlue)
                readinessRow(label: "Voice notes recorded", passed: handoff.visit.readiness.hasNotes)
            }

            if !handoff.missingEvidence.isEmpty {
                detailSection("Missing evidence") {
                    ForEach(handoff.missingEvidence, id: \.self) { item in
                        Label(item, systemImage: "minus.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !handoff.unresolvedEvidence.isEmpty {
                detailSection("Unresolved items") {
                    ForEach(handoff.unresolvedEvidence, id: \.self) { item in
                        Label(item.message, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !handoff.geometryQAFlags.isEmpty {
                detailSection("Geometry QA flags") {
                    ForEach(handoff.geometryQAFlags, id: \.self) { flag in
                        Label(flag.message, systemImage: "triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var actionsView: some View {
        VStack(spacing: 12) {
            if let handoff {
                Button {
                    OpenAtlasMind.openMind(with: handoff)
                    onDone()
                } label: {
                    Label(
                        requiresReview ? "Continue in Atlas Mind for Review" : "Continue in Atlas Mind",
                        systemImage: "brain.head.profile"
                    )
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    let url = OpenAtlasMind.makeQuotePlannerURL(for: handoff)
                    quotePlannerLinkURL = url
                    OpenAtlasMind.openQuotePlanner(with: handoff)
                } label: {
                    Label("Open Quote Planner in Atlas Mind", systemImage: "list.clipboard")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(!canOpenFinalOutputs)
                .opacity(canOpenFinalOutputs ? 1 : 0.5)

                if requiresReview {
                    Text("Final outputs stay locked until review is completed in Atlas Mind.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let url = quotePlannerLinkURL, canOpenFinalOutputs {
                    quotePlannerFallbackRow(url: url)
                }
            }

            Button {
                onDone()
            } label: {
                Label("Return to Home", systemImage: "house")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func readinessRow(label: String, passed: Bool) -> some View {
        Label(label, systemImage: passed ? "checkmark.circle.fill" : "xmark.circle")
            .font(.caption)
            .foregroundStyle(passed ? .green : .secondary)
            .accessibilityLabel("\(label): \(passed ? "passed" : "failed")")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Incomplete draft") {
    VisitCompleteView(handoff: ScanToMindHandoffFixtures.incompleteDraft, onDone: {})
}

#Preview("Complete") {
    VisitCompleteView(handoff: ScanToMindHandoffFixtures.complete, onDone: {})
}
#endif
