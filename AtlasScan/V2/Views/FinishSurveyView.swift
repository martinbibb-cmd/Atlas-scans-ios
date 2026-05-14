/// FinishSurveyView — End-of-survey confirmation screen with the four
/// actions described in the brief.

import SwiftUI
import AtlasScanCore

public struct FinishSurveyView: View {

    @ObservedObject public var viewModel: FinishSurveyViewModel

    public let onSendToMind: () -> Void
    public let onSaveAndContinueLater: () -> Void
    public let onDiscard: () -> Void
    public let onBackToSurvey: () -> Void

    @State private var showDiscardConfirm = false

    public init(
        viewModel: FinishSurveyViewModel,
        onSendToMind: @escaping () -> Void,
        onSaveAndContinueLater: @escaping () -> Void,
        onDiscard: @escaping () -> Void,
        onBackToSurvey: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSendToMind = onSendToMind
        self.onSaveAndContinueLater = onSaveAndContinueLater
        self.onDiscard = onDiscard
        self.onBackToSurvey = onBackToSurvey
    }

    public var body: some View {
        Form {
            summarySection
            notesSection
            if let error = viewModel.sendError, !error.isEmpty {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
            actionsSection
        }
        .navigationTitle("Finish Survey")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", action: onBackToSurvey)
            }
        }
        .confirmationDialog(
            "Discard this survey?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive, action: onDiscard)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All captured rooms, photos, and notes will be removed from this device. This cannot be undone.")
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            HStack {
                Text("Captured rooms")
                Spacer()
                Text("\(viewModel.capturedRooms.count)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Needs review")
                Spacer()
                Text("\(viewModel.needsReviewRooms.count)")
                    .foregroundStyle(viewModel.needsReviewRooms.isEmpty ? Color.secondary : Color.orange)
            }
            HStack {
                Text("Photos")
                Spacer()
                Text("\(viewModel.session.photos.count)")
                    .foregroundStyle(.secondary)
            }
            if viewModel.willBeIncompleteDraft {
                Label("This will be sent as an incomplete draft.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var notesSection: some View {
        Section("Engineer notes") {
            TextEditor(text: $viewModel.engineerNotes)
                .frame(minHeight: 80)
        }
    }

    private var actionsSection: some View {
        Section {
            Button(action: onSendToMind) {
                Label("Send to Atlas Mind", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)

            Button(action: onSaveAndContinueLater) {
                Label("Save & Continue Later", systemImage: "tray.and.arrow.down")
            }

            Button(role: .destructive) {
                showDiscardConfirm = true
            } label: {
                Label("Discard Survey", systemImage: "trash")
            }

            Button(action: onBackToSurvey) {
                Label("Back to Survey", systemImage: "arrow.uturn.backward")
            }
        }
    }
}
