import SwiftUI

enum MatchConfidence: Int, Comparable, Sendable {
    case low = 0, medium = 1, high = 2
    static func < (l: MatchConfidence, r: MatchConfidence) -> Bool { l.rawValue < r.rawValue }

    var label: String {
        switch self {
        case .high: return L10n.text("High")
        case .medium: return L10n.text("Medium")
        case .low: return L10n.text("Low")
        }
    }
    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        }
    }
    var explanation: String {
        switch self {
        case .high: return L10n.text("Exact bundle-ID match")
        case .medium: return L10n.text("App name + path match")
        case .low: return L10n.text("Fuzzy name match — review carefully")
        }
    }
}

enum LeftoverCategory: String, CaseIterable, Sendable {
    case appBundle
    case preferences, caches, appSupport, containers, groupContainers
    case logs, launchAgents, launchDaemons, savedState, http, other

    var label: String {
        switch self {
        case .appBundle: return L10n.text("Application")
        case .preferences: return L10n.text("Preferences")
        case .caches: return L10n.text("Caches")
        case .appSupport: return L10n.text("Application Support")
        case .containers: return L10n.text("Containers")
        case .groupContainers: return L10n.text("Group Containers")
        case .logs: return L10n.text("Logs")
        case .launchAgents: return L10n.text("Login / Background Items")
        case .launchDaemons: return L10n.text("Launch Daemons")
        case .savedState: return L10n.text("Saved State")
        case .http: return L10n.text("Web/HTTP Storage")
        case .other: return L10n.text("Other")
        }
    }
    var symbol: String {
        switch self {
        case .appBundle: return "app.badge"
        case .preferences: return "slider.horizontal.3"
        case .caches: return "internaldrive"
        case .appSupport: return "folder"
        case .containers: return "shippingbox"
        case .groupContainers: return "square.stack.3d.up"
        case .logs: return "doc.text"
        case .launchAgents: return "bolt.badge.clock"
        case .launchDaemons: return "gearshape.2"
        case .savedState: return "macwindow"
        case .http: return "network"
        case .other: return "questionmark.folder"
        }
    }
}

struct LeftoverFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let category: LeftoverCategory
    let confidence: MatchConfidence
    let size: Int64
    var selected: Bool

    var displayName: String { url.lastPathComponent }
    var path: String { url.path }
}

struct AppScanResult: Sendable {
    let appName: String
    let bundleID: String?
    let appURL: URL
    let version: String?
    var items: [LeftoverFile]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.selected).count }

    func grouped() -> [(LeftoverCategory, [LeftoverFile])] {
        LeftoverCategory.allCases.compactMap { cat in
            let matches = items.filter { $0.category == cat }
            return matches.isEmpty ? nil : (cat, matches)
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
