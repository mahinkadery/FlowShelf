# Owner review checklist

Updated October 1, 2026. Current review target: FlowShelf 1.6.2, local build 87.
Installation/automated verification is recorded in [the roadmap](UPGRADE-ROADMAP.md).
Unchecked means awaiting your review, not a confirmed failure. No UI automation
is being performed, as requested. Use disposable test content, never real passwords.
Nothing here authorizes a release. Scrolling screenshots remain excluded.

## Build 87 — stale OCR/QR and screenshot cleanup

- [ ] Normal screenshot and OCR still add the expected fresh result.
- [ ] With disposable content, start OCR/QR and Clear All before it finishes:
  no late item/clipboard overwrite or false “No QR code found” alert should appear.
- [ ] Confirm startup stays quiet and Command-comma opens real Settings.

Installed universal build/signature/binary identity verified. Read-only startup
metadata shows one app process and zero ordinary windows. Native Vision tests
reproduce both old OCR/QR races and pass with the fix using an isolated clipboard.
Fresh/stale/invalid capture cleanup passes without interacting with screen capture.
These are not live screen-selection or visual-approval checks.
Rollback: `backups/pre-ocr-fixes-build87/`; continuation: `docs/CLAUDE-HANDOFF.md`.

## Build 86 — startup and data-safety fixes

- [ ] Quit and reopen normally: no empty “FlowShelf Settings” window should appear.
- [ ] Open the dashboard; press Command-comma. The real Settings pane should open.
- [ ] Check Copy/Paste/Undo in editable fields and closing/minimizing the dashboard.
- [ ] Close an AI result while it is loading; reopening must not show that stale result.
- [ ] Preview Muted: the volume bar should be empty, not a nonzero sliver.
- [ ] Using disposable images, check Clear All and switching Private Mode while copying.
- [ ] Review startup/login, multiple displays and sleep/wake on your normal setup.

Two cold-launch checks of the installed final build found one FlowShelf process
and zero on-screen ordinary windows. This was window metadata inspection, not
automated clicking or visual approval. Universal build, signature and binary
identity checks passed. Isolated tests cover pending image cancellation, pinned
preservation, safe installer replacement, and damaged history protection without
touching real clipboard data. Do not deliberately corrupt your live database.

Unreadable shelf/snippet history now triggers a warning and pauses saving that
history for the session; new items in it are temporary until the file is restored
and the app restarted. Existing files/images are preserved, not auto-repaired.
Full audit scope and remaining checks: [build 86 audit](BUG-AUDIT-BUILD86.md).
Rollback build 85 and source: `backups/pre-startup-fixes-build86/`.
No release or appcast update was performed.

## Build 85 — native event icons

- [ ] Notch → Preview: review Charging, Low battery, Low Power Mode, Volume,
  Muted, Brightness and AirPods connection confirmation at normal screen size.
- [ ] Check the native pulses/draw-on settle promptly and never continue looping
  after the HUD closes. These demos do not change power/audio settings.
- [ ] With Reduce Motion enabled, verify static symbols without pulses or draw-on.
  The automated runtime check was skipped while that system setting was off.
- [ ] macOS 14–15 device check: native bounce fallback and battery symbols.

Build 85 is installed and signature/binary checks pass. Offscreen layouts and
symbol lookup pass; live animation appearance still needs owner approval.
Rollback build 84 is at `backups/pre-native-hud-build85/FlowShelf.app`.

## Build 84 — AirPods connection presentation

- [ ] Dashboard → Notch → Preview → AirPods connection demo: inspect the new
  upright, overlapping artwork and compact → expanded → compact presentation.
  Test the AirPods Pro demo too; both deliberately use the same licensed artwork.
- [ ] Reconnect your actual AirPods: check the same artwork appears, the actual
  name remains identifiable, and no stale HUD reappears after another event.
- [ ] Review at normal screen size, including the physical camera area. The green
  check means connected, not a reported battery percentage.
- [ ] With Reduce Motion enabled, check the presentation stays static rather than
  performing the multi-stage morph. Disable it again only if you prefer.

Build 84 is installed; signing, architecture, routing, atlas, offscreen layout
and production-model timing/cancellation checks passed. Live reconnection and
your visual approval remain unverified. Build 83 rollback is preserved in
`backups/pre-airpods-build84/FlowShelf.app`.

