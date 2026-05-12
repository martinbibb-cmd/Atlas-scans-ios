/// SurveyHomeView — The visit-level home screen of the new continuous-
/// survey shell.
///
/// Layout (top → bottom):
///   - Visit header (workspace + visit reference + property address)
///   - Room list (visible rooms only — suggested/discarded are hidden)
///   - Three primary buttons: Continue Survey / Review Evidence / Finish Survey
///   - Footer toolbar: Save & Exit · Visit Notes · (DEBUG) Debug
///
/// The "Finish Survey" action is *always* enabled, even with zero rooms —
/// incomplete handoffs are valid (`completionStatus == .incompleteDraft`).

import SwiftUI
import AtlasScanCore

struct SurveyHomeView: View {

    @ObservedObject public var viewModel: SurveyHomeViewModel

    let onContinueSurvey: () -> Void
    let onReviewEvidence: () -> Void
    let onFinishSurvey: () -> Void
    let onSaveAndExit: () -> Void
    let onOpenVisitNotes: () -> Void
    let onOpenDebug: () -> Void

    init(
        viewModel: SurveyHomeViewModel,
        onContinueSurvey: @escaping () -> Void,
        onReviewEvidence: @escaping () -> Void,
        onFinishSurvey: @escaping () -> Void,
        onSaveAndExit: @escaping () -> Void,
        onOpenVisitNotes: @escaping () -> Void,
        onOpenDebug: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onContinueSurvey = onContinueSurvey
        self.onReviewEvidence = onReviewEvidence
        self.onFinishSurvey = onFinishSurvey
        self.onSaveAndExit = onSaveAndExit
        self.onOpenVisitNotes = onOpenVisitNotes
        self.onOpenDebug = onOpenDebug
    }

    var body: some View {
        VStack(spacing: 0) {
            visitHeader
            roomList
            primaryActions
        }
        .navigationTitle("Survey")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    // MARK: - Header

    private var visitHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let workspace = viewModel.workspace {
                Text(workspace.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let visit = viewModel.visit {
                Text(visit.visitReference)
                    .font(.title3.weight(.semibold))
                if let address = visit.propertyAddress, !address.isEmpty {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No visit selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            statusBadge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }

    private var statusBadge: some View {
        Text(viewModel.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
    }

    // MARK: - Room list

    private var roomList: some View {
        List {
            Section {
                if viewModel.visibleRooms.isEmpty {
                    Text("No rooms captured yet — tap Continue Survey to start.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.visibleRooms, id: \.id) { room in
                        SurveyHomeRoomRow(room: room)
                    }
                }
            } header: {
                HStack {
                    Text("Rooms")
                    Spacer()
                    if viewModel.hasNeedsReviewRooms {
                        Label("Needs review", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Primary actions

    private var primaryActions: some View {
        VStack(spacing: 8) {
            Button(action: onContinueSurvey) {
                Label("Continue Survey", systemImage: "video.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: onReviewEvidence) {
                Label("Review Evidence", systemImage: "list.bullet.rectangle.portrait")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(action: onFinishSurvey) {
                Label("Finish Survey", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.canFinish)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Save & Exit", action: onSaveAndExit)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                onOpenVisitNotes()
            } label: {
                Image(systemName: "note.text")
            }
            #if DEBUG
            Button {
                onOpenDebug()
            } label: {
                Image(systemName: "ladybug")
            }
            #endif
        }
    }
}

// MARK: - Room row

private struct SurveyHomeRoomRow: View {
    let room: RoomCaptureV2

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(roomTitle)
                    .font(.body)
                Text(room.captureStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if room.captureStatus == .needsReview {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var roomTitle: String {
        let trimmed = room.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled room" : trimmed
    }
}
