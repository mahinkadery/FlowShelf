# Changelog

All notable changes to FlowShelf. Versioning is [semantic](https://semver.org):
`MAJOR.MINOR.PATCH` — bump PATCH for fixes, MINOR for features, MAJOR for breaking
changes. The number in parentheses is the build number (`CFBundleVersion`).

## [1.6.0] — 2026-07-18 (build 63)

### Added
- **Animated first-launch onboarding** — a four-step native tour for the shelf,
  notch, customizable shortcuts, and privacy. Its SVG artwork is rendered by
  AppKit and animated by SwiftUI without a browser or third-party runtime;
  Reduce Motion is respected. Existing users can replay it from Settings or the
  menu-bar right-click menu.
- **Permission Health dashboard** — Accessibility, Screen Recording, Input
  Monitoring, optional Full Disk Access, and unused Notifications are explained
  in one honest status page with direct macOS controls.
- **Complete shortcut customization** — the window switcher and all ten window
  snapping zones now use the same recorder and conflict checks as FlowShelf's
  five global actions.
- **Settings search** — find features, permissions, and shortcut controls without
  scrolling through the full preferences page.

### Changed
- **Native Liquid Glass dashboard on macOS 26** with a refined sidebar, backdrop,
  pane headers, cards, empty states, and clearer visual hierarchy throughout
  Shelf, Snippets, Notch, Peek, Clean, Permissions, and Settings.
- The dashboard now restores its previous size, screen position, and selected
  section.
- The notch liquid lens is clearer and more focused, while retaining the legacy
  renderer as a rollback option.

### Fixed
- Denying Screen Recording no longer causes the notch lens to retry and pressure
  the system repeatedly during the same launch.
- Shortcut recording now suspends every shortcut engine, preventing the key
  combination being edited from firing another FlowShelf action.

## [1.5.0] — 2026-07-17 (build 61)

### Added
- **Customizable shortcuts** — every global hotkey (floating shelf, search,
  screenshot, OCR, dashboard) can be rebound: click the shortcut in Settings
  and press any combination. Conflicts inside FlowShelf are flagged, and
  combos macOS refuses (owned by the system or another app) get an honest
  warning. Changes apply instantly, no restart.
- **Sound output inside the notch** — tap the AirPlay button and the island
  itself grows sideways to reveal your output devices (speakers, AirPods,
  displays) with a per-device volume slider. Live device tracking; devices
  without volume control say so instead of showing a dead slider.
- **Notch section in the dashboard** — all island settings (shelf, media
  player, audio-reactive bars, HUDs) in one place as modular emblem rows.
- **Copy confirmation everywhere** — copying from the notch, menu bar, or
  dashboard flashes a "Copied ✓" on the exact item, like the floating shelf.

### Changed
- The notch shelf now shows up to 40 items (scroll with a plain mouse wheel).
- Dashboard redesign (phase 1): grouped sidebar with colored icon chips, big
  pane headers for Snippets/Peek/Clean, restyled settings cards with tinted
  emblem chips, unified typography and roomier spacing.

## [1.4.0] — 2026-07-15 (build 60)

### Added
- **Notch media player** — now-playing for any app (Music, Spotify, browsers):
  a Dynamic-Island live activity when collapsed (album art + audio bars tinted
  to the artwork's color, dancing to the actual music) and a compact player
  when open (marquee title, artist, prev/play/next, click-or-drag-to-seek
  progress bar). Powered by the vendored BSD `mediaremote-adapter`, fully
  on-device.
- **Sound-output switcher** — an iPhone-style device panel beside the notch
  (Apple Liquid Glass, Control-Centre pop animation) with per-device volume
  control and live device tracking.
- **Real liquid-glass notch** — the card's transparent bottom genuinely
  refracts the desktop behind it (live capture + displacement lens), with the
  Dynamic-Island bounce, drag-to-notch auto-open, and file-promise drops.
- **System HUDs in the notch** — volume, brightness, charging and low-battery
  as sleek live activities replacing Apple's center-screen overlay (optional).
- **Glassmorphism pass** — frosted floating shelf with raised 3D tiles, frosted
  dashboard, Apple `.glassEffect` surfaces on macOS 26, unified design language,
  friendlier empty states, ⌘1–⌘5 dashboard section shortcuts.

### Changed
- Floating shelf summoned by shake now auto-hides after ~4s unless you're
  actively using it.
- Big performance work: the notch lens renders only the card-sized region
  (~60× less per-frame work), media parsing/artwork decoding moved off the
  main thread, list rows use hover-only blur/shadow.

### Accessibility
- **Reduce Transparency** is honored everywhere: the lens turns off, all glass
  falls back to solid panels, live-updating with the system setting.
- Audio-reactive bars have an explicit toggle (they show the macOS recording
  indicator) and pause while the screen is locked; Reduce Motion is respected
  across animations.

## [1.3.5] — 2026-07-02 (build 40)

### Fixed
- Restored the **branded drag-to-install DMG window** with the FlowShelf
  background, aligned app/Applications icons, and current notarized-install
  guidance. The builder now styles a unique temporary volume and fails the
  release if Finder does not persist the required layout metadata, preventing a
  plain fallback installer from being published again.

## [1.3.4] — 2026-07-02 (build 39)

### Fixed
- **Critical distribution hotfix:** the first notarized v1.3.3 DMG omitted
  `Sparkle.framework`, causing FlowShelf to terminate immediately at launch.
  The release bundle now embeds every required framework and resource, signs
  Sparkle's nested helpers in the correct inside-out order, and is cold-launch
  tested before publishing.

### Changed
- FlowShelf is now **Developer ID signed and notarized by Apple**, so new users
  can open it normally without the old System Settings → Open Anyway workaround.
  Users upgrading from the previous self-signed build may need to grant
  Accessibility and Screen Recording once more; future updates keep the stable
  Developer ID identity.

## [1.3.3] — 2026-06-26 (build 38)

### Added
- **A full screenshot studio.** The annotation editor grew a complete toolkit:
  - **Arrows** (arrow / line / double-headed), **boxes** (outline / filled /
    rounded / ellipse), a real **highlighter marker**, numbered/lettered
    **steps**, and **text** in four sizes.
  - **Redaction** with three modes — **pixelate, blur, or solid black-out**.
  - **Spotlight** (dim everything but a region), a **magnifier callout**
    (select an area to show it zoomed, baked into the image), a **pixel ruler**,
    and **beautify backdrops** (gradient background, rounded corners, shadow).
  - Every tool has its own options row, and **⌘Z / ⇧⌘Z** undo & redo.
- **Pin to Screen** — float any screenshot on top of everything; drag to move,
  scroll to resize, double-click or Esc to dismiss.
- **Window capture** without the macOS drop-shadow.
- **Scan QR codes** from any image on your shelf.
- **Image Tools** — combine images into one canvas, or make a before/after GIF.

### Fixed
- **Notch shelf** now reliably opens when you drag a file onto it.
- **⌥-Tab switcher** now raises the chosen window every time (not just once).
- **Much lower memory use** — the editor builds heavy image copies only when a
  tool needs them, instead of up front.

## [1.3.2] — 2026-06-18 (build 21)

### Added
- **Ask AI** — a button in the shelf that answers any question using your shelf
  (and snippets) as context. Fully on-device and private. "What did I save about
  taxes?" actually looks through your stuff first.

### Changed
- **AI results now open in a small window** with **Copy** and **Add to Shelf** —
  they're no longer dumped onto the shelf automatically.
- **Friendlier, more detailed AI summaries** — recaps read like a friend catching
  you up, not a dry list.
- **Smarter search** — matches all your words in any order, case- and
  accent-insensitive; AI smart search now matches by **meaning**, not just exact
  words.

### Fixed
- Notch shelf no longer captures clicks over the menu bar on **external monitors**
  (collapsed pill is click-through there; still opens with a downward swipe).
- Lighter notch mouse handling — no more spawning work on every mouse move.

## [1.3.1] — 2026-06-18 (build 18)

### Changed
- **Notch shelf opens on a downward swipe**, not on hover — flick the pointer down
  out of the notch to open it. It no longer pops open just because the mouse passed
  near the top of the screen.
- **Notch shelf now appears on every display** — the built-in screen uses its real
  notch; external monitors get a matching top-center pill, each with its own shelf.

## [1.3.0] — 2026-06-18 (build 15)

A big feature release. **Everything new is opt-in (off by default) and fully local** —
no accounts, no servers, nothing leaves your Mac.

### Added
- **Snippets** — a searchable library of reusable text (signatures, addresses,
  canned replies). Open it in the dashboard, or grab one from the menu-bar
  right-click ▸ *Copy Snippet*. Click to copy.
- **Window snapping** (Magnet-style) — hold **⌃⌥** and press arrows / **U I J K** /
  **Return** / **C** to snap the focused window to halves, quarters, maximize, or
  center. Toggle in Settings (needs Accessibility).
- **Notch shelf** — a Dynamic-Island-style shelf that lives in the MacBook notch
  (or a top-center pill on notchless Macs). Hover to expand, drop files/images/text
  to add them, click a tile to copy. Toggle in Settings.
- **Screenshot annotation** — mark up captures with arrows, boxes, highlight,
  **blur** (to hide sensitive info), and text, then copy, save, or add to the shelf.
  Auto-open after a screenshot (Settings), or right-click any shelf image ▸
  *Annotate*.
- **Permanent clipboard history** — keep items for 24 hours (default) or Permanent,
  in Settings ▸ Clipboard.
- **On-device AI** (Apple Intelligence) — runs entirely on your Mac, no cost, no
  network:
  - Right-click any text item ▸ *Summarize*, *Clean up*, *Smart title*, or
    **Ask AI** (Reply, Explain, Make formal/casual, Bullet points, Translate, or a
    custom prompt).
  - **Smart Search** — type a natural query and hit the **✨** button to let AI find
    it (runs only when you ask).
  - **Summarize my day** — one click digests everything you collected today.
  - **Auto-title** new items (optional toggle, off by default).
  - Requires an Apple-Intelligence-capable Mac (Apple Silicon, macOS 26) with Apple
    Intelligence turned on.

### Fixed
- **Window-snapping no longer hijacks the app's other shortcuts.** Turning on
  snapping previously broke ⌘⇧S / ⌘⇧V / ⌘⇧7 / ⌘⇧O / ⌘⇧D (they'd snap a window
  instead of doing their job). They all work alongside snapping now.

### Privacy
- On-device AI uses Apple's Foundation Models — prompts and results never leave your
  Mac. AI runs only on explicit action (the one exception, *Auto-title*, is an
  off-by-default toggle).
- Snippets and clipboard history are stored locally with owner-only permissions and
  are excluded from backups. Password managers are excluded from capture by default;
  Private Mode pauses capture entirely.

## [1.2.2] — 2026-06-18 (build 6)

### Fixed / Changed
- **App Cleaner** now shows a list of any files it **couldn't remove**, each with a
  reason (*needs Full Disk Access* / *needs admin* / *protected by macOS*) and a
  Reveal-in-Finder button, so you can find and delete them yourself. The failed
  paths are also saved to the cleanup report on your shelf.
- Built-in macOS apps (on the protected system volume) are now detected and clearly
  marked as un-removable instead of failing silently.

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