Build 72 verification: universal compilation, Developer ID signature,
installed-binary identity, isolated privacy/batch tests and OCR regression checks
passed. Your UI and receiving-app checks below are still intentionally unchecked.
Build 73 is installed and running with the opt-in audio-tap prototype. Universal
build/signature/binary checks and synthetic audio/lifecycle checks passed; details
are in the roadmap. Live capture, permission prompts and your visuals remain unchecked.
Build 74 is installed with the notch background-work fixes. Universal compilation,
Developer ID/binary identity and isolated visibility/audio regressions passed.
Real-device capture lifecycle, visual smoothness and energy gains remain unchecked.
Builds 75–76 add pausable media motion and optional private window symbols. Build 76
is installed/running; signature, binary identity and both architectures' import
tables were verified. Synthetic motion, missing-symbol and audio checks passed.
Build 77 introduced action confirmations and safer hardware HUD fallbacks. Build 78
removes those misplaced floating confirmations and implements the requested system
events inside the notch instead. Build 78 is installed/running; universal compilation,
signature, binary identity and synthetic event checks pass, recorded in the roadmap.
No live app UI was opened or automated for inspection.

Build 79 replaces build 78's cards with compact iPhone-inspired notch animations.
Static layouts were checked using offscreen renders; this is not live visual approval.
Build 79 is installed/running. Universal compilation, signature/binary identity,
event/geometry checks and isolated lifecycle tests passed. No release was published.

Build 80 introduced 3D-rendered accessory animation. Universal
compilation, signature, executable/resource identity and isolated asset/playback
checks passed. Offline renders were inspected; live motion remains for your review.

The owner rejected build 80's AirPods resemblance. Build 81 replaces the AirPods Pro
artwork and adds a visible device name below the camera strip. Other accessory models
are unchanged. The new artwork is a detailed raster with a finite depth-style entrance,
not a real turning mesh. Focused tests and offscreen layout inspection passed.
Build 81 is installed and running; universal release build, Developer ID signature,
installed executable and artwork identity checks passed. It has not been released.

## AirPods routing correction — build 83

Build 82 did not fix the owner's actual event: the ordinary AirPods branch still
loaded old artwork. Build 83 removes that runtime branch and uses the supplied
model for both AirPods symbols. The current CoreAudio output name was tested
through event classification and artwork selection successfully, without changing
the audio output. Offscreen renders are not a live reconnection test.

- [ ] Reconnect your actual AirPods and inspect the new artwork and one-second turn.
- [ ] Try both AirPods preview entries: neither should show the old long-stem model.
- [ ] Check that long connection names still show the AirPods name at the end.

## AirPods mesh review — builds 82–83

Build 81's flat illustration was rejected. Build 82 uses the owner-supplied GLB
from Jed Falcone (CC BY 4.0), rendered offline into a finite one-second animation.
It is installed/running; compilation, signature, executable/assets identity,
frame/crop/lifecycle checks and offscreen HUD renders passed. No live UI approval
or real-device verification is implied. The previous app/source are backed up.

- [ ] Dashboard → Notch → Preview → AirPods Pro · connection demo: inspect the new
  white product artwork, Connected label, device name and green connection check.
- [ ] Check entry/exit, long device names, a physical-notch Mac and external display.
  The blank top strip reserves space for the camera. No AirPods battery is invented.
- [ ] Check Reduce Motion, Low Power Mode, repeated previews and actual audio-route
  changes. This is a one-shot one-second turn rendered from a real 3D mesh,
  not a flat image tilt or a continuous spin. Both AirPods variants use the chosen
  Pro-shaped illustration; headphones stay separate. Completely renamed devices
  without an AirPods keyword still cannot be identified by the current name heuristic.
- [ ] Confirm existing expanded Liquid Glass remains unchanged.

## Start here

- [ ] Open Settings → About and confirm the installed review build.
- [ ] Review the dashboard, menu-bar shelf and floating shelf visually. Confirm
  the inset selection circles are aligned, readable and do not overlap icons.
- [ ] Confirm the approved notch glass appearance has not changed.

## Legacy 3D accessory review — build 80 (AirPods Pro superseded)

