# Changelog

All notable changes to FlowShelf. Versioning is [semantic](https://semver.org):
`MAJOR.MINOR.PATCH` — bump PATCH for fixes, MINOR for features, MAJOR for breaking
changes. The number in parentheses is the build number (`CFBundleVersion`).

## [1.2.1] — 2026-06-17 (build 5)

### Fixed
- **Permissions no longer reset on update.** Releases are now signed with a stable
  identity instead of ad-hoc, so macOS recognizes each update as the same app and
  keeps your Accessibility / Screen Recording grants. (One last re-grant when
  updating to this version, then they stick.)

## [1.2.0] — 2026-06-17 (build 4)

### Added
- **Window switcher (⌥Tab)** — hold Option and press Tab for a live-preview
  switcher across all apps. Arrows/Tab to navigate, release Option or Return to
  switch, Esc to cancel. Balanced grid (2×2 → 3×3 → 4×4) or compact List layout.
  Opt-in, with a layout picker in Settings.
- **Peek tuning** — choose Dock-preview size (Small / Medium / Large) and adjust
  the hover delay.

### Changed
- **Redesigned Settings** — clean card-based layout with every feature toggle
  grouped sensibly.
- Larger, more visible Buy Me a Coffee button.

## [1.1.1] — 2026-06-17 (build 3)

### Fixed
- **Universal binary** — now runs natively on both Apple Silicon and Intel Macs
  (1.1.0 was Apple-Silicon-only by mistake).

## [1.1.0] — 2026-06-16 (build 2)

### Added
- **Automatic updates** via Sparkle — checks daily and prompts when a new version
  is available; "Check for Updates…" in Settings.
- **Buy Me a Coffee** support button in Settings (buymeacoffee.com/mahinkadery).
- **Launch at login** toggle (General settings).

### Changed
- **Privacy hardening:** the clipboard store is now owner-only (0700/0600) and
  excluded from iCloud / Time Machine backups, so copied text never syncs off-device.
- **Lighter on memory:** window thumbnails are released when the Peek tab closes
  and when a Dock preview hides (idle RAM stays low).

### Fixed
- Cleaner now quits a running app before trashing it (no more half-failed uninstalls).
- Shelf "time left" labels count down live instead of only updating on open.
- Hardened Accessibility value casts against unexpected system responses.

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
