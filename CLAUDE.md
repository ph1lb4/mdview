# Markdown Viewer

Minimal native macOS app (SwiftUI, SPM — no Xcode project) that opens `.md` files on double-click and renders them GitHub-style in a `WKWebView`.

## Toolchain

`xcode-select` on this machine points to the Command Line Tools, which cannot build SwiftUI or run tests. Every `swift` command needs the full Xcode toolchain:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

`build-app.sh` sets this itself.

## Commands

```sh
./build-app.sh                  # build, Developer ID sign, notarize, staple, register; outputs dist/MarkdownViewer.zip
NOTARIZE=0 ./build-app.sh       # same but skip the Apple round-trip (signed only) — fast local iteration
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # run core tests (Swift Testing, not XCTest)
DEVELOPER_DIR=… swift test --filter blocksRemoteImagesByDefault       # run a single test by its function name
```

## Architecture

- `Sources/MarkdownViewerCore/MarkdownPage.swift` — the only real logic: markdown → complete styled HTML page (Ink parser + embedded CSS with light/dark + `@media print` support) plus the Content-Security-Policy. Pure and shared by both the app and the Quick Look extension. Covered by tests in `Tests/`; changes here are developed test-first. See **Security model** below.
- `Sources/MarkdownViewer/` — UI shell: `DocumentGroup` viewer app, read-only `FileDocument`, `WKWebView` wrapper (JavaScript disabled; links open in the default browser), Settings window, the File-menu Print / Save-as-PDF commands, and the View-menu Zoom commands. See **Security model**, **Print / PDF export**, and **Zoom** below.
- `Sources/QuickLookPreview/` — Quick Look preview extension (space bar in Finder): a data-based `QLPreviewProvider` returning `MarkdownPage` HTML, which Quick Look renders itself — no web view in the extension. Entry point is `NSExtensionMain` via linker flags in `Package.swift`; `main.swift` is a required-but-unused stub. `build-app.sh` assembles `Contents/PlugIns/QuickLookPreview.appex` from the binary plus `Resources/QuickLookPreview-Info.plist` and signs it with `Resources/QuickLookPreview.entitlements` (app extensions must be sandboxed; sign the appex before the app). Debug: `pluginkit -m -p com.apple.quicklook.preview` shows registration, `qlmanage -p file.md` previews, `qlmanage -r` resets caches. (`qlmanage -p -o dir` crashes inside ExtensionFoundation on this macOS — not an appex bug.)
- `Resources/Info.plist` — declares the `net.daringfireball.markdown` document type (`md`, `markdown`, `mdown`, `mkdn`, `mkd`); this is what makes Finder offer the app for double-click.
- `tools/make-icon.swift` — the app icon is code, not an asset: draws a white squircle with black monospace ".md" at all iconset sizes; `build-app.sh` compiles it to `Resources/AppIcon.icns` if missing. Delete the `.icns` to force regeneration after changing the drawing.

## Security model (untrusted Markdown)

`.md` files are untrusted input and Ink passes raw embedded HTML through **unsanitised**, so safety never relies on the parser — the *rendering surface* is locked down in two independent layers:

1. **CSP** — `MarkdownPage.csp` emits `default-src 'none'; style-src 'unsafe-inline'; img-src data:` in a `<meta>` tag: no scripts, no remote fetches, inline (`data:`) images only. `style-src 'unsafe-inline'` is the one allowance, for our own embedded `<style>`.
2. **JavaScript off** — `WebView.swift` sets `allowsContentJavaScript = false` on the `WKWebView`, so even a CSP gap can't run script.

The **Load remote images** toggle (`DefaultsKey.loadRemoteImages`, off by default) is the only knob that loosens this: when on, `MarkdownPage.html(allowRemoteImages:)` widens `img-src` to `data: https: http:` — nothing else changes. It's off by default because remote images leak the reader's IP and act as tracking beacons. Quick Look always renders with the default (blocked): the appex calls `MarkdownPage.html(contentsOf:)` with no opt-in. This behaviour is pinned by tests in `MarkdownPageTests.swift` — keep them green when touching the CSP.

## Print / PDF export

