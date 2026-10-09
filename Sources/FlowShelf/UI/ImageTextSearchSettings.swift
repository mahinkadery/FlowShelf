import SwiftUI

struct ImageTextSearchSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var indexer = ImageTextIndexer.shared
    @ObservedObject private var store = ShelfStore.shared
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Search text inside images", isOn: $settings.imageTextSearchEnabled)
                .toggleStyle(.switch).controlSize(.small)
            Text("Scan existing and new saved screenshots and images on this Mac, one at a time. No cloud or Apple Intelligence required. Pauses in Private Mode.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                if indexer.isIndexing { ProgressView().controlSize(.small) }
                Text(indexer.summary).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("Recognized text may contain mistakes or miss small lettering. Turning this off stops scanning; it does not remove text already indexed.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                if indexer.failedCount > 0 {
                    Button("Retry unread images") { indexer.retry() }
                        .disabled(!settings.imageTextSearchEnabled || settings.privateMode)
                }
                Button("Clear indexed text…") { confirmingClear = true }
                    .disabled(!store.items.contains { $0.imageSearchText != nil } && !indexer.isIndexing)
            }
            .controlSize(.small)
        }
        .padding(12).raisedCard()
        .confirmationDialog("Clear indexed image text?", isPresented: $confirmingClear) {
            Button("Clear text and turn off indexing", role: .destructive) { indexer.clearIndex() }
        } message: {
            Text("Your images stay on the shelf. Only extracted search text is removed. You can enable indexing again later to rebuild it.")
        }
    }
}
