import SwiftUI

// MARK: - QuotePlannerCaptureView
//
// Quote-planner anchor and route capture UI.
//
// Lets the engineer tag candidate install/service locations and lightweight
// pipe/service route evidence during a visit:
//
// Anchors:
//   • Kind (existing_boiler, proposed_boiler, gas_meter, …)
//   • Optional free-text label
//   • Optional links to photos or object pins
//   • Provenance (how the anchor was placed)
//
// Routes:
//   • Route type (gas, condensate, heating_flow, …)
//   • Status (existing, proposed, reused_existing, assumed)
//   • Optional install method, start/end anchor links, notes
//   • Provenance
//
// Design rules:
//   • Raw observation only — no pricing, no scope, no recommendations.
//   • All items default to .confirmed (manually created).
//   • Completion flags are NOT altered by this view.
//   • Atlas Mind owns all interpretation downstream.

struct QuotePlannerCaptureView: View {

    @ObservedObject var store: CaptureSessionStore

    // MARK: - Anchor state

    @State private var editingAnchor: CapturedQuotePlannerAnchorDraft?
    @State private var showingAddAnchor = false

    // MARK: - Route state

    @State private var editingRoute: CapturedCandidateRouteDraft?
    @State private var showingAddRoute = false

    var body: some View {
        List {
            anchorsSection
            routesSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Quote Points")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddAnchor = true
                    } label: {
                        Label("Add Quote Point", systemImage: "mappin.circle")
                    }
                    Button {
                        showingAddRoute = true
                    } label: {
                        Label("Add Route", systemImage: "arrow.triangle.branch")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        // Add anchor sheet
        .sheet(isPresented: $showingAddAnchor) {
            QuotePlannerAnchorEditSheet(
                anchor: CapturedQuotePlannerAnchorDraft(),
                availablePhotos: store.draft.photos,
                availablePins: store.draft.objectPins
            ) { saved in
                store.addQuotePlannerAnchor(saved)
                showingAddAnchor = false
            }
        }
        // Edit anchor sheet
        .sheet(item: $editingAnchor) { anchor in
            QuotePlannerAnchorEditSheet(
                anchor: anchor,
                availablePhotos: store.draft.photos,
                availablePins: store.draft.objectPins
            ) { saved in
                store.updateQuotePlannerAnchor(saved)
                editingAnchor = nil
            }
        }
        // Add route sheet
        .sheet(isPresented: $showingAddRoute) {
            CandidateRouteEditSheet(
                route: CapturedCandidateRouteDraft(),
                availableAnchors: store.draft.quotePlannerAnchors
            ) { saved in
                store.addCandidateRoute(saved)
                showingAddRoute = false
            }
        }
        // Edit route sheet
        .sheet(item: $editingRoute) { route in
            CandidateRouteEditSheet(
                route: route,
                availableAnchors: store.draft.quotePlannerAnchors
            ) { saved in
                store.updateCandidateRoute(saved)
                editingRoute = nil
            }
        }
    }

    // MARK: - Anchors section

    private var anchorsSection: some View {
        Section {
            if store.draft.quotePlannerAnchors.isEmpty {
                Label("No quote points recorded. Tap + to add an anchor.",
                      systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(store.draft.quotePlannerAnchors) { anchor in
                    anchorRow(anchor)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        store.removeQuotePlannerAnchor(id: store.draft.quotePlannerAnchors[idx].id)
                    }
                }
            }
        } header: {
            Text("Quote Points (\(store.draft.quotePlannerAnchors.count))")
        }
    }

    // MARK: - Routes section

    private var routesSection: some View {
        Section {
            if store.draft.candidateRoutes.isEmpty {
                Label("No routes recorded. Tap + to add a route.",
                      systemImage: "arrow.triangle.branch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(store.draft.candidateRoutes) { route in
                    routeRow(route)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        store.removeCandidateRoute(id: store.draft.candidateRoutes[idx].id)
                    }
                }
            }
        } header: {
            Text("Candidate Routes (\(store.draft.candidateRoutes.count))")
        }
    }

    // MARK: - Anchor row

