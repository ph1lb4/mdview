import SwiftUI
import WebKit
import PDFKit
import UniformTypeIdentifiers

/// Owns the `WKWebView` for one document window and performs print / PDF export
/// against it. Exposed to the menu bar via a focused scene value so the File
/// menu acts on whichever document window is frontmost.
final class WebViewHolder: ObservableObject {
    weak var webView: WKWebView?

    /// The rendered HTML for this document, used for PDF export.
    var html: String = ""

    /// Base name (no extension) used for the print job and the default PDF
    /// filename in the save panel.
    var documentName: String = "Document"

    var hasContent: Bool { webView != nil }

    /// Token for the UserDefaults observer that keeps this window's zoom in sync
    /// with the shared factor (see `init`).
    private var zoomSyncObserver: NSObjectProtocol?

    init() {
        // The zoom factor lives in UserDefaults, so a change made in one window
        // must be re-applied to every other open window — not only to windows
        // opened afterwards. Re-apply the stored zoom whenever defaults change
        // (idempotent and cheap; `applyStoredZoom` no-ops while detached).
        zoomSyncObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyStoredZoom()
        }
    }

    deinit {
        if let zoomSyncObserver { NotificationCenter.default.removeObserver(zoomSyncObserver) }
    }

    // Page-zoom limits and step for the View-menu ⌘+/⌘-/⌘0 commands. `pageZoom`
    // is a native `WKWebView` property (no JavaScript), so zooming leaves the
    // locked-down rendering surface untouched.
    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 3.0
    private static let zoomStep: CGFloat = 0.1

    /// The page-zoom factor (1.0 == 100%), persisted in `UserDefaults` so it is
    /// shared across every document window and remembered across launches.
    var pageZoom: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: DefaultsKey.pageZoom)
            return stored == 0 ? 1.0 : CGFloat(stored)
        }
        set {
            let bounded = min(max(newValue, Self.minZoom), Self.maxZoom)
            let clamped = (bounded * 10).rounded() / 10 // keep clean 0.1 steps
            UserDefaults.standard.set(Double(clamped), forKey: DefaultsKey.pageZoom)
            webView?.pageZoom = clamped
        }
    }

    /// Apply the persisted zoom to the web view. Called once the view is attached
    /// (so each new window opens at the reader's chosen size) and again whenever
    /// the shared factor changes (so already-open windows stay in sync).
    func applyStoredZoom() { webView?.pageZoom = pageZoom }

    func zoomIn() { pageZoom += Self.zoomStep }
    func zoomOut() { pageZoom -= Self.zoomStep }
    func resetZoom() { pageZoom = 1.0 }

    /// Print the rendered document through the standard print panel. Uses the
    /// web view's own paginating print operation, so it honours the `@media
    /// print` styles in `MarkdownPage`.
    func print() {
        guard let webView else { return }
        let info = NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let margin: CGFloat = 36 // 0.5"
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin

        let operation = webView.printOperation(with: info)
        operation.jobTitle = documentName
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = webView.window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    /// Ask for a destination, then render the document to a paginated PDF there.
    ///
    /// This deliberately avoids the headless `NSPrintOperation` (save
    /// disposition, no panel) path: with `WKWebView` that can enter a runaway
    /// pagination loop that produces an ever-growing file and hangs the app.
    /// Instead we use `WKWebView.createPDF` against a short-lived, forced-light
    /// off-screen web view and split the result into pages ourselves.
    func exportPDF() {
        guard webView != nil else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(documentName).pdf"
        panel.canCreateDirectories = true
        panel.title = "Save as PDF"

        let html = self.html
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            PDFExportSession.run(html: html, destination: url)
        }

        if let window = webView?.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
}

/// Renders HTML to a paginated PDF file using an off-screen `WKWebView`.
/// Retains itself for the lifetime of the asynchronous render so the web view
/// and navigation delegate stay alive until the PDF is written.
private final class PDFExportSession: NSObject, WKNavigationDelegate {
    private static var live: [PDFExportSession] = []

    private static let pageSize = CGSize(width: 612, height: 792) // US Letter
    private static let margin: CGFloat = 36 // 0.5"

    private let destination: URL
    private let webView: WKWebView

    static func run(html: String, destination: URL) {
        let session = PDFExportSession(destination: destination)
        live.append(session)
        session.webView.loadHTMLString(html, baseURL: nil)
    }

    private init(destination: URL) {
        self.destination = destination
        let contentWidth = Self.pageSize.width - 2 * Self.margin
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: contentWidth, height: Self.pageSize.height))
        super.init()
        // Force light rendering so the PDF never comes out dark on paper.
        webView.appearance = NSAppearance(named: .aqua)
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give layout and image decoding a moment to settle before capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                if case .success(let data) = result {
                    let paged = Self.paginate(data) ?? data
                    try? paged.write(to: self.destination)
                }
                self.finish()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    private func finish() {
        webView.navigationDelegate = nil
        Self.live.removeAll { $0 === self }
    }

    /// Split a single tall PDF page (as produced by `createPDF`) into fixed-size
    /// pages, drawing each vertical slice into its own page with margins.
    private static func paginate(_ data: Data) -> Data? {
        guard let source = PDFDocument(data: data),
              let sourcePage = source.page(at: 0),
              let sourceRef = sourcePage.pageRef else { return nil }

        let bounds = sourcePage.bounds(for: .mediaBox)
        let contentRect = CGRect(x: margin, y: margin,
                                 width: pageSize.width - 2 * margin,
                                 height: pageSize.height - 2 * margin)
        let sliceHeight = contentRect.height
        let pageCount = max(1, Int(ceil(bounds.height / sliceHeight)))

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            context.saveGState()
            context.clip(to: contentRect)
            // Place the content area, then offset the source page so this
            // page's vertical band lines up with the top of the content area.
            context.translateBy(x: contentRect.minX, y: contentRect.minY)
            context.translateBy(x: 0, y: -(bounds.height - CGFloat(page + 1) * sliceHeight))
            context.drawPDFPage(sourceRef)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }
}

/// Lets the menu commands find the frontmost document's web view.
struct WebViewHolderKey: FocusedValueKey {
    typealias Value = WebViewHolder
}

extension FocusedValues {
    var webViewHolder: WebViewHolder? {
        get { self[WebViewHolderKey.self] }
        set { self[WebViewHolderKey.self] = newValue }
    }
}
