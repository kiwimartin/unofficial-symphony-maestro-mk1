# Sequoia 15 and Tahoe 26 compatibility

Scope: Apple Silicon developer builds of the existing Maestro app, the isolated
LegacyMaestroPreview GUI, diagnostics, USB components and both DriverKit build
paths. This change introduces no new hardware command, DMA enable, clock/routing
write, signing input, updater URL, version sequence or activation ownership.

## Common runtime floor, independent SDK/OS tests

`Tools/platform-compatibility.json` defines macOS 15.0 / DriverKit 24.0 / arm64.
The Swift package, app plist, generated preview plist, installer OS check and
both driver manifests must agree. Both driver build scripts read that policy
for compilation, linking and iig generation; conflicting deployment overrides
fail before SDK access. Newer SDKs may build the older deployment floor. The
packaged driver records the actual selected SDK version separately.

| CI job | Host OS / architecture | Toolchain | Purpose |
| --- | --- | --- | --- |
| Sequoia | macOS 15, native arm64 | Xcode 16.4, macOS 15 / DriverKit 24.5 SDK | Compile against the older real SDK and execute tests/preview on Sequoia |
| Tahoe | macOS 26, native arm64 | Runner-selected current Xcode/SDKs, recorded in artifact | Preserve newer-SDK compilation, Tahoe UI path and execute the same checks on Tahoe |

A missing Xcode 16.4 installation fails explicitly; CI never silently replaces
that older-SDK check with a Tahoe SDK. Host OS and architecture are asserted, not
inferred from a runner label. The two jobs do not cancel one another on failure.
After both builds pass, two lightweight cross-OS jobs verify the downloaded
artifact checksums, then launch the Tahoe-built preview on Sequoia and the
Sequoia-built preview on Tahoe. Each launch checks the same visible-window marker
and binary deployment floors; no driver is loaded. Reports are retained even
on failure. Thus the preview binaries are exercised on both OSes, not only
rebuilt separately.
Artifact names include the OS, observed environment and source commit.

The only explicit Tahoe-only SwiftUI call found in the audit is
`scrollEdgeEffectHidden`. It retains its macOS 26 runtime availability gate and
now also has a compiler gate for the Xcode 16 toolchain, whose SDK does not even
declare it. Sequoia keeps the existing scroll-bounce fallback; Tahoe keeps the
same styling. The older compiler also exposed existing main-actor violations
in scroll notifications and monitor undo callbacks. Notifications now assert
their documented main-thread delivery synchronously; undo updates UI state on
the main actor through a weak, actor-isolated context. The asynchronous tasks
never transfer the non-Sendable UndoManager callback target between executors.
Scroll debounce/restoration and monitor values remain the same. No audio
timing/register/lifecycle logic changes for compatibility.

The audited AudioDriverKit construction, latency/safety-offset, configuration-
change and IO-operation-handler methods predate DriverKit 24; their public Apple
metadata identifies introductions at DriverKit 21. The real older-SDK build
checks PCI/API availability too. Availability warnings are errors in both driver
builds, so a newer-SDK API cannot silently raise the deployment requirement.

Public references:
- https://developer.apple.com/documentation/audiodriverkit/iouseraudiodevice/setiooperationhandler
- https://developer.apple.com/documentation/audiodriverkit/iouseraudioclockdevice
- https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md
- https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md

## Verification

Each CI job runs the full existing Swift suite, Python tests, C++ sanitizers,
passive-driver safety gates and USB shared-memory/clock contracts. It builds
both GUI products, diagnostics, USB plugin/proxy and both DriverKit executables.
The packaged app and actual Mach-O `LC_BUILD_VERSION` records are checked for
correct arm64 architecture and matching macOS/DriverKit minimums. Checking only
plists would not catch a binary that still requires a newer OS.

The isolated preview additionally launches from its assembled .app executable
with `--smoke-test`. Success requires a real visible SwiftUI/AppKit window and
marker within 30 seconds, then orderly termination. This exercises loader and
GUI startup on each OS. It does not press diagnostic refresh, load a driver,
start audio, instantiate shipping AppState or perform vendor writes. The
shipping application itself is compiled/tested but not automatically launched,
because its normal activation/control path is outside a passive CI smoke.

Local Linux can verify metadata consistency, parser failures and drift/override
protection. Actual OS execution is established only by the resulting macOS CI
jobs, not by these local tests.

```sh
python3 Tools/check-platform-compatibility.py
python3 -m unittest discover -s Tools/tests -v
# macOS only, after release build and preview assembly:
python3 Tools/check-platform-compatibility.py --runner-label macos-15 \
  --preview-bundle build/legacy-ci/LegacyMaestroPreview.app --smoke-preview \
  --binaries Apps/Maestro/.build/release/MaestroApp \
    Apps/Maestro/.build/release/LegacyMaestroPreview \
    Drivers/Thunderbolt/build/com.danielraffel.maestro.thunderbridge \
    Drivers/Thunderbolt/build/passive/SymphonyPassiveDiagnostics-unsigned
```

## Hardware and release limits

Dual OS compilation, tests and preview startup do not establish signed extension
activation, device discovery, physical USB/MK I audio, Port-2 DMA, 64-channel
streams, legacy routing/clock operation, sleep/reconnect or sustained stability.
Those require own approved profiles/certificates and a real hardware acceptance
record on **each** OS. No such physical tests were performed in this environment.
Sequoia support therefore remains developer/software compatibility, not a newly
released, hardware-qualified installer. Existing released assets/feed remain
untouched. A future signed fork installer needs the prior own-ID/signing gates
plus Sequoia and Tahoe installation/upgrade/hardware tests.