Both live in `WebViewHolder` and reach the File menu through a `FocusedValue` (`\.webViewHolder`), so the commands act on whichever document window is frontmost and disable when no web view is attached. The `@media print` block in `MarkdownPage`'s CSS forces a light, full-width layout so output is never dark or narrow-columned on paper.

- **Print** uses `WKWebView.printOperation` directly (honours `@media print`).
- **Save as PDF** deliberately avoids the headless `NSPrintOperation` save path — with `WKWebView` that can enter a runaway pagination loop, producing an ever-growing file and hanging the app. Instead `PDFExportSession` renders the HTML in a short-lived, forced-light (`.aqua`) off-screen `WKWebView` via `WKWebView.createPDF`, then splits the single tall page into US-Letter pages with margins itself (`paginate`). The session retains itself in a static array for the async render's lifetime.

## Zoom

View-menu **Zoom In / Zoom Out / Actual Size** (⌘+ / ⌘- / ⌘0) reach the frontmost document through the same `FocusedValue(\.webViewHolder)` pattern as Print/PDF, and disable when no web view is attached. They drive `WebViewHolder.pageZoom`, a thin wrapper over the **native `WKWebView.pageZoom`** property — so zoom uses no JavaScript and the locked-down rendering surface (see **Security model**) stays untouched. The factor is clamped to 0.5–3.0 in 0.1 steps and persisted globally in `UserDefaults` (`DefaultsKey.pageZoom`), so the chosen reading size is shared across every document window and remembered across launches: `WebView.makeNSView` calls `applyStoredZoom()` once the view is attached (the property survives `loadHTMLString`), and each `WebViewHolder` observes `UserDefaults.didChangeNotification` to re-apply the factor live, so already-open windows follow a change made in any other window — not just windows opened afterwards. ⌘+ is the HIG-conventional binding (`+` is the shifted `=`, i.e. ⌘⇧=); a hidden button in `DocumentView` adds the un-shifted browser-style ⌘= as an alias without a duplicate menu entry.

## Default handler for .md

Declaring the document type only makes the app *an option* in "Open with". Making it the *default* is a per-user Launch Services setting. The app's Settings window (⌘,) has a button for this (`SettingsView.swift` — uses `NSWorkspace.setDefaultApplication` on `Bundle.main.bundleURL`, so it works from any install location). It can also be set from the CLI:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift -e '
import AppKit
import UniformTypeIdentifiers
let url = URL(fileURLWithPath: "/Applications/MarkdownViewer.app")  // adjust path
let sem = DispatchSemaphore(value: 0)
NSWorkspace.shared.setDefaultApplication(at: url, toOpen: UTType(importedAs: "net.daringfireball.markdown")) { error in
    print(error.map { "ERROR: \($0)" } ?? "default handler set"); sem.signal()
}
sem.wait()'
```

The setting points at a concrete bundle path — re-run it if the app moves (e.g. from `dist/` to `/Applications`).

## Signing & notarization

Ad-hoc signing (`codesign --sign -`) makes the app launch on the build machine but get flagged as "unidentified developer" / damaged on any other Mac (Gatekeeper + download quarantine). To distribute, `build-app.sh` does the full Developer ID flow:

- **Sign** the nested `.appex` first, then the app, with `Developer ID Application: Soon Up GmbH (6A2SZH3VT5)` plus `--options runtime` (hardened runtime) and `--timestamp`. All three are required for notarization. No `--deep` on the app, so the appex signature stays intact. The main app needs no entitlements; the appex keeps its sandbox entitlements.
- **Notarize** via `xcrun notarytool submit … --wait` using the keychain profile `NOTARY_PROFILE` (default `ainstype-notary`, shared from the sibling `ainstype` project — same Apple team, so it just works). Create a fresh one with `xcrun notarytool store-credentials <name> --apple-id … --team-id 6A2SZH3VT5 --password <app-specific-password>`.
- **Staple** the ticket onto the `.app` (`xcrun stapler staple`) so Gatekeeper passes offline / on first launch, then re-zip the stapled bundle as `dist/MarkdownViewer.zip` — the distributable artifact.

Override `SIGN_IDENTITY` / `TEAM_ID` / `NOTARY_PROFILE` via env when building from a fork. Verify a build with `spctl -a -vvv -t exec dist/MarkdownViewer.app` (expect `source=Notarized Developer ID`) and `xcrun stapler validate`.
