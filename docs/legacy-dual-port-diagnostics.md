# Legacy Phase A / Phase B preparation: passive dual-port diagnostics

Baseline inspected: `main` at `8d5526603ae1924d8e4bbcaaff6a7c62c59bddcf`
(2026-11-07). **Not tested on physical hardware. No 64-channel audio support
is enabled by this change.** No firmware operations or new hardware writes.

## Current implementation versus model

| Area | Actual code on inspected main | Remaining work |
| --- | --- | --- |
| Legacy capabilities | `LegacySymphonyTopology.swift`: extensible AD/DA-16X, initial analog-only Rosetta profiles; independent 32-channel port capacity checks | Logical arithmetic only; not a physical slot map, rate capability table, or compatibility proof |
| Identity | `LegacyConverterAssignments.swift`: local persistence, model/mode confirmation, provenance and identity mismatch checks | No verified enumeration of individual legacy converters |
| UI | `LegacyConverterConfigurationView.swift`: per-position local assignments and individual ambiguity dialogs | `AppState.swift` observations deliberately empty; no trustworthy physical positions available |
| XLink | `ConfigureSymphonyLink`, `ReadVendorRequest`, `SendVendorRequest` use XLink1 registers and MK I vendor protocol | No legacy enumeration or XLink2 bus initialization/response queue |
| DMA | `SymphonyThunderbridge_IVars`: one A2H/H2A buffer, mapping and DMA command pair | No second directional buffer pair or per-port recovery state |
| Audio | `Start` ASBD uses `kMaxChannelsPerPort` (32); IO operation handler copies 128-byte frames | No 64-channel interleave/deinterleave and synchronized dual-port timestamp model |
| Routing | `ThunderboltCardRouting.swift`: 32-channel MK I board destination translation | Legacy device → physical channel → XLink slot → host channel mapping unverified |
| Clock | MK I clock-source control and port-1 link watcher | No independent legacy clock manager; RX detection is not PLL lock; no Big Ben assumption |

Existing MK I/USB connection, routing and clock paths remain unchanged. The new
CLI does not instantiate those paths or the general HardwareTest executable.

## New passive interface

`SymphonyThunderbridgeShared.h` adds selector **6**, schema **1**, exactly **26
UInt32 words / 104 bytes**. Existing selectors/layouts retain their values.
Unknown selectors on older drivers fail; the CLI never falls back to selectors
3/4, RX reads, vendor requests, or recovery. Selector 3 (`ReadTimingHealth`)
transmits a ClockRateAndLock request and can invoke recovery; it is **not passive**.
The old `Tools/read-thunderbridge-health.swift` comment now states that limitation.

| Word | Meaning |
| --- | --- |
| 0–4 | IOReturn status, schema, word count, register-valid bitmap, PCI identity |
| 5–20 | Registers listed below, in order; bit i of bitmap validates register i |
| 21–22 | Global interrupt callback count, low/high words (not a DMA error count) |
| 23–24 | Port-1 audio wrap count while I/O ran, low/high words |
| 25 | Flags: bit 0 means counters unavailable (passive-only service); other bits zero |

Register allowlist in `SymphonyPassiveDiagnostics.h`:

| Index | Register | BAR0 byte offset |
| --- | --- | --- |
| 0 | IDReg | 0x00 |
| 1 | XLinkClocking | 0x5C |
| 2 | DNALower (raw lower card DNA only) | 0x70 |
| 3 | ClkCtrl | 0x14 |
| 4–9 | GCSR, XLink1Status, A2HBUFSIZE, H2ABUFSIZE, A2HCHA, H2ACHA | 0x04, 0x40, 0x24, 0x4C, 0x2C, 0x34 |
| 10–15 | GCSR2, XLink2Status, A2H2BUFSIZE, H2A2BUFSIZE, A2H2CHA, H2A2CHA | 0x90, 0x60, 0x78, 0x8C, 0x80, 0x88 |

Offsets, GCSR2 masks, RX clock detect and sample-rate bit fields are defined in
`Sym64Registers.h`. This is repository evidence, not independent verification
against FPGA documentation or a legacy chain. Port-2 status uses the same
current down/slip masks as XLink1 provisionally; retain the raw words and
validate that interpretation on hardware before operational decisions.
The reported `dataState` refers only to these status bits, not converter
presence, enumeration completeness or usable audio. No source switching occurs.

