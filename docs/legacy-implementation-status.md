# Legacy Symphony implementation and acceptance status

No phase is declared hardware-complete by CI. The final goal remains stable
physical 64x64 audio under Tahoe, not a 64-channel UI or buffer simulation.

| Phase | Implemented software | Remaining physical/production acceptance |
| --- | --- | --- |
| A | Passive dual-port snapshots, strict validity, converter resolution/manual provenance | Verified individual legacy enumeration and identity/mode evidence |
| B | Independent register descriptors, DMA-region validation, IRQ/lifecycle policy and sanitizer tests | Actual second DMA allocation/programming, verified XLink2 session, timing/error recovery |
| C | Actual 32/64 buffer interleave/deinterleave, integrated existing 32-channel path, exhaustive tests | 64-channel publication, Port-2 DMA, shared hardware timestamps and physical I/O |
| D | Physical endpoint catalog, explicit sparse slot mapping, guarded routing presets | Authoritative chain/mode/rate slot tables and verified hardware routing commands |
| E | Independent clock intent/status, loss/rate/lock handling, presets, no silent fallback | Actual legacy source switch, PLL lock and Internal/External restart validation |
| F | Integrated SwiftUI configuration/diagnostics/routing drafts, per-port status, presets/export | GUI runtime acceptance and enabled verified legacy hardware controls |
| G | Separate passive-only PCI service, no-write lifecycle, controlled test protocol | Own-signed activation, real converter/port/clock/audio/stability tests |
| H | Unsigned all-component CI, retained evidence/checksums, own-signing preflight | Own Apple approvals/IDs, identifier migration, signed/notarized installer and release approval |

PR sequence: #3 (B), #4 (C), #5 (D), #6 (E), #7 (F), #8 (G), #9 (H).
Later PRs are stacked on the preceding phase to keep each change reviewable.
No automatic PR merge, production tag or publication is authorized here.

Hard blockers: no physical ThunderBridge/converters, no own approved Apple
signing/DriverKit permissions, and no validated legacy enumeration/slot/clock
protocol evidence. Filling those gaps with guessed writes or simulated success
would violate the development requirements. All safe software work is supplied
for review; hardware-dependent controls remain explicitly unavailable.

See legacy-phase-b.md through legacy-phase-h.md for source boundaries, commands,
tests and acceptance limits. See legacy-dual-port-diagnostics.md for register ABI.
