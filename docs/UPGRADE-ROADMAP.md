# FlowShelf upgrade roadmap

Approved September 20, 2026. Scrolling screenshots are explicitly excluded.
Local app changes must be installed for visual review. Do not publish a release
until the owner approves it. Retain existing macOS 14 support.

Owner follow-up: [review checklist](OWNER-REVIEW-CHECKLIST.md). Keep this updated
after each local install; automated checks are not visual approval.

## Build 87: finish Clear All protection for OCR, QR and captures

Installed October 1, 2026. Shared content generation rejects late Vision results
and screenshot completions after Clear All, before they add items or write the
clipboard. QR caller suppresses stale-result alerts. Invalid/stale capture files
are cleaned up. Fresh capture/OCR/QR behavior remains intact in isolated tests.

Native Vision baseline reproduced both races. Post-fix tests pass using generated
images and a named test clipboard; actual ShelfStore image cancellation regressions
also pass with temporary storage. Universal build, strict signature, installed
binary identity and read-only startup metadata passed. Live UI still needs review.
No public release. Build 86/source preserved in `backups/pre-ocr-fixes-build87/`.
Local Claude entry point: `CLAUDE.md`; full handoff: `docs/CLAUDE-HANDOFF.md`.

## Build 86: remove the blank Settings window and protect pending work

Installed September 30, 2026. Removed the empty SwiftUI Settings scene; AppKit
now owns application startup and menus, with Command-comma routed to the actual
dashboard Settings pane. Reopen events are handled once, without default fallback.

- Pending image writes are invalidated by Clear All, clipboard disable/private
  mode transitions and monitor shutdown; cancelled image files are cleaned up.
- Muted volume reports zero and zero-level bars no longer have a minimum white fill.
- Closing the AI result window cancels its task and invalidates late results.
- Shutdown stops Notch, media helper and shake monitoring explicitly.
- App relocation stages a complete copy before replacing the installed bundle;
  replacement failure attempts rollback. Failed relaunch leaves the old app running.
- Failed history loads no longer overwrite the unreadable shelf/snippets file;
  shelf orphan cleanup is also suspended to preserve images. A warning explains
  temporary, unsaved new items and manual recovery. No user history was reset.

Final universal build, Developer ID signature, installed binary identity and two
cold-launch metadata checks passed: one app process, no ordinary startup windows.
Isolated data-safety and installer tests passed. Interactive Settings/menu behavior,
live permissions, Bluetooth events and long-run performance still need device review.
See [audit details](BUG-AUDIT-BUILD86.md) and [owner checklist](OWNER-REVIEW-CHECKLIST.md).
Previous app/source retained in `backups/pre-startup-fixes-build86/`.
No push, tag, notarization, DMG, release or appcast change in this task.

## Build 85: native Apple symbols for existing event HUDs

Installed and running September 30, 2026. Universal arm64/x86_64 Developer ID
signature, hardened runtime, installed executable identity and build number
verified. No release, push, tag or appcast change.

- Removed the hand-drawn battery and checkmark geometry. Uses system SF Symbols
  for battery levels, charging, connection confirmation, mute, volume and brightness.
- Connection confirmation uses the native draw-on transition on macOS 26+;
  macOS 14–15 retain a native bounce fallback. Native pulses are non-repeating;
  replacement transitions handle changes between supported symbols.
- Low Power Mode uses a yellow battery mode icon instead of the rotating leaf.
  This mode icon is not a battery reading. Actual battery HUD percentages remain
  numeric, clamped readings; noncharging glyphs use system quarter-charge steps.
- Added Volume, Muted and Brightness preview menu items. They simulate HUDs only;
  they do not change system settings. AirPods 3D artwork and build-84 choreography
  remain unchanged. No private Apple animation assets were extracted.

Checks passed: build; symbol existence and battery thresholds; static previews
of all affected HUDs; installed assets and actual CoreAudio name routing; finite
atlas playback, cancellation and offscreen visibility regressions. The SDK
availability guard compiled for the supported deployment target. Runtime tests on
macOS 14–15 and live native-effect timing remain owner/device checks. Reduce Motion
branches were inspected; a runtime comparison was skipped because the system
setting is off and was not changed. An initial test tried to inject that read-only
environment value; it was corrected rather than changing system preferences.

Rollback build 84 and source: `backups/pre-native-hud-build85/`. The reviewed
gallery and focused test source are in its `review/` directory. Existing SDK
x86_64 and CIKernel deprecation warnings remain unrelated to this change.

References:
- https://developer.apple.com/sf-symbols/
- https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:)
- https://developer.apple.com/design/human-interface-guidelines/sf-symbols

These are native symbols/effects in custom FlowShelf layouts, not a claim of
pixel-identical private iPhone system animations.

## Build 84: reposed AirPods and coordinated connection presentation

Installed and running September 29, 2026. Universal arm64/x86_64 Developer ID
build, hardened-runtime signature, installed executable identity and resource
identity verified. No release, tag, appcast or push.

- Reposed the licensed imported model's two earbuds independently into an upright,
  overlapping pair. Preserved mesh normals, UVs and materials; asserted that
  separation crosses zero triangles. Corrected framing without pivot-dependent
  bounds. No live SceneKit renderer or new animation dependency in the app.
- Connection HUD now enters compact, expands after 0.38 seconds, holds the actual
  device name, then returns compact for 0.55 seconds before dismissal. Camera
  exclusion space is retained. Expanded width is at least 400 points.
- Added cancellation for the pending expansion; replaced/cleared/short-lived
  events cannot reopen a stale banner. Reduce Motion skips the staged morph.
- Green check remains connection success; no made-up earbud battery percentage.
  Shelf Liquid Glass and unrelated event HUD designs are unchanged.

Verification: actual CoreAudio device name resolves to the imported artwork;
60 distinct alpha frames have clear edges; final atlas crop matches poster;
finite playback, cache, fallbacks and ten simulated-visible start/stop/detach
cycles pass. Extracted production NotchModel tests pass compact/expanded/compact/
clear timing, replacement, cancellation, Reduce Motion and expanded suppression.
Inspected compact/expanded offscreen layouts using installed resources and the
actual NotchShape. These checks are not live Bluetooth reconnection or owner
visual approval. Existing SDK x86_64 and CIKernel deprecation warnings remain.

Rollback: `backups/pre-airpods-build84/FlowShelf.app` contains installed build 83;
`source.tar.gz` holds the touched source/resources before this change. Review
images and focused test sources are in that backup's `review/` directory.
Research and reference comparison: [visual review](AIRPODS-HUD-VISUAL-REVIEW.md).
Native state animation reference: https://developer.apple.com/documentation/swiftui/animations

