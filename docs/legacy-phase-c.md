# Phase C: actual audio buffer copy implementation

`SymphonyAudioRingCopy.h` implements allocation-free 32-bit interleaved ring
copying for one or two 32-channel port buffers. In 64-channel mode host frame
channels 1–32 belong to Port 1 and 33–64 to Port 2. Capture interleaves and
playback deinterleaves the two independent buffers. Complete source/destination
bounds and overlap checks occur before any destination changes. Missing Port 2
fails without mirroring, shifting channels or partially copying Port 1.

The existing driver's **32-channel** IO operation handler now uses the same
tested function. Its current channel format, IRQ/timestamp lifecycle and hardware
configuration remain unchanged. The function clamps frame counts before byte
multiplication, avoiding overflow for an invalid oversized request.

Tests exhaust every start offset of a non-power-of-two ring, both directions,
32/64 channels, zero/single/partial/full/oversized frame counts, sentinel channel
values, wrap, short/null/overlapping buffers and missing Port 2. Address/UB
sanitizers run locally and in Tahoe CI. Existing lifecycle checks still pass.
Run `bash Drivers/Thunderbolt/Scripts/test-audio-ring-copy.sh`.

NOT completed: actual 64-channel AudioDriverKit stream publication, physical
Port-2 DMA, a common hardware-verified timestamp anchor, high-rate capacity,
rate-change rollback with two active ports or physical channel tests. Publishing
64 channels without those would expose unusable audio, so this PR does not do
so. No success in these software tests establishes stable physical audio.

Hardware tests: **NOT RUN**. Own signing, hardware and the Phase B register/
timing gates remain prerequisites. This PR depends on the Phase B foundation;
review it separately and do not auto-merge either PR.
