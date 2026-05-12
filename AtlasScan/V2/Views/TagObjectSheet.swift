/// TagObjectSheet — UI surfaced when the user taps Tag in
/// `CaptureBottomBar`. Lets the engineer pick an `EquipmentObjectCategory`,
/// attempt a raycast (handled by the parent), and optionally link a photo.
///
/// The sheet itself does not own raycast state — the parent provides the
/// resolved `AnchorConfidence` (and optional `WorldTransform`/`ScreenPosition`
/// elements) when the user commits. This keeps the sheet free of ARKit
/// imports and reusable in unit tests.

import SwiftUI

public struct TagObjectSheet: View {

    public let initialCategory: EquipmentObjectCategory
    public let availableConfidences: [AnchorConfidence]

    /// Called when the user commits the tag with a chosen category and the
    /// best anchor confidence the parent could resolve.
    public let onCommit: (EquipmentObjectCategory, AnchorConfidence, String?) -> Void
    public let onCancel: () -> Void

    @State private var category: EquipmentObjectCategory
    @State private var confidence: AnchorConfidence
    @State private var label: String = ""

    public init(
        initialCategory: EquipmentObjectCategory = .other,
        availableConfidences: [AnchorConfidence] = [.worldLocked, .raycastEstimated, .screenOnly, .manual],
        onCommit: @escaping (EquipmentObjectCategory, AnchorConfidence, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialCategory = initialCategory
        self.availableConfidences = availableConfidences
        self.onCommit = onCommit
        self.onCancel = onCancel
        _category = State(initialValue: initialCategory)
        _confidence = State(initialValue: availableConfidences.first ?? .raycastEstimated)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Object") {
                    Picker("Category", selection: $category) {
                        ForEach(EquipmentObjectCategory.allCases, id: \.self) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                    TextField("Optional label", text: $label)
                        .textInputAutocapitalization(.sentences)
                }

                Section {
                    Picker("Anchor", selection: $confidence) {
                        ForEach(availableConfidences, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    if confidence.requiresReview {
                        Label("This pin will be flagged for review.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Anchor confidence")
                } footer: {
                    Text("World-locked pins re-appear in AR on room re-entry. Screen-only and manual pins surface in the review screen instead.")
                }

                Section {
                    Button {
                        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCommit(category, confidence, trimmed.isEmpty ? nil : trimmed)
                    } label: {
                        Label("Tag this object", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Tag object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
