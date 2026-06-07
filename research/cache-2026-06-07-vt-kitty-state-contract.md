# VT Kitty State Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-vt-kitty-state.txt`
- `reference-index.md`
- kitty-state references listed in researcher session `ses_15dd56c02ffe470ByRNLEaLErq`

Findings:

- The exact owner noun is `KittyState`.
- Only direct typed consumer is `howl-vt/src/terminal.zig`.

Worker-ready contract:

- Allowed files:
  - `howl-vt/src/kitty/state.zig`
  - `howl-vt/src/terminal.zig`
- Required shape:
  - in `howl-vt/src/kitty/state.zig`, rename `pub const State = struct` to `pub const KittyState = struct`
  - in `howl-vt/src/kitty/state.zig`, rename the method receivers/signatures from `*State` / `*const State` to `*KittyState` / `*const KittyState` for `deinit`, `activeScreen`, `activeScreenConst`, and `resetTerminalState`
  - in `howl-vt/src/terminal.zig`, change `const KittyState = kitty_state.State;` to `const KittyState = kitty_state.KittyState;`
  - keep the `Terminal.kitty` field name as `kitty`
  - keep `ScreenState`, `GlobalState`, helper free functions, field layout, behavior, allocation/deinit flow, and reset behavior unchanged
- Non-goals:
  - no Kitty protocol behavior changes
  - no split of `kitty/state.zig` into smaller owners
  - no rename of `ScreenState` or `GlobalState`
  - no edits to `kitty/apply.zig`, `input/encode.zig`, or tests unless a direct typed `kitty_state.State` use appears
  - no `Terminal` ownership redesign
- Verification:
  - `python utils/hygene/style_scan.py "howl-vt/src/kitty/state.zig" "howl-vt/src/terminal.zig"`
  - `zig build test && zig build check` in `howl-vt`
  - grep gate: no `pub const State = struct` in `howl-vt/src/kitty/state.zig`
  - grep gate: no `kitty_state.State` in `howl-vt/src/terminal.zig`
  - grep gate: `pub const KittyState = struct` appears in `howl-vt/src/kitty/state.zig`
- Stop conditions:
  - stop if any direct typed consumer beyond `howl-vt/src/terminal.zig` appears
  - stop if review requires a noun other than `KittyState`
  - stop if the rename broadens into moving fields or splitting owners
  - stop if any public ABI, protocol-matrix wording, or host/render consequence changes are requested
