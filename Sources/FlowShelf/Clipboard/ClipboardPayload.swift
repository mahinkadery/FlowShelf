import AppKit

enum ClipboardPayload {
    static let maximumRTFBytes = 256 * 1024

    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        var seen = Set<URL>()
        return urls.filter(\.isFileURL).map(\.standardizedFileURL).filter { seen.insert($0).inserted }
    }

    static func boundedRTF(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty, data.count <= maximumRTFBytes,
              data.starts(with: Data("{\\rtf".utf8)) else { return nil }
        return data
    }
}
