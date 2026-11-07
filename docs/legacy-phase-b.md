# Phase B: dual-port DMA foundation

Baseline main: 23276dab81c7c4e7743a43400a27006c91d6586c (PR #2 merged).

Implemented: independent Port 1/2 register descriptors derived from existing
Sym64Registers.h, 32-bit DMA region validation (bounds, alignment, all four
buffer overlap combinations), port-specific wrap/overrun/underrun decoding,
and generation-based lifecycle policy. Clock loss, rate change, suspend,
stop and reconnect invalidate a prepared generation. One port's error does not
change the other's state. Meter-only IRQs cannot count as audio wraps.

Tests: standalone C++ with address/undefined-behavior sanitizers; invalid IOVA,
short buffers, overlap, invalid ports, mixed IRQs, coalesced wraps, loss of
clock, stale start generations, suspend/resume and independent faults.
Run `bash Drivers/Thunderbolt/Scripts/test-dual-port-dma.sh`.

This is a reusable **software foundation, not operational Port-2 DMA**. It
contains no register write operation and is not wired into the current IRQ or
allocation path. `kPort2HardwareValidated` remains false. Simulator calls with
explicit true verify policy transitions only. No developer option enables Port 2.
Existing 32-channel MK I/USB paths are unchanged.

Still blocked: verified XLink2 initialization and legacy enumeration, actual
second IODMACommand/mappings, FPGA endian/conversion and ring-size semantics,
IRQ timing/coalescing/acknowledgement with both ports running, common sample
clock, rate-dependent capacity, and signed physical tests. Register definitions
are repository evidence; they are not proof of live hardware behavior.

Before integration: obtain controlled passive captures with an own-signed
read-only activation path, confirm register semantics and timing, then allocate
and unwind separate capture/playback mappings and validate startup/teardown on
hardware. Do not turn this foundation into speculative FPGA writes.

Acceptance for this PR: sanitizer tests pass locally/Tahoe, existing Swift and
DriverKit compile/tests pass, no shipping behavior or hardware write changes.
Hardware acceptance: **NOT RUN; no physical hardware/signing available**.
