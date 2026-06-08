# VT Host Consequence Capacity

Date: 2026-05-30

## Question

Inventory VT host consequence dynamic storage and decide whether the next slice is ready to convert
one path to bounded storage without changing OSC 52, hyperlink, title, report, or parser semantics.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-05-30-hygiene-audit/roadmap.md` Slice 4.2
- `howl-vt/src/host/state.zig`
- `howl-vt/src/host/apply.zig`
- `howl-vt/src/parser/events.zig`
- `howl-vt/src/control/report.zig`
- `howl-vt/src/control/locator.zig`
- `howl-vt/src/control/osc_color.zig`

## Current Bounds

- `host_state.pending_output_max_bytes` is `parser.max_large_osc_control_bytes`.
- `host_state.retained_payload_max_bytes` is `parser.max_large_osc_control_bytes`.
- `host_state.retained_metadata_max_bytes` is `parser.max_metadata_control_bytes`.
- `host_state.title_max_bytes` is `1024`.
- `host_state.hyperlink_target_max_count` is `4096`.
- `ParsedEvents.max_queued_events` is `1024 * 1024`.
- APC payload capture is bounded by `parser.max_apc_control_bytes`.
- DCS and PM payload capture are bounded by `parser.max_metadata_control_bytes`.
- Report formatting scratch is bounded by `input_encode.Scratch`; most formatted reports use
  `format_output_max_bytes = 64` or the caller scratch buffer.

## Dynamic Storage Inventory

- `howl-vt/src/host/state.zig` owns host consequence retention.
- `State.pending_output: std.ArrayList(u8)` retains bytes hosts later drain.
- `State.hyperlink_targets: std.ArrayList([]u8)` retains URI slices, with each URI allocated by
  `internHyperlink`.
- `State.pending_clipboard: ?ClipboardRequest` retains OSC 52 raw payload through `replaceClipboard`.
- `State.current_title: ?[]u8` retains title bytes through `replaceOwned`.
- `State.dcs_payload: ?DcsPayloadOwned` retains DCS payload bytes through `replaceDcsPayload`.
- `appendOutput` checks `pending_output_max_bytes` before `ArrayList.appendSlice`.
- `replaceOwned`, `replaceClipboard`, and `replaceDcsPayload` check retained byte bounds before
  `dupe`.
- `internHyperlink` checks URI byte bound and hyperlink count before allocating and appending.
- `drainPendingClipboardSet` still allocates a decoded slice for the caller allocator; the non-allocating
  `drainPendingClipboardSetInto` path already exists.
- `howl-vt/src/parser/events.zig` owns parser-event materialization for tests/proofs and any event
  consumers that request materialized events.
- `ParsedEvents` has `ArrayList(EventMeta)`, `ArrayList(u8)`, `ArrayList(i32)`, `ArrayList(u8)` aux,
  and separate APC/DCS/PM byte buffers.
- `ParsedEvents.appendMeta` bounds event count, but aggregate byte/int/aux `ArrayList` growth is
  bounded indirectly by parser string-control limits and input volume, not by a single explicit store
  capacity.
- `collectParsedEvents` allocates a test/proof `[]Event`; it is not on the live host consequence drain.
- `howl-vt/src/control/report.zig`, `locator.zig`, and `osc_color.zig` append into
  `host_state.pending_output`; their capacity boundary is `host_state.appendOutput`.

## Readiness Judgment

The first implementation slice is not static-storage conversion. The source is bounded but still
heap-backed in several semantically different stores. Converting one store now would risk a fake
bounded story because capacity ownership is not unified: pending output bytes, retained title, OSC 52,
DCS payloads, hyperlink target count, hyperlink target bytes, and parser-event materialization each
have different lifetime and drain rules.

The worker-ready next slice is a capacity contract documentation slice inside code: add compile-time
assertions and narrow owner comments to `host/state.zig` and `parser/events.zig` that bind each limit
to its owner and make the current heap-backed bounded behavior explicit. That slice should not
replace storage.

## Proposed Next Slice

Name: `Document VT Consequence Capacity Contracts`.

Exact files:

- `howl-vt/src/host/state.zig`
- `howl-vt/src/parser/events.zig`
- tests only if an existing capacity test needs an exact assertion update

Changes:

- Add compile-time assertions for the capacity constants that are protocol/product limits.
- Add a short owner comment above `State` in `host/state.zig` stating that heap storage is currently
  bounded by the constants in this file and owned by host consequence retention.
- Add a short owner comment above `ParsedEvents` stating that parser-event materialization is bounded
  for queued events and string-control payloads but still has an explicit proof gap for aggregate
  byte/int/aux store capacity.
- Do not convert `ArrayList` storage.

Verification:

- `zig build check`
- `zig build test`
- `git diff --check`
- `rg 'pending_output_max_bytes|retained_payload_max_bytes|retained_metadata_max_bytes|title_max_bytes|hyperlink_target_max_count|max_queued_events' howl-vt/src/host/state.zig howl-vt/src/parser/events.zig`

## Proof Gaps

- Parser-event aggregate byte/int/aux capacity is not expressed as one explicit bound.
- Hyperlink URI retained bytes are bounded per URI, not by total retained hyperlink bytes.
- Static storage sizing needs a product capacity decision before implementation.
