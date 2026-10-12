import Foundation

/// Shared by SwiftUI labels, computed display names and AppKit alerts.
/// Keys retain the English wording. Interpolated values are substituted only
/// after lookup so user content and filenames never become localization keys.
enum L10n {
    struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        let key: String
        let arguments: [String]

        init(stringLiteral value: String) {
            key = value
            arguments = []
        }

        init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []

            init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity)
                arguments.reserveCapacity(interpolationCount)
            }

            mutating func appendLiteral(_ literal: String) { key += literal }

            mutating func appendInterpolation<T>(_ value: T) {
                key += "{\(arguments.count)}"
                arguments.append(String(describing: value))
            }
        }
    }

    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    static func text(_ message: Message, bundle: Bundle = resourceBundle) -> String {
        let template = bundle.localizedString(forKey: message.key, value: message.key, table: nil)
        guard !message.arguments.isEmpty else { return template }
        // Replace only placeholders in the template, never inside user values.
        var result = ""
        var cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}"),
               let index = Int(template[template.index(after: cursor)..<end]),
               message.arguments.indices.contains(index) {
                result += message.arguments[index]
                cursor = template.index(after: end)
            } else {
                result.append(template[cursor])
                cursor = template.index(after: cursor)
            }
        }
        return result
    }
}
