# Host Selection Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-host-selection.txt`
- `reference-index.md`
- host/selection references listed in researcher session `ses_15dd56c1cffeq3haqIb6IbVaQe`

Findings:

- The exact owner noun is `Selection`.
- Only direct typed consumer is `howl-linux-host/src/terminal/context.zig`.

Worker-ready contract:

- Allowed files:
  - `howl-linux-host/src/terminal/selection.zig`
  - `howl-linux-host/src/terminal/context.zig`
- Required shape:
  - rename `pub const State = struct` to `pub const Selection = struct` in `howl-linux-host/src/terminal/selection.zig`
  - update local type references in `selection.zig` from `State` to `Selection` only where required by the type rename
  - update `Context.selection` in `howl-linux-host/src/terminal/context.zig` from `terminal_selection.State` to `terminal_selection.Selection`
  - keep the field name `selection` unchanged
  - keep `MouseHandlingOutcome`, `SelectionCell`, `handleMouse`, `eventCell`, and the VT selection calls unchanged
- Non-goals:
  - no rename to `HostSelection`, `SelectionGesture`, `MouseSelection`, or any other noun
  - no rename of the `selection` field in `Context`
  - no behavior change in press/move/release handling
  - no movement of selection fields out of `Context`
  - no edits to `terminal/input.zig`, `terminal/links.zig`, `terminal/scrollbar.zig`, `howl-vt`, or C ABI files
  - no new tests in this slice
- Verification:
  - `python utils/hygene/style_scan.py "howl-linux-host/src/terminal/selection.zig" "howl-linux-host/src/terminal/context.zig"`
  - `zig build test && zig build check` in `howl-linux-host`
  - grep gate: no `pub const State = struct` in `howl-linux-host/src/terminal/selection.zig`
  - grep gate: no `terminal_selection.State` in `howl-linux-host/src/terminal/context.zig`
- Stop conditions:
  - stop if any file beyond `selection.zig` and `context.zig` needs editing
  - stop if the rename requires choosing a broader noun than `Selection`
  - stop if the slice broadens into moving gesture state, changing input routing, or changing VT selection consequences
  - stop if build/test failures come from pre-existing host selection ownership debt rather than the direct rename
  - stop if any public ABI consequence changes
