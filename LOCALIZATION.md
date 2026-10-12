# Localization

FlowShelf supports English and Polish. It follows the macOS preferred language,
including the per-app language in **System Settings → General → Language & Region
→ Applications**. Restart FlowShelf after changing the language. Other languages
fall back to English.

Interface strings live in `Sources/FlowShelf/Resources/<language>.lproj/Localizable.strings`.
Use `L10n.text("English wording")` for user-facing SwiftUI and AppKit strings,
including computed labels. For dynamic text, use Swift interpolation:

```swift
L10n.text("Volume \(Int(level * 100)) percent")
```

The catalog key is `Volume {0} percent`. Keep every numbered placeholder exactly
once; translators can move placeholders to fit the sentence. Values such as
filenames, clipboard contents and app names are inserted after lookup and are
never translated or interpreted as format strings. Prefer count-neutral wording
where the English template does not provide plural variants.

Permission descriptions live separately in `Resources/<language>.lproj/InfoPlist.strings`.
Both bundle targets in the Makefile copy these descriptions and the SwiftPM
resource bundle into the finished app. Keep filesystem paths, clipboard type
names, persisted identifiers, SF Symbols, attribution names and AI instructions
out of the interface catalogs.

Run `make check-localizations` to check catalog parity, placeholders, bundle
lookups, interpolation, English fallback, user content and permission descriptions.
Then run `make bundle` to build and bundle both architectures. Review the Polish
screens visually, especially labels with fixed widths, before release.
