import AppKit

/// First-run guard against macOS "app translocation".
///
/// When FlowShelf is launched straight from the DMG or the Downloads folder
/// (still quarantined), macOS runs it from a random, throwaway path inside
/// `/private/.../AppTranslocation/`. TCC records any Screen-Recording or
/// Accessibility grant against *that* path — which disappears on the next
/// launch — so the permission silently "vanishes" and the user is forced to
/// remove and re-add FlowShelf over and over. Moving the app into
/// `/Applications` with a real file move gives it a stable identity so grants
/// persist. This is the single biggest cause of the Peek setup pain.
@MainActor
enum AppRelocator {

    /// If we're running translocated or from anywhere outside `/Applications`,
    /// offer to move the app there and relaunch. No-op in debug builds and when
    /// already correctly installed.
    static func offerToMoveIfNeeded() {
        #if DEBUG
        return
        #else
        guard needsMove else { return }
        let installed = URL(fileURLWithPath: "/Applications/FlowShelf.app")

        let alert = NSAlert()
        alert.messageText = "Move FlowShelf to Applications?"
        alert.informativeText = """
        FlowShelf works best from your Applications folder. Running it from the \
        disk image or your Downloads folder can make macOS forget Screen \
        Recording and Accessibility permissions between launches — which is why \
        window previews sometimes stop working until you re-grant them.

        Move it now and FlowShelf will reopen from Applications.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        move(to: installed)
        #endif
    }

    /// True when the running bundle is translocated or not under `/Applications`.
    private static var needsMove: Bool {
        let path = Bundle.main.bundleURL.path
        if path.contains("/AppTranslocation/") { return true }
        return !path.hasPrefix("/Applications/")
    }

    private static func move(to dest: URL) {
        let fm = FileManager.default
        let source = Bundle.main.bundleURL
        do {
            if fm.fileExists(atPath: dest.path) {
                // The running copy is the translocated/Downloads one, never the
                // /Applications copy — so replacing it is safe.
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: source, to: dest)
        } catch {
            // Usually a write-permission error on /Applications. Fall back to
            // revealing the app so the user can drag it across by hand.
            let a = NSAlert()
            a.messageText = "Couldn’t move FlowShelf automatically"
            a.informativeText = "Please drag FlowShelf into your Applications folder, then open it from there."
            a.addButton(withTitle: "Reveal in Finder")
            a.addButton(withTitle: "Cancel")
            if a.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([source])
            }
            return
        }
        stripQuarantine(dest)
        relaunch(at: dest)
    }

    /// Remove the quarantine flag so the moved copy opens without a Gatekeeper
    /// prompt (and is never itself translocated).
    private static func stripQuarantine(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? p.run()
        p.waitUntilExit()
    }

    private static func relaunch(at url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
