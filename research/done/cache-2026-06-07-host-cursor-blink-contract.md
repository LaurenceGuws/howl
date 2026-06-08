# Host Cursor Blink Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `reference-index.md`
- `research/cache-2026-06-01-terminal-chrome-owner.md`
- `howl-linux-host/src/terminal/cursor_blink.zig`
- `howl-linux-host/src/terminal/context.zig`
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/scheduler.rs`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event.rs`

Findings:

- `howl-linux-host/src/terminal/cursor_blink.zig` is a dedicated leaf owner for blink cadence and visibility planning.
- The generic top-level owner name `State` is real bucket debt under `AGENTS.md` bucket rules.
- The exact smallest source-backed noun is `CursorBlink`, derived from the file owner noun plus Alacritty blink vocabulary.
- Current consumer scope is limited to `howl-linux-host/src/terminal/context.zig`.

Worker-ready contract:

- Allowed files:
  - `howl-linux-host/src/terminal/cursor_blink.zig`
  - `howl-linux-host/src/terminal/context.zig`
- Required shape:
  - rename `pub const State = struct` to `pub const CursorBlink = struct`
  - update method receivers in `cursor_blink.zig` from `State` to `CursorBlink`
  - update the owner-local test local from `State` to `CursorBlink`
  - update `Context.cursor_blink` in `context.zig` from `cursor_blink.State` to `cursor_blink.CursorBlink`
  - keep `Plan`, `interval_ms`, `interval_ns`, `nextDeadline`, and all behavior unchanged
  - keep `Context` cursor-blink methods as delegating composition only
  - do not add aliases like `pub const State = CursorBlink`
- Non-goals:
  - no blink policy changes
  - no timer behavior changes
  - no scheduler extraction
  - no movement of `cursorBlinkShouldAnimate`, `setCursorBlinkVisible`, or render ABI calls out of `context.zig`
  - no edits to `context.zig` beyond the field type rename
  - no edits to `term.zig`, event loop code, config, or tests outside `cursor_blink.zig`
- Verification:
- `python utils/hygene/style_scan.py "howl-linux-host/src/terminal/cursor_blink.zig" "howl-linux-host/src/terminal/context.zig"`
- `zig build test && zig build check` in `howl-linux-host`
- grep gate: no `pub const State = struct` in `howl-linux-host/src/terminal/cursor_blink.zig`
- grep gate: no `cursor_blink.State` in `howl-linux-host/src/terminal/context.zig`
- grep gate: `\bCursorBlink\b` appears exactly 6 times in `howl-linux-host/src/terminal/cursor_blink.zig` (owner definition, 4 method signatures/receivers, 1 owner-local test local)
- grep gate: `cursor_blink.CursorBlink` appears exactly once in `howl-linux-host/src/terminal/context.zig` at the `Context.cursor_blink` field type
- Stop conditions:
  - stop if any consumer outside `context.zig` depends on `cursor_blink.State`
  - stop if the worker needs to rename the file, move methods across owners, or touch timer/event-loop scheduling
  - stop if review asks for a noun other than `CursorBlink` based on a stronger direct reference than the current file-path plus Alacritty blink naming pressure
  - stop if the slice expands into focus-policy, VT cursor-truth, or render-surface behavior changes