    private func anchorRow(_ anchor: CapturedQuotePlannerAnchorDraft) -> some View {
        Button {
            editingAnchor = anchor
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: anchor.reviewStatus.symbolName)
                    .foregroundStyle(statusColor(anchor.reviewStatus))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(anchor.label ?? anchor.kind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(anchor.kind.displayName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        provenanceBadge(anchor.provenance)
                    }
                }

                Spacer()

                Image(systemName: anchor.kind.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.removeQuotePlannerAnchor(id: anchor.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Route row

    private func routeRow(_ route: CapturedCandidateRouteDraft) -> some View {
        Button {
            editingRoute = route
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: route.reviewStatus.symbolName)
                    .foregroundStyle(statusColor(route.reviewStatus))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(route.routeType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(route.status.displayName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if let method = route.installMethod {
                            Text(method.displayName)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        provenanceBadge(route.provenance)
                    }
                }

                Spacer()

                Image(systemName: route.routeType.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.removeCandidateRoute(id: route.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Shared helpers

    private func provenanceBadge(_ provenance: QuoteAnchorProvenance) -> some View {
        Text(provenance.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }

    private func statusColor(_ status: EvidenceReviewStatus) -> Color {
        switch status {
        case .confirmed: return .green
        case .rejected:  return .red
        case .pending:   return .orange
        }
    }
}

// MARK: - QuotePlannerAnchorEditSheet

private struct QuotePlannerAnchorEditSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var anchor: CapturedQuotePlannerAnchorDraft
    let availablePhotos: [CapturedPhotoDraft]
    let availablePins:   [CapturedObjectPinDraft]
    let onSave: (CapturedQuotePlannerAnchorDraft) -> Void

    init(
        anchor: CapturedQuotePlannerAnchorDraft,
        availablePhotos: [CapturedPhotoDraft],
        availablePins: [CapturedObjectPinDraft],
        onSave: @escaping (CapturedQuotePlannerAnchorDraft) -> Void
    ) {
        _anchor = State(initialValue: anchor)
        self.availablePhotos = availablePhotos
        self.availablePins   = availablePins
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                detailSection
                provenanceSection
                photoLinksSection
                pinLinksSection
                reviewSection
            }
            .navigationTitle("Quote Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(anchor) }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Kind

    private var kindSection: some View {
        Section {
            Picker("Kind", selection: $anchor.kind) {
                ForEach(QuoteAnchorKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                }
            }
        } header: {
            Text("Anchor Type")
        }
    }

    // MARK: - Detail

    private var detailSection: some View {
        Section {
            TextField("Label (optional)", text: Binding(
                get: { anchor.label ?? "" },
                set: { anchor.label = $0.isEmpty ? nil : $0 }
            ))
        } header: {
            Text("Label")
        } footer: {
            Text("Optionally describe this specific location (e.g. \"Kitchen boiler\").")
                .font(.caption2)
        }
    }

    // MARK: - Provenance

    private var provenanceSection: some View {
        Section {
            Picker("Placed via", selection: $anchor.provenance) {
                ForEach(QuoteAnchorProvenance.allCases) { provenance in
                    Text(provenance.displayName).tag(provenance)
                }
            }
        } header: {
            Text("Provenance")
        } footer: {
            Text("How this anchor was placed determines its default confidence for Atlas Mind.")
                .font(.caption2)
        }
    }

    // MARK: - Photo links

    private var photoLinksSection: some View {
        Section {
            if availablePhotos.isEmpty {
                Text("No photos captured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availablePhotos) { photo in
                    let isLinked = anchor.linkedPhotoIds.contains(photo.id)
                    Button {
                        togglePhotoLink(photo.id)
                    } label: {
                        HStack {
                            Text(photo.kind.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isLinked {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Linked Photos (\(anchor.linkedPhotoIds.count))")
        }
    }

    // MARK: - Pin links

    private var pinLinksSection: some View {
        Section {
            if availablePins.isEmpty {
                Text("No object pins captured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availablePins) { pin in
                    let isLinked = anchor.linkedObjectPinIds.contains(pin.id)
                    Button {
                        togglePinLink(pin.id)
                    } label: {
                        HStack {
                            Label(pin.label ?? pin.type.displayName,
                                  systemImage: pin.type.symbolName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isLinked {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Linked Object Pins (\(anchor.linkedObjectPinIds.count))")
        }
    }

    // MARK: - Review

    private var reviewSection: some View {
        Section {
            Picker("Review Status", selection: $anchor.reviewStatus) {
                ForEach(EvidenceReviewStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
        } header: {
            Text("Review Status")
        }
    }

    // MARK: - Helpers

    private func togglePhotoLink(_ id: UUID) {
        if let idx = anchor.linkedPhotoIds.firstIndex(of: id) {
            anchor.linkedPhotoIds.remove(at: idx)
        } else {
            anchor.linkedPhotoIds.append(id)
        }
    }

    private func togglePinLink(_ id: UUID) {
        if let idx = anchor.linkedObjectPinIds.firstIndex(of: id) {
            anchor.linkedObjectPinIds.remove(at: idx)
        } else {
            anchor.linkedObjectPinIds.append(id)
        }
    }
}

// MARK: - CandidateRouteEditSheet

private struct CandidateRouteEditSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var route: CapturedCandidateRouteDraft
    let availableAnchors: [CapturedQuotePlannerAnchorDraft]
    let onSave: (CapturedCandidateRouteDraft) -> Void

    init(
        route: CapturedCandidateRouteDraft,
        availableAnchors: [CapturedQuotePlannerAnchorDraft],
        onSave: @escaping (CapturedCandidateRouteDraft) -> Void
    ) {
        _route = State(initialValue: route)
        self.availableAnchors = availableAnchors
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                routeTypeSection
                statusSection
                installMethodSection
                anchorLinksSection
                notesSection
                provenanceSection
                reviewSection
            }
            .navigationTitle("Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(route) }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Route type

    private var routeTypeSection: some View {
        Section {
            Picker("Route Type", selection: $route.routeType) {
                ForEach(CandidateRouteType.allCases) { type in
                    Label(type.displayName, systemImage: type.symbolName).tag(type)
                }
            }
        } header: {
            Text("Route Type")
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            Picker("Status", selection: $route.status) {
                ForEach(CandidateRouteStatus.allCases) { status in
                    Label(status.displayName, systemImage: status.symbolName).tag(status)
                }
            }
        } header: {
            Text("Route Status")
        }
    }

    // MARK: - Install method

    private var installMethodSection: some View {
        Section {
            Picker("Install Method", selection: Binding(
                get: { route.installMethod ?? .unknown },
                set: { route.installMethod = $0 == .unknown ? nil : $0 }
            )) {
                Text("Not specified").tag(CandidateRouteInstallMethod.unknown)
                ForEach(CandidateRouteInstallMethod.allCases.filter { $0 != .unknown }) { method in
                    Text(method.displayName).tag(method)
                }
            }
        } header: {
            Text("Install Method")
        } footer: {
            Text("Optional — record how the pipe or service would be routed.")
                .font(.caption2)
        }
    }

    // MARK: - Anchor links (start / end)

    private var anchorLinksSection: some View {
        Section {
            if availableAnchors.isEmpty {
                Text("No quote points captured yet. Add anchors first to link start/end points.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Start anchor picker
                Picker("Start Point", selection: $route.startAnchorId) {
                    Text("None").tag(nil as UUID?)
                    ForEach(availableAnchors) { anchor in
                        Text(anchor.label ?? anchor.kind.displayName).tag(anchor.id as UUID?)
                    }
                }

                // End anchor picker
                Picker("End Point", selection: $route.endAnchorId) {
                    Text("None").tag(nil as UUID?)
                    ForEach(availableAnchors) { anchor in
                        Text(anchor.label ?? anchor.kind.displayName).tag(anchor.id as UUID?)
                    }
                }
            }
        } header: {
            Text("Start & End Anchors")
        } footer: {
            Text("Link to quote points to describe where this route runs.")
                .font(.caption2)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section {
            TextField("Notes (optional)", text: $route.notes, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("Notes")
        } footer: {
            Text("Routing constraints, pipe sizing observations, etc.")
                .font(.caption2)
        }
    }

    // MARK: - Provenance

    private var provenanceSection: some View {
        Section {
            Picker("Recorded via", selection: $route.provenance) {
                ForEach(QuoteAnchorProvenance.allCases) { provenance in
                    Text(provenance.displayName).tag(provenance)
                }
            }
        } header: {
            Text("Provenance")
        } footer: {
            Text("How this route evidence was recorded determines its default confidence for Atlas Mind.")
                .font(.caption2)
        }
    }

    // MARK: - Review

    private var reviewSection: some View {
        Section {
            Picker("Review Status", selection: $route.reviewStatus) {
                ForEach(EvidenceReviewStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
        } header: {
            Text("Review Status")
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = CaptureSessionStore(
        draft: CaptureSessionStore.newSession(visitReference: "PREVIEW-QP-001")
    )
    NavigationStack {
        QuotePlannerCaptureView(store: store)
    }
}
#endif
