import AppKit

enum HistoryRecovery {
    static func load<Value: Decodable>(_ type: Value.Type, from url: URL) -> Result<Value?, Error> {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return .success(try decoder.decode(type, from: data))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .success(nil)
        } catch {
            return .failure(error)
        }
    }

    @MainActor static func showWarning(for url: URL) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "FlowShelf couldn’t read \(url.lastPathComponent)"
            alert.informativeText = "Your existing file has not been changed. Saving changes to this history is paused for this session to protect your data. New items in this history are temporary. Quit FlowShelf before restoring a known-good copy of this file, then reopen it. Do not delete the original file or its images."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show File")
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