## Build 83: fix the actual AirPods connection path

Follow-up verification September 29 (no app code changes): installed build 83,
signature, binary identity, all Notch3D resources and readable build-82 rollback
archive rechecked. Both Mach-O slices and Info.plist specify macOS 14.0 minimum,
despite the SDK's x86_64 deprecation warning. Tests ran again using installed
resources and the actual connected CoreAudio name. Added ten offscreen simulated-
visible presentations: start, cancel, no same-event replay and detach all passed;
visibility rejection covers hidden/occluded/minimized/suspended/missing-window
conditions. No windows were displayed. All frame/alpha/crop/cache/routing checks
passed. Reviewed HUD generation IDs, dismissal cancellation and service enable/stop
guards; no new blocker found in this scoped path. Apple's discrete keyTimes docs
confirm the 60 values / 61 times setup is intentional:
https://developer.apple.com/documentation/quartzcore/cakeyframeanimation/keytimes

One process snapshot: PID 24365, 0.1% CPU and 126880 KiB RSS (~124 MiB).
This is not a sustained performance profile or physical-footprint measurement.
Remaining limitations: classification uses display-name keywords; no genuine
AirPods battery telemetry; live hardware reconnect/visual smoothness and sustained
energy/memory behavior still unverified. This is not a whole-app bug-free claim.

September 29: owner screenshots still showed the rejected long-stem procedural
earbuds. Root cause was our incomplete integration: only `airpodspro` selected the
imported mesh, while an ordinary `airpods` event still selected legacy artwork.
Read-only CoreAudio verification confirmed the actual connected device selects
the `airpods` symbol. This was not a stale installation or missing model download.

- Removed the legacy earbuds runtime kind. Both `airpods` and `airpodspro` now
  resolve to the owner-selected imported artwork, while headphones/Max stay separate.
  This intentionally shares illustrative artwork; it does not claim to identify
  the actual AirPods generation. No Bluetooth probing or new permission was added.
- Middle truncation preserves the device-type end of long connection names.
- Isolated tests include full event routing (state change → HUD symbol → asset),
  ordinary/Pro/case variants, actual connected CoreAudio name, duplicate event
  suppression, Max/speaker fallbacks and build-82 animation/lifecycle checks.
  All passed. Offscreen render uses the real current output name, not a hardcoded
  Pro preview. Hardware disconnect/reconnect and live visual approval remain pending.
- Pre-change build 82 app/source are preserved in `backups/pre-airpods-routing-build83/`.
  No release is authorized.
- Installed/running: FlowShelf 1.6.2 build 83, PID 24365 at verification. Universal
  release build, Developer ID signature, installed binary/atlas identity and diff
  checks passed. Executable SHA256:
  `90f6045629107c5a57b66335fcc6303c10a9ada43f3cea7820ce237dd7a32b02`.
  Actual-route offscreen gallery and regression harness saved in the backup review
  folder. No live app UI automation, hardware switching, release, commit or push.

## Build 82: supplied AirPods Pro mesh, installed September 29

- The owner supplied `/Users/mac/Downloads/airpods_pro.glb` after Sketchfab's
  download control returned 403 despite a signed-in session. Embedded metadata
  confirms Jed Falcone, the researched source URL and CC BY 4.0. The unmodified
  source is retained under `scripts/assets/` with attribution and SHA256.
- Replaced the rejected build-81 flat-image tilt with 60 transparent frames from
  actual mesh geometry. Isolated the Airpods node, excluded the case, used precise
  transformed-vertex bounds, studio lighting and a new one-second turn. The GLB
  includes three animation channels, but the HUD intentionally uses the new turn,
  not the source case-opening sequence. Ordinary earbuds/headphones are unchanged.
- The ~220 KB Pro atlas decodes to 2,211,840 pixel bytes (excluding compositor/GPU
  allocations). One shared atlas cache; finite Core Animation playback; static
  fallback for Reduce Motion/Low Power Mode. No live SceneKit renderer or GLB is
  bundled. Source importer/renderer runs offline only.
- Settings → About now credits the artist and links source/license. Bundled asset
  documentation records modifications. No Apple endorsement or battery data implied.
  Approved expanded Liquid Glass, event routing and connection layout are unchanged.
- Backup: `backups/pre-imported-airpods-build82/FlowShelf.app` preserves build 81;
  `source.tar.gz` preserves pre-edit code/assets. Review subfolder holds the focused
  test harness, first/middle/final 384px renders and offscreen HUD gallery.
- Verification passed: arm64 debug build, both release architectures, 60 bounded
  alpha frames, distinct poses, matching final still, CALayer contentsRect crop
  comparison, cache reuse, finite playback, fallback assets, hidden-view no-play,
  teardown and HUD geometry. Actual rendered poses and short/long-name offscreen
  HUD layouts were inspected. Plist and `git diff --check` passed.
- Installed/running: **FlowShelf 1.6.2 build 82**, PID 16996 at verification.
  Developer ID signature passed; installed executable and new assets match the
  workspace bundle. Executable SHA256:
  `ff48fedaba1c684d06782dc86d8950d4638003d03d9461f1ee16bed85e47611c`.
  No live FlowShelf UI automation, release, notarization, commit or push.
- Owner still needs to review the Pro connection demo and real-device connections.
  Existing display-name classification can misclassify renamed devices; it was not
  changed here. Existing SDK deprecation warnings remain outside this asset task.

