# Peek and dashboard — local build 89

October 25, 2026. Version 1.7.0, build 89, installed at `/Applications/FlowShelf.app`.
Local owner review only: no release, push, tag, notarization, DMG or appcast update.

## Changes

- Removed the 0.40-second exit grace and 0.12-second dismissal polling. Local/global
  mouse-event monitors now initiate dismissal on exit. No enlarged hover region.
- The preview stays interactive while the pointer is actually inside it. Its edge
  touches the Dock icon's boundary, allowing direct travel into window controls
  without a timed grace period. Moving elsewhere starts dismissal immediately.
- Cancel pending hover timers and invalidate queued panel presentation and thumbnail
  results. Stop/disable also cancels an in-progress transition.
- Custom Genie-inspired funnel: 64 raster strips, Core Animation keyframes, 280 ms
  reveal / 160 ms withdrawal toward the current Dock icon. Bottom, left, right and
  top edges supported. These durations are animation time, not dismissal delay.
- Reduce Motion bypasses the funnel, scale and slide. An interrupted reveal closes
  immediately instead of jumping back to the fully expanded card before shrinking.
- Preview width fits up to three windows, constrained to the current display;
  additional windows remain horizontally scrollable. The transition preserves the
  horizontal viewport offset. Late thumbnail results cannot reopen the panel.
- Dashboard navigation uses unboxed monochrome SF Symbols; pane/setting emblems use
  neutral backgrounds. Onboarding retains its existing colors. Meaningful status
  colors, third-party app icons and the approved Notch glass are unchanged.

## Implementation limits

This is a custom animation, not access to Apple's internal Dock Genie implementation.
The settled preview keeps its existing native glass implementation. During the
short deformation it uses a static SwiftUI-rendered content image with a solid
appearance-matched surface; live backdrop refraction is not warped per frame.
Native AppKit cacheDisplay omitted SwiftUI content in the offscreen test, and
ImageRenderer omitted native ScrollView content. The final transition explicitly
renders the same thumbnail strip without a native scroll container.

Research: [Apple Desktop & Dock settings](https://support.apple.com/en-ie/guide/mac-help/mchlp1119/27/mac/27),
[Core Animation transforms](https://developer.apple.com/documentation/QuartzCore/CATransform3D).
No changes to the user's Dock preferences or private animation APIs.

## Verification

- ARM64 debug build passed before the final rendering refinement; final ARM64 and
  Intel release builds passed after all source changes.
- Developer ID deep/strict signature verification passed. Designated requirement
  matches the previous installation, preserving its app identity.
- Installed executable matches the signed local bundle, SHA-256:
  `d27c7b9e795e8fe7c7472025a915f5295af8e8d7c932d4b089b23b01ff0c4155`.
- Read-only process inspection confirmed the final installed executable running
  from `/Applications/FlowShelf.app/Contents/MacOS/FlowShelf` (PID 38806 at verification).
- Both slices retain macOS 14.0 minimum deployment. Existing Core Image kernel and
  Intel deprecation warnings remain; unrelated code was not changed.
- Isolated production-code tests: 32,320 geometry samples, all Dock orientations,
  endpoints, finite positive dimensions and negative-origin screen translations.
- Model cancellation before/during capture, out-of-order application results and
  hide-before-deferred-presentation tests passed. No test window was shown.
- Production icon/thumbnail renders and four synthetic funnel stages were inspected
  offscreen. Synthetic one-window raster averaged about 1.35 ms over 10 warm runs;
  this is not a live Dock performance benchmark.
- `git diff --check` passed. No personal clipboard or real window contents were
  used by the test harness. No system accessibility preferences were changed.

Live visual approval, real Dock magnification/auto-hide, pointer travel into the
preview, multi-window scrolling, multiple displays and Reduce Motion runtime
behavior remain owner checks. Passing compilation/render fixtures is not proof
that those live interactions have been visually verified.

## Rollback and evidence

`backups/pre-peek-build89/FlowShelf.app` is the previous installed build 88.
`project.tar.gz` contains the pre-edit sources, resources and project documents.
The same folder contains `PeekChecks.swift`, test results, build logs and synthetic
render PNGs. Backups are ignored by Git and contain no clipboard history backup.

For rollback: quit FlowShelf, replace `/Applications/FlowShelf.app` with the backed-up
app, then reopen. No data-format or settings migrations were made in this change.
The pre-existing `docs/CODE-REVIEW-2026-10-22.md` was left untouched; its unrelated
findings, including the unconfirmed AirPods-volume cause, are not fixed by build 89.
