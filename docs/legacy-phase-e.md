# Phase E: independent legacy clock state and preferences

Internal and External Word Clock are local preferences independent of MK I's
ClockConfig, ClockMode opcodes and Loop Sync. Big Ben is optional, never an
inventory dependency. Sample-rate choices require evidence for every required
port and use the intersection of those capabilities; no conventional-rate list
is treated as hardware support or a promise of full channel count.

The state machine distinguishes unknown, detected-but-unverified, missing clock,
unlocked, rate mismatch and verified lock. Passive RX clock detection alone
cannot become locked. Disconnect clears observations. External loss preserves
External preference and never silently switches to Internal. New preferences
invalidate prior status; saved preferences do not claim an applied source.

Presets persist only local intent, with schema validation. Hardware application
requires confirmation and supported-rate evidence, then remains explicitly
unavailable because no verified legacy clock transport exists. No saved preset,
user flag, MK I vendor opcode or mock backend can enable real writes.

Tests cover capability intersections, missing ports, clock loss, lock and rate
mismatch, controlled state recovery and preset persistence. Runtime channel
profile changes also invalidate routing inventory signatures, preventing a new
capability set from silently reusing an old routing map.

Hardware tests: **NOT RUN**. Selecting the actual converter master/source,
reading genuine PLL lock/measured rates, and controlled restart on real chains
remain blocked by protocol evidence, hardware access and own signing. Internal/
External hardware acceptance has not passed. Depends on Phase D PR.
