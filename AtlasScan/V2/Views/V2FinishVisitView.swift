/// V2FinishVisitView — Readiness checklist and export actions for finishing a V2 visit.
///
/// Derives readiness flags from the active session and lets the engineer:
///   • See what evidence is complete or missing
///   • Finish the visit as a draft (incomplete data allowed)
///   • Export / open Atlas Mind once data is ready

import SwiftUI
import AtlasScanCore

struct V2FinishVisitView: View {

    @ObservedObject var coordinator: ScanSessionCoordinator
    let onDismiss: () -> Void
    @State private var showMissingItemsReview = false
    @State private var engineerNotesDraft = ""

    private var readiness: VisitReadinessV1 {
        VisitReadinessV1.derive(from: coordinator.session)
    }

    var body: some View {
        NavigationStack {
            List {
                visitSummarySection
                readinessSection
                actionsSection
            }
            .navigationTitle("Finish Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .sheet(isPresented: $coordinator.showHandoff) {
                HandoffView(coordinator: coordinator)
            }
            .sheet(isPresented: $showMissingItemsReview) {
                NavigationStack {
                    List {
                        Section("Missing items") {
                            ForEach(readiness.unmetConditions, id: \.self) { item in
                                Label(item, systemImage: "exclamationmark.circle")
                            }
                        }
                        Section("Reason / note") {
                            TextEditor(text: $engineerNotesDraft)
                                .frame(minHeight: 120)
                        } footer: {
                            Text("This note is included in the handoff so Atlas Mind can review incomplete evidence.")
                        }
                        Section("Options") {
                            Button("Go back and complete missing items") {
                                showMissingItemsReview = false
                            }
                            Button("Finish as Draft / Incomplete Visit") {
                                coordinator.updateEngineerNotes(engineerNotesDraft)
                                coordinator.transition(to: .incompleteReadyForReview)
                                coordinator.handOffToMind()
                                showMissingItemsReview = false
                                onDismiss()
                            }
                        }
                    }
                    .navigationTitle("Missing Evidence Review")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showMissingItemsReview = false }
                        }
                    }
                }
            }
            .onAppear {
                engineerNotesDraft = coordinator.session.engineerNotes ?? ""
            }
        }
    }

    // MARK: - Sections

    private var visitSummarySection: some View {
        Section("Visit Summary") {
            if let reference = coordinator.session.visitReference?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reference.isEmpty {
                LabeledContent("Reference", value: reference)
            }
            if let label = coordinator.session.visitLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !label.isEmpty {
                LabeledContent("Label", value: label)
            }
            LabeledContent("Rooms", value: "\(coordinator.session.rooms.count)")
            LabeledContent("Photos", value: "\(coordinator.session.photos.count)")
            LabeledContent("Voice notes", value: "\(coordinator.session.voiceNotes.count)")
        }
    }

    private var readinessSection: some View {
        Section {
            readinessRow(
                label: "Rooms captured",
                passed: readiness.hasRooms,
                note: "At least one room must be saved"
            )
            readinessRow(
                label: "Photos attached",
                passed: readiness.hasPhotos,
                note: "At least one photo required"
            )
            readinessRow(
                label: "Boiler / heat-pump",
                passed: readiness.hasBoilerDetails,
                note: "Pin a boiler or heat-pump object"
            )
            readinessRow(
                label: "Flue terminal",
                passed: readiness.hasFlueDetails,
                note: "Pin a flue terminal object"
            )
            readinessRow(
                label: "Clearance check",
                passed: readiness.hasClearanceCheck,
                note: "Complete a clearance measurement"
            )
            readinessRow(
                label: "Voice notes",
                passed: readiness.hasTranscripts,
                note: "Record at least one voice note"
            )
            readinessRow(
                label: "Property address",
                passed: readiness.hasPropertyAddress,
                note: "Enter address via Set Visit Reference"
            )
        } header: {
            Text("Readiness Checklist")
        } footer: {
            if readiness.isReady {
                Label("All checks passed — ready to export", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Missing items won't prevent finishing, but are needed for a complete record.")
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                if readiness.isReady {
                    coordinator.updateEngineerNotes(engineerNotesDraft)
                    coordinator.transition(to: .readyToExport)
                    coordinator.handOffToMind()
                    onDismiss()
                } else {
                    showMissingItemsReview = true
                }
            } label: {
                Label("Review & Finish Visit", systemImage: "flag.checkered")
            }

            Button {
                coordinator.updateEngineerNotes(engineerNotesDraft)
                coordinator.transition(to: .draft)
                onDismiss()
            } label: {
                Label("Finish as Draft (incomplete)", systemImage: "doc.badge.clock")
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func readinessRow(label: String, passed: Bool, note: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(passed ? .green : .secondary)
                .font(.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                if !passed {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