- [ ] Dashboard → Notch → Preview notch animations: try AirPods Pro, AirPods and
  Headphones 3D demos. Look for actual changing depth, overlapping parts and surface
  highlights, not a flat symbol tilting. These are stylized models, not exact Apple assets.
- [ ] Confirm the turn completes once, settles facing forward, and does not restart
  or loop while the connection HUD remains visible. The green check is not a battery gauge.
- [ ] Enable Reduce Motion / Low Power Mode: expect a still 3D pose, not a spin.
  Restore your preferred settings afterward; these checks have not been automated.
- [ ] Rapidly replace a demo, open/close the shelf, disable the notch, and lock/unlock.
  No stale animation should replay. Check multiple monitors and actual audio routing.
- [ ] Compare Activity Monitor before/during/after several previews. Code bounds the
  source-image cache; total RAM/GPU usage and perceived smoothness need real-device review.

## Compact notch animation review — builds 79–80

- [ ] Dashboard → Notch → Preview notch animations → Preview. Try all five demo
  event types. These are simulated, explicitly labeled examples—not real readings.
- [ ] AirPods: 3D product turns/settles left of the camera; a green ring then checkmark
  draws on the right. This check means connected for audio, not battery percentage.
- [ ] Charging / low battery: slim text on the left, numeric level and battery on
  the right. No tall notification card; nothing overlaps the camera cutout.
- [ ] Low Power Mode: yellow On/leaf versus subdued Off/leaf; distinct from charging.
- [ ] Notice the entrance and gentle withdrawal. Try another preview during exit:
  the previous dismissal must not cut the new one short. Test with music playing.
- [ ] Test Reduce Motion and multiple screens. Stop/disable Notch or HUDs midway;
  no leftover symbol or delayed restart. Confirm the expanded shelf glass is unchanged.

## Notch system-event behavior — builds 78–79

- [ ] Dashboard → Notch → System events in the notch: enable it. With the shelf
  collapsed, connect/select AirPods or headphones as the Mac's audio output. The HUD
  should grow from the notch and disappear after about 3 seconds; its tooltip and
  accessibility label carry the device name.
  Bluetooth connection alone without becoming the audio output is not detected.
- [ ] Switch back to the Mac speakers or another output. Confirm the correct name,
  no repeated card for an unchanged route, and no invented AirPods battery percentage.
- [ ] Change Low Power Mode in macOS Battery settings, if supported. Check both On
  and Off states. Simply opening FlowShelf must not announce the initial state.
- [ ] Plug in the charger and test a genuine low-battery event when convenient.
  Verify the reported battery level and no text behind the physical camera cutout.
- [ ] Repeat events quickly: newest card wins without an older dismissal hiding it.
  Open the shelf while a card is visible: it should clear, not replay after closing.
- [ ] Disable System events in the notch while a card is showing. It must disappear;
  reconnecting/changing power should remain quiet. Repeat with Notch itself disabled.
- [ ] Lock/sleep and resume: no stale queued card. Relaunching should also be quiet.
- [ ] Copy, pin and change Private Mode: the unwanted bottom-screen HUDs are gone.
- [ ] Try a missing image/file and an unwritable save destination using disposable
  data. A missing copy source should leave the existing clipboard untouched; an
  export error should show an error alert. Cancel export: no success confirmation.
- [ ] Test Reduce Motion, Reduce Transparency, VoiceOver, multiple monitors and
  fullscreen apps. These visual/accessibility behaviors are not manually verified.
- [ ] Press volume/mute/brightness keys. The system overlay should remain intact;
  optional notch indicators appear only with readable values. Test external fixed-
  volume devices and unsupported displays: no invented 0%/50% custom indicator.
- [ ] Disable Notch/system HUDs while holding/releasing a hardware key, then lock/
  unlock. No delayed custom HUD should appear after the monitor has stopped.

Automated checks use synthetic readings and presentation state only. No live key,
capture, user clipboard, export or app UI automation was used for verification.

## Selection and batch transfers — builds 67–70

- [ ] Tick/untick items on each of the three shelf surfaces. A tick must only
  change selection, not copy content. Clear selection should restore the count.
- [ ] Select two text items and use the batch Copy action. Paste into a text
  editor: order follows the visible shelf, with blank lines between items.
