import SwiftUI

// MARK: - VisitCaptureCoordinatorAction

/// Navigation actions emitted by child capture screens.
///
/// Child screens post these actions; `VisitCaptureCoordinator` decides
/// which screen to navigate to or which sheet to present.
enum VisitCaptureCoordinatorAction {
    case switchScreen(VisitCaptureScreen)
    case startRoomScan
    case addObject
    case addPhoto
    case recordVoiceNote
    case finishSession
}

// MARK: - VisitCaptureCoordinator

/// Coordinates navigation between visit capture screens and cross-screen modals.
///
/// Lives inside `VisitCaptureRootView` and receives actions from child screens.
/// Keeps navigation logic out of individual screen views.
@MainActor
final class VisitCaptureCoordinator: ObservableObject {

    // MARK: Sheet presentation flags

    @Published var showingRoomScan = false
    @Published var showingAddObject = false
    @Published var showingAddPhoto = false
    @Published var showingRecordVoiceNote = false
    @Published var showingFinishConfirm = false

    // MARK: Weak reference to the parent ViewModel

    private weak var viewModel: VisitCaptureViewModel?

    // MARK: Init

    init(viewModel: VisitCaptureViewModel) {
        self.viewModel = viewModel
    }

    // MARK: Handle action

    func handle(_ action: VisitCaptureCoordinatorAction) {
        switch action {
        case .switchScreen(let screen):
            viewModel?.navigate(to: screen)

        case .startRoomScan:
            showingRoomScan = true

        case .addObject:
            showingAddObject = true

        case .addPhoto:
            showingAddPhoto = true

        case .recordVoiceNote:
            showingRecordVoiceNote = true

        case .finishSession:
            showingFinishConfirm = true
        }
    }
}
