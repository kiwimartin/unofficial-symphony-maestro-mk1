# Phase D: physical endpoints, explicit slot maps and routing presets

The routing inventory derives analog/digital input/output endpoints from runtime
converter profiles and manual/detected metadata. Unknown identities expose no
invented channels. Capacity is validated before use. No studio layout is built in.

`LegacySlotMap` requires explicit endpoint → per-port XLink-slot entries. It
never treats the topology planner's additive ranges as physical slot addresses.
Slots may be sparse or reversed. Duplicate slots in a direction, duplicate
endpoints and out-of-range/missing endpoints are rejected. Host labels preserve
Port 1=1–32 and Port 2=33–64. Evidence references are audit metadata, not a grant
of hardware trust; no legacy write executor is implemented or registered.

Presets save requested routes and the full chain/mode/identity configuration,
explicit map signature and sample rate. Restore requires confirmation, rechecks
all routes against the current inventory/map, and refuses to overwrite different
existing routes unless explicitly requested. Reconnect requires new evidence and
confirmation; a saved preset cannot establish detected hardware or verified slots.
Persistence rejects malformed/future-schema data without overwriting it.

Tests cover Advanced digital paths, unknown entries, sparse/reversed mappings,
duplicate slots, preset round-trip, changed configuration/rate and overwrite
protection. Tahoe CI runs these with the existing suite.

Hardware tests: **NOT RUN**. Actual routing commands and authoritative slot maps
for each model/order/mode/rate remain blocked by protocol and hardware evidence.
This is the safe, usable configuration architecture; it is not a claim that a
saved routing preset has changed the FPGA or converter. Depends on Phase C PR.
