# Phase F: integrated legacy control workspace

System Setup's existing Legacy section now contains a dedicated workspace:
per-port converter assignment, source provenance/individual ambiguity prompts,
on-demand passive reports for every card service, both port statuses, RX clock
and rate, unknown PLL lock, available counters, JSON export, physical channel
rows, explicit slot selection, up-to-64-channel local routing drafts, routing
preset save/confirmed restore and independent Internal/External preferences.
Existing MK I and USB controls remain present and use their previous paths.

A shared isolated LegacyDiagnosticTransport target is used by both the app and
CLI. It only opens already registered services and invokes selector 6, with
exact packet/size checking and no vendor/fallback/activation. Reads run off the
UI thread. Each refresh clears old reports before reading; failures never retain
stale live status. Registry IDs distinguish cards. Local assignments are not
claimed to be bound to detected converters or a selected card.

Mapping/routing controls are clearly local drafts; no automatic slot assignment
is generated. Presets now contain explicit slot entries so they can restore the
entire local map after confirmation, while validating current topology/mode/rate.
Duplicate names and malformed stores are not silently overwritten. Unknown
converters expose no invented physical channels. Hardware apply buttons remain
disabled, with clear explanations, because validated legacy transports are not
available. Conventional rates entered for draft mapping are not offered as
verified supported clock rates.

Automated validation: Tahoe compiles SwiftUI and the standalone CLI; the existing
core tests cover persistence, explicit mapping, overwrite protection and clock
state. GUI runtime/accessibility and physical hardware tests: **NOT RUN** (Linux
workspace, no macOS GUI/hardware/signing). This is an integrated configuration
and diagnostic interface, not operational legacy hardware control. Depends on
Phase E PR. No production update feed, identifiers or activation ownership changes.
