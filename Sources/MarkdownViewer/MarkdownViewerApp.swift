import SwiftUI
import MarkdownViewerCore

@main
struct MarkdownViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            DocumentView(
                text: configuration.document.text,
                fileURL: configuration.fileURL
            )
        }
        // Open documents in a comfortable portrait reading window.
        .defaultSize(width: 820, height: 1040)
        .commands {
            DocumentCommands()
            FindCommands()
        }
        Settings {
            SettingsView()
        }
    }
}

/// Renders one Markdown document and exposes its web view + find bar to the
/// menu bar.
struct DocumentView: View {
    let text: String
    let fileURL: URL?
    @AppStorage(DefaultsKey.loadRemoteImages) private var loadRemoteImages = false
    @StateObject private var holder = WebViewHolder()
    @StateObject private var find = FindController()

    var body: some View {
        let html = MarkdownPage.html(from: text, allowRemoteImages: loadRemoteImages)
        VStack(spacing: 0) {
            if find.isPresented {
                FindBar(find: find)
                Divider()
            }
            WebView(html: html, holder: holder)
        }
        .frame(minWidth: 480, minHeight: 600)
        .focusedSceneValue(\.webViewHolder, holder)
        .focusedSceneValue(\.findController, find)
        .onAppear {
            find.holder = holder
            holder.html = html
            if let name = fileURL?.deletingPathExtension().lastPathComponent {
                holder.documentName = name
            }
        }
        // Keep the export HTML in sync when the image setting is toggled
        // while a document is open.
        .onChange(of: html) { holder.html = $0 }
    }
}

/// Print and "Save as PDF" entries in the File menu, acting on the frontmost
/// document window.
struct DocumentCommands: Commands {
    @FocusedValue(\.webViewHolder) private var holder

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print…") { holder?.print() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(holder?.hasContent != true)

            Button("Save as PDF…") { holder?.exportPDF() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(holder?.hasContent != true)
        }
    }
}

/// Edit ▸ Find entries, acting on the frontmost document window.
struct FindCommands: Commands {
    @FocusedValue(\.findController) private var find

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find…") { find?.open() }
                    .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") { find?.findNext() }
                    .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") { find?.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.shift, .command])
            }
            .disabled(find == nil)
        }
    }
}
