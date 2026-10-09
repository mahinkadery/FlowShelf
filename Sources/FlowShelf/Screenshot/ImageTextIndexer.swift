import Foundation
import Combine

@MainActor
final class ImageTextIndexer: ObservableObject {
    static let shared = ImageTextIndexer()
    @Published private(set) var summary = "Off — no images are being scanned."
    @Published private(set) var isIndexing = false
    @Published private(set) var failedCount = 0
    private let queue = DispatchQueue(label: "app.flowshelf.image-text-index", qos: .utility)
    private var subscriptions = Set<AnyCancellable>()
    private var job: ImageTextRecognition?
    private var currentID: UUID?
    private var failedIDs = Set<UUID>()
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        Publishers.CombineLatest(AppSettings.shared.$imageTextSearchEnabled, AppSettings.shared.$privateMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        ShelfStore.shared.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    func stop() {
        started = false
        job?.cancel()
        isIndexing = false
        subscriptions.removeAll()
    }

    func retry() {
        failedIDs.removeAll()
        failedCount = 0
        refresh()
    }

    func clearIndex() {
        AppSettings.shared.imageTextSearchEnabled = false
        job?.cancel()
        failedIDs.removeAll()
        failedCount = 0
        ShelfStore.shared.clearImageSearchText()
        refresh()
    }

    private func refresh() {
        guard started else { return }
        let settings = AppSettings.shared
        let store = ShelfStore.shared
        guard settings.imageTextSearchEnabled, !settings.privateMode else {
            job?.cancel()
            isIndexing = false
            summary = settings.imageTextSearchEnabled ? "Paused by Private Mode."
                : "Off — existing indexed text stays searchable until cleared."
            return
        }
        let images = store.visibleItems.filter(\.supportsImageTextSearch)
        failedIDs.formIntersection(Set(images.map(\.id)))
        failedCount = failedIDs.count
        let completed = images.filter { $0.imageSearchText != nil }.count
        if let currentID, !images.contains(where: { $0.id == currentID }) { job?.cancel() }
        guard job == nil else {
            summary = "Scanning saved images: \(completed) of \(images.count) checked…"
            return
        }
        guard let item = images.first(where: { $0.imageSearchText == nil && !failedIDs.contains($0.id) }),
              let url = store.imageURL(for: item), let relativePath = item.imageRelPath else {
            isIndexing = false
            let searchable = images.filter { !($0.imageSearchText ?? "").isEmpty }.count
            summary = images.isEmpty ? "Ready — new saved images will be scanned."
                : "\(completed) of \(images.count) checked · \(searchable) contain searchable text."
            if failedCount > 0 { summary += " \(failedCount) could not be read." }
            return
        }
        let request = ImageTextRecognition()
        job = request
        currentID = item.id
        isIndexing = true
        summary = "Scanning saved images: \(completed) of \(images.count) checked…"
        queue.async { [weak self] in
            let result = Result { try request.recognize(at: url) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard let self else { return }
                self.job = nil
                self.currentID = nil
                guard self.started else { return }
                if !request.isCancelled, AppSettings.shared.imageTextSearchEnabled, !AppSettings.shared.privateMode {
                    switch result {
                    case .success(let text):
                        ShelfStore.shared.setImageSearchText(item.id, relativePath: relativePath, text: text)
                    case .failure:
                        self.failedIDs.insert(item.id)
                    }
                }
                self.refresh()
            }
        }
    }
}
