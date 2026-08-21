import SwiftUI
import AppKit
import WebKit

/// Find-in-page for one document window.
///
/// This drives `WKWebView`'s **native** find — WebKit's own text search, not
/// injected script — so it keeps working with `allowsContentJavaScript = false`
/// and needs no relaxation of the page's Content-Security-Policy. The hardened
/// rendering surface is untouched.
///
/// `WKFindResult` reports only *whether* something matched, so the bar shows
/// "Not found" rather than a match counter.
final class FindController: ObservableObject {
    /// The window's web view, wired by `DocumentView`. Weak: the view owns it.
    weak var holder: WebViewHolder?

    @Published var isPresented = false
    @Published var query = ""
    @Published var caseSensitive = false
    @Published private(set) var status = ""

    /// Bumped whenever ⌘F is pressed, so the bar moves the keyboard into the
    /// search field even when it is already open.
    @Published private(set) var focusRequest = 0

    func open() {
        isPresented = true
        focusRequest += 1
        find(backwards: false)
    }

    func close() {
        isPresented = false
        status = ""
        // Hand the keyboard back to the page the user was reading.
        if let webView = holder?.webView {
            webView.window?.makeFirstResponder(webView)
        }
    }

    // Deliberately not gated on `isPresented`: ⌘G / ⇧⌘G conventionally continue
    // the last search after the bar has been closed, and `query` survives `close()`.
    func findNext() { find(backwards: false) }
    func findPrevious() { find(backwards: true) }

    /// Re-run the search as the user types or flips the case toggle. WebKit
    /// resumes at the start of the current selection, so extending the query
    /// refines the match you are on instead of walking down the page.
    func refresh() { find(backwards: false) }

    private func find(backwards: Bool) {
        guard let webView = holder?.webView else { return }
        guard !query.isEmpty else { status = ""; return }

        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = caseSensitive
        configuration.wraps = true
        webView.find(query, configuration: configuration) { [weak self] result in
            let matched = result.matchFound
            DispatchQueue.main.async { self?.status = matched ? "" : "Not found" }
        }
    }
}

/// Lets the Edit ▸ Find commands reach the frontmost document window.
struct FindControllerKey: FocusedValueKey {
    typealias Value = FindController
}

extension FocusedValues {
    var findController: FindController? {
        get { self[FindControllerKey.self] }
        set { self[FindControllerKey.self] = newValue }
    }
}
