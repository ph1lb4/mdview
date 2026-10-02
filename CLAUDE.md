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
```

## Architecture

- `Sources/MarkdownViewerCore/MarkdownPage.swift` — the only real logic: markdown → complete styled HTML page (Ink parser + embedded CSS with light/dark support). Covered by tests in `Tests/`; changes here are developed test-first. A pre-pass (`keepingLineBreaks`) keeps single line breaks as `<br>` and turns `•` lines into list items, so Slack/AI-style files don't collapse into one paragraph. It skips code fences, tables and blockquotes (Ink garbles hard breaks inside quotes).
- `Sources/MarkdownViewer/` — UI shell: `DocumentGroup` viewer app, read-only `FileDocument`, `WKWebView` wrapper (links open in the default browser).
- `Sources/MarkdownViewer/RichCopy.swift` — `MarkdownWebView` replaces WebKit's Copy (⌘C and context menu). WebKit's own copy inlines every computed style and web apps like Slack/Notion/Google Docs mangle it. An injected script (runs even with page JS disabled) serializes the selection as clean HTML plus Markdown; the pasteboard gets HTML, RTF and Markdown plain text. Quick Look can't be hooked, so copying from the preview still uses WebKit's default.
- `Sources/QuickLookPreview/` — Quick Look preview extension (space bar in Finder): a data-based `QLPreviewProvider` returning `MarkdownPage` HTML, which Quick Look renders itself — no web view in the extension. Entry point is `NSExtensionMain` via linker flags in `Package.swift`; `main.swift` is a required-but-unused stub. `build-app.sh` assembles `Contents/PlugIns/QuickLookPreview.appex` from the binary plus `Resources/QuickLookPreview-Info.plist` and signs it with `Resources/QuickLookPreview.entitlements` (app extensions must be sandboxed; sign the appex before the app). Debug: `pluginkit -m -p com.apple.quicklook.preview` shows registration, `qlmanage -p file.md` previews, `qlmanage -r` resets caches. (`qlmanage -p -o dir` crashes inside ExtensionFoundation on this macOS — not an appex bug.)
- `Resources/Info.plist` — declares the `net.daringfireball.markdown` document type (`md`, `markdown`, `mdown`, `mkdn`, `mkd`); this is what makes Finder offer the app for double-click.
- `tools/make-icon.swift` — the app icon is code, not an asset: draws a white squircle with black monospace ".md" at all iconset sizes; `build-app.sh` compiles it to `Resources/AppIcon.icns` if missing. Delete the `.icns` to force regeneration after changing the drawing.

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
