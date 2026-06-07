# VT ScreenSet Options Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-vt-screen-set-options.txt`
- `reference-index.md`
- `howl-vt/src/screen_set.zig`
- `howl-vt/src/terminal.zig`
- `howl-vt/src/simulation/protocol.zig`
- `howl-vt/src/terminal_snapshot_test.zig`
- `howl-vt/src/terminal_surface_test.zig`
- `howl-vt/src/terminal_modes_test.zig`
- `howl-vt/src/simulation/scrollback.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/ScreenSet.zig`

Findings:

- `screen_set.Options` is a one-field bag and should be deleted, not renamed.
- `visibleView` should take direct `scrollback_offset: u32`.
- Current direct caller set is fixed and bounded.

Worker-ready contract:

- Allowed files:
  - `howl-vt/src/screen_set.zig`
  - `howl-vt/src/terminal.zig`
  - `howl-vt/src/terminal_snapshot_test.zig`
  - `howl-vt/src/terminal_surface_test.zig`
  - `howl-vt/src/terminal_modes_test.zig`
  - `howl-vt/src/simulation/protocol.zig`
  - `howl-vt/src/simulation/scrollback.zig`
- Required shape:
  - delete `pub const Options = struct { scrollback_offset: u32 = 0 }` from `howl-vt/src/screen_set.zig`
  - change `visibleView` to take direct `scrollback_offset: u32`
  - inside `visibleView`, replace `options.scrollback_offset` with the direct scalar parameter and keep clamping/invariants unchanged
  - keep `surfaceSnapshot(screen_state: *const Set, scrollback_offset: u64)` unchanged and preserve its clamp to `u32` before calling `visibleView`
  - update all current `visibleView` callers from bag literals to direct integer arguments
  - update test helper signatures that currently take `screen_set.Options` to take `scrollback_offset: u32` directly
  - leave `View.scrollback_offset` unchanged
  - no replacement bucket type and no new alias
- Non-goals:
  - do not change `View` fields or semantics
  - do not change `SurfaceSnapshot` shape or behavior
  - do not change scrollback clamping behavior
- do not change any C ABI, FFI, or host-facing terminal API
- the local Zig `ScreenSet.visibleView` signature change is explicitly allowed in this slice
  - do not touch `Terminal.InitOptions`, `simulation/protocol.zig::Options`, or `simulation/scrollback.zig::PreservationOptions`
  - do not redesign `screen_set.Set`
- Verification:
  - `python utils/hygene/style_scan.py "howl-vt/src/screen_set.zig" "howl-vt/src/terminal.zig" "howl-vt/src/terminal_snapshot_test.zig" "howl-vt/src/terminal_surface_test.zig" "howl-vt/src/terminal_modes_test.zig" "howl-vt/src/simulation/protocol.zig" "howl-vt/src/simulation/scrollback.zig"`
  - `zig build test && zig build check` in `howl-vt`
  - grep gate: no `pub const Options = struct` in `howl-vt/src/screen_set.zig`
  - grep gate: no `screen_set.Options|ScreenSet.Options` in the allowed files
  - grep gate: no `screen_set.visibleView(..., .{` bag-literal callsites remain in the allowed VT files
- Stop conditions:
  - stop if re-grep finds any additional `screen_set.visibleView` caller outside the allowed files
- stop if changing `visibleView` requires touching FFI/C ABI files or any host-facing/public ABI surface beyond the local Zig `ScreenSet.visibleView` signature itself
  - stop if the slice grows beyond deleting the one-field input bag and updating its direct callers
  - stop if a second view input parameter appears necessary