Research: [Khronos glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html),
[Jed Falcone source](https://sketchfab.com/3d-models/airpods-pro-3f84ddc3d87a4ec0a5e5f379abfecd9c).

## Build 81: AirPods Pro artwork and readable connection banner (superseded)

September 29 owner feedback: still not the requested result; do not mark visually
approved. Read-only verification confirms PID 6032 runs the installed build 81 and
its binary matches the workspace bundle. Code only replaced the `airpodspro` asset;
plain `airpods` and headphones still use legacy geometry. Route classification uses
the device display name, so renamed devices can select an unexpected appearance.
This is a possible explanation, not a verified diagnosis of the owner's visible HUD.

Further asset research: Lottielab homepage/templates and indexed search yielded no
verified ready-made realistic AirPods animation. IconScout has AirPods 3D assets;
Lordicon candidates are icon-style rather than realistic product animation. Stronger
candidate: [AirPods Pro by Jed Falcone](https://sketchfab.com/3d-models/airpods-pro-3f84ddc3d87a4ec0a5e5f379abfecd9c).
The author says created in Cinema4D; the page lists CC BY 4.0. In-app browser visually
showed an animated opening case and recognizable earbuds, with an animation named
`CINEMA_4D_Main`. Download requires Sketchfab sign-in. No file downloaded, so included
formats, separated mesh nodes and exported animation tracks remain unverified (a
comment also asks about animation missing from GLB). Candidate approach: render a
short transparent earbud turn offline from actual mesh, then use finite atlas playback
with author/license attribution; do not substitute another tilted generated PNG.
No app code/install/release change made during this research follow-up.

- The owner rejected build 80's generic-looking procedural earbuds. Visually checked
  LottieFiles candidates: those inspected were flat icons, not the desired product
  artwork. Generated an original transparent product-style AirPods Pro illustration
  with the built-in image tool; provenance/brief in `Resources/Notch3D/README.md`.
- A 192×192 PNG (~21 KB; ~144 KiB RGBA pixels) replaces the AirPods Pro atlas at
  runtime. A finite 0.65-second Core Animation perspective/scale entrance gives depth
  without a live 3D renderer. This is not a real mesh rotation or a Lottie animation.
- Connection banners now put the product, Connected/audio-output label, actual
  device name and green connection check below the reserved camera strip. Long names
  truncate instead of colliding. Battery data is not fabricated. Other event layouts,
  audio-route detection and approved expanded Liquid Glass remain unchanged.
- Low Power Mode changes now notify active view lifecycle observers immediately.
  Hidden, detached, suspended, reduced-motion and low-power views retain static art.
- Backup: `backups/pre-accessory-art-build81/` contains installed build 80 and source.
- Validation: debug build and isolated tests passed for alpha/dimensions, cache reuse,
  no Pro atlas loading, other accessory fallbacks, finite animation, notch/external
  geometry, unchanged volume geometry, hidden-view no-play and teardown. Offscreen
  renders of short/long device names and a display route were visually inspected.
  Actual connection hardware and perceived motion remain owner-review items.

Installed and running: FlowShelf 1.6.2 build 81, PID 6032 at verification. Both release
architectures built, Developer ID signature verification passed, installed binary
and product PNG matched the build/source. Signed executable SHA256:
`0dbce74af5ea4e6bb913a7f88aa21a548b41463848c6658fee6fb2fed66e430b`.
`git diff --check` and plist validation passed. Offscreen gallery and test harness
are retained in `backups/pre-accessory-art-build81/review/`. Existing SDK deprecation
warnings remain. No live UI inspection, release, notarization, commit or push.

Research: [Apple Dynamic Island design](https://developer.apple.com/videos/play/wwdc2023/10194/),
[inspected LottieFiles candidate](https://lottiefiles.com/free-animation/airpods-iaZm8KZyx4),
[Lottie Simple License](https://lottiefiles.com/page/license). No third-party animation
was downloaded, purchased or bundled.

## Build 80: real 3D-rendered accessory animation (Pro artwork superseded by 81)

- The owner correctly identified build 79 as a tilted flat symbol. Replaced that
  approximation for AirPods-style earbuds and headphones with original lit 3D
  geometry rendered into a 60-frame, one-second turn. Surfaces, vents, stems and
  earcups change perspective/occlusion and lighting as the product turns.
- Three stylized models: short-stem earbuds, longer-stem earbuds and over-ear
  headphones. These are our procedural models, not Apple's exact proprietary assets.
  Speaker/display and unrecognized routes retain a normal SF Symbol fallback.
- Offline generator: `scripts/render-notch-accessories.swift`, using SceneKit's
  renderer. Runtime: `NotchAccessoryAnimation.swift`, using Core Animation only.
  No live 3D scene, video player, recurring timer or per-frame SwiftUI state updates.
- Six PNG resources total roughly 0.5 MB. A single decoded 960×576 atlas (~2.1 MiB
  at RGBA8) is shared/cached, plus three tiny stills. Layer references and system
  GPU/compositing allocations are additional; total app RAM has not been profiled.
- Stops after one second and holds the last pose; hidden/detached/locked/exiting
  views stop immediately. Reduce Motion and Low Power Mode show a still 3D pose.
  Missing/invalid atlas falls back to the still, or an SF Symbol if assets are absent.
- Accessory HUD height is now 42 points so the small product has more visual room.
  Other compact HUDs, event detection and the approved expanded notch glass remain
  unchanged. No AirPods battery readings have been fabricated.
- Notch → Preview notch animations includes AirPods Pro, AirPods and Headphones
  3D demos, as well as the existing battery/power demos. They are simulations only.
- Backup: `backups/pre-3d-hud-build80/` contains installed build 79 and source.

Research: [Apple renderer snapshots](https://developer.apple.com/documentation/scenekit/scnrenderer/snapshot(attime:with:antialiasingmode:)),
[CALayer texture regions](https://developer.apple.com/documentation/quartzcore/calayer/contentsrect),
and [discrete keyframes](https://developer.apple.com/documentation/quartzcore/caanimationcalculationmode/discrete).
The deprecated SceneKit framework is restricted to regenerating assets, not the app
runtime. Bundled PNGs make playback independent of that generator's future support.

Validation: debug compilation passed. Isolated tests verify symbol mapping, all six
resources, shared cache reuse, 60 frame rectangles / 61 discrete key times, one-second
non-repeating playback configuration, hidden-view no-play and layer teardown. Actual
CALayer crops were rendered offscreen at start/middle/end; this caught and fixed a
vertical atlas-coordinate reversal. Models/lighting were inspected in offline proof
renders. Existing route/power/geometry tests passed with the new 42-point accessory
height. Decoding all three atlases and posters took ~11–15 ms in isolated local runs;
this is not an end-to-end frame-rate or memory benchmark. Live visuals remain pending.

Installed and running: 1.6.2 build 80, PID 66463 at verification. Universal release
compilation, installed Developer ID signature and executable identity passed. All six
installed PNGs match source assets. The executable has no direct SceneKit/RealityKit
dependency. Signed binary SHA256:
`6e3819b25212fe5d529987052c782b6a9c36e0a643d6706d95572ebf9de12f46`.
`git diff --check` passed. No release, notarization, commit or push performed.

## Build 79: iPhone-inspired compact notch motion (flat accessory symbol superseded by 80)

The owner rejected build 78's generic icon-and-text cards. Researched Apple's
[Dynamic Island design session](https://developer.apple.com/videos/play/wwdc2023/10194/)
and visually inspected/frame-stepped the AirPods and low-battery sections of
[this real iPhone demonstration](https://www.youtube.com/watch?v=ymtRAdfF23c)
(AirPods around 0:28–0:30, low battery around 1:22). Playback failed when seeking to
charging; do not claim that segment was visually verified. Apple stresses distinct
event identities, compact layouts around the sensor and elastic shape transitions.

- Replaces the tall shared card with symmetric compact wings around the physical
  camera. Minimum height is 34 points rather than the old ~98-point event card.
  Each event has its own width; no text or graphic is placed over the camera.
- AirPods/audio route: small shaded SF Symbol turns and settles into the leading
  wing; a green outline draws followed by a checkmark in the trailing wing. It is
  a connection confirmation, NOT an AirPods battery gauge. Device name remains
  available through the tooltip and accessibility label. This is a 2D symbol with
  perspective motion, not Apple's proprietary 3D accessory animation/model.
- Charging: label on the left, true reported percentage and green filled battery
  with lightning bolt on the right. Low battery uses the same readable layout
  with red fill. Low Power Mode uses yellow On/leaf or subdued Off/leaf, without
  inventing a battery level. Hardware volume/brightness also get symmetric wings.
- Separate container expansion, staggered symbol entrance, ring/fill resolution,
  and checkmark completion. Exit fades/retracts the wings before removing the HUD;
  return to media reserves the existing media width. Cancellation/generation guards
  protect a newly arrived event from an older dismissal.
- Motion finishes in less than a second; no repeating timer or animation loop.
  Reduce Motion skips the entrance sequence and animated exit. Existing expanded
  notch lens/glass and system-event detection are unchanged.
- Dashboard → Notch → Preview notch animations provides clearly labeled simulated
  AirPods, 75% charging, 20% battery, and Low Power Mode on/off events. It changes
  no device connection or power setting. Enabled only with Notch and its HUDs on.
- Backup: `backups/pre-iphone-hud-build79/` contains installed build 78 and source.

Validation so far: debug build passed. Event reducer and geometry checks passed for
120/200/240-point camera widths. Actual SwiftUI HUD views were rendered offscreen
and visually inspected for static alignment, clipping, spacing and text contrast.
The gallery used a simple dark backing, not the live notch lens or desktop. Live
motion smoothness, hardware triggers and owner visual approval remain unverified.
Isolated tests of the extracted current NotchModel passed: staged dismissal,
replacement during exit, explicit clear/cancellation, expanded-shelf suppression,
media-width restoration and 100-event bursts. These are logic tests, not animation
frame-rate measurements.

Installed and running: 1.6.2 build 79, PID 63587 at verification. Universal release
build, installed signature validation and signed binary identity passed. Both slices
retain macOS 14.0 minimum deployment and Team ID 27T48QHU7X. Built/installed executable
SHA256: `da35704d58533269c82e95dae9ccaa472da28a466f698b93d9cafda696d5734a`.
`git diff --check` passed. Existing Core Image / Intel deprecation warnings remain.
No release, notarization, commit or push performed.

## Build 78: system-event HUDs inside the notch (card design superseded by 79)

- Corrects the misunderstood HUD request: removes the build 77 bottom-screen action
  confirmations and their General setting. Retains clipboard write safety, image
  export error reporting and hardware-reading fixes from build 77.
- AirPods/headphone/audio-output changes now produce a short expanded notch card
  with a device symbol, name and status. Detection uses the actual Core Audio default
  output route, not Bluetooth pairing. Connecting a device without selecting it for
  audio may not trigger a card. AirPods symbols are name-based; renamed devices may
  use a generic symbol. No invented earbud/case battery readings.
- Low Power Mode on/off uses ProcessInfo's actual power-state notification. Charging
  and low-battery events use the existing power-source monitor, now shown as richer
  cards. Volume and brightness keep their compact side indicators.
- System events in the notch lives in the dedicated Notch pane and uses the existing
  HUD preference. New route/power monitoring adds no audio capture, microphone access,
  Bluetooth permission or polling loop. Existing hardware-key HUDs still use their
  existing Input Monitoring permission path; Apple's own overlays remain intact.
- Camera space stays clear; the event content sits below it. One brief spring entrance,
  Reduce Motion fallback, roughly 2.5–3.5 second dismissal. Latest event replaces the
  previous one; events do not interrupt an expanded shelf or create a queue.
- Start/resume silently seed current route/power state. Identical routes/power states
  are deduplicated; failed route reads are ignored. Device callbacks coalesce for
  150 ms. Stop removes listeners; sleep/lock clears cards; stale dismissals are rejected.
- Approved notch glass/lens implementation is unchanged by this HUD correction.
- Backup: `backups/pre-notch-events-build78/` contains installed build 77 and source.

Validation so far: debug compilation and isolated event tests pass (duplicate bursts,
failed route reads, route changes, power transitions, silent reseeding, labels, symbol
availability and detailed/compact event types). These tests do not connect hardware,
toggle system power settings or open the app UI.
Real device events, screen layouts, VoiceOver and visual motion remain owner checks.

Installed and running: 1.6.2 build 78, PID 49830 at verification. Universal release
compilation, Developer ID signing, installed signature validation and both architecture
checks passed. Both slices retain macOS 14.0 minimum deployment. Built/installed signed
binary SHA256 matches `8f051a1767cdff315f259241e4e1be9a50b37b831bc1191ddf320e0d7f400338`.
No release, notarization, commit or push performed. Existing Core Image kernel and Intel
architecture deprecation warnings remain; no compilation errors. `git diff --check` passed.

References: [Apple Live Activities guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities),
[power-state notifications](https://developer.apple.com/documentation/foundation/processinfo/powerstatedidchangemessage),
and [Core Audio Bluetooth transport](https://developer.apple.com/documentation/coreaudio/kaudiodevicetransporttypebluetooth).
These are Apple-inspired SwiftUI notch HUDs, not Apple's private AirPods/iPhone UI.

## Build 77: action HUDs and safer hardware indicators (action HUDs superseded by 78)

- Adds compact iPhone-inspired action confirmations above the Dock/bottom edge
  on the action's screen. A native non-activating, click-through panel does not
  steal keyboard focus. Uses the existing native macOS 26+ glass surface and
  older-system fallback, with Reduce Transparency and Reduce Motion support.
- Covers explicit item/batch copy, pin/unpin, image export, Private Mode on/off,
  and copy/save failures. Copy feedback follows a successful pasteboard write;
  missing item content no longer clears the clipboard or reports success. Image
  export errors are no longer silently ignored. Pin feedback confirms the in-memory
  shelf change, not durable storage completion.
- Settings → General → Action confirmations enables/disables the new feedback
  (on by default). It is independent of Notch/system HUDs, needs no extra permission,
  and does not announce automatic clipboard captures or expose item content/paths.
- Latest message replaces the current one; no visual backlog. Success disappears
  after two seconds, errors after 3.5. Token checks reject stale dismissals. Turning
  feedback off or locking/sleeping dismisses it. VoiceOver receives an announcement.
- Hardware volume/brightness reads validate success and finite 0–1 values. Missing,
  failed or unsupported readings produce no custom HUD rather than fake 50%/zero.
  Brightness lookup is cached once; a failed symbol lookup closes its library handle,
  while the successful cached function retains one library reference for process life.
- Hardware-key reads are coalesced after 35 ms to let macOS apply the change; stopping
  the monitor cancels pending work. No polling loop was added.
- Removed OSDUIHelper force-termination. Apple's own volume/brightness overlay is
  deliberately left intact; the optional notch indicator now appears alongside it.
  Updated the Notch setting's caption to reflect this change. Notch lens unchanged.
- Backup: `backups/pre-action-hud-build77/` contains installed build 76 and source.

Validation: debug compilation passed. Isolated tests cover valid/invalid readings,
missing/error/nonfinite/untouched brightness results, feedback labels, disabled
clipboard state, latest-only presentation, stale dismissal and 100-event bursts.
Static review confirms no OSDUIHelper termination/fake brightness fallback remains
in SystemHUDMonitor. These are not end-to-end panel, keyboard, permission, device,
VoiceOver, clipboard or export tests; owner checks remain explicitly pending.

Reference: [Apple feedback guidance](https://developer.apple.com/design/human-interface-guidelines/feedback)
supports passive feedback appropriate to the action; these are custom FlowShelf
confirmations, not a port of a private iPhone HUD API.

Installed and running: 1.6.2 build 77. Universal release compilation and Developer
ID signing completed; built/installed signed executable SHA256 matches
`7c7f5db322445cf121b3b01f2027a254a73899bbf337fc21c86b6733357049bc`.
Strict signature verification passed during installation and again outside the
sandbox for both bundles. A sandboxed follow-up had reported an inconsistent
arm64 signature error; the unsandboxed recheck passed without changing/re-signing
either bundle. Existing designated requirement is retained. HUD, motion, visibility,
synthetic audio and optional-symbol smoke tests passed; plist/diff checks passed.
Existing Core Image/Intel deprecation warnings remain. No release, notarization,
commit, push or live app UI verification was performed.

## Build 76: B04 — optional private window symbols

Continued after build 75 verification. Four hard-linked private window/Dock APIs
now use cached optional C-function lookup. Missing components disable the affected
operation instead of requiring those symbols from the dynamic linker. Peek/Dock
copy distinguishes unavailable OS components from permission problems. Present
APIs retain the existing behavior; this does not replace them with public APIs.

Arm64 debug compilation and fixture tests passed: missing/partial symbols,
one-time resolution, C signatures, output reset, guarded capture and repeated
retained-array handoffs. Host lookup finds capture/window-ID symbols without
calling them. Motion/visibility/audio regressions passed again. Real captures,
switching, older OS behavior and private ABI compatibility remain unverified.

Audit findings and follow-ups: [private API audit](PRIVATE-API-AUDIT.md).
Backup: `backups/pre-private-api-build76/` (installed build 75 and source snapshot).
No glass or selection redesign, scrolling capture, release or push authorized.

Installation verified: universal release build and `make install` completed;
1.6.2 build 76 is running from `/Applications/FlowShelf.app`. Strict Developer ID
verification passed and the designated requirement remains unchanged. Built and
installed signed executables match SHA256
`e8a5ea4d80c3cb55ea1b7c691e73f2f8e7db41d128d0d60e928e0f31d6117bdc`.
`nm -u` confirms all four private symbol imports are absent from both arm64 and
x86_64 slices. Plist/whitespace checks passed. Existing deprecation warnings remain.
Nothing was notarized, released, committed or pushed.

## Build 75: U11 — title/progress motion lifecycle

Reverified build 74: installed/built signed hashes match, signature is valid, the
installed process is running, and visibility/audio smoke checks passed again.
Real visual smoothness, capture-race behavior and energy savings remain unverified;
they are recorded in the owner checklist rather than treated as blockers.

- Replaces the unbounded repeat-forever title animation with a pausable timeline.
  Long titles retain 24-point/second scrolling, the 36-point gap and two-second
  dwell. Short titles remain static. Width changes reset the scroll safely.
- A non-interactive visibility probe pauses title/progress timelines on hiding,
  occlusion, disappearance or suspension. Paused playback stops both timelines;
  Reduce Motion stops decorative title motion. Progress also pauses while scrubbing
  and otherwise updates at most twice per second. Seeking remains event-driven.
- No glass, gradient, bar-count or capture-engine changes in this pass.
- Backup: `backups/pre-media-motion-build75/` (installed build 74 and source).

Validation: arm64 debug and universal release builds passed. Isolated tests cover
marquee speed/dwell/loop boundaries, short/invalid/static states, the actual AppKit
visibility reporter's notifications, duplicate suppression, hiding, detachment,
pending callback cancellation, pass-through hit testing and weak lifetime. These
are not a visual SwiftUI timeline or real music-player seeking test.

Installed and running: 1.6.2 build 75, Developer ID verified. Built/installed signed
executable SHA256: `e04fc1a104d168cf3d6654cb871e9ff77355e8553366dc67e374409e4d222386`.
No release, notarization, commit or push. Existing deprecation warnings remain.

References: [Apple pausable timelines](https://developer.apple.com/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:)),
[Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion).

## Build 74: B06 / U11 — notch background-work pass

- Preserves the approved custom lens, transparent bottom, gradients, bar count,
  capture resolution and frame-rate limits. This is not a glass redesign or a
  claim that the custom renderer has become Apple's native Liquid Glass.
- Lens capture and its display link stop when the hosting window is hidden,
  occluded, minimized, detached, or the session is locked/asleep. Ordinary visible
  collapse retains the existing 0.45-second warm grace; rendered contents are
  cleared immediately. Disabling Notch also detaches the hosting tree.
- A weak display-link target breaks target ownership of the lens view. The
  asynchronous capture start rechecks visibility and its generation, selects only
  the requested display, and handles interrupted streams with a retry cooldown.
- Reuses the last rendered image when the captured frame, crop and scale have not
  changed, rather than repeating the same Core Image work. In-flight results are
  rejected after a clear/reopen, resize or capture-session change.
- Music-bar drawing/decorative timers stop in invisible or suspended views and
  respect Reduce Motion. Decorative timers gain scheduling tolerance. This does
  not disable the shared audio service merely because one display is occluded.
- Backup: `backups/pre-notch-energy-build74/` contains the installed build 73 and
  the pre-change source snapshot. No new capture permissions or settings enabled.

Validation: arm64 debug compilation and isolated helper tests passed: all 32
visibility-policy combinations, offscreen view/ancestor hiding, scoped window
notifications, observer reattachment/detachment, weak lifetime and render-key
invalidation. Synthetic audio DSP/controller regression tests passed again. These
do not exercise real ScreenCaptureKit startup or visually approve the notch.

A passive 10-second Time Profiler attachment to build 73 completed without opening
or manipulating app UI. Its exported table had only 24 sample rows and raw stack
addresses; this is insufficient for a useful notch hotspot or before/after claim.
Controlled expanded/collapsed, moving-background, multi-monitor and energy profiling
remain pending. Marquee/progress-timeline auditing and native-glass comparison are
also not completed by this pass. Raw traces stay in temporary storage, not the repo.

References: [Apple window occlusion](https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification),
[timer efficiency](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html),
[efficient graphics](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/UsingEfficientGraphics.html).

Installation: `make install` completed for 1.6.2 build 74. Universal arm64/x86_64
release compilation and strict Developer ID verification passed; both slices retain
macOS 14.0 minimum deployment. Installed and built signed executables match SHA256
`56689fe58cb752a3f06602f12a5f21da776eb57f431205ea8942cf3c0822c528`.
The designated requirement is unchanged from the build 73 backup. Plist lint and
diff whitespace checks passed. Existing Core Image/Intel deprecation warnings
remain. No UI inspection, release, notarization, commit or push was performed.

## Build 73: U08–U09 — opt-in public audio-tap prototype

- Dashboard → Notch → Audio source adds experimental system-mix and current-player
  process taps. Compatibility (ScreenCaptureKit) remains the default and a manual
  rollback option. Explicit confirmation precedes selecting a tap mode.
- Uses public Core Audio process taps on macOS 14.4+, a private tap-only aggregate,
  unmuted output, and a dedicated audio-capture usage description. No video stream,
  microphone, audio files, upload, default-device changes or private TCC APIs.
- Player-only uses exact Core Audio process bundle IDs; macOS 26+ also restores
  matching processes by bundle ID. Unknown/browser-helper sources fail visibly,
  never silently widening to system capture. Media metadata still uses the existing
  adapter; this does not replace that separate private-API dependency.
- IO copies at most 2048 stereo frames into a fixed ring using a nonblocking lock;
  analysis runs at 20 Hz on a utility queue. A latest-result slot prevents queued
  spectrum updates from accumulating. Separate-channel FFT power avoids opposite-
  phase cancellation and handles planar/interleaved Float32 correctly. Six existing
  frequency ranges and existing notch styling/envelopes are retained. This is not
  lyric/instrument separation or a guarantee of improved live performance.
- Session tokens reject late starts/samples after stop, player change, sleep or
  screen lock, including the compatibility path. No automatic retry loop on failure.
  Output/format changes stop the prototype with an explicit Retry action; missing
  buffers time out after six seconds. Silent buffers are reported honestly.
- Capture is conditional on enabled Notch/media/bars and reported playback. Existing
  decorative fallback remains and is described as non-measured animation in settings.
  The settings card observes status only, not every spectrum frame. Notch glass,
  capture resolution for the lens, bar count, dimensions and gradients are untouched.
- Backup: `backups/pre-audio-tap-build73/` (installed build 72 and source snapshot).

Validation so far: arm64 debug build passed. Synthetic DSP checks passed for all
six ranges, stereo interleaving/planar layouts, antiphase channels, 44.1 kHz mono,
ring wrapping/bounds, silence and unsupported/nonfinite input. The actual spectrum
controller with a fixture backend passed duplicate prevention, target changes,
failure/no-fallback, explicit retry, stale completions, lock/sleep and rollback tests.
No live system audio/microphone or user clipboard was captured. Real tap delivery,
permission behavior, Bluetooth, older-OS behavior and energy comparisons are still
owner-review/profiling work, not verified shipping claims.

Installation: final-source synthetic/lifecycle checks passed again. Universal
arm64/x86_64 release compilation, Developer ID signing and `make install` completed.
The running app is `/Applications/FlowShelf.app`, version 1.6.2 build 73. Installed
and built signed executables match SHA256
`8acc312001b75ba8b52e20f60cbce8a3b04583ca1f70223fc4a9df15369c9d12`.
The usage description and experimental player-mode string are present in the
installed bundle. Both slices retain macOS 14.0 minimum deployment and the
designated requirement matches build 72. Plist/whitespace checks passed. Existing
Core Image and Intel deprecation warnings remain. No preferences were changed to
enable the prototype, no live capture/UI automation was performed, and nothing
was notarized, released, committed or pushed. Final lifecycle hardening ignores
device-alive notifications that still report a healthy device and refuses to start
hardware if no IO callback was created.

References: [Apple audio-tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps),
[CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription),
[AudioCap implementation notes](https://github.com/insidegui/AudioCap).
Also checked installed Core Audio SDK headers for mute behavior, process IDs,
format properties, bundle-ID restoration, aggregate devices and cleanup contracts.

## Build 72: U07 — configurable ignored clipboard types

- Privacy & Permissions now has an advanced Ignored clipboard types card.
  Custom rules are opt-in, persisted locally and removable. Adding a rule
  requires confirmation; any matching type skips the entire new capture.
- Exact, case-sensitive matching checks board and individual item type metadata
  before reading payloads. No wildcard matching or clipboard-content logging.
- Existing concealed/transient/auto-generated rules remain non-removable;
  recognized legacy confidential/transient markers are also honored. This is
  marker-based protection, not detection of every password or secret.
- Validation handles blanks, duplicates, built-ins, control characters, wildcards
  and length/count limits. Legacy names containing spaces are allowed.
- Rules affect new automatic captures, not existing history, normal pasting or
  manual file drops. No new permissions, timer or background service added.
- Source/app backup: `backups/pre-clipboard-privacy-build72/`.
  Owner UI review deferred.

Validation: arm64 debug and arm64/x86_64 release builds passed. Isolated named
pasteboard tests passed for built-ins, custom types on later items, case-sensitive
matching, removal, ordinary text/Handoff preservation, no payload-provider read
when checking markers, and input limits. The legacy marker containing spaces was
tested directly against the matcher because modern NSPasteboardItem.setData
rejects that non-UTI name; live legacy-app interoperability remains unverified.
Batch-transfer and real Vision OCR/indexer regression harnesses also passed on
temporary data. Batch tests emitted sandbox-extension diagnostics but all
assertions passed; these do not establish real receiving-app interoperability.
Plist lint and git diff whitespace checks passed. Existing Core Image and Intel
deprecation warnings remain. No real clipboard content or owner images were read
by the tests; no UI automation was performed.

Installation: `make install` completed and the app is running from
`/Applications/FlowShelf.app`, version 1.6.2 build 72. Installed and newly built
signed executables match SHA256
`128d75790d14e5872d7f5053d4452e706974a3a7090b6f8f1662f45d39098403`.
Developer ID verification passed and the designated requirement matches build
71. Both slices retain macOS 14.0 minimum deployment; the installed executable
contains the new privacy confirmation text. No release, notarization or push.

References: [NSPasteboard marker conventions](https://nspasteboard.org/),
[Apple pasteboard items](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboarditems).

## Build 71: U06 — searchable text in saved images

- Settings → Capture & AI → Image text search → Search text inside images.
  Opt-in and OFF by default; scans existing and new image/screenshot items
  stored by FlowShelf, not arbitrary linked files or external folders.
- Uses Apple's Vision OCR locally, one image at a time on a utility queue.
  ImageIO downsamples to at most 2048 pixels on the longest edge before OCR;
  extracted text is capped at 20,000 characters per item. No cloud service,
  Apple Intelligence requirement, clipboard writes or additional shelf items.
- Stores an optional text field with the original item. Ordinary shelf search
  and the smart-search candidate list include it. This is text recognition,
  not semantic image search; it can miss tiny lettering or misread characters.
- Disabling pauses scanning but keeps indexed text searchable. Private Mode
  cancels current work and pauses future scans. A confirmed Clear indexed text
  action disables indexing and removes the extracted text, not the images.
- Deleted/expired items cannot be restored by late scan completions. Empty OCR
  results are cached; failed reads do not retry endlessly and have a Retry action.
  The optional JSON field preserves compatibility with existing shelf history.
- Selection design and notch appearance remain unchanged. Scrolling excluded.

Validation: arm64 debug build passed. An isolated harness compiled the actual
recognition worker, index coordinator and item model with in-memory settings/store
fixtures. Real Vision OCR on generated text/blank PNGs passed, along with old/new
JSON, keyword/accent matching, opt-in, Private Mode pause/resume, no re-scan after
rename, failure/retry, and clear-during-scan cancellation without late writes.
The harness used temporary images; it did not read the owner's images or clipboard.
No UI automation is planned, per the owner's request. Backup:
`backups/pre-image-search-build71/`.

Installation: `make install` completed with both arm64 and x86_64 release
builds, Developer ID signing and signature verification. The installed build
71 executable hash matches the newly built signed bundle and includes the
image-text-index worker and settings strings. Both slices retain macOS 14.0
minimum deployment. Final-source smoke tests were rerun and passed. Existing
Core Image/Intel deprecation warnings remain; no release or push was made.

References: [Apple Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images),
[ImageIO thumbnail decoding](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)),
[Vision request cancellation](https://developer.apple.com/documentation/vision/vnrequest/cancel()).

## Build 70: selection layout correction

The owner rejected build 69's protruding top-left circles. Replaced these with
smaller, hollow circles aligned inside a reserved right-hand column on dashboard
and menu-bar rows; floating tiles use inset top-right circles, with the pin at
top-left. Removed the added top padding and opaque fills on list-row circles.
Selection still uses a 28-point hit target and a filled checkmark when selected.
The shared batch-action bar is now one compact row rather than two.

The owner explicitly requested no further UI inspection. Dashboard selection
was exercised in build 69 without changing the clipboard counter; menu-bar and
floating-shelf interactions have not been manually verified. Build 70 visual
approval is left to the owner. Backup: `backups/pre-selection-polish-build70/`.

## Build 69: direct circular selection on all three shelf surfaces

- Removed the dashboard Select items / Done mode and square checkboxes.
- Added an always-visible top-left circular check control to each item in the
  dashboard, menu-bar popover and floating shelf. The check control sits outside
  the card's copy gesture; the card retains its normal copy/open/drag actions.
- Added a shared compact batch-action bar to all three views, shown only while
  items are selected. It supports Copy files / Copy as text, copy-only batch
  dragging, mixed-type guidance and Clear selection.
- Selection is local to each surface, clears on filter/search changes, and
  drops IDs that no longer appear in the result set. It is not persisted.
- Kept the corrected output-path-aware universal build process from build 68.
  Rollback bundle/source: `backups/pre-circle-selection-build69/`.

arm64 debug compilation and the isolated batch-transfer smoke checks passed.
Runtime checks are recorded after installation below. No release authorized.

## Build 68: correction to the installation checkpoints

The build 66/67 installation checks below were insufficient: the installed
bundle had a new version label and valid signature, but still contained an old
executable. Swift 6.4 defaults to Swift Build and reports
`.build/out/Products/Release` rather than the old architecture-specific paths.
The Makefile continued combining stale August binaries from those old paths.
Direct inspection of the running dashboard confirmed that Select items was
absent. Source compilation and isolated smoke tests did not verify installation.

The build recipe now asks Swift for `--show-bin-path`, checks the actual slice
architecture, and stages each executable immediately before building the next
architecture (the new engine reuses the same output directory). It verifies
both slices before replacing the universal executable. This fixes packaging for
both local installs and future releases; no release is authorized here.

Rollback bundle and source: `backups/pre-build-path-fix-build68/`. That bundle is
the prior mislabeled build 67, not proof that the batch features worked there.
References: [SwiftPM build-system change](https://forums.swift.org/t/swiftpm-development-update-default-build-system-change/85548),
[shared output directory report](https://github.com/swiftlang/swift-build/issues/1363).

Build 68 installation completed with current arm64 and x86_64 slices, both
retaining macOS 14.0 minimum deployment. Developer ID verification passed.
Actual running-app UI verification passed: Select items appears; clicking it
reveals checkboxes and batch controls; selecting two rows shows 2 selected,
Copy as text and Drag 2 items. Deselect all returns the count to zero. A native
window screenshot confirmed the controls are visible, not merely present in
source. Left selection mode open, with no items selected. No real clipboard
copy or external drag was performed during this UI check.

## Build 66: first review checkpoint

- B01: capture all copied file URLs, preserving order and removing duplicates.
- B02 / U05: Ask your shelf retrieves matching text and snippets, provides source
  inspection buttons, and instructs the model to answer only from those excerpts.
  This reduces unsupported answers; it is not a guarantee against hallucination.
- B04 (partial): prevent stale media-helper callbacks and unlimited fatal-error
  restart loops; show a failure message in the Notch pane.
- B05 (partial): detect explicit macOS pasteboard denial or ask-every-time mode;
  pause background reads and explain the access restriction.
- U01 (partial): preserve RTF up to 256 KiB alongside plain text; support Copy as
  Plain Text. No HTML/RTFD preservation or rich-content rendering was added.
- U04 (partial): keyword-rank full supplied text across all eligible items before
  creating the bounded 40-item AI shortlist. Excerpts surround matching terms.
  This is local lexical retrieval, NOT a Spotlight semantic index. Questions
  with no lexical match return guidance rather than invented shelf answers.
- Prevent obsolete AI-search responses from replacing a newer query or filter.
- Preserve existing stored items via optional, backward-compatible RTF data.

## Build 67: dashboard multi-item actions

- U02 (partial): Dashboard → Shelf → Select items enables checkbox selection,
  Select all / Deselect all, and a dedicated Drag N items handle. Selection is
  scoped to the current search/filter and pruned when items disappear.
- Batch copy joins text/link/OCR selections as plain text, with blank lines in
  shelf order. File/image selections copy file URLs without decoding images;
  duplicate file URLs are removed. Mixed file/text copy is disabled explicitly.
- Batch dragging creates one native AppKit dragging item per selected item,
  including mixed types. The destination determines which types it accepts.
  Individual text drag payloads retain bounded RTF when available.
- U03 (partial): the batch drag source offers copy only, ignores move modifiers,
  never deletes originals, and distinguishes destination acceptance from
  cancellation. Acceptance is not proof that every item was imported.
- The complete batch is validated before clipboard clearing or drag creation;
  a missing file/image rejects it instead of silently transferring a subset.
- Outgoing batch payloads carry the existing auto-generated clipboard marker
  so FlowShelf does not re-capture its own copies.
- Scope: dashboard only. Existing single-item row drags, floating shelf and
  notch behavior remain unchanged. Collections and paste queues are not added.

Isolated named-pasteboard smoke checks passed for ordering, duplicate removal,
Unicode file URLs, self-capture markers, plain-text joining, individual RTF drag
payloads, mixed-type rejection for copy, image URL transfer, missing files and
empty selections. The test uses temporary files, not the user's clipboard.
Visual approval and real receiving-app drag/paste checks remain required.

Build 67 verification: arm64 debug and universal arm64/x86_64 release builds
passed. Installed with `make install`; the signed executable matches the built
bundle, Developer ID verification passes, and the designated requirement is
unchanged from build 66. Both slices retain macOS 14.0 minimum deployment.
Existing Core Image and Intel deprecation warnings remain. Nothing published.

## Remaining work

Validation for this checkpoint: arm64 debug and arm64/x86_64 release builds
passed. Isolated temporary-pasteboard checks passed for multi-file order and
deduplication, RTF limits and round-trip, old/new JSON decoding, full-history
lexical ranking, long-text excerpts, accents and no-match behavior. Developer ID
signature verification passed after installation; the designated requirement
matches the previous installed app. Both executable slices retain macOS 14.0
minimum deployment. Existing Core Image kernel and Intel deprecation warnings
remain. Automated native UI inspection stalled; visual approval and end-to-end
AI/permission/media testing remain outstanding.

| IDs | Scope | Status |
| --- | --- | --- |
| B03 | Window switching, Mission Control, monitors, minimization, sleep/wake | Pending runtime checks |
| B04 | Private API availability and failure fallbacks | Builds 76–77 optional symbols and honest HUD fallback; hardware/live media checks pending |
| B05 | Permission transitions and broader clipboard status coverage | Partially addressed; manual checks pending |
| B06 | Notch stale frames, opening latency, hidden capture | Build 74 lifecycle/render guards; real-device profiling and owner review pending |
| U01 | Additional safe clipboard representations | RTF completed; others pending |
| U02–U03 | Multi-item drags and confirmed drop feedback | Dashboard/menu-bar/floating selection and batch controls implemented in build 69; receiving-app interoperability checks pending |
| U04–U05 | Semantic retrieval and source grounding evaluation | Lexical groundwork only; further evaluation pending |
| U06 | Saved image OCR search | Implemented in build 71; opt-in local OCR, owner review pending |
| U07 | Configurable ignored clipboard types and privacy coverage | Implemented and installed in build 72; automated checks passed, owner review pending |
| U08–U09 | Public process-tap audio and player-specific capture | Opt-in prototype implemented in build 73; real-device validation and profiling pending |
| U10–U11 | Native clear-glass comparison and energy profiling | Builds 74–75 lifecycle/motion pass; controlled profiling/native comparison pending; appearance preserved |
| U12–U13 | OS fallbacks and broader regression checks | Pending |
| N01–N02 | Reorderable collections and explicit paste queue | Pending |
| N03–N05 | Siri, Shortcuts, opt-in Spotlight for curated items | Pending |
| N06–N08 | Object cutout, screenshot understanding, reviewed solid redaction | Pending |
| N09 | Optional Music Understanding evaluation | Research/prototype, not a shipping promise |
| N10–N12 | Curated shelf, snippet, collection widgets | Pending extension/signing work |
| N13 | Separate iPhone/Duo companion | Later, separate project |
| N14 | Optional cloud AI | Deferred pending eligibility and explicit opt-in design |

## Review checklist

1. Copy several Finder files and verify all appear on the shelf.
2. Copy formatted text, verify normal Copy preserves formatting, and verify
   Copy as Plain Text removes formatting in a receiving app.
3. Ask about a unique phrase in an older saved item; inspect the source button.
4. Ask about absent content; verify a clear no-match response.
5. Change a query or filter while AI search runs; old results must not return.
6. If testing clipboard access settings, check denial and ask states without
   repeated background prompts, then restore the user's preferred access.
7. Review media-helper failure recovery separately from normal playback.
8. Select two text items using their circles, then Copy from the batch toolbar.
   Paste into a text editor; check shelf order and blank-line separation.
9. Select two files/images and use Drag N items into Finder. Check both arrive
   and originals remain, including with Command held. Escape should cancel.
10. Try a mixed file/text drag into a compatible app. Verify each imported type;
    receiving apps may accept only part of a mixed selection.
11. Change search/filter or remove a selected item; check selection updates.
12. Enable image text search in Capture & AI. Wait for indexing to finish, then
    search for a distinctive word inside a saved screenshot. The original image
    should appear; no extra text item should be created or clipboard replaced.
13. Disable indexing to stop new scans, or use Clear indexed text to turn it off
    and remove extracted text while retaining images. Re-enable to rebuild later.

## Rollback

The previous installed bundle and source snapshot are saved under
`backups/pre-shelf-upgrade-build66/`. No release, tag, appcast update, or push is
authorized by this checkpoint. New RTF fields are optional; the prior app ignores
them but will not preserve them when it rewrites history.

Before build 67, the installed build 66 and all current source were backed up
under `backups/pre-batch-actions-build67/`. No release or push is authorized.
