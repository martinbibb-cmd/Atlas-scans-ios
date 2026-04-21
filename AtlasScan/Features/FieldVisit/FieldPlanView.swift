import SwiftUI
import AtlasContracts

// MARK: - FieldPlanView

/// Plan tab skeleton for the field visit shell.
///
/// Shows summary counts for the planning overlay and exposes placeholder
/// actions for adding radiators, routes, and planning notes.
/// Deeper planning editor features are wired in later PRs.
struct FieldPlanView: View {

    @ObservedObject var store: FieldVisitStore

    @State private var showingAddAnnotation = false
    @State private var newAnnotationKind: PlanningAnnotationKind = .accessNote
    @State private var newAnnotationText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                actionsSection
                annotationsList
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingAddAnnotation) {
            addAnnotationSheet
        }
        .onAppear { store.enterPlanningPhase() }
    }

    private var summarySection: some View {
        let overlay = store.planningOverlay
        return VStack(spacing: 10) {
            SectionHeader(title: "Planning Summary")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PlanSummaryCard(
                    count: overlay.proposedEmitters.count,
                    label: "Proposed Emitters",
                    symbol: "thermometer.medium",
                    tint: .orange
                )
                PlanSummaryCard(
                    count: overlay.routeMarkups.count,
                    label: "Route Markups",
                    symbol: "line.diagonal",
                    tint: .blue
                )
                PlanSummaryCard(
                    count: overlay.accessNotes.count,
                    label: "Access Notes",
                    symbol: "door.left.hand.open",
                    tint: .purple
                )
                PlanSummaryCard(
                    count: overlay.roomPlanNotes.count,
                    label: "Room Plans",
                    symbol: "rectangle.portrait",
                    tint: .green
                )
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Add Planning Data")

            // Placeholder: wire to install markup editor in a subsequent PR.
            PlanActionRow(
                label: "Add Radiator",
                symbol: "thermometer.medium",
                tint: .orange
            )
            PlanActionRow(
                label: "Add Route Note",
                symbol: "line.diagonal",
                tint: .blue
            )

            // Access note — functional via inline sheet.
            Button {
                newAnnotationKind = .accessNote
                newAnnotationText = ""
                showingAddAnnotation = true
            } label: {
                PlanActionRowLabel(
                    label: "Add Access Note",
                    symbol: "door.left.hand.open",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)

            // Room plan note — functional via inline sheet.
            Button {
                newAnnotationKind = .roomPlanNote
                newAnnotationText = ""
                showingAddAnnotation = true
            } label: {
                PlanActionRowLabel(
                    label: "Add Room Plan Note",
                    symbol: "rectangle.portrait",
                    tint: .green
                )
            }
            .buttonStyle(.plain)

            // Spec note — functional via inline sheet.
            Button {
                newAnnotationKind = .specNote
                newAnnotationText = ""
                showingAddAnnotation = true
            } label: {
                PlanActionRowLabel(
                    label: "Add Spec Note",
                    symbol: "list.bullet.clipboard",
                    tint: .gray
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Existing annotations list

    @ViewBuilder
    private var annotationsList: some View {
        let all = store.session.planningAnnotations
        if !all.isEmpty {
            VStack(spacing: 10) {
                SectionHeader(title: "Planning Notes")
                ForEach(all) { annotation in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: annotation.kind.symbolName)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(annotation.kind.displayName)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(annotation.text)
                                .font(.body)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Add annotation sheet

    private var addAnnotationSheet: some View {
        NavigationStack {
            Form {
                Section(newAnnotationKind.displayName) {
                    TextField("Note text", text: $newAnnotationText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add \(newAnnotationKind.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddAnnotation = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !newAnnotationText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let annotation = PlanningAnnotation(
                            text: newAnnotationText,
                            kind: newAnnotationKind
                        )
                        store.update { $0.addPlanningAnnotation(annotation) }
                        showingAddAnnotation = false
                    }
                    .disabled(newAnnotationText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - PlanSummaryCard

private struct PlanSummaryCard: View {
    let count: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(count > 0 ? tint : .secondary)
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - PlanActionRow / PlanActionRowLabel

private struct PlanActionRow: View {
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        Button {} label: {
            PlanActionRowLabel(label: label, symbol: symbol, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

struct PlanActionRowLabel: View {
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    let session = PropertyScanSession(propertyAddress: "12 Coronation Street")
    let visitStore = FieldVisitStore(session: session, sessionStore: store)
    return FieldPlanView(store: visitStore)
}
#endif