- [ ] Select files/images and use the **batch drag handle**, not a single row,
  to drag into Finder. Both items should arrive; originals must remain even
  with Command held. Escape should cancel the drag without deleting anything.
- [ ] Try mixed text/file selection. Copy explains the unsupported combination;
  dragging depends on the receiver. Verify which items the receiving app imports.
- [ ] Change search/filter or delete a selected item. Selection must not retain
  hidden/deleted IDs. Selection is independent in each shelf surface.

## Image text search — build 71

- [ ] Settings → Capture & AI → Image text search: enable **Search text inside
  images**. It is off by default. Wait for the status to finish indexing.
- [ ] Save a screenshot with a distinctive readable word, then search that word
  on the shelf. The original image should appear, without an extra text item or
  replacing the clipboard. Tiny lettering can be missed or misrecognized.
- [ ] Disable indexing: new scans stop, but existing indexed text remains
  searchable. Private Mode also pauses/cancels indexing; leaving it resumes.
- [ ] Use **Clear indexed text…** and confirm: images remain, extracted text is
  removed and indexing turns off. Re-enabling rebuilds the search index.
- [ ] If the status reports unread images, try Retry and note persistent failures.

## Clipboard privacy rules — build 72

- [ ] Settings → Privacy & Permissions → Ignored clipboard types: expand the
  locked built-in list. These rules must not have removal controls.
- [ ] Add a custom type supplied by an app you use. Check the warning before
  confirming; matching is exact and case-sensitive, with no wildcard patterns.
- [ ] Optional controlled test: temporarily add `public.utf8-plain-text`, then
  copy a unique dummy sentence from TextEdit. It should still paste normally
  into other apps, but not be saved to FlowShelf. Remove the rule immediately,
  copy a different dummy sentence and confirm normal capture resumes.
- [ ] Try duplicate/empty/invalid entries. They should not create duplicate or
  broken rules. Canceling the confirmation must not add a rule.
- [ ] Restart FlowShelf and confirm custom rules persist. Removing custom rules
  must leave built-in protection enabled. Existing shelf history must remain.
- [ ] Using only dummy credentials, check an excluded password-manager app.
  Markers are conventions—not a guarantee that every app marks secrets.

## Notch background work — build 74

- [ ] Open/close/reopen the notch quickly over a changing background. Confirm the
  transparent bottom retains its approved appearance, without stale flashes or a
  newly delayed lens. Repeat after leaving it collapsed for several seconds.
- [ ] Disable/re-enable Notch, change displays/Spaces, and lock/unlock or sleep/wake.
  Confirm the notch and bars resume on the correct display, without frozen frames.
- [ ] With music playing, enable macOS Reduce Motion: the bars should become static.
  Turn it off and confirm normal measured/decorative behavior resumes as before.
- [ ] Compare Activity Monitor with the notch open, collapsed and disabled. Use the
  same playback/background conditions; audio capture is a separate enabled service.
  No specific CPU/energy improvement has been measured or promised yet.

## Title and progress motion — build 75

- [ ] Play a long song title: it should wait two seconds, scroll, and repeat.
  Short titles should stay still. Change tracks and resize the notch layout.
- [ ] Pause playback, close/reopen the notch, change Spaces, and lock/unlock.
  Confirm scrolling resumes cleanly only while visible and playing.
- [ ] Turn Reduce Motion on/off while the notch is open. Long titles should become
  static immediately, then restart when motion is allowed again.
- [ ] Scrub the progress bar while playing and paused. Confirm the chosen position
  is sent to the player and the elapsed position resumes correctly.

Automated checks cover visibility helpers/observer cleanup and render-key identity,
not actual occlusion delivery, capture races or visual smoothness on your Mac.

## Window API compatibility — build 76

- [ ] Confirm Peek, Dock previews and the window switcher still list, preview and
  raise the expected windows. Try minimized windows and multiple monitors.
- [ ] If a missing-component banner appears, record the macOS version; repeatedly
  changing Screen Recording permission will not restore a removed OS symbol.
- [ ] Older macOS machines still need an end-to-end test. Injected missing-symbol
  tests passed, but no actual Apple API was removed or patched for verification.

See [the private API audit](PRIVATE-API-AUDIT.md) for the build 77 HUD follow-up and
remaining media-helper/permission-state concerns. Real device tests remain open.

