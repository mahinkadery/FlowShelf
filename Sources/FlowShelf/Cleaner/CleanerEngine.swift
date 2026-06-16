import AppKit

/// Scans the usual macOS locations for files an app leaves behind, scored by
/// confidence. Never deletes — `moveToTrash` is the only removal path, and that
/// is reversible (Put Back in Finder).
enum CleanerEngine {

    private struct ScanLocation {
        let url: URL
        let category: LeftoverCategory
    }

    /// Scan an app bundle for leftover files. Pure file IO — call off the main actor.
    static func scan(appURL: URL) -> AppScanResult {
        let info = readBundleInfo(appURL)
        let bundleID = info.bundleID
        let appName = info.name
        let execName = info.executable

        // Build the set of name fragments we'll match against.
        let bundleLower = bundleID?.lowercased()
        let compactName = appName
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        let nameTokens = appName.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 }

        var items: [LeftoverFile] = []
        var seen = Set<String>()

        // The app bundle itself — uninstalling should remove the app, not just its
        // leftovers. Listed first, pre-selected, highest confidence.
        seen.insert(appURL.path)
        items.append(LeftoverFile(
            url: appURL, category: .appBundle, confidence: .high,
            size: directorySize(appURL), selected: true))

        for loc in scanLocations() {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: loc.url, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else { continue }

            for child in children {
                // Never offer to remove the app bundle itself.
                if child.standardizedFileURL == appURL.standardizedFileURL { continue }
                let path = child.path
                if seen.contains(path) { continue }

                guard let confidence = match(
                    name: child.deletingPathExtension().lastPathComponent,
                    fullName: child.lastPathComponent,
                    bundleID: bundleLower, compactName: compactName,
                    tokens: nameTokens, execName: execName?.lowercased())
                else { continue }

                seen.insert(path)
                let size = directorySize(child)
                items.append(LeftoverFile(
                    url: child, category: loc.category, confidence: confidence,
                    size: size,
                    selected: confidence >= .medium))   // pre-select high+medium
            }
        }

        items.sort { ($0.confidence, $0.size) > ($1.confidence, $1.size) }
        return AppScanResult(appName: appName, bundleID: bundleID,
                             appURL: appURL, version: info.version, items: items)
    }

    /// Quit the app being uninstalled before trashing it (a running .app can fail
    /// to trash or relaunch). Asks nicely, then force-quits stragglers.
    @MainActor
    static func quitApp(bundleID: String?, timeout: TimeInterval = 4) async {
        guard let bundleID else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        func running() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { !$0.isTerminated && $0.processIdentifier != ownPID }
        }
        let initial = running()
        guard !initial.isEmpty else { return }

        initial.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if running().isEmpty { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        running().forEach { $0.forceTerminate() }
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    @MainActor
    static func moveToTrash(_ urls: [URL]) -> (trashed: Int, failed: [URL]) {
        var failed: [URL] = []
        var ok = 0
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                ok += 1
            } catch {
                failed.append(url)
            }
        }
        return (ok, failed)
    }

    // MARK: - Matching

    private static func match(name: String, fullName: String,
                              bundleID: String?, compactName: String,
                              tokens: [String], execName: String?) -> MatchConfidence? {
        let lname = name.lowercased()
        let lfull = fullName.lowercased()

        // HIGH — anchored on the bundle ID, which is specific enough to trust.
        if let bid = bundleID, !bid.isEmpty {
            if lname == bid || lfull == bid || lfull.hasPrefix(bid + ".") || lname.hasPrefix(bid + ".") {
                return .high
            }
            // A folder/file whose name *contains* the full reverse-DNS id, e.g.
            // "com.apple.Safari.Extension". Still specific → high.
            if lname.contains(bid) { return .high }
        }

        // MEDIUM — precise app-name matches only (exact or clean prefix). We do
        // NOT treat an arbitrary substring as medium: that pre-selects things
        // like a 3rd-party "…safari…" extension, which is exactly how a cleaner
        // trashes the wrong files.
        if !compactName.isEmpty, compactName.count >= 4 {
            if lname == compactName || lfull.hasPrefix(compactName + ".") {
                return .medium
            }
        }
        if let exec = execName, exec.count >= 4, lname == exec { return .medium }

        // LOW — loose, unchecked-by-default hints for the user to review.
        if compactName.count >= 5, lname.contains(compactName) { return .low }
        for token in tokens where token.count >= 5 && lname.contains(token) {
            return .low
        }
        return nil
    }

    // MARK: - Bundle info

    private static func readBundleInfo(_ appURL: URL) -> (bundleID: String?, name: String, executable: String?, version: String?) {
        let fallbackName = appURL.deletingPathExtension().lastPathComponent
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return (nil, fallbackName, nil, nil)
        }
        let bundleID = plist["CFBundleIdentifier"] as? String
        let name = (plist["CFBundleName"] as? String) ?? fallbackName
        let exec = plist["CFBundleExecutable"] as? String
        let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
        return (bundleID, name, exec, version)
    }

    // MARK: - Locations

    private static func scanLocations() -> [ScanLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let lib = home.appendingPathComponent("Library")
        func u(_ base: URL, _ path: String) -> URL { base.appendingPathComponent(path) }

        var locs: [ScanLocation] = [
            .init(url: u(lib, "Application Support"),    category: .appSupport),
            .init(url: u(lib, "Caches"),                 category: .caches),
            .init(url: u(lib, "Preferences"),            category: .preferences),
            .init(url: u(lib, "Containers"),             category: .containers),
            .init(url: u(lib, "Group Containers"),       category: .groupContainers),
            .init(url: u(lib, "Logs"),                   category: .logs),
            .init(url: u(lib, "LaunchAgents"),           category: .launchAgents),
            .init(url: u(lib, "Saved Application State"),category: .savedState),
            .init(url: u(lib, "HTTPStorages"),           category: .http),
            .init(url: u(lib, "WebKit"),                 category: .http),
            .init(url: u(lib, "Cookies"),                category: .http),
        ]
        // System-level (read-only without admin, but still surfaced).
        let slib = URL(fileURLWithPath: "/Library")
        locs += [
            .init(url: u(slib, "Application Support"), category: .appSupport),
            .init(url: u(slib, "Caches"),              category: .caches),
            .init(url: u(slib, "Preferences"),         category: .preferences),
            .init(url: u(slib, "LaunchAgents"),        category: .launchAgents),
            .init(url: u(slib, "LaunchDaemons"),       category: .launchDaemons),
            .init(url: u(slib, "Logs"),                category: .logs),
        ]
        return locs
    }

    // MARK: - Size

    private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
           values.isDirectory == false {
            return fileSize(url)
        }
        var total: Int64 = 0
        guard let en = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [], errorHandler: { _, _ in true }) else {
            return fileSize(url)
        }
        for case let item as URL in en {
            total += fileSize(item)
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
    }
}
