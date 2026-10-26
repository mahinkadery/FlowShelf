# Peek hover follow-up — build 90

October 26, 2026. FlowShelf 1.7.0 local build 90 installed and running.
No release, tag, push, notarization, DMG or appcast changes.

The owner approved build 89's animation but reported slower appearance and losing
the preview while moving from the Dock icon toward its controls.

## Fix

Both the Dock accessibility selection callback and pointer-event handler now use
one shared keep-open region: icon, preview and the connecting tapered corridor.
The corridor spans the real gap and allows diagonal movement toward the preview's
edges. Original and updated icon bounds account for Dock magnification changes.
Leaving this combined region still starts dismissal immediately, without a grace
timer. Entering another actual Dock app still switches previews.

Default appearance delay is 0.10 seconds rather than 0.28. This Mac's saved setting
was also changed from 0.28 to 0.10 after quitting the old process. Other existing
users' custom preferences are not migrated or overwritten by the source change.
The appearance timer now runs in common run-loop modes. The preview panel explicitly
accepts mouse-moved events. Genie source and timings are unchanged byte-for-byte.

Primary API reference: [Apple mouse-tracking documentation](https://developer.apple.com/documentation/appkit/nstrackingarea).
The corridor is application hit-testing logic, not an undocumented Apple effect.

## Verification

- Reproduced build 89 closing in the icon-to-preview gap using its actual observer
  code in an isolated fixture. No pointer movement or live app UI automation.
- The fixed observer survives Dock deselection in the corridor and over controls;
  exits immediately outside; leaving before presentation cancels pending timers.
- 1,212 straight/diagonal corridor samples across bottom, top, left and right Dock
  orientations pass. Neighboring-icon/outside points are rejected.
- Previous 32,320 geometry samples, stale-load/deferred-show cancellation and
  synthetic render regressions pass against the new sources.
- Both release architectures compile. Developer ID strict/deep signature and
  installed/local binary identity pass; signing requirement matches build 89.
- Installed process was verified at `/Applications/FlowShelf.app/Contents/MacOS/FlowShelf`.
  Installed SHA-256: `6fadef5ebbfad6167c9231aff048058534ff0652ad54672e7ab7fc2e6c7ca226`.
- Saved hover-delay readback is 0.1. `git diff --check` passes.

Fixture substitutions expose private members, supply synthetic pointer coordinates,
and stub the Dock AX query and preview panel. They test production observer decisions,
not real-device accessibility event delivery or successful clicks on actual windows.
Owner verification remains: move into Peek, click close/minimize/activate, move away,
and try magnification/auto-hide and secondary displays. No live visual approval of
this fix is claimed. No personal clipboard history or real window captures were used.

## Rollback

`backups/pre-peek-build90/` retains build 89, pre-edit source/documents, the previous
hover delay, test fixtures, baseline reproduction, passing results and build log.
Quit FlowShelf before restoring the saved app; restore hover delay to 0.28 if desired.
No data-format migrations or unrelated audio/dashboard changes were made.
