# What’s improved in FlowShelf 1.6.1

- **The Notch opens more smoothly.** It no longer flashes an old desktop image,
  and the transparent lower section appears sooner.
- **Music bars finally move independently.** Different bars now react to bass,
  instruments, vocal presence, and treble instead of bouncing together.
- **Notch services switch off properly.** Media, audio capture, battery checks,
  and system HUD monitoring now follow your Notch settings reliably.
- **No unnecessary Input Monitoring prompt.** FlowShelf only starts the system
  HUD monitor when Notch HUDs are actually enabled.
- **Screen Recording prompts behave properly.** FlowShelf no longer keeps asking
  again after permission has already been handled during the current launch.
- **The welcome tour is safer and more polished.** Closing it stops its animations,
  and clicking **Open FlowShelf** no longer crashes the app.
- **Settings are easier to navigate.** They are split into six clear sections,
  screenshot actions share one Capture menu, and clipboard capture shows one
  honest status.
- **Permission Health is more accurate.** Required permissions are separated from
  optional enhancements based on the features you enabled.
- **Clearing the shelf is safer.** FlowShelf asks for confirmation and lets you
  remove only unpinned items instead of immediately deleting everything.
- **Large screenshots and busy histories feel lighter.** Image processing and
  shelf saving now avoid more work on the main interface thread.

FlowShelf remains local-first: these improvements do not add an account or upload
your clipboard, screenshots, or AI requests to a FlowShelf server.
