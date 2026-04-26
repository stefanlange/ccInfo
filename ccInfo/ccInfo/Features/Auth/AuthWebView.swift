import SwiftUI
import WebKit
import OSLog

struct AuthWebView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Claude").font(.headline)
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.7) }
                Button {
                    appState.authReloadToken &+= 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload")
            }.padding()
            Divider()
            AuthWebViewRepresentable(
                onCredentials: { handleCredentials($0) },
                onLoading: { isLoading = $0 },
                dataStore: appState.authWebsiteDataStore,
                reloadToken: appState.authReloadToken
            )
        }
        .frame(width: 500, height: 600)
        .onDisappear { appState.showingAuth = false }
    }

    private func handleCredentials(_ credentials: ClaudeCredentials) {
        appState.signIn(credentials: credentials)
        dismiss()
    }
}

/// Defers the initial load until AppKit has assigned a real frame. Loading
/// at construction time leaves WebKit's first layout pass with a 0×0 viewport,
/// which renders an empty page that only a manual reload escapes.
final class AuthWKWebView: WKWebView {
    var pendingRequest: URLRequest?
    override func layout() {
        super.layout()
        if let req = pendingRequest, bounds.width > 0 {
            pendingRequest = nil
            load(req)
        }
    }
}

struct AuthWebViewRepresentable: NSViewRepresentable {
    let onCredentials: (ClaudeCredentials) -> Void
    let onLoading: (Bool) -> Void
    let dataStore: WKWebsiteDataStore
    let reloadToken: Int

    // Static URL is guaranteed valid - using compile-time initialization
    static let loginURL = URL(string: "https://claude.ai/login")! // swiftlint:disable:this force_unwrapping

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        let webView = AuthWKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 550), configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.startObserving(webView)
        context.coordinator.lastReloadToken = reloadToken
        webView.pendingRequest = URLRequest(url: Self.loginURL)
        return webView
    }
    func updateNSView(_ webView: WKWebView, context: Context) {
        if reloadToken != context.coordinator.lastReloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.credentialsExtracted = false
            (webView as? AuthWKWebView)?.pendingRequest = nil
            webView.load(URLRequest(url: Self.loginURL))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: AuthWebViewRepresentable
        var credentialsExtracted = false
        var lastReloadToken: Int = 0
        private weak var webView: WKWebView?
        private var urlObservation: NSKeyValueObservation?
        private let logger = Logger(subsystem: "com.ccinfo.app", category: "Auth")

        init(_ parent: AuthWebViewRepresentable) { self.parent = parent }

        func startObserving(_ webView: WKWebView) {
            self.webView = webView
            // Observe URL changes via KVO (catches SPA navigation)
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                self?.checkURL(webView.url)
            }
        }

        private func checkURL(_ url: URL?) {
            guard !credentialsExtracted, let url, let host = url.host else { return }
            logger.debug("checkURL host=\(host, privacy: .public) path=\(url.path, privacy: .public)")
            guard host.contains("claude.ai") else { return }
            let skipPaths = ["login", "sso-callback", "oauth"]
            if skipPaths.contains(where: { url.path.contains($0) }) {
                logger.debug("checkURL: skipping auth-flow path \(url.path, privacy: .public)")
                return
            }
            if let webView {
                extractCredentials(from: webView)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoading(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoading(false)
        }

        private func extractCredentials(from webView: WKWebView) {
            let urlString = webView.url?.absoluteString ?? "<no URL>"
            let tokenAtCall = lastReloadToken
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                Task { @MainActor [weak self] in
                    guard let self,
                          !self.credentialsExtracted,
                          self.lastReloadToken == tokenAtCall else { return }

                    let summary = cookies.map { "\($0.name)@\($0.domain)(\($0.value.count)b)" }.joined(separator: ", ")
                    self.logger.debug("extractCredentials at \(urlString, privacy: .public): \(cookies.count) cookies → [\(summary, privacy: .public)]")

                    var sessionKey: String?
                    var orgId: String?

                    // Only accept cookies from official Claude.ai domain (exact match for security)
                    let validDomains = ["claude.ai", ".claude.ai"]
                    for cookie in cookies where validDomains.contains(cookie.domain) {
                        if cookie.name == "sessionKey" {
                            sessionKey = cookie.value
                        } else if cookie.name == "lastActiveOrg" {
                            orgId = cookie.value
                        }
                    }

                    guard let sk = sessionKey, let oi = orgId else {
                        self.logger.warning("extractCredentials: missing required cookies (sessionKey present: \(sessionKey != nil), lastActiveOrg present: \(orgId != nil))")
                        return
                    }

                    self.credentialsExtracted = true

                    // Fetch organization name (best-effort)
                    let fetchedOrgName: String?
                    do {
                        fetchedOrgName = try await ClaudeAPIClient.fetchOrganizationName(organizationId: oi, sessionKey: sk)
                    } catch {
                        fetchedOrgName = nil
                        self.logger.warning("Failed to fetch organization name: \(error.localizedDescription)")
                    }

                    self.parent.onCredentials(ClaudeCredentials(
                        sessionKey: sk,
                        organizationId: oi,
                        organizationName: fetchedOrgName,
                        createdAt: Date()
                    ))
                }
            }
        }

    }
}
