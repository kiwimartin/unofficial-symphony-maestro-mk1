# Optional stereo input/output strips

Feature branch: `feature/stereo-input-output-links`, based on the Sequoia/Tahoe
compatibility branch. No automatic merge or release.

On the Input and Output pages, a link button on a mono strip combines complete
physical odd/even pairs (1/2, 3/4, …) into one stereo strip. Input and output
links are independent. The stereo strip has separate L/R meters and peaks, a
common gain/trim fader where compatible, an unlink button and an L/R-settings
popover exposing the original individual controls. Show/Hide Trims is honored.

As requested, linking matches the **quieter gain/trim setting**: it chooses the
lower current dB value, leaves that side unchanged and lowers only the other.
This compares control settings, not instantaneous signal meters; it does not
normalize or sum live stereo audio. Equal settings require no hardware write.
A required alignment uses the existing per-channel property path and links only
after successful write returns. An error or device/layout change prevents a new
link and is shown; no new XLink/vendor opcode is introduced. Subsequent common
moves are serialized per pair, coalesce rapid requests to the newest complete
L/R target and persist levels only after confirmation. A real connection identity
and layout check before and after every await blocks stale reconnect writes and
saved links. Individual controls and reset actions are blocked during alignment.
Moves respect both ranges and preserve any deliberate L/R offset made in the
individual settings. Unlinking leaves levels and routing unchanged.

Pairs must be complete, odd/even and within the same physical board. Unknown
layouts, missing partners, incompatible input/reference modes or incompatible
ranges cannot be linked with an automatic level match. Shared microphone gain
requires both existing firmware gain groups to be Off; otherwise double-applying
firmware group changes could produce the wrong gain. Instrument gain remains
individual because its existing hardware transport is not fully supported.
Phantom, phase, filters, references, groups and inserts remain per-channel; link
never enables phantom, changes mode or sends a routing/clock command.

Stereo preferences are saved separately for input/output, scoped by the existing
card-layout/simulation store and device UID. Reloading preferences changes
presentation only; it does not replay level writes. Changed/incomplete layouts
ignore invalid pairs. Every physical/Core Audio channel remains independently
addressable; DAW numbering, stream channel count, slots and audio buffers do not
change. Digital meter pairs retain their existing display.

The separate Legacy preview also supports local physical odd/even grouping within
one converter/port/direction/media. It preserves explicit L/R slots/routes and
can select a requested DAW stereo pair after both slots are assigned. It has no
verified hardware level read/write path: level matching is explicitly unavailable
there, and no level is invented or routed to simulate it. Links are local
preferences tied to the full inventory signature and independent of routing
presets; saved malformed link data is not overwritten.

Automated tests cover 1/2…63/64, odd/missing counts, invalid saved indices,
board/port boundaries, unchanged source indices, quieter-side matching,
nonfinite values, incompatible ranges and bounded relative motion. Continuation-
controlled transport tests cover fast repeated moves, failures, invalidation and
reentrant requests without overlapping pair writes. Existing
Sequoia/Tahoe builds/tests and cross-OS preview startup remain in CI.
Physical level matching and interactive channel-strip operation on hardware:
**NOT RUN** (no connected converter/own signed hardware-test environment).