Read safety: serialized on the existing XLink queue, rejecting stopping,
TX shutdown, provider-off and suspended states. Config-space presence and
Memory Space Enable must pass before BAR loads. No call to `HardwareReachable`
(which can clear interrupts), no state changes, RX FIFO reads, TX writes,
interrupt acknowledgement, route/clock writes, or reinitialization. IntStatus
is excluded because the existing IRQ code describes read acknowledgement
behavior. Unsupported BAR offsets and all-ones reads clear validity, not a
fabricated “down” or “empty chain”. PCIe 2100 is explicitly unsupported here.

Capture is sequential, not atomic. IRQs and the preexisting driver watch can
independently run; the latter may perform recovery writes. This diagnostic does
not make driver startup itself passive. Config-space checks cannot guarantee
survival of an arbitrary surprise removal between check and BAR transaction;
controlled power/cable testing remains a hardware gate. No new polling timer.

## Modular discovery and fallback

`LegacyXLinkDiscovery` accepts a read-only evidence source. Its live source
reports only passive card observations: no converter positions, identities or
counts are invented. `enumerationSupported=false` distinguishes lack of an
enumerator from a successfully enumerated empty chain. Saved choices never
become observations.

A future evidence-backed enumerator can provide reliably located observations
through the same interface. Existing `LegacyAssignmentResolver` handles each
unknown/ambiguous position, unsupported profile and Standard/Advanced mode.
Down/slipping/unknown links or missing RX clock suppress buffered identities.
Every refresh resolves from new evidence; an unavailable read throws and callers
must discard their prior result. The CLI retains no discovery state. Stable
identity mismatches discard saved candidates; untrusted model/mode reads require
manual confirmation. Advanced selection remains local metadata, never a
hardware mode switch. No AppState observations are populated until a verified
legacy enumerator exists. Simulator cases are not a substitute for that work.

## Run and export on Tahoe

Compilation (no installation):

```sh
swift test --package-path Apps/Maestro --filter LegacyXLinkDiscovery
swift build --package-path Apps/Maestro --product LegacyXLinkDiagnostics
bash Drivers/Thunderbolt/Scripts/test-passive-diagnostics.sh
bash Drivers/Thunderbolt/Scripts/build.sh --unsigned
```

With an independently approved/signed diagnostic client and matching loaded
driver supporting selector 6:

```sh
Apps/Maestro/.build/debug/LegacyXLinkDiagnostics > dual-port-report.json
```

Exit 0: all enumerated card services answered; **not hardware acceptance**.
Exit 2: no driver service, open denied, old selector, sleeping/missing endpoint,
or another per-card read failure; inspect JSON. Exit 1: collection/encoding
failure. Every service gets a separate registry ID; multiple cards are not
silently merged. `driverVersion` is unavailable when not exposed by IORegistry;
record the installed/loaded build identity separately before hardware acceptance.
PCI identity, raw card/port registers, RX clock detection/rate and available
counters are exported. Lock, converter inventory, active physical channel map,
per-port error counters and any unavailable values remain explicitly unknown.
The binary does not activate/install a driver, sign itself, or bypass SIP.

Unsigned CI artifacts cannot open the production user client merely because
they compiled. Do not install the existing MK I initialization path on an
unverified legacy chain expecting a passive probe: Start already writes MK I
configuration. A separately reviewed, own-signed diagnostic-only activation
path is a prerequisite for safely bringing up previously unsupported chains.

## Concrete Phase B gaps (baseline source anchors)

Use function/statement anchors below; line numbers move as diagnostics are added.

- `SymphonyThunderbridge.cpp` `ConfigureSymphonyLink`, `SendXLinkCommand`,
  `ReadVendorRequest`: XLink1 TX/RX only. There is no verified XLink2 command
  session, address assignment, independent sequence state, timeout/retry or
  legacy identity parser. Never copy MK I vendor opcodes to 16X units blindly.
- `Start` step 24 (`kRegA2H2BUFSIZE/H2A2BUFSIZE/HBA = 0`), baseline lines
  3057–3060; `ReprogramCardAfterReset` lines 1978–1981 repeats those zeros.
  GCSR2 channel-size programming alone does not establish Port-2 DMA.
- `SymphonyThunderbridge_IVars` baseline lines 96–120 and `Start` DMA
  allocation: only one capture/playback pair. Need separate buffers, mappings,
  32-bit address validation, complete/unwind paths and fault isolation.
- `Start` step 27 / `ReprogramCardAfterReset`: mask only `kInt_A2HWrap`.
  `InterruptOccurred` baseline line 4067: `hasAudioWrap` tests only Port-1 wrap;
  there are no per-port overrun/underrun counters or second wrap ownership.
  Port-2 wrap/overflow/underflow masks already exist in `Sym64Registers.h`
  (`kInt_A2H2Wrap=0x02000000`, overflow `0x01000000`, underflow `0x00800000`,
  H2A2 wrap `0x00400000`). Their presence is useful source evidence; actual
  IRQ timing/coalescing/acknowledgement on two active ports remains untested.
