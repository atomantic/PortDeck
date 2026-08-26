import SwiftUI
import WebKit

struct RemoteDesktopDestination: Identifiable {
    let id = UUID()
    let instanceName: String
    let url: URL
}

struct RemoteDesktopView: View {
    @Environment(\.dismiss) private var dismiss
    let destination: RemoteDesktopDestination

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RemoteDesktopWebView(url: destination.url)
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
    }
}

private struct RemoteDesktopWebView: UIViewRepresentable {
    let url: URL

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
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
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
