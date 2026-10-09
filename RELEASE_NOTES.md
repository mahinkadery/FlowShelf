# What’s new in FlowShelf 1.7.0

### New

- **Find text inside your saved images.** FlowShelf can now read the words in
  your screenshots and photos, so a search finds them by what they *say* — not
  just their file name. It runs entirely on your Mac, and it is **off until you
  turn it on** in Settings. You can clear what it has read at any time.
- **Select several items at once.** Tick a few shelf items, then copy them
  together or drag the whole group into another app in one motion. Your
  originals stay on the shelf.
- **Keep sensitive copies off the shelf.** FlowShelf already skips things your
  password manager marks private. Now you can add your own list of clipboard
  types to ignore, so the copies you choose never land on the shelf.
- **The Notch reacts to more of your Mac.** Switching to AirPods, headphones, or
  another speaker shows a quick pill in the notch (with a small AirPods
  animation), and so do Low Power Mode and brightness changes.
- **A sharper music visualizer (optional, experimental).** A new mode can read
  audio straight from your current player or from the whole system for tighter,
  more responsive bars. It is **off by default** — the standard visualizer works
  exactly as before — and you can switch back any time if your setup doesn’t
  support it.

### Fixed

- **Clear All really clears.** A screenshot scan or QR read that finished a
  moment late can no longer quietly refill the shelf or overwrite your clipboard
  after you’ve pressed Clear All.
- **No more false “No QR code found.”** Cancelling a QR scan no longer shows that
  message.
- **Safer updates.** When FlowShelf moves or replaces itself, it now copies the
  new version in full before swapping, and restores the working version if
  anything goes wrong.
- **Your history is protected if a file goes bad.** If FlowShelf can’t read your
  saved shelf or snippets, it stops saving over them and explains how to restore
  a good copy, rather than risking your data.
- **Quitting shuts everything down cleanly.** Media, audio capture, and notch
  monitoring all stop as they should.

FlowShelf stays local-first: this update adds no account and still never uploads
your clipboard, screenshots, or AI requests to a FlowShelf server. The image
text-reading and the experimental audio visualizer both run only on your Mac,
and both stay off until you switch them on.
