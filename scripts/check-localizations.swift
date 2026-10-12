import Foundation

@main
struct LocalizationChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resources = root.appendingPathComponent("Sources/FlowShelf/Resources")
        func catalog(_ language: String) throws -> [String: String] {
            let data = try Data(contentsOf: resources.appendingPathComponent("\(language).lproj/Localizable.strings"))
            return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
        }
        func require(_ condition: Bool, _ description: String) {
            guard condition else { fatalError(description) }
        }
        let en = try catalog("en")
        let pl = try catalog("pl")
        require(Set(en.keys) == Set(pl.keys), "English and Polish catalog keys differ")
        let placeholders = try NSRegularExpression(pattern: #"\{\d+\}|%(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?[diuoxXfFeEgGaAcsp@]"#)
        func tokens(_ text: String) -> [String] {
            placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { String(text[Range($0.range, in: text)!]) }.sorted()
        }
        let english = Bundle(url: resources.appendingPathComponent("en.lproj"))!
        let polish = Bundle(url: resources.appendingPathComponent("pl.lproj"))!
        for (key, value) in en {
            require(value == key, "English fallback differs from source: \(key)")
            require(tokens(value) == tokens(pl[key]!), "Interpolation arguments differ: \(key)")
            require(english.localizedString(forKey: key, value: nil, table: nil) == value,
                    "English bundle cannot resolve: \(key)")
            require(polish.localizedString(forKey: key, value: nil, table: nil) == pl[key]!,
                    "Polish bundle cannot resolve: \(key)")
        }
        require(L10n.text("Settings", bundle: polish) == "Ustawienia", "Static Polish lookup failed")
        require(L10n.text("Volume \(60) percent", bundle: polish) == "Głośność: 60 procent",
                "Polish interpolation failed")
        require(L10n.text("Volume \(60) percent", bundle: english) == "Volume 60 percent",
                "English interpolation changed")
        require(L10n.text("Unknown key \(42)", bundle: polish) == "Unknown key 42",
                "Missing-key fallback failed")
        let filename = "{1}% 👩🏽‍💻.png"
        require(L10n.text("No snippets match “\(filename)”", bundle: polish)
                == "Brak fragmentów pasujących do „\(filename)”", "User values were reinterpreted")
        require(L10n.text("{0} is literal", bundle: polish) == "{0} is literal",
                "A noninterpolated literal was changed")
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        try #""First {0}, then {1}" = "{1} / {0}";"#.write(
            to: fixture.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        let reordered = Bundle(url: fixture)!
        require(L10n.text("First \(filename), then \("second")", bundle: reordered)
                == "second / \(filename)", "Translation argument reordering failed")
        for language in ["en", "pl"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Resources/\(language).lproj/InfoPlist.strings"))
            let info = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
            require(info.count == 4 && info.values.allSatisfy { !$0.isEmpty }, "Permission descriptions missing")
        }
        print("LOCALIZATION OK: \(en.count) English/Polish keys, interpolation, fallback, user content, reordering and permission descriptions")
    }
}
