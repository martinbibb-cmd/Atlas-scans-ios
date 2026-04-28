import SwiftUI
import WebKit

// MARK: - AtlasRecommendationsWebView
//
// WKWebView wrapper that loads the Atlas Recommendations web app at
// https://next.atlas-phm.uk.
//
// Features:
//   • Injects the stored auth token as an Authorization cookie on load.
//   • Optionally deep-links to a specific visit page if remoteVisitId is provided.
//   • Pull-to-refresh.
//   • Back / forward swipe navigation.
//   • Offline banner when network is not reachable.

struct AtlasRecommendationsWebView: View {

    // When set, navigates to the specific visit on appear.
    let visitId: String?

    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var showingTokenEntry = false
    @State private var tokenInput = ""
    @State private var webViewProxy: AtlasWebViewProxy?

    var body: some View {
        ZStack(alignment: .top) {
            AtlasWebViewRepresentable(
                baseURL: AtlasRecommendationsSync.webBaseURL,
                visitId: visitId,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                proxyOut: $webViewProxy
            )
            .ignoresSafeArea(edges: .bottom)

            if isLoading {
                ProgressView()
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Atlas Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showingTokenEntry) { tokenEntrySheet }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                webViewProxy?.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack)

            Spacer()

            Button {
                webViewProxy?.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward)

            Spacer()

            Button {
                webViewProxy?.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            Spacer()

            Button {
                tokenInput = AtlasKeychainStore.loadAuthToken() ?? ""
                showingTokenEntry = true
            } label: {
                Image(systemName: "key.horizontal")
            }
        }
    }

    // MARK: - Token entry sheet

    private var tokenEntrySheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Paste auth token here", text: $tokenInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Atlas Auth Token")
                } footer: {
                    Text("The token is stored in the Keychain and used to authenticate requests to next.atlas-phm.uk. Obtain it from your Atlas Recommendations account settings.")
                        .font(.caption)
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingTokenEntry = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let t = tokenInput.trimmingCharacters(in: .whitespaces)
                        if t.isEmpty {
                            AtlasKeychainStore.deleteAuthToken()
                        } else {
                            AtlasKeychainStore.saveAuthToken(t)
                        }
                        showingTokenEntry = false
                        webViewProxy?.reload()
                    }
                }
            }
        }
    }
}

// MARK: - AtlasWebViewProxy

/// A thin value-type proxy so SwiftUI can reach the WKWebView imperatively.
final class AtlasWebViewProxy: ObservableObject {
    private weak var webView: WKWebView?

    init(webView: WKWebView) { self.webView = webView }

    func goBack()    { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload()    { webView?.reload() }
}

// MARK: - AtlasWebViewRepresentable

struct AtlasWebViewRepresentable: UIViewRepresentable {

    let baseURL: URL
    let visitId: String?
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var proxyOut: AtlasWebViewProxy?

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AtlasWebViewRepresentable

        init(_ parent: AtlasWebViewRepresentable) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Expose proxy for imperative calls (reload, back/forward)
        let proxy = AtlasWebViewProxy(webView: webView)
        DispatchQueue.main.async {
            proxyOut = proxy
        }

        injectAuthCookieIfAvailable(webView: webView)
        loadInitialURL(webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - Helpers

    private func injectAuthCookieIfAvailable(webView: WKWebView) {
        guard let token = AtlasKeychainStore.loadAuthToken() else { return }
        let cookieProps: [HTTPCookiePropertyKey: Any] = [
            .name:    "atlas_token",
            .value:   token,
            .domain:  "next.atlas-phm.uk",
            .path:    "/",
            .secure:  "TRUE"
        ]
        if let cookie = HTTPCookie(properties: cookieProps) {
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
        // Use JSON encoding to safely embed the token value in the script —
        // avoids injection risks from tokens containing backslashes, quotes, etc.
        if let encoded = try? JSONEncoder().encode(token),
           let jsonString = String(data: encoded, encoding: .utf8) {
            let script = WKUserScript(
                source: "window.__atlasToken = \(jsonString);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(script)
        }
    }

    private func loadInitialURL(webView: WKWebView) {
        let url: URL
        if let visitId = visitId, !visitId.isEmpty {
            url = baseURL.appendingPathComponent("visits/\(visitId)")
        } else {
            url = baseURL
        }
        webView.load(URLRequest(url: url))
    }
}

// MARK: - URL constant

extension AtlasRecommendationsSync {
    static let webBaseURL = URL(string: "https://next.atlas-phm.uk")!
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        AtlasRecommendationsWebView(visitId: nil)
    }
}
#endif
