# Markdown Viewer

A minimal, native macOS app that opens `.md` files on double-click and renders them GitHub-style — with proper light and dark mode. It also ships a Quick Look extension, so hitting the space bar on a `.md` file in Finder shows the rendered preview instantly.

<p align="center">
  <em>Double-click a Markdown file → read it rendered. That's the whole app.</em>
</p>

## Why I built this

I'm working with AI tools all day, and they produce `.md` files *constantly* — plans, notes, specs, READMEs, agent output. On macOS there's no good built-in way to just *read* one: double-clicking opens a code editor showing raw `#` and `*`, and the heavier Markdown apps want you to manage a library, sign in, or sync to a cloud.

I just wanted the dead-simple thing: double-click a `.md` file and see it rendered nicely, the way GitHub shows it. No accounts, no library, no clutter. So I built it.

## Download

Grab the latest `.app` from the [**Releases**](../../releases/latest) page, unzip it, and drag **MarkdownViewer.app** into `/Applications`.

The app is ad-hoc signed (not notarized), so the first time you open it macOS may warn that it's from an unidentified developer. Right-click the app → **Open**, then confirm — you only have to do this once.

> Requires macOS 13 (Ventura) or later.

### Make it the default for `.md` files

Open the app's Settings (**⌘,**) and click **"Use Markdown Viewer for Markdown Files"**. From then on, every `.md` file opens here on double-click, and the space-bar Quick Look preview works in Finder too.

## Features

- 📄 **Double-click to read** — opens `.md`, `.markdown`, `.mdown`, `.mkdn`, and `.mkd` files
- 🎨 **GitHub-style rendering** — clean typography, code blocks, tables, the works
- 🌗 **Light & dark mode** — follows your system appearance automatically
- 🔍 **Adjustable zoom** — **⌘+** / **⌘-** / **⌘0** scale the text (⌘= works too); your size sticks across windows and launches
- 👀 **Quick Look preview** — press space on a Markdown file in Finder
- 🔗 **Links open in your browser** — no surprise in-app navigation
- 🪶 **Tiny & native** — pure SwiftUI + WebKit, no Electron, no telemetry, no accounts

## Build from source

Requires the full Xcode toolchain (the Command Line Tools alone can't build SwiftUI):

```sh
./build-app.sh
```

This produces `dist/MarkdownViewer.app`, ad-hoc signs it, and registers it with Launch Services. Move it to `/Applications` if you like.

## Project structure

- `Sources/MarkdownViewerCore` — Markdown → styled HTML page (tested; uses [Ink](https://github.com/JohnSundell/Ink))
- `Sources/MarkdownViewer` — SwiftUI document app showing the HTML in a `WKWebView`
- `Sources/QuickLookPreview` — Quick Look extension rendering the same HTML for Finder's space-bar preview
- `Resources/Info.plist` — declares the Markdown document type so Finder offers the app

## Test

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## License

MIT
