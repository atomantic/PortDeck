import SwiftUI
import WebKit

struct RemoteDesktopDestination: Identifiable {
    let id = UUID()
    let instanceName: String
    let url: URL
    var tunnelToken: String? = nil
}

struct RemoteDesktopView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let destination: RemoteDesktopDestination

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RemoteDesktopWebView(url: destination.url, tunnelToken: destination.tunnelToken)
                .ignoresSafeArea()
                .accessibilityLabel("Remote desktop for \(destination.instanceName)")

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(.primary)
            .padding(.top, 8)
            .padding(.trailing, 10)
            .accessibilityLabel("Close remote desktop")
        }
        .background(Color.black)
        .statusBarHidden()
        .onChange(of: scenePhase) {
            if scenePhase == .background && destination.tunnelToken != nil { dismiss() }
        }
    }
}

private struct RemoteDesktopWebView: UIViewRepresentable {
    let url: URL
    let tunnelToken: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        context.coordinator.loadedURL = url
        load(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        load(webView)
    }

    private func load(_ webView: WKWebView) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let tunnelToken else { webView.load(request); return }
        // A separate non-persistent data store per viewer prevents localhost
        // cookies from crossing profiles. The cookie also admits WebSockets and
        // same-origin subresources after the initial authorized navigation.
        request.setValue(tunnelToken, forHTTPHeaderField: "X-PortDeck-Tunnel")
        guard let cookie = HTTPCookie(properties: [
            .name: "PortDeckTunnel", .value: tunnelToken, .domain: "127.0.0.1",
            .path: "/", .discard: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ]) else { return }
        webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
            webView.load(request)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let destination = navigationAction.request.url, let loadedURL else {
                decisionHandler(.cancel)
                return
            }
            let sameOrigin = destination.scheme == loadedURL.scheme
                && destination.host == loadedURL.host
                && destination.port == loadedURL.port
            decisionHandler(sameOrigin ? .allow : .cancel)
        }
    }
}
