# Build 86 bug audit — September 30, 2026

Follow-up October 1: build 87 fixes the OCR/QR/capture Clear All race described
below; native Vision baseline reproduction and passing regression evidence are
saved in `backups/pre-ocr-fixes-build87/review/`. See `CLAUDE-HANDOFF.md` for current
installed status. This document otherwise retains the build-86 audit checkpoint.

## Scope

Reviewed application startup/reopen/termination, dashboard and onboarding window
lifecycle, clipboard capture/privacy, shelf and snippet persistence, image work,
AI result cancellation, relocation/relaunch, and Notch service/HUD lifecycle.
Also inspected screenshot/OCR completion, shake monitoring and related cleanup.
This is a targeted code audit with regression checks, not proof that every app
feature or every supported macOS version is bug-free.

## Fixed

1. Blank Settings window: an empty SwiftUI Settings scene coexisted with the
   AppKit dashboard. Removed that second window system, supplied native menus,
   routed Command-comma to actual Settings, and suppressed fallback reopen handling.
2. Clear All/image-save race: invalidate pending encodes and remove abandoned files.
3. Clipboard privacy race: invalidate in-flight images on privacy/capture changes;
   recheck original source exclusion before accepting completion.
4. Muted HUD showed the stored volume; zero values still had a minimum white fill.
5. Closing AI output with the window close button did not cancel pending work.
   Now cancels cooperatively and rejects stale results. This cannot forcibly stop
   third-party work that ignores cancellation.
6. Relocation removed the working installation before proving a full copy succeeded.
   Now stages first and attempts rollback on commit failure.
7. Failed relaunch still terminated the working app. Now keeps it running and warns.
8. Termination did not explicitly stop media/Notch/shake services. Now stops them.
9. Unreadable history looked like an empty store, permitting overwrite and orphan
   image deletion. Shelf/snippet saving is now paused for that session, shelf orphan
   cleanup is blocked, and a warning explains recovery and temporary new items.

## Verification

- Universal arm64/x86_64 release compilation and Developer ID signature passed.
- Installed app is version 1.6.2 build 86; executable matches the local signed build.
- Final installed executable SHA-256:
  `88850b1937f38b7a1eb038bcb6da68ddfcd3d22b749b9eb3154b9e93705fa812`.
- Two cold-launch metadata checks: one process, zero layer-0 on-screen windows;
  only existing higher-level Notch overlays were listed. Window titles were not
  available, so this establishes absence of ordinary startup windows, not a visual
  screenshot inspection. No automated UI clicking was performed.
- Isolated store tests: Clear All during encoding, invalidated image completion,
  cancelled-file cleanup, normal save, pinned preservation.
- Isolated installer tests: failed source copy retains old installation, successful
  replacement, self-replacement rejection, staging cleanup.
- Isolated damaged-history tests: malformed shelf/snippets remain byte-identical
  after mutations and termination; an old unreferenced image is retained; warnings
  are emitted; missing, valid-empty and unreadable paths are distinguished.
- Fixtures redirect storage to temporary directories. Recovery alert presentation
  is stubbed in tests; actual parsing/protection code runs. Live data is not modified.
- `git diff --check` passed. Regression sources/logs are saved under
  `backups/pre-startup-fixes-build86/review/`.
- HUD regression: mute/zero-level assertions, native symbols, static offscreen
  layouts, finite accessory playback and hidden-view teardown passed. The gallery
  was visually inspected; this is not live animation approval. Reduce Motion
  runtime comparison was skipped because the system setting was off and unchanged.

## Remaining risks and unverified cases

- Live Settings/editing shortcuts, permissions, login launch, Bluetooth reconnect,
  multiple displays and sleep/wake need owner/device checks. No claim of universal
  OS-version compatibility or measured energy/animation performance is made.
- OCR completion is a separate asynchronous path; clearing history during OCR may
  still deliver a later text result. The image-write generation fix does not cover
  all operations that create text. Needs a targeted reproduction before changing
  the intended screenshot/OCR workflow.
- Image-to-CGImage conversion and uncached thumbnail loading still involve the
  main actor. Profiling with a large history is required before claiming no hitches.
- Relocation rollback failure was not fault-injected. A failed rollback retains
  the `.FlowShelf-previous-…app` backup rather than deleting it. OS launch failure
  and real AI-model cancellation were reviewed in code, not forced on this machine.
- Existing Core Image kernel deprecation and SDK x86_64 deprecation warnings remain.
  These are not new runtime failures; changing the Notch rendering architecture is
  outside this bug-fix pass. Existing private API risks remain documented separately.
- Damaged history is preserved, not automatically repaired. Saving is disabled for
  that history until a valid file is restored and the app restarted. No evidence of
  actual corruption in the owner's data was gathered or required for this fix.

## References and rollback

Apple's [default launch behavior](https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:))
and [scene restoration behavior](https://developer.apple.com/documentation/swiftui/scene/restorationbehavior(_:))
were reviewed while tracing the duplicate SwiftUI/AppKit window ownership.

Pre-change app and source are preserved in `backups/pre-startup-fixes-build86/`.
No public release, push, tag, DMG, notarization or Sparkle appcast update was made.
