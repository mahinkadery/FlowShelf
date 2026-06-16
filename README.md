<div align="center">

<img src="Resources/AppIcon.png" width="128" alt="FlowShelf icon" />

# FlowShelf

### The temporary workspace your Mac deserves.

Keep today's files, screenshots, links, and windows within reach —
then clear the clutter automatically.

[![Download](https://img.shields.io/badge/Download-for%20macOS-FFC107?style=for-the-badge&logo=apple&logoColor=black)](https://github.com/mahinkadery/FlowShelf/releases/latest)

![Platform](https://img.shields.io/badge/macOS-14%2B-1C1C1C?logo=apple)
![Apple Silicon + Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-1C1C1C)
![License](https://img.shields.io/badge/license-PolyForm%20Strict-orange)
![Latest release](https://img.shields.io/github/v/release/mahinkadery/FlowShelf?color=FFC107)
![Downloads](https://img.shields.io/github/downloads/mahinkadery/FlowShelf/total?color=FFC107)

</div>

<!-- Add a hero screenshot here once you have one:
![FlowShelf](docs/screenshot.png)
-->

---

## What is FlowShelf?

FlowShelf is a lightweight, native macOS menu-bar app that gives you a **temporary
home for everything you collect today** — copied text, links, screenshots, dragged
files. It remembers them for 24 hours, keeps them a keystroke away, and clears
itself so your Mac stays tidy. Pin anything you want to keep.

No Electron. No cloud. No account. **~7 MB, everything stays on your Mac.**

## Features

| | |
|---|---|
| 🗂️ **Shelf** | A 24-hour home for everything you collect — text, links, images, files. Search it, pin it, drag items back out. Auto-clears so it never piles up. |
| 📸 **Capture** | Region screenshots with the native crosshair + **local OCR** (Apple Vision). The image lands on the Shelf and the recognized text goes to your clipboard. |
| 🪟 **Peek** | Hover a Dock icon to see **live previews** of that app's windows; click to switch, or close/minimize right from the preview. |
| 🧹 **Clean** | Drag an app in to uninstall it — FlowShelf finds the leftovers, scores them by confidence, quits the app, and moves everything to the Trash (reversible). |

Plus a **floating drop-shelf** you can shake-summon at your cursor, and a unified
dashboard tying it all together.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧V` | Open the Shelf / search |
| `⌘⇧S` | Toggle the floating drop-shelf |
| `⌘⇧7` | Screenshot a region → Shelf |
| `⌘⇧O` | Screenshot a region → OCR + Shelf |
| `⌘⇧D` | Open the Dashboard |

## Privacy

FlowShelf is **private by design**:

- **Everything stays on your Mac** — no accounts, no cloud, no analytics.
- Clipboard history is stored **owner-only** and **excluded from iCloud/Time
  Machine backups**.
- Password managers and apps you exclude are **never recorded**; "Private mode"
  pauses capture entirely.
- The **only** network request is a once-a-day check for app updates.

## Install

1. **[Download the latest `.dmg`](https://github.com/mahinkadery/FlowShelf/releases/latest)**
2. Open it and **drag FlowShelf into Applications**.
3. **First launch:** because the app isn't notarized yet, macOS shows a security
   prompt. Open **System Settings → Privacy & Security → scroll down → "Open
   Anyway."** (One time only.)
4. Grant permissions when asked — **Accessibility** powers Peek; **Screen
   Recording** adds the live window thumbnails. FlowShelf asks only when you first
   use a feature that needs them.

FlowShelf keeps itself up to date automatically (via Sparkle); you can also check
manually in **Settings → General**.

## Build from source

Requires the Swift toolchain (Xcode Command Line Tools are enough — no full Xcode).

```sh
git clone https://github.com/mahinkadery/FlowShelf.git
cd FlowShelf
make install      # build, bundle, sign, install to /Applications
```

Other targets: `make run` (build + launch), `make dmg` (build a distributable
disk image), `make clean`. Contributors build with an ad-hoc signature by default.

## Architecture

```
FlowShelf.app
├── FlowShelfApp / AppDelegate  – menu-bar status item, popover, wiring
├── Models / Store              – ShelfItem, persistence + 24h expiry
├── Clipboard                   – NSPasteboard monitoring
├── Screenshot                  – screencapture + Vision OCR
├── Shelf                       – floating drop-shelf + shake-to-summon
├── Peek                        – Dock window previews (Accessibility + CGS capture)
├── Cleaner                     – app uninstaller (scan + Trash)
├── Dashboard / UI              – SwiftUI views
└── AX / Util                   – Accessibility helpers, updater, helpers
```

Native Swift + SwiftUI + AppKit. Window thumbnails via the same window-capture API
DockDoor/AltTab use; OCR via Apple's Vision; updates via Sparkle.

## Contributing

Issues and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) and the [changelog](CHANGELOG.md).

## License

FlowShelf is **source-available**, not open-source. You may read, learn from, and
contribute to the code, but you may **not redistribute, sell, or ship your own
copy** of the app, and the **FlowShelf name and icon are reserved**. Licensed under
the **[PolyForm Strict License 1.0.0](LICENSE.md)**.

## Support

FlowShelf is free. If it saves you time, you can
**[buy me a coffee ☕️](https://buymeacoffee.com/mahinkadery)**.

<div align="center">
<sub>Built for Mac by <a href="https://github.com/mahinkadery">@mahinkadery</a></sub>
</div>
