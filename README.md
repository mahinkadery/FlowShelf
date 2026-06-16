# FlowShelf

A smarter temporary shelf for your Mac. Everything you copy, capture, or drag
lands in one place for 24 hours — then clears itself automatically. Pin what
matters to keep it.

Native Swift / SwiftUI + AppKit. No Electron, no cloud, no account. Runs as a
menu-bar app (no Dock icon).

## What works today

**Shelf (v1)**
- **24-hour Shelf** — one list for everything temporary. Search, filter, pin,
  drag items out, auto-clears after a day.
- **Clipboard history** — text, links, images, and copied files are captured
  automatically. Privacy markers (1Password, etc.) and excluded apps are skipped.
- **Screenshot + OCR** — region capture with the native crosshair; the image is
  shelved and (optionally) OCR'd locally with Apple's Vision. Recognized text
  becomes its own shelf item *and* is put on the clipboard.
- **Floating drop-shelf** — a small always-on-top glass card you can drag files
  into while moving between apps, then drag back out at the destination.

**Dashboard** — a real app window (`⌘⇧D` or the tray menu). While it's open
FlowShelf becomes a normal app (Dock icon + Cmd-Tab); closing it drops back to a
menu-bar agent. Sidebar: Shelf · Peek · Clean · Settings.

**Peek — Dock window previews (v2)**
- Hover a Dock icon → a glass popover with **live window thumbnails**; click to
  switch, hover a thumbnail for minimize/close. Enable it in the Peek tab.
- The **Peek tab** also shows every app's open windows in a grid (the always-on
  fallback / switcher).
- Captures thumbnails *only on hover / when Peek is open* — nothing runs in the
  background. Needs Accessibility + Screen Recording.

**Clean — App uninstaller (v3)**
- Drop an app (or pick one) → FlowShelf scans `~/Library` + `/Library` for
  leftovers, scored **High / Medium / Low** confidence and grouped by category
  (Preferences, Caches, Containers, Logs, Login Items…).
- High + precise-Medium matches are pre-checked; loose name matches are Low and
  left unchecked. **Nothing is deleted** — selected items go to the **Trash**
  (reversible via Finder’s “Put Back”), and a cleanup report lands on your Shelf.

## Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧7`  | Screenshot a region → Shelf |
| `⌘⇧O`  | Screenshot a region → OCR + Shelf |
| `⌘⇧S`  | Toggle the floating drop-shelf |
| `⌘⇧V`  | Open the menu-bar shelf/search |
| `⌘⇧D`  | Open the Dashboard |

Click the menu-bar tray icon to open the main shelf any time.

## Build & run

Requires the Swift toolchain (Command Line Tools is enough — no full Xcode needed).

```sh
make run          # build, bundle into FlowShelf.app, and launch
make install      # build and copy to /Applications (recommended)
make bundle       # just produce FlowShelf.app
make clean
```

`make install` copies the app to a stable path in `/Applications`.

> **Permissions persistence — important.** The default build is *ad-hoc* signed,
> whose signature changes on every rebuild, so macOS **resets Accessibility /
> Screen-Recording grants each time you rebuild.** Fine if you install once and
> don't rebuild. If you iterate, create a stable identity once (`make cert-help`)
> and build with `make install CODESIGN_ID="FlowShelf"` — then the grants stick.

### Permissions

FlowShelf asks for permission only when you first use a feature that needs it:

- **Accessibility** — *required for Peek.* It's how FlowShelf reads the Dock
  (which icon you're hovering), lists each app's windows, and switches/closes
  them. Grant it, then **quit & reopen FlowShelf** (macOS only applies the new
  trust on next launch).
- **Screen Recording** — for screenshots (`⌘⇧7` / `⌘⇧O`) and Peek's *live
  thumbnails*. Without it Peek still lists windows and switches to them — you
  just won't see thumbnail images.
- Clipboard, the Shelf, drag-and-drop, and the Cleaner need no special
  permission (the Cleaner only moves files to *your* Trash).

## Architecture

```
FlowShelf.app
├── FlowShelfApp / AppDelegate   – menu-bar status item + popover, wiring
├── Models/ShelfItem             – the one currency: every temp thing is a ShelfItem
├── Store/ShelfStore             – persistence (JSON + files), 24h expiry sweep
├── Store/AppSettings            – clipboard privacy + preferences
├── Clipboard/ClipboardMonitor   – NSPasteboard changeCount polling
├── Screenshot/ScreenshotService – screencapture + Vision OCR
├── Shelf/FloatingShelf          – the floating NSPanel drop-shelf
├── Dashboard/                   – DashboardWindow (activation policy) + DashboardView
├── Peek/                        – WindowService (ScreenCaptureKit), DockObserver,
│                                  DockPreviewPanel, PeekView   ← v2
├── Cleaner/                     – CleanerEngine (scan + Trash), CleanView   ← v3
├── AX/                          – Accessibility helpers + permission prompts
├── Hotkeys/HotKeyManager        – Carbon global hotkeys
├── Util/DragDrop, ItemActions   – ingest/export + copy/reveal/open/OCR
└── UI/                          – MenuBarView, ShelfItemRow, SettingsView
```

Storage rules: text in the JSON store; images/screenshots as compressed PNGs in
`~/Library/Application Support/FlowShelf/files`; files kept as security-scoped
bookmarks (not duplicated). Window thumbnails live in memory only. Nothing leaves
your Mac.

### Debug flags

- `FlowShelf --scan /Applications/Some.app` — print the Cleaner scan and exit.
- `FlowShelf --dashboard` — launch straight into the Dashboard window.
- `FlowShelf --windows` — print permission state + the Accessibility window
  enumeration (what Peek sees), then exit.

## How Peek works (and what was learned from DockDoor)

The Dock-preview implementation follows the approach proven by the open-source
[DockDoor](https://github.com/ejbills/DockDoor):

- **Hover detection** subscribes to the Dock's
  `kAXSelectedChildrenChangedNotification` — macOS itself marks the hovered Dock
  item as the list's "selected child". This is far more reliable than polling the
  mouse and hit-testing icon rectangles (the original buggy approach).
- **Window enumeration** uses the Accessibility API (`kAXWindowsAttribute`), so
  the window *list* works with only Accessibility granted. ScreenCaptureKit is
  used **only** for the thumbnail images (which additionally need Screen
  Recording). Never use ScreenCaptureKit just to learn what windows exist — it
  returns nothing until Screen Recording is granted *and* the app is relaunched.
- **Positioning** reads the real Dock orientation via
  `CoreDockGetOrientationAndPinning` and anchors to the hovered icon's actual AX
  frame, with correct CoreGraphics→Cocoa coordinate flipping.
- **Dismissal** uses a short hysteresis timer: the popover hides only after the
  pointer has been outside both the icon and the popover for ~0.28 s, so it
  survives the gap between icon and card without flickering.
- Window raising/closing uses the Accessibility API plus the private
  `_AXUIElementGetWindow` bridge (the same one AltTab/DockDoor use to map AX
  windows to CoreGraphics window ids).

Multi-display positioning is tuned around the primary display; secondary-display
anchoring may be slightly off. If a preview never appears: confirm Accessibility
is granted, **relaunch**, and that "Dock hover previews" is on in the Peek tab.

## Possible next steps

- Keyboard navigation in the Dock preview popover (arrow keys + Return).
- "Remove leftover files too?" prompt when you drag an app to the Trash yourself
  (FSEvents watch on `/Applications`).
- Per-shortcut customization UI (currently fixed defaults).