- `Start` ASBD baseline lines 3442–3445: 32 channels, 128 bytes per frame.
  IO operation handler baseline line 3840 onwards copies one 32-channel ring.
  Need tested 32/64-channel packing, wrap boundaries, partial-port failure,
  common sample-time anchor and rate-dependent channel capacities.
- `StartDevice`, `StopDevice`, `SetPowerState`, `Stop`,
  `MaybeRecoverSymphonyLink`, `ReprogramCardAfterReset`: lifecycle and link
  watch operate around one configured MK I link. Need independently specified
  two-port start/stop, suspend/reconnect and rate/clock-loss behavior.
- `ThunderboltCardRouting.swift` `channelCount`, `channel(forDestination:)`,
  driver `cardOutputRoute[32]`: MK I destinations and one port only. Existing
  `LegacyTopologyPlanner` contiguous ranges must not become FPGA slot addresses.

Before any Port-2 DMA enable: verify FPGA versions and read semantics, clocking
bit interpretations per port, buffer-size units, alignment/address limits,
GCSR2 endian/conversion behavior, port-2 interrupt masks, synchronization and
error acknowledgement with controlled hardware traces. Then implement pure DMA
layout/IRQ policy tests in a separate Phase B PR; enable writes only after
register/timing/error tests and explicit hardware evidence. No guessed writes.

## Validation and release gates

Local Linux: passive C++ tests and source safety gates pass; no Swift/Apple SDK
is installed locally. Tahoe GitHub Actions compiles SwiftUI/diagnostic binaries,
runs the existing and new Swift tests, tests passive C++ capture, and compiles/
links arm64 DriverKit with `--unsigned`. The latter exits before bundle/profile
lookup. Full test output (plus XML when emitted by SwiftPM), source SHA, build
environment and binary checksums are retained.
Read actual PR checks for the resulting run; CI success is never hardware proof.

Hardware tests **not run**: initial passive capture, each converter identity,
chain ordering/Advanced behavior, port-2 status semantics, PLL lock, DMA/IRQ,
64-channel audio, rate changes, sleep/reconnect and stability. Blockers: no
physical ThunderBridge access, no own approved signing identities/entitlements,
no verified legacy enumeration/slot/clock protocol. These block hardware
activation and subsequent write-enabling phases, not developer compilation.

Build classes: developer = unsigned compile/diagnostics; hardware-test = own
signed/entitled and controlled; release candidate = acceptance/stability gates
passed; production = explicitly approved signed/notarized installer. No release
or update-feed change belongs in this PR.

Own signing plan (identifiers below are proposals, not modified shipping IDs):
reserve app `com.kiwimartin.symphonymaestro`, diagnostic client
`com.kiwimartin.symphonymaestro.diagnostics`, driver
`com.kiwimartin.symphonymaestro.thunderbridge` under the fork owner's own team;
confirm ownership/availability in Apple Developer. Request DriverKit,
AudioDriverKit and PCI transport permissions restricted to required device IDs,
and matching user-client-access permission for app/diagnostic client. Add host
system-extension installation entitlement only to the activating app. Verify
Apple-approved profiles actually contain the requested entitlements. Request
Developer ID Application/Installer identities, store all keys/profiles externally,
and plan separate helper identifiers, install ownership and signing checks in
a dedicated migration PR. Preserve current IDs and production Sparkle feed in
this phase; future fork updates need a separate key/feed or disabled updates.
No upstream private keys/profiles, SIP changes or automatic clock fallback.

PR acceptance: versioned selector with no hardware writes; independent passive
port reports with validity; unknown inventory remains unknown; synthetic
ambiguity/reconnect tests resolve through existing fallback; C++/Swift/Tahoe
build checks pass; all hardware and signing blockers remain visible. Hardware
acceptance and enabling Port-2 DMA are explicitly outside these criteria.

CI evidence: runs 9 and 10 passed all 1,236 tests in 89 suites, existing and new
Swift executables, and the unsigned DriverKit build. Artifact inspection found
the relative XML output path did not produce a retained report. The follow-up
uses an absolute path and always captures test stdout/stderr with `tee` and
`pipefail`, requiring a test artifact to exist. Consult the final PR run for
verification of this correction. Compiler warnings remain in existing code
(e.g. CFString pointer usage and Swift actor-isolation warnings); no test or
build failure was reported in those runs. Hardware tests remain unperformed.
