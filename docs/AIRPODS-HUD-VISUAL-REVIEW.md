# AirPods HUD visual review — September 29, 2026

Initial status: reference and source inspection of build 83. The build-84 follow-up
reposes the two earbuds independently and adds coordinated compact/expanded
presentation. See the roadmap for installation/verification results. Owner visual
approval remains separate from automated checks.

## All six supplied references

1. Lottielab dashboard screenshot: confirms the intended signed-in tool, not an
   animation reference. The in-app browser account was accessible.
2. Dynamic Island collage: black surfaces, restrained typography, event-specific
   artwork, and distinct compact and expanded layouts. It is not a request to
   implement every illustrated iPhone service on macOS.
3. Compact iPhone island: small, tightly grouped earbuds on the left and a thin
   green status ring on the right, leaving the physical camera area clear.
4. MacBook island concept: the same compact composition adapted to a Mac screen.
   This concept image does not establish an available Apple macOS API.
5. Second MacBook concept: corroborates the compact silhouette and grouped artwork;
   it does not show enough detail to establish an animation sequence.
6. Expanded connection banner: the primary artwork/layout target. Upright,
   closely overlapping white earbuds; grey Connected label above a readable
   device name; green battery ring with a numeric battery reading on the right.

These are still images. Motion timing and transitions cannot be verified from
them; any proposed choreography must be identified as FlowShelf's interpretation.

## Lottielab findings

Inspected the signed-in All templates list and Icons category. There were 189
listed template-detail links; title searches for AirPods, earbuds, headphones,
battery, Bluetooth and island returned no match. This is a catalogue finding,
not a claim that no such asset exists anywhere.

Inspected the Verified icon template visually. It is a flat scalloped badge and
checkmark, not realistic earbud artwork or a battery gauge. It should not replace
the requested asset just because it is animated.

- Import documentation: https://docs.lottielab.com/file-management/files/import-a-file
- Inspected template: https://www.lottielab.com/template/verified-icon
- Format/background: https://docs.lottielab.com/getting-started/faq

The documented import workflow accepts Lottie and SVG. No GLB import workflow
was established. Lottielab can author UI motion, but does not automatically repair
the supplied model's pose, framing or rendering.

## Current implementation mismatch

- The rendered imported mesh has two widely separated, outward-tilted earbuds.
  Reference 6 uses a narrow, upright, overlapping composition. Changing the
  global camera turn alone does not correct their relative placement.
- `scripts/render-imported-airpods.swift` imports the Airpods subtree and applies
  one global one-second turn. It does not independently choreograph two earbuds
  or use the GLB's original case-opening animation.
- `NotchHUD.swift` presents a camera-safe top strip and a 64-point connection row.
  It does not implement the distinct compact accessory state in references 3–5.
- The green check is connection success, not battery telemetry. The supplied
  reference's 75 must not be copied as a fabricated reading. A numeric battery
  ring requires an actual, validated battery source and an unknown-data state.
- Name truncation and asset routing were addressed in build 83. Those technical
  fixes do not establish that the visual result matches the user's references.

## Next implementation acceptance criteria

1. Repose the licensed source artwork into an upright, closely overlapping pair;
   compare the complete banner and native-size icon with reference 6 before
   replacing installed assets. Preserve the artist's attribution.
2. Design compact and expanded states around the actual Mac camera exclusion
   region, not an iPhone-sized assumed camera. Keep the approved shelf glass
   separate from the black connection HUD.
3. Coordinate shape, artwork and copy transitions as one finite presentation,
   rather than a rotating icon inside an otherwise static banner. Treat proposed
   timing as custom motion, not a reproduction verified from these stills.
4. Use truthful status: connected if battery is unknown; a battery percentage
   only when supported by genuine device data. Preserve the actual device name.
5. Retain reduced-motion/low-power stills and stop playback on hide/detach.
6. Verify actual route-to-HUD rendering, not just isolated Pro previews. Install
   any changed app locally for owner review; do not publish a release.
