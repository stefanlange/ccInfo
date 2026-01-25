import SwiftUI
import WebKit

struct AuthWebView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Claude").font(.headline)
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.7) }
            }.padding()
            Divider()
            AuthWebViewRepresentable(onCredentials: { handleCredentials($0) }, onLoading: { isLoading = $0 })
        }
        .frame(width: 500, height: 600)
        .onDisappear { appState.showingAuth = false }
    }

    private func handleCredentials(_ credentials: ClaudeCredentials) {
        appState.signIn(credentials: credentials)
        dismiss()
    }
}

struct AuthWebViewRepresentable: NSViewRepresentable {
    let onCredentials: (ClaudeCredentials) -> Void
    let onLoading: (Bool) -> Void
    
    private static let loginURL = URL(string: "https://claude.ai/login")!

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.startObserving(webView)
        webView.load(URLRequest(url: Self.loginURL))
        return webView
    }
    func updateNSView(_ webView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: AuthWebViewRepresentable
        private var credentialsExtracted = false
        private weak var webView: WKWebView?
        private var urlObservation: NSKeyValueObservation?

        init(_ parent: AuthWebViewRepresentable) { self.parent = parent }

        func startObserving(_ webView: WKWebView) {
            self.webView = webView
            // Observe URL changes via KVO (catches SPA navigation)
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                self?.checkURL(webView.url)
            }
        }

        private func checkURL(_ url: URL?) {
            guard !credentialsExtracted, let url, let host = url.host, host.contains("claude.ai") else { return }
            // Skip auth flow pages - wait for final destination
            let skipPaths = ["login", "sso-callback", "oauth"]
            if skipPaths.contains(where: { url.path.contains($0) }) { return }
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
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.credentialsExtracted else { return }

                var sessionKey: String?
                var orgId: String?

                for cookie in cookies where cookie.domain.contains("claude.ai") {
                    if cookie.name == "sessionKey" {
                        sessionKey = cookie.value
                    } else if cookie.name == "lastActiveOrg" {
                        orgId = cookie.value
                    }
                }

                guard let sk = sessionKey, let oi = orgId else { return }

                self.credentialsExtracted = true
                DispatchQueue.main.async {
                    self.parent.onCredentials(ClaudeCredentials(sessionKey: sk, organizationId: oi, createdAt: Date()))
                }
            }
        }

    }
}
