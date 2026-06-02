# VT Direct Stream Readiness Research Cache - 2026-06-02

Research cache. Research only. No product code edits.

## Answer

A worker-ready narrow slice can remove live terminal feed's dependency on queued `ParsedEvents` while preserving current observable behavior, if scoped to `stream_terminal.zig` and keeping `parser/events.zig` as test/materialization vocabulary for now.

The remaining missing fact is only for a later broader cut: removing `parser/events.zig` from `route.zig`/`xterm/dcs.zig` entirely requires the owner-specific action vocabulary split to be settled first.

## Source-Backed Facts

- Current Howl live feed: `stream_terminal.State` owns both `parser` and queued `ParsedEvents`.
- `nextSummary` parses one byte, appends parser phases into `ParsedEvents`, finishes a batch, then drains queued events through `route.apply`.
- Parser failure resets parser via `errdefer state.parser.reset()`.
- Append failure rolls back queued events, bytes, DCS/APC/PM buffers, DCS hook, and charset state.
- Route failure drops queued events but does not roll back already-applied terminal mutations.
- `ParsedEvents` currently owns queued event storage, payload stores, rollback snapshot, APC/DCS/PM accumulation, DCS hook/body reconstruction, charset state and DEC special graphics mapping, event iteration/reconstruction.
- `Terminal` already owns charset state.
- `route.apply` mutates terminal charset state for invoke/configure charset.
- Reports read charset from terminal.
- DCS request/status and host payloads are still real Howl consequences and must be preserved.
- Ghostty parser emits transient actions directly, stream maps parser actions directly into handler callbacks, and terminal handler applies actions directly to terminal state.

## Worker-Ready Slice

Allowed implementation scope:

- `howl-vt/src/stream_terminal.zig`
- Targeted tests under existing curated test entrypoint, preferably `howl-vt/src/test/terminal_end_to_end.zig`, `terminal_surface.zig`, or `terminal_modes_reports.zig`

Do not delete `parser/events.zig`, split vocabulary, or change ABI.

Required shape:

- Remove `events: parsed_events.ParsedEvents` from `stream_terminal.State`.
- Keep `parser: parser_mod.Parser`.
- Add stream-owned private DCS accumulator in `stream_terminal.zig` with exact responsibilities:
  - Capture `dcs_hook` params/intermediates/final.
  - Build DCS `body` as current `appendDcsBody` does: params separated by `;`, then intermediates, final, then payload.
  - Track `payload_start` so `.payload` slices match current `DcsEvent`.
  - Enforce payload length against `parser_mod.max_metadata_control_bytes`.
- Add stream-owned APC/PM bounded counters or buffers:
  - APC enforces `parser_mod.max_apc_control_bytes`.
  - PM enforces `parser_mod.max_metadata_control_bytes`.
  - APC/PM terminal consequences remain no-op because route currently returns null for `.apc` and `.pm`.
- Map parser actions directly in `stream_terminal.nextSummary`.
- Apply generated ephemeral `parsed_events.Event` values immediately through `route.apply`.
- Preserve current error semantics:
  - Any `FeedError` resets parser.
  - Accumulator mutation for the current byte rolls back on accumulation/limit/OOM errors.
  - Consequence errors propagate without terminal-wide rollback.
- Move charset mapping out of `ParsedEvents` live path:
  - `execute` SO/SI applies `invoke_charset` to terminal first.
  - ESC `(` and `)` applies `configure_charset` to terminal first.
  - `print` maps DEC special graphics from terminal fields before applying `.text`/`.codepoint`.

## Non-Goals

- Do not delete `parser/events.zig`.
- Do not split `action/vocabulary.zig`.
- Do not change C ABI.
- Do not introduce a manager/controller/types owner.
- Do not change parser state machine behavior.

## Tests And Gates

- From `howl-vt`: `zig build test:unit`.
- From `howl-vt`: `zig build test:abi`.
- From `howl-vt`: `zig build check`.
- Required tests: DEC special graphics through split feed; DCS DECRQSS pending output; DCS retained payload kind/body/payload; overlong APC fails then following byte succeeds; add PM overlong/recovery if absent.

## Grep Gates

- `stream_terminal.zig` must not instantiate or store `ParsedEvents`.
- `stream_terminal.State` must not contain `events`.
- Live stream must not call `beginBatch`, `appendPhases`, `front`, `popFront`, or `dropPrefix`.
- `parser/events.zig` may remain for parser materialization tests and action mapping until later vocabulary-owner split.

## Risks

- DCS body equivalence is the main implementation risk. Preserve `body` vs `payload` exactly.
- Preserve rollback semantics: current behavior rolls back parser/event accumulation, not arbitrary terminal mutations.
- Do not weaken APC/PM bounds.
