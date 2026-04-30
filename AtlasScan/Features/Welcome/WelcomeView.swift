import SwiftUI
import AtlasContracts

// MARK: - HomeView
//
// Atlas Scan home screen.
//
// Three navigation paths:
//   • Open Atlas Mind          → full-screen Atlas Recommendations WebView
//   • Start Local Capture Visit → sheet to enter visit number, then VisitDetailView
//   • Saved Visits              → full-screen list of persisted local visits
//
// Developer mode:
//   Tap the "Atlas Scan" version label seven times to toggle developer mode.
//   A subtle banner confirms the toggle.
//
// URL scheme:
//   atlasscan://?visitId=<ref>         → open / create a visit by reference
//   atlasscan://?handoff=<base64-pack> → receive VisitHandoffPackV1 from Mind

struct HomeView: View {

    @StateObject private var developerMode = DeveloperModeStore.shared

    @State private var showingMind        = false
    @State private var mindVisitId: String?

    @State private var showingNewVisit    = false
    @State private var showingSavedVisits = false
    @State private var openVisit: CaptureSessionDraft?

    // Dev-mode unlock tap counter
    @State private var devTapCount  = 0
    @State private var showDevToast = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Header
                VStack(spacing: 8) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(.tint)
                        .padding(.top, 60)

                    Text("Atlas")
                        .font(.system(size: 48, weight: .bold, design: .rounded))

                    Text("Choose how you'd like to work today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 48)

                // MARK: Action tiles
                VStack(spacing: 16) {
                    HomeCard(
                        title: "Open Atlas Mind",
                        subtitle: "View recommendations, reports and visit history.",
                        symbolName: "brain.head.profile",
                        accentColor: .purple
                    ) { showingMind = true }

                    HomeCard(
                        title: "Start Local Capture Visit",
                        subtitle: "Begin a new on-site evidence capture visit.",
                        symbolName: "camera.viewfinder",
                        accentColor: .blue
                    ) { showingNewVisit = true }

                    HomeCard(
                        title: "Saved Visits",
                        subtitle: "Reopen, review or export a previous visit.",
                        symbolName: "tray.2",
                        accentColor: .green
                    ) { showingSavedVisits = true }
                }
                .padding(.horizontal, 24)

                Spacer()

                // MARK: Version tag (tap 7× to toggle developer mode)
                VStack(spacing: 4) {
                    Text("Atlas Scan")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .onTapGesture { handleDevTap() }

                    if developerMode.isEnabled {
                        Label("Developer Mode", systemImage: "wrench.and.screwdriver")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        // Atlas Mind — full-screen WebView
        .fullScreenCover(isPresented: $showingMind) {
            MindRootView(visitId: mindVisitId) {
                showingMind = false
                mindVisitId = nil
            }
        }
        // New visit flow — sheet to enter reference, then full-screen detail
        .sheet(isPresented: $showingNewVisit) {
            StartVisitView { draft in
                showingNewVisit = false
                openVisit = draft
            }
        }
        // Open a specific visit (from new-visit or from saved-visits or URL)
        .fullScreenCover(item: $openVisit) { draft in
            VisitDetailView(initialDraft: draft) {
                openVisit = nil
            }
        }
        // Saved visits list
        .fullScreenCover(isPresented: $showingSavedVisits) {
            SavedVisitsView(
                onOpen: { draft in
                    showingSavedVisits = false
                    openVisit = draft
                },
                onClose: { showingSavedVisits = false }
            )
        }
        // Developer mode toast overlay
        .overlay(alignment: .bottom) {
            if showDevToast {
                Text(developerMode.isEnabled ? "Developer mode on" : "Developer mode off")
                    .font(.caption.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 60)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showDevToast)
        // URL scheme handler: atlasscan://?visitId=<ref>&handoff=<base64>
        .onOpenURL { url in
            handleIncomingURL(url)
        }
    }

    // MARK: - Developer mode tap counter

    private func handleDevTap() {
        devTapCount += 1
        if devTapCount >= 7 {
            devTapCount = 0  // Reset immediately so any taps during the toast start a fresh sequence
            developerMode.toggle()
            showDevToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showDevToast = false
            }
        }
    }

    // MARK: - URL scheme handling

    private func handleIncomingURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let params = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )

        // Handle ?handoff=<base64-encoded-VisitHandoffPackV1>
        if let encoded = params["handoff"],
           let pack = decodeHandoffPack(encoded) {
            openOrCreateVisit(
                visitReference: pack.visitReference,
                propertyAddress: pack.propertyAddress,
                customerName: pack.customerName
            )
            return
        }

        // Handle ?visitId=<visitReference>
        if let visitId = params["visitId"], !visitId.isEmpty {
            openOrCreateVisit(visitReference: visitId, propertyAddress: nil, customerName: nil)
        }
    }

    private func openOrCreateVisit(
        visitReference: String,
        propertyAddress: String?,
        customerName: String?
    ) {
        // Try to find an existing local draft with this reference.
        let all = CaptureSessionPersistence.shared.loadAll()
        if let existing = all.first(where: { $0.visitReference == visitReference }) {
            openVisit = existing
            return
        }

        // No existing draft — create a new session stub.
        var draft = CaptureSessionStore.newSession(visitReference: visitReference)
        if let addr = propertyAddress, !addr.isEmpty { draft.propertyAddress = addr }
        if let name = customerName, !name.isEmpty { draft.customerName = name }
        let store = CaptureSessionStore(draft: draft, persistence: .shared)
        store.saveNow()
        openVisit = store.draft
    }
}

// MARK: - HomeCard

private struct HomeCard: View {

    let title: String
    let subtitle: String
    let symbolName: String
    let accentColor: Color
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: symbolName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(accentColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeIn(duration: 0.05)) { isPressed = true } }
                .onEnded   { _ in withAnimation(.easeOut(duration: 0.15)) { isPressed = false } }
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    HomeView()
}
#endif
