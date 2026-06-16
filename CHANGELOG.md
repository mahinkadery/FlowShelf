# Changelog

All notable changes to FlowShelf. Versioning is [semantic](https://semver.org):
`MAJOR.MINOR.PATCH` — bump PATCH for fixes, MINOR for features, MAJOR for breaking
changes. The number in parentheses is the build number (`CFBundleVersion`).

## [1.0.0] — 2026-06-16 (build 1)

First release.

### Shelf
- 24-hour temporary shelf — one place for everything you copy, capture, or drag.
- Items show **time left** until auto-delete (live countdown); pin to keep forever.
- Clipboard history: text, links, images, files. Privacy markers + excluded apps skipped.
- Screenshot + local OCR (`⌘⇧7` / `⌘⇧O`) via the native crosshair + Apple Vision.
- Floating drop-shelf (`⌘⇧S`): type-aware tiles, click-to-copy, drag in/out,
  opens at the cursor, **shake-to-summon** (toggle in Settings).

### Peek (Dock window previews)
- Hover a Dock icon → live window thumbnails; click to switch, hover to close/minimize.
- Window list via Accessibility; thumbnails via the system window-capture API.
- "Capture working" self-test so the UI reflects real permission state.

### Clean (App uninstaller)
- Drop an app → scans `~/Library` + `/Library` for leftovers, scored High/Medium/Low.
- Removes the **app itself + leftovers**, quitting the app first; Trash-only (reversible).

### Dashboard & system
- Unified window (`⌘⇧D`): Shelf · Peek · Clean · Settings.
- Launch-at-login, custom app icon, menu-bar agent.

---

<!-- Template for the next release — copy this block above:

## [1.1.0] — YYYY-MM-DD (build N)
### Added
### Changed
### Fixed
-->