## Experimental audio taps — build 73

- [ ] Dashboard → Notch: leave Compatibility selected initially and confirm the
  approved notch glass, gradient and six-bar layout are unchanged.
- [ ] Enable Notch, Now-playing media and Audio-reactive bars. Play music, then
  choose **System audio (experimental tap)** in Audio source and confirm. macOS
  may request separate audio-recording permission. This mode analyzes the system
  mix; do not enable it during a private call just to test the bars.
- [ ] Check the status reports received audio, not just starting/connected. Test
  bass-heavy and higher-frequency passages. The six ranges are frequency energy,
  not lyric detection or AI instrument separation. No sound should be muted.
- [ ] Choose **Current player only (experimental tap)**. Check the status names
  the expected player's bundle ID. It follows the reported Now Playing player;
  playing another app can change that target. Browser/helper processes may not
  match. It must not silently switch to capturing all apps if isolation fails.
- [ ] Pause/resume, toggle bars/media/notch off and on, and switch players.
  Capture should stop/reset while disabled and use only the new selected source.
- [ ] Lock/unlock and sleep/wake with media playing. Check no stale moving bars
  or restarted capture while the feature remains disabled. OS recording indicators
  can also reflect other active features, including the unchanged notch lens.
- [ ] Switch speakers/headphones/Bluetooth output. The prototype intentionally
  stops on output/format changes and offers Retry; verify reconnecting works.
- [ ] If permission is denied or the source is silent, inspect the status. It
  should not repeatedly prompt or fall back to wider capture. Grant access via
  macOS settings if desired, then Retry. Some protected/helper audio may be silent.
- [ ] Switch back to **Compatibility (ScreenCaptureKit)** to undo the experiment.
  Confirm only one engine runs, normal playback continues, and the choice persists.
- [ ] Compare Activity Monitor during the two engines and after disabling bars.
  Real-device CPU, memory, energy and Bluetooth behavior still need profiling.

Automated build 73 checks use generated PCM and a fixture capture backend. They
do not verify real macOS permission prompts, live tap delivery or specific music
apps. The prototype is off by default, does not save/upload audio, and never uses
the microphone. No live audio capture or UI inspection was run for these tests.

## Earlier updates and broader regressions

- [ ] Copy several Finder files and confirm every file reaches the shelf.
- [ ] Copy formatted text. Normal Copy should preserve supported RTF; Copy as
  Plain Text should remove formatting in the receiving editor.
- [ ] Ask AI about a unique phrase in an older text item; inspect its sources.
  Ask about absent content and check for a no-match response. AI can still err.
- [ ] Change query/filter during AI search. Old results must not replace the
  current query's results; cancellation should leave the app responsive.
- [ ] Verify clipboard Active / Paused by Private Mode / Disabled behavior.
  If testing macOS denied/ask access, check no repeated background prompts;
  restore your preferred permission afterwards.
- [ ] Check normal music playback, pause/resume, player switching and sleep/wake.
  Report a stuck media status; helper failure recovery needs separate testing.
- [ ] Check window switching with minimized windows, multiple monitors,
  Mission Control and sleep/wake. These runtime cases remain unverified.
- [ ] In Activity Monitor compare idle use with indexing off, active indexing,
  and after it finishes. Note persistent CPU/RAM growth or lag; record build,
  image count and steps. OCR is optional and processes one downsized image at a time.

## Before release — only after your approval

- [ ] Send any visual/behavior issues with the build number and reproduction steps.
- [ ] Approve the installed visuals and feature behavior explicitly.
- [ ] Ask for release preparation: final regression/signing checks, plain-English
  update notes, Developer ID build, notarization, DMG, GitHub release and Sparkle
  appcast verification. Local installation alone does not do these steps.

## Rollback and reporting

The build 72 app and source snapshot are in `backups/pre-audio-tap-build73/`.
The build 71 backup remains in `backups/pre-clipboard-privacy-build72/`.
Older per-build backups are listed in the roadmap. Backups are not a backup of
your live shelf database. Avoid resetting/deleting your data to test a rollback.
Ask for restoration if needed; newer optional metadata may be lost when an old
version rewrites history.

When reporting an issue, include: build, shelf surface, steps, expected result,
actual result and (if helpful) a screenshot. Keep personal clipboard data hidden.
