# Legacy X-Symphony: development roadmap (macOS Tahoe)

Status: **Phase 1, pure logical model — no physical hardware verification**.

This is a separate development branch for legacy Apogee converters. It must not
change the shipping Symphony I/O MK I behavior or bypass macOS security.

## Dynamic topology: design requirement

The software must NOT contain a hard-coded device count, fixed converter order,
preselected studio topology, or special-case logic for particular model combinations.
The caller supplies a runtime topology from verified discovery, manually selected
identities, or a saved configuration. The planner uses reported channel capabilities,
the selected mode, and the physical port's capacity only. A user configuration
is not proof that the hardware supports the requested chain.

**Phase 1 only provides a pure software planner.** Physical device discovery
is not yet implemented. A manually selected identity must never be presented
as hardware-detected, and identification provenance is preserved on channel
assignments. Additional device profiles can be supplied at runtime without
changing the planner.

## Optional hardware validation scenario (never compiled into application logic)

One reported ThunderBridge setup to use later during hardware acceptance tests:

| Port | Reported converters | Logical I/O at base sample rate |
| --- | --- | --- |
| 1 (host channels 1–32) | 1x AD-16X Standard, 2x DA-16X Standard | 16 analog inputs / 32 analog outputs |
| 2 (host channels 33–64) | 1x DA-16X Standard, 1x DA-16X Advanced | 16 digital inputs / 32 analog outputs |

Expected totals: 16 analog inputs + up to 16 Advanced-mode digital inputs,
64 analog outputs. **Not yet a verified hardware map.** Chain order within
each port has NOT been confirmed. Actual assignment depends on cable ordering,
device firmware and configuration, sample rate and the legacy protocol.

Clocking must support both *internal* and *external word clock*; Big Ben is
an **optional** external source, not a prerequisite. No automatic, silent clock
fallback or unsupported "Loop Sync" for these legacy devices.

## Manufacturer compatibility caveat

Apogee's published supported combinations include two AD-16X or two DA-16X
units and several specific mixed chains. They do **not explicitly list**
(1 AD-16X + 2 DA-16X) on a single port, nor a two-DA chain with one in
Standard and one in Advanced mode. These are documented as one validation scenario only,
not proven compatible by software-side capacity arithmetic. **Do not encode
warnings or behavior for these particular combinations in the planner.**

Advanced mode is selected on the physical device at power-on; the application
cannot safely assume that setting. An Advanced-mode DA-16X can also be
misidentified as an AD-16X. Any future identification layer should track
provenance (detected/manual/unverified) and offer a manual correction.

Sources:
- https://knowledge.apogeedigital.com/using-legacy-interfaces-ad16x-da16x-rosetta-with-symphony64-card-or-thunderbridge
- https://knowledge.apogeedigital.com/how-to-turn-on-advanced-routing-mode-on-the-ad-16x-and-da-16x
- https://knowledge.apogeedigital.com/symphony64-pcie-thundebridge-users-guide-documentation-and-downloads

## Repository findings

The upstream default branch currently handles one ThunderBridge XLink port:
- Drivers/Thunderbolt/Source/SymphonyThunderbridge.cpp publishes 32-channel
  Core Audio I/O streams. The second port's DMA addresses are set to zero.
- Drivers/Thunderbolt/Source/Sym64Registers.h contains separate registers for
  port 2, such as GCSR2, port-2 buffers, XLink2, and 64 routing crosspoints.
  Definitions alone do not implement the second port.
- Apps/Maestro/MaestroDevice/ThunderboltCardRouting.swift uses 32-channel
  MK I Symphony I/O-specific channel and destination mapping.
- Apps/Maestro/MaestroCore/ClockConfig.swift represents the Symphony I/O MK I
  clock model, which is NOT automatically interchangeable with 16X firmware.

## Phase 1: implemented

- Read-only, pure Swift LegacySymphonyTopology.swift in MaestroCore; no embedded studio fixture, no named-combination special cases.
- Device profiles for AD-16X, DA-16X, and initial analog-only Rosetta
  200/800 profiles; further profiles can be added.
- Independent 32-channel per-port planning, combined maximum host bus 64x64.
- Optional internal/external word-clock preference.
- Identity provenance preserved through assignments, plus checks for invalid
  port, duplicated IDs, missing mode capability, and exceeding 32 channels per port.
- Automated model tests in MaestroCoreTests.

**Explicitly NOT implemented:** physical discovery, verified real routing
addresses, Core Audio 64-channel streams, XLink 2 initialization, analog
signal monitoring, vendor control of legacy units, clock switching,
or any write to converter hardware.

Test on a development Mac:

    cd Apps/Maestro
    swift test --filter LegacySymphonyTopology

## Phase 2A: read-only discovery (next development step)

1. Add isolated, read-only hardware capability reporting per ThunderBridge
   port: card identity, link present/down, detected sample rate and clock lock.
2. Design bounded read-only XLink enumeration; do not guess legacy vendor
   opcodes or write to a converter to "probe" it.
3. Distinguish explicitly between live detected, manually identified, and
   unknown devices. Unknown Advanced equipment must NOT become an AD-16X by
   default.
4. Return structured diagnostics for both ports and, when available, compare
   them against a separately provided user configuration; do not enable port 2
   audio DMA yet.
5. Add simulator tests for absent second port, no lock, unknown converter,
   device power cycle, and incorrect manually supplied type.
6. On macOS Tahoe, run a **read-only** diagnostic on available hardware. No Sonoma
   installation is assumed to be available.

## Phase 2B: driver and actual audio channels (requires hardware tests)

- Initialize the second XLink bus and independently manage its DMA registers,
  two directional buffers, wrap/underflow/overflow IRQs, rate changes and
  teardown sequence. Do NOT simply change "32" to "64".
- Publish a correctly constructed 64x64 Core Audio stream (or equivalent
  supported driver structure), preserving the working MK I path.
- Implement verified per-port crosspoint routing, Advanced-mode digital
  sources, and clock switching, only after capturing known-good behavior.
- Provide a dynamic, operator-correctable UI and presets.
- Validate channel mapping and stable audio operation at every supported
  sample rate with actual studio hardware.

## Safety and integration rules

Follow root AGENTS.md. Keep production signing, firmware flashing,
DriverKit activation, install/uninstall, update feeds, release assets and
existing app/driver bundle identifiers untouched in this phase.

The pure Swift model is NOT proof that an unsupported hardware daisy chain
will work. Never claim the current fork supports 64-channel audio until
the dedicated driver path has passed hardware tests.
