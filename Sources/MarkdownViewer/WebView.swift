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
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload only when the rendered HTML actually changed: a reload throws
        // away the scroll position and the find-in-page highlight, and now that
        // the find bar's state lives in the same view, this view can be updated
        // for reasons that have nothing to do with the content.
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// The HTML currently loaded in the web view, so `updateNSView` can tell a
        /// real content change from a re-render triggered by unrelated state.
        var loadedHTML: String?

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
