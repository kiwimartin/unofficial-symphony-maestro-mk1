# Legacy X-Symphony — first production release readiness

Status: **NOT READY FOR A PRODUCTION RELEASE**.

This project must not tag, package, notarize, or publish a signed installer
for legacy 16X configurations until each gate below is satisfied. The
repository's existing MK I update feed, bundle identifiers, and installation
paths must remain unchanged.

## Implemented in draft PR #1

- Generic channel-capability model for dynamically supplied converter chains.
- Per-converter manual assignment and Standard/Advanced choice.
- Persisted manual selections, identity provenance, prompt for ambiguous
  observations, and re-confirmation when mode cannot be trusted.
- UI in System Setup on ThunderBridge, clearly labeled as a local-only
  configuration with no hardware-routing writes.
- 14 generic channel-topology unit tests and 12 manual-assignment tests.
- macOS Swift package CI workflow.

**The app's legacy converter observation array is deliberately empty today.**
The published ThunderBridge driver doesn't identify individual AD-16X/DA-16X
devices. A manual entry in the UI is **not** automatic discovery. No logical
channel map in this PR proves hardware compatibility.

## Mandatory gates before production

- [ ] macOS package builds and test suite passes on the target release commit.
- [ ] Legacy converter detection / ambiguity reporting is backed by actual
      read-only XLink evidence for each supported converter and port.
- [ ] Correct Port 2 DMA buffers, IRQ handling, Core Audio channel map and
      64-channel routing tested on physical ThunderBridge hardware.
- [ ] Device-specific routing behavior verified for Standard and Advanced
      configurations, with a safe path for unknown devices.
- [ ] Internal/External word-clock selection and clock lock/failure reporting
      tested with AND without an external master.
- [ ] Audio I/O, sample-rate changes, power cycling, startup and reconnect
      tested under macOS 26 Tahoe, including sustained stress tests.
- [ ] Release signing entitlement, notarization, upgrade/rollback, and exact
      published artifact hashes checked without changing the established
      MK I production release channel.
- [ ] Explicit hardware sign-off before enabling legacy vendor writes.

## Test without an older Sonoma reference machine

Start with a read-only two-port hardware diagnostic under Tahoe (no routing or
clock writes). Save port links, converter addresses if reliably observable,
clock state, sample rates and the driver build identity. When legacy converter
command behavior is unknown, do not guess opcodes or push vendor commands.

The first **release candidate** may ship to a closed test environment only
after a successful macOS build, but must be labeled as *manual assignment UI
and unverified legacy hardware support*. It cannot be called a production-
ready 64x64 Maestro replacement until the above gates are complete.

See also: docs/legacy-symphony-development.md
