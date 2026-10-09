import Foundation
import ImageIO
@preconcurrency import Vision

final class ImageTextRecognition: @unchecked Sendable {
    static let maximumDimension = 2048
    static let maximumTextLength = 20_000
    private let lock = NSLock()
    private var cancelled = false
    private var activeRequest: VNRecognizeTextRequest?

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        let request = lock.withLock {
            cancelled = true
            return activeRequest
        }
        request?.cancel()
    }

    func recognize(at url: URL) throws -> String {
        try autoreleasepool {
            guard !isCancelled else { throw CancellationError() }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.maximumDimension,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            guard !isCancelled else { throw CancellationError() }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.preferBackgroundProcessing = true
            let canStart = lock.withLock {
                guard !cancelled else { return false }
                activeRequest = request
                return true
            }
            guard canStart else { throw CancellationError() }
            defer { lock.withLock { activeRequest = nil } }
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            guard !isCancelled else { throw CancellationError() }
            var text = ""
            for observation in request.results ?? [] {
                guard let line = observation.topCandidates(1).first?.string else { continue }
                if !text.isEmpty { text.append("\n") }
                text.append(contentsOf: line.prefix(max(0, Self.maximumTextLength - text.count)))
                if text.count >= Self.maximumTextLength { break }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
