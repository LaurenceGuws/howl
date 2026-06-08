# VT Parser Action Next Research Cache - 2026-06-02

Research cache. Research only. No product code edits.

## Result

No broad worker-ready split is justified yet. Ghostty supports reshaping away from Howl's live queued parser-event store, but the exact Howl cut still needs one more narrow design pass because Howl currently uses the queue for DCS/APC/PM buffering, charset materialization, rollback, and event iteration.

## Source-Backed Findings

- Ghostty parser emits transient actions directly from `Parser.next`, not a queued event store.
- Ghostty stream maps parser actions directly into handler callbacks, and terminal handler mutates terminal state or effects directly from stream actions.
- Howl live stream currently materializes parser phases into `ParsedEvents` before applying them, then drains immediately.
- Howl `ParsedEvents` is a real multi-owner bundle today: event surface, queue and payload stores, rollback state, parser-action materialization, DCS reconstruction, and event reconstruction.
- Howl parser itself already has a Ghostty-like transient phase action shape.
- Howl action vocabulary is a bucket: `SemanticEvent` spans screen, mode, report, Kitty, host, DCS, locator, and protocol outcomes, then duplicates owner-specific unions.
- True execution owners already exist: screen, mode, report, host, and Kitty apply owners.
- `action/route.zig` is the current central router from parsed event to semantic/action owners.

## Owner Map

- `parser/main.zig`: owns VT state machine, transient parser actions, CSI/OSC/DCS/APC/PM parsing bounds.
- `parser/events.zig`: currently owns queued event materialization, payload storage, DCS/APC/PM accumulation, charset mapping, rollback, compaction, and iteration. This is too broad for live stream use.
- `stream_terminal.zig`: should own stream-to-terminal sequencing. Current queue use is not Ghostty-backed for live application.
- `xterm/*`: owns protocol decoding from parser-level CSI/OSC/DCS/ESC/C0 facts into terminal consequences.
- `screen/apply.zig`, `control/mode.zig`, `control/report.zig`, `host/apply.zig`, `kitty/apply.zig`: true consequence owners.
- `action/vocabulary.zig`: current bucket only; should not remain the long-term home for owner-specific action types.

## Proposed Order

1. Research/design one narrow direct-stream cut before any action vocabulary split: define a Howl stream handler shape that consumes parser phase actions directly, preserving `FeedError`, rollback-on-error behavior, DCS body needs, APC/PM behavior, charset state, and `FeedSummary`.
2. After direct-stream ownership is settled, split vocabulary based on surviving owners, not the current bucket shape.
3. If direct-stream is accepted, `ParsedEvents` should become test/materialization-only or a parser debug/export helper, not live terminal feed state.
4. Only then move action unions into true owners.

## Tests And Gates

- From `howl-vt`: `zig build test:unit`, `zig build test:abi`, `zig build check`.
- Preserve parser/event tests, parser behavior tests, action mapping tests, and terminal stream behavior tests.
- Future grep gates: no new `types.zig`, no `manager`/`engine`; `action/vocabulary.zig` must shrink only after owner files own their action vocabulary; live stream must not depend on queued `ParsedEvents` unless explicitly justified.

## Risks / Gaps

- Direct stream must preserve current error rollback semantics.
- DCS reconstruction currently depends on queued `ParsedEvents.appendDcsBody`; direct streaming needs a source-backed owner for DCS accumulation before implementation.
- Charset mapping currently exists in `ParsedEvents`; direct stream must decide whether terminal owns all charset state, matching Ghostty terminal charset behavior.
- `SemanticEvent` may disappear or shrink substantially if Howl follows Ghostty's stream handler pattern; splitting it now risks preserving a fake intermediate abstraction.
