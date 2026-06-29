import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let html: String
    let holder: WebViewHolder

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        // This view only renders static, locally-produced HTML, so disable
        // JavaScript entirely. Combined with the page's Content-Security-Policy,
        // it stops scripts embedded in untrusted .md files from executing.
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        holder.webView = webView
        // pageZoom survives loadHTMLString, so apply the persisted zoom once here.
        holder.applyStoredZoom()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        // Open clicked links in the default browser instead of navigating the viewer.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
