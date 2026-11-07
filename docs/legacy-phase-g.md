# Phase G: independently passive hardware-validation path

The previous selector-6 probe was passive, but attaching the shipping MK I
AudioDriverKit driver still programs hardware. This PR adds a separate
`SymphonyPassiveDiagnostics` IOService and user client, **without AudioDriverKit**.
It compiles as an unsigned executable only; no installable bundle is assembled,
no activation is requested, no profiles or signing identities are accessed.
The personality template has mandatory own-identifier placeholders and must
never replace the shipping driver's identity. A signed host/permission plan
belongs to Phase H; no upstream credentials or security bypass is acceptable.

Start opens PCI exclusively, requires the exact ThunderBridge ID and already
set Memory Space Enable, obtains BAR bounds, and refuses active/dirty DMA or
interrupt state. It never enables PCI memory/bus mastering, clears IRQs, repairs
registers, sends XLink commands, programs DMA, or accesses firmware. If the
endpoint is unavailable or configuration is not already safe, it refuses with
an explicit error. This is intentionally less permissive than an audio driver.
Stop drains the serial read queue before closing PCI and performs no hardware
writes. Power-off gates and drains reads; resume does not reconfigure hardware.
The user client exposes selector 6 only. The app/CLI discover this service by
its separate name, while retaining compatibility with the existing audio driver.

The shared packet's previously reserved word 25 now defines bit 0 as counters
unavailable; the passive-only service sets it because it has no audio/IRQ engine.
Older clients safely reject that flag rather than show fake zero counters. New
clients preserve validity and don't display nonexistent engine counters. The
shipping audio-driver snapshot retains flag 0 and its existing counters.

Validation: source gates reject hardware write calls, DMA/IRQ engines, vendor
requests and unsafe teardown order. Tahoe compiles/iig-links the standalone
service and both clients. Existing Swift and C++ suites run. Local source gates
and shell syntax pass. Physical activation, surprise removal and sleep/wake:
**NOT RUN**. A PCI presence check still cannot eliminate every physical unplug
race on Apple Silicon; signed controlled hardware validation is mandatory.

## Reproducible physical test record (all currently NOT RUN)

1. Record macOS version, machine/ThunderBridge identity, own team/bundle IDs,
   exact signed binary/package hashes and installed/loaded driver identity.
2. Confirm no competing audio driver/clients and a quiescent device. If this
   passive service refuses dirty state, stop; never add a speculative reset.
3. Export the CLI report for each independently connected port, no converters,
   unknown units and every supported converter/model/mode. Preserve raw words,
   validity and the test wiring; no identity is inferred from position or DNA.
4. Repeat on restart, controlled device power loss, cable change and sleep/wake.
   Record old/new registry identities, failures and unavailable fields. No
   automatic source switching or routing replay should occur.
5. Independently verify RX/status/rate semantics on each FPGA version and the
   legacy enumeration/slot protocol. Publish only authorized public evidence.
6. After the Phase B/C write gates pass, test isolated output positions, record
   every physically present input, sample-rate capacity, coalesced IRQs, buffer
   wrap, overruns/underruns, clock loss and controlled restart. Then run sustained
   bidirectional audio/stability tests with exact durations and error counts.

Software CI cannot check off any item above. No old Sonoma/Maestro installation
is assumed. No firmware update, SIP change or private manufacturer source.
