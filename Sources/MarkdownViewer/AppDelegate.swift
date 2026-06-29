import AppKit

/// Centralised `UserDefaults` keys so the app and its views agree on spelling.
enum DefaultsKey {
    /// Whether the viewer is allowed to load remote (http/https) images. Off by
    /// default for privacy — remote images leak the reader's IP and can act as
    /// tracking beacons.
    static let loadRemoteImages = "LoadRemoteImages"

    /// Set once we've offered to become the default Markdown handler, so the
    /// first-launch prompt only ever appears once.
    static let didPromptDefaultHandler = "DidPromptDefaultHandler"

    /// The page-zoom factor applied to the rendered document (1.0 == 100%).
    /// Persisted so the chosen reading size carries across windows and launches.
    static let pageZoom = "PageZoom"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        promptToBecomeDefaultIfNeeded()
    }

    /// On first launch, offer to make Markdown Viewer the default app for `.md`
    /// files. Only asks once (tracked in defaults) and never if it's already the
    /// default. The same choice is always available later in Settings (⌘,).
    private func promptToBecomeDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.didPromptDefaultHandler) else { return }

        if DefaultHandler.isDefault {
            defaults.set(true, forKey: DefaultsKey.didPromptDefaultHandler)
            return
        }

        // Defer so the prompt appears after the launch settles (and after any
        // document window has been created).
        DispatchQueue.main.async {
            defaults.set(true, forKey: DefaultsKey.didPromptDefaultHandler)

            let alert = NSAlert()
            alert.messageText = "Make Markdown Viewer your default?"
            alert.informativeText = "Open Markdown (.md) files with Markdown Viewer when you double-click them in Finder. You can change this any time in Settings."
            alert.addButton(withTitle: "Use as Default")
            alert.addButton(withTitle: "Not Now")

            if alert.runModal() == .alertFirstButtonReturn {
                DefaultHandler.makeDefault { _ in }
            }
        }
    }
}
