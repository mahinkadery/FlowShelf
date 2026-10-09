# Private API audit — September 23, 2026

Scope: FlowShelf source declarations, call sites and installed executable imports.
This is a compatibility audit, not a claim of App Store eligibility or complete
macOS-version coverage. No UI automation, real capture test or system setting
change was performed for this audit.

## Addressed in local build 76

The prior executable directly imported four undocumented symbols:

| Symbol | Purpose | Behavior if missing after this change |
| --- | --- | --- |
| CoreDockGetOrientationAndPinning | Dock orientation | Existing bottom-Dock fallback; positioning can be inaccurate |
| CGSMainConnectionID | Window-server capture connection | Zero sentinel; capture is skipped |
| CGSHWCaptureWindowList | Window preview images | No thumbnail; existing placeholders remain |
| _AXUIElementGetWindow | Match Accessibility windows to CGWindowID | No matched ID; AX-based window listing/actions are limited |

These are now looked up once using `dlsym`, behind optional C function pointers,
rather than remaining required imports of the main executable. Capture requires
both symbols and a nonzero connection. Failed window-ID lookup clears its output.
Capture options use their UInt32 raw value at the C boundary; returned arrays use
an explicit retained-result bridge, preserving the previous owned-return contract.
Peek/Dock previews distinguish missing components from a Screen Recording prompt.

This protects against symbol absence only. It does **not** make private APIs
public, restore a removed implementation, detect every ABI change, or guarantee
that present functions work correctly on future macOS versions. The existing
window switcher can still activate an app without precisely raising a chosen
window if the AX-to-window-ID bridge is unavailable. No fabricated window match
or expanded capture fallback was added.

## Verification

- Arm64 debug compilation passed.
- Universal release compilation and strict Developer ID installation passed for
  build 76. The installed executable matches the signed build, and both slices'
  undefined-symbol tables contain none of the four former required private imports.
- Fixture tests exercise all-missing and partially missing symbols, cached lookup,
  orientation and window-ID outputs, C calling conventions, invalid capture
  requests, and 1,000 retained-array handoffs using generated data.
- Host-only symbol lookup finds the window-ID and capture functions. Tests do not
  invoke those real functions, enumerate user windows or inspect captured pixels.
- End-to-end switching, captures, memory behavior of Apple's undocumented return
  value, older macOS versions and future removal scenarios remain unverified.
  Synthetic callbacks cannot establish those properties.

## HUD follow-up — build 77

Brightness lookup is now cached once, validates the status/value, and returns no
custom HUD when unavailable. Failed symbol lookup closes its handle; successful
lookup keeps one library reference for the cached function's process lifetime.
Volume readings also validate failure/unsupported-device conditions. The fake 50%
fallback and OSDUIHelper force-termination have been removed. Apple's system HUD
remains untouched even when the optional notch indicator is enabled. Synthetic
reading tests passed; actual hardware-key/device behavior is still unverified.

## Remaining findings

1. **MediaRemote adapter:** now-playing metadata still depends on the vendored
   private-framework adapter, even when spectrum analysis uses public Core Audio
   taps. Existing subprocess exit handling clears stale state and limits retries,
   but an alive-yet-silent helper is not a proven healthy connection. Exercise
   missing adapter, unsupported OS and stalled-output cases separately.
2. **Permission state:** a failed private window capture is not conclusive proof
   of missing Screen Recording permission. Missing-symbol banners improve one
   case; a present-but-incompatible API can still be misdiagnosed. Broader B05
   permission-state work remains pending.

Reference: [Apple dynamic library usage](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/DynamicLibraries/100-Articles/DynamicLibraryUsageGuidelines.html)
documents runtime symbol lookup; [dlsym reference](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/dlsym.3.html)
documents missing-symbol behavior. These sources do not endorse the undocumented
window APIs or promise their ABI stability.
