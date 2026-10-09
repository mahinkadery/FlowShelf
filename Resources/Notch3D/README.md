# Notch accessory animations

## Build 84: independently reposed earbuds

The same licensed Jed Falcone source is now separated into two earbuds in the
offline renderer. A triangle-boundary assertion rejects a model that cannot be
separated safely. Vertex positions, normals, UVs and materials are retained.
Each earbud is recentered and independently rotated/positioned into an upright,
overlapping pair before the finite one-second turn is rendered. The runtime
remains a 60-frame atlas player, not a live SceneKit scene.

The complete connection HUD now enters compact, expands after 0.38 seconds,
holds the connection name, then returns compact for 0.55 seconds before its
existing dismissal. This is custom FlowShelf choreography inspired by the
supplied still references, not Apple's private accessory animation. The green
check still means connection success, not an invented battery percentage.

## Build 83: shared AirPods artwork routing

Both `airpods` and `airpodspro` HUD symbols use the owner-selected imported Pro
model. The rejected procedural earbuds variant is no longer a runtime accessory
kind. This is a shared illustrative artwork choice, not hardware-model detection:
the actual connected device name is preserved. AirPods Max/headphones retain
their separate artwork. The old generated earbuds files are historical only.

## AirPods Pro — build 82

Model: **AirPods Pro** by **Jed Falcone** (https://sketchfab.com/jedlas012).
Source: https://sketchfab.com/3d-models/airpods-pro-3f84ddc3d87a4ec0a5e5f379abfecd9c
License: **Creative Commons Attribution 4.0 International (CC BY 4.0)**
https://creativecommons.org/licenses/by/4.0/

The owner supplied the GLB on September 29, 2026. Its embedded metadata identifies
the same author, source and license. Source SHA256:
`f6683b3fa1f46c33a6a91ccb6075d09a3c6a8291dc0726d4ff1b8fbdc39937e2`.

Modifications: isolate the Airpods node (exclude the case), normalize framing,
adapt materials to SceneKit, add studio lighting and a new one-second turn,
and render/downsample transparent frames. The source includes animation tracks;
the HUD uses a new turn rather than the original case-opening animation.
This attribution applies to `earbuds-pro-atlas.png` and `earbuds-pro-still.png`.
Attribution/license links are also available in Settings → About.
Neither the artist nor Apple endorses FlowShelf.

Regenerate using:

```sh
swift scripts/render-imported-airpods.swift scripts/assets/airpods-pro-jed-falcone.glb /tmp/flowshelf-airpods
cp /tmp/flowshelf-airpods/earbuds-pro-{atlas,still}.png Resources/Notch3D/
```

The GLB and SceneKit importer are offline tools, not app resources or runtime
dependencies. The importer is scoped to this verified GLB: triangle meshes,
packed/strided float attributes, integer indices, embedded textures and node
transforms. It does not implement arbitrary glTF extensions, rigs or playback.
The Pro atlas now uses the same finite playback/lifecycle rules described below.

## Historical AirPods Pro artwork — build 81 (no longer loaded)

`earbuds-pro-product.png` replaces the rejected procedural AirPods Pro appearance.
It is an AI-generated, transparent product-style illustration, not an Apple-supplied
asset or extracted system artwork. Generated with the built-in image-generation tool
on September 28, 2026; resized to 192×192 with alpha preserved for a 52-point view.
The runtime uses this image with a finite 0.65-second perspective/scale entrance.
This is a 3D-looking raster illustration, not a new animated 3D mesh or a Lottie file.
Build 82 replaces this entrance with rendered frames from the supplied mesh.

Generation brief: photorealistic pair of white AirPods Pro, accurate short slender
stems, sculpted asymmetric bodies, silicone tips and black vents; upright three-quarter
view, compact pair; soft studio reflections; transparent background; no case, logo,
text, floor or cast shadow. Avoid spherical generic earbuds and thick tubes.

The procedural generator below does not overwrite this new product asset.

## Legacy procedural assets

Original procedural accessory models, created by `scripts/render-notch-accessories.swift`.
Only headphones still use these assets. Do not overwrite
the imported Pro assets using this legacy generator.
These are stylized earbuds and headphones, not Apple's private product models or assets.

Each `*-atlas.png` contains 60 transparent 96×96 frames in a 10-column, 6-row grid.
Frames are ordered left-to-right, then top-to-bottom. The matching `*-still.png`
contains the final pose. Lighting and camera-space rotation are rendered from actual
3D geometry; they are not transformations of a flat symbol.

Regenerate from the repository root on a Mac with Metal and the Swift SDK:

```sh
swift scripts/render-notch-accessories.swift Resources/Notch3D
```

SceneKit is used only by this offline asset generator. FlowShelf plays the frames
with a finite Core Animation contentsRect animation and does not link SceneKit for
these HUDs. The player compensates for CALayer's vertical texture coordinates.
Update the frame-grid constants in the generator and NotchAccessoryFrames together.

Reduce Motion / Low Power Mode use the still pose. Hidden, detached, suspended or
exiting views stop playback. The shared decoded atlas cache holds one atlas at a
time; the small three-poster cache is separate. This bounds source-image caching,
not macOS's internal compositing/GPU allocations.
