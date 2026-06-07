# VT Stream Terminal Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-vt-stream-terminal.txt`
- `reference-index.md`
- `research/cache-2026-06-02-vt-direct-stream-readiness.md`
- `howl-vt/src/stream_terminal.zig`
- `howl-vt/src/terminal.zig`
- Ghostty stream references listed in researcher session `ses_15de1cd3effecRC3nkMYfntu5w`

Findings:

- `howl-vt/src/stream_terminal.zig:116-137` exports the generic owner `pub const State = struct` and uses that type name locally in `initAlloc` and `deinit`.
- `howl-vt/src/terminal.zig:26,52,67,80,95` contains the only current `stream_terminal.State` typed consumer spellings in the tree.
- Current grep confirms there are no other `stream_terminal.State` matches outside `howl-vt/src/terminal.zig`.
- The exact owner noun is `TerminalStreamState`.

Worker-ready contract:

- Allowed files:
  - `howl-vt/src/stream_terminal.zig`
  - `howl-vt/src/terminal.zig`
- Required shape:
  - rename `pub const State = struct` in `howl-vt/src/stream_terminal.zig` to `pub const TerminalStreamState = struct`
  - rename only the owner-local type spellings tied to that export in `stream_terminal.zig`
  - update all five `stream_terminal.State` spellings in `howl-vt/src/terminal.zig` at lines `26,52,67,80,95` to `stream_terminal.TerminalStreamState`
  - keep the field name `stream_state` unchanged
  - keep `pub const Stream = struct` unchanged
  - keep behavior unchanged and add no compatibility alias
- Non-goals:
  - no rename of `Stream`
  - no rename of `Terminal.stream_state`
  - no parser, route, feed, or apply-flow redesign
  - no movement of parser/DCS/APC/PM ownership out of `stream_terminal.zig`
  - no changes outside the two allowed files
  - no ABI, test-root, or behavior changes
- Verification:
  - `python utils/hygene/style_scan.py "howl-vt/src/stream_terminal.zig" "howl-vt/src/terminal.zig"`
  - `zig build test && zig build check` in `howl-vt`
  - grep gate: no `pub const State = struct` in `howl-vt/src/stream_terminal.zig`
  - grep gate: no `stream_terminal.State` in `howl-vt/src/terminal.zig`
  - grep gate: `pub const TerminalStreamState = struct` appears in `howl-vt/src/stream_terminal.zig`
- Stop conditions:
  - stop if the rename requires touching any file beyond the two allowed files
  - stop if the worker concludes `Stream` must also be renamed for consistency
  - stop if any required behavior change appears during compile/test repair
  - stop if a new direct consumer of `stream_terminal.State` appears in the current tree before editing
  - stop if orchestrator wants a Ghostty-closer handler/stream reshaping rather than a rename-sized slice
