import SwiftUI

// MARK: - VisitCaptureRootView

/// Root view for the single-session visit capture experience.
///
/// Provides two navigation modes:
///   1. Swipe — PageTabView so engineers can swipe left/right between screens.
///   2. Direct — Segmented picker in the toolbar for one-tap access to any screen.
///
/// All screens share one `VisitCaptureViewModel` backed by one `PropertyScanSession`.
/// Switching screens never creates a separate session or session fragment.
struct VisitCaptureRootView: View {

    @StateObject private var viewModel: VisitCaptureViewModel
    @StateObject private var coordinator: VisitCaptureCoordinator

    init(session: PropertyScanSession, sessionStore: ScanSessionStore, atlasSync: AtlasSync) {
        let vm = VisitCaptureViewModel(session: session, sessionStore: sessionStore, atlasSync: atlasSync)
        _viewModel = StateObject(wrappedValue: vm)
        _coordinator = StateObject(wrappedValue: VisitCaptureCoordinator(viewModel: vm))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                tabContent
            }
            .navigationTitle(viewModel.session.propertyAddress)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
    }

    // MARK: - Tab content (swipe)

    private var tabContent: some View {
        TabView(selection: $viewModel.activeScreen) {
            VisitOverviewView(viewModel: viewModel)
                .tag(VisitCaptureScreen.overview)

            VisitLiDARScreenView(viewModel: viewModel)
                .tag(VisitCaptureScreen.lidar)

            VisitPhotosScreenView(viewModel: viewModel)
                .tag(VisitCaptureScreen.photos)

            VisitVoiceScreenView(viewModel: viewModel)
                .tag(VisitCaptureScreen.voice)

            VisitObjectsScreenView(viewModel: viewModel)
                .tag(VisitCaptureScreen.objects)

            VisitSummaryView(viewModel: viewModel)
                .tag(VisitCaptureScreen.summary)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        // Screen title + save indicator
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(viewModel.activeScreen.title)
                    .font(.headline)
                saveStateBadge
            }
        }

        // Segmented screen picker
        ToolbarItem(placement: .bottomBar) {
            screenPicker
        }
    }

    @ViewBuilder
    private var saveStateBadge: some View {
        switch viewModel.saveState {
        case .unsaved:
            Text("Unsaved")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .saving:
            Text("Saving…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .saved:
            Text("Saved")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var screenPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(VisitCaptureScreen.allCases, id: \.self) { screen in
                    screenTab(screen)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }

    private func screenTab(_ screen: VisitCaptureScreen) -> some View {
        let isActive = viewModel.activeScreen == screen
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.navigate(to: screen)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: screen.symbolName)
                    .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                Text(screen.shortLabel)
                    .font(.system(size: 9, weight: isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.12))
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    let session = PropertyScanSession(
        jobReference: "JOB-001",
        propertyAddress: "12 Coronation Street"
    )
    return VisitCaptureRootView(
        session: session,
        sessionStore: store,
        atlasSync: AtlasSync()
    )
}
#endif
