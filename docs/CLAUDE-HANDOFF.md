# FlowShelf handoff for Claude and Codex

Updated October 1, 2026 (Australia/Sydney). This file is a local handoff, not a
message sent to another model or an upload to an external service.

## Project and owner request

Repository: `/Volumes/Externel ssd/website/personal app/FlowShelf`.
App: `/Applications/FlowShelf.app`, bundle identifier `com.flowshelf.app`.
SPM Swift/SwiftUI/AppKit macOS app. Build with Xcode at
`/Volumes/Externel ssd/Applications/Xcode.app`. Owner requested a fix for a blank
“FlowShelf Settings” window at every startup plus a broader bug audit. Latest
request: save everything for Claude and continue. No public release authorization.

## Current verified checkpoint: version 1.6.2, build 87

Installed October 1, 2026. Universal arm64/x86_64 Developer ID signature passed;
installed and locally built executable SHA-256 match:
`4a5c8fdfa271577659dd880de34ad0e5af8078b68418e69fa79ad903471dbfbb`.
Read-only startup metadata: one FlowShelf process, zero ordinary on-screen
windows. Notch overlays remain. No public release or appcast changes.

Continued the audit: confirmed with native Vision that build-86 OCR and QR
callbacks can refill the shelf and overwrite the clipboard after Clear All.
Build 87 uses the store's shared content generation to reject stale OCR, QR and
capture results. QR cancellation no longer triggers the caller's false “No QR
code found” alert. Invalid/stale screenshot temporary files are now removed.

Tests use generated text/QR images, real Vision, stubbed store/settings and an
isolated named pasteboard; the real clipboard is not read or overwritten. Native
Vision exceeded the initial 10-second test timeout; after a 60-second bound it
completed, reproduced both baseline failures and passed against the fix. This
is recorded as a harness timing limitation, not a proved production latency bug.
The actual ShelfStore separately passes image-write cancellation and pinned-item
regressions using a temporary database. Capture cleanup tests invoke a fixture's
exposed completion method, not the interactive system screen-selection UI.

Evidence: `backups/pre-ocr-fixes-build87/review/`. Build-86 app and source rollback:
`backups/pre-ocr-fixes-build87/FlowShelf.app` and `project.tar.gz`.
Final build-87 source/app handoff archive: `backups/handoff-build87/`.

## Earlier verified checkpoint: version 1.6.2, build 86

Installed and running September 30. Final binary SHA-256:
`88850b1937f38b7a1eb038bcb6da68ddfcd3d22b749b9eb3154b9e93705fa812`.
Universal arm64/x86_64 Developer ID signature verified. Installed/local binaries
match. Two cold launches showed one process and zero ordinary on-screen windows;
only existing high-level Notch overlays. This was metadata, not live visual QA.

Root startup fix: removed `Settings { EmptyView() }` SwiftUI App scene. AppKit
already owned all actual windows; now it also owns app startup and menus. Native
Settings / Command-comma opens dashboard Settings. Reopen handling returns false
after explicitly showing the dashboard to prevent additional fallback handling.

Other changes: Clear All invalidates pending image saves; clipboard/private-mode
changes invalidate pending clipboard images; muted HUD displays zero fill; AI
window close cancels and invalidates late results; termination stops Notch/media/
shake services; installation stages a full copy before replacement and attempts
rollback; failed relaunch leaves the existing session running; unreadable history
cannot be overwritten or have its images orphan-cleaned. Recovery warning explains
that new items in that failed history are temporary until manual recovery/restart.

Full details: `docs/BUG-AUDIT-BUILD86.md`.

## Tests and evidence

`backups/pre-startup-fixes-build86/review/` contains regression Swift fixtures,
install log, results summary and an offscreen HUD gallery. Data tests redirect
storage to temporary directories. They do not touch real history. Confirmed:
- Pending image cancellation, abandoned image cleanup, pinned survival, normal save.
- Damaged shelf/snippets stay byte-identical after mutation/termination; old image
  retained; missing/empty/unreadable inputs correctly distinguished.
- Failed source copy retains installed fixture; successful replacement;
  self-replacement rejection; staging cleanup.
- Muted/zero HUD assertions, native symbol lookup, offscreen layouts, finite
  accessory playback and hidden-view teardown.

Reduce Motion runtime test was skipped (system setting off, unchanged). Live
Settings/edit shortcuts, permissions, Bluetooth, sleep/wake and long-run CPU/energy
remain owner/device checks. No claim that every bug has been found.

The last optional command, rerendering the gallery with a corrected build-number
caption, did NOT run: approval review hit an account usage limit. Tests had already
passed on build-86 code; saved gallery still says build 85 because the harness
caption was inherited. This does not mean the installed app is build 85. Temporary
edited harness may be newer than its saved copy; do not treat /tmp as durable.

## Backups and working tree

- `backups/pre-startup-fixes-build86/FlowShelf.app`: prior installed build 85.
- `backups/pre-startup-fixes-build86/source.tar.gz`: complete pre-edit Sources and plist.
- Earlier: `backups/pre-native-hud-build85/` and `backups/pre-airpods-build84/`.
- Existing tree has many earlier modified/untracked sources, docs and resources;
  they predate this audit. Do not discard them, commit them all blindly, or imply
  the entire Git diff belongs to the current changes.
- Backups do not contain a backup of the owner's live clipboard history.

## Continuation status and next checks

OCR/QR/capture cancellation and temporary-file cleanup are fixed and verified in
build 87 as recorded above. No in-progress build/test process is required to resume.
Next checks are live owner review of Settings/Command-comma, fresh capture/OCR,
and Clear All on disposable content, followed by measured large-history profiling
if the owner requests continuing the performance audit. Do not claim all bugs fixed.

Before further editing: preserve current installed app and source. After app edits:
increment local build, compile/sign/install with `make install`, verify signature,
binary identity and startup, then update this file and owner checklist. If install
or verification is blocked, record exactly what completed and what did not.

Other remaining risks: main-actor image decoding/thumbnail loading needs measured
profiling; rollback failure and failed OS launch were not fault-injected; private
APIs and existing Core Image/x86_64 deprecation warnings remain. No speculative
large rendering rewrite or unrelated feature work during this bug-fix pass.

## Prior product context

AirPods HUD work uses licensed custom 3D atlas artwork, not extracted Apple-private
animations. SF Symbols handle native battery/mute/volume/brightness/checkmarks.
Existing source/docs explain the earlier Notch, onboarding, selection, privacy,
audio-tap and search changes. Owner wants real tested behavior, not repeated small
cosmetic edits or unverified claims. Keep the existing visuals unchanged here.

## Commands and references

Use `make install` from the repo for the universal Developer ID local build.
`git diff --check` is the whitespace check; Swift fixture tests are preserved in
backup review folders (no project-wide formal test suite was introduced).

Apple documents [cooperative task cancellation](https://developer.apple.com/documentation/swift/task/cancel())
and [default scene launch behavior](https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:)).
Cancelling a task alone does not prove an asynchronous callback cannot apply stale
results; validate identity/generation before changing state.
