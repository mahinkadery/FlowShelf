import Foundation

enum AppBundleInstaller {
    static func install(from source: URL, to destination: URL) throws {
        guard source.resolvingSymlinksInPath().standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".FlowShelf-incoming-\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent(".FlowShelf-previous-\(UUID().uuidString).app")
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: source, to: staging)
        let replacing = manager.fileExists(atPath: destination.path)
        if replacing { try manager.moveItem(at: destination, to: backup) }
        do {
            try manager.moveItem(at: staging, to: destination)
        } catch {
            if replacing { try? manager.moveItem(at: backup, to: destination) }
            throw error
        }
        if replacing { try? manager.removeItem(at: backup) }
    }
}
