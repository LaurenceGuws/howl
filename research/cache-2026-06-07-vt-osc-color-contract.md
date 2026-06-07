# VT OSC Color Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `reference-index.md`
- `research/2026-05-30-hygiene-audit/vt-host-consequence-capacity.md`
- `research/2026-05-30-hygiene-audit/researcher-b.md`
- `howl-vt/src/control/osc_color.zig`
- `howl-vt/src/host/state.zig`
- `howl-vt/src/kitty/color.zig`
- `howl-vt/src/kitty/state.zig`
- `howl-vt/src/terminal.zig`
- `howl-vt/protocol_matrix.md`
- `utils/dev_references/terminals/ghostty/src/terminal/color.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/kitty/color.zig`
- `utils/dev_references/terminals/ghostty/src/termio/stream_handler.zig`

Findings:

- `howl-vt/src/control/osc_color.zig` owns the retained terminal color snapshot, not parser scratch.
- `howl-vt/src/host/state.zig` and `howl-vt/src/kitty/color.zig` are the only required typed consumers for a narrow rename.
- The smallest exact source-backed noun is `TerminalColorState`.

Worker-ready contract:

- Allowed files:
  - `howl-vt/src/control/osc_color.zig`
  - `howl-vt/src/host/state.zig`
  - `howl-vt/src/kitty/color.zig`
- Required shape:
  - rename `pub const State = struct` in `howl-vt/src/control/osc_color.zig` to `pub const TerminalColorState = struct`
  - update all local signatures and helpers in `osc_color.zig` from `State` to `TerminalColorState`
  - update `howl-vt/src/host/state.zig` field and accessor types from `OscColorNs.State` to `OscColorNs.TerminalColorState`
  - update `howl-vt/src/kitty/color.zig` alias from `pub const State = OscColor.State` to `pub const State = OscColor.TerminalColorState`
  - keep every field, default, function name, control-sequence behavior, storage layout, and call flow unchanged
  - do not rename `terminalColorState()`
- Non-goals:
  - no OSC color behavior changes
  - no field reshaping of `TerminalColorState`
  - no split into Ghostty-style `DynamicPalette`, `DynamicRGB`, or nested `Colors`
  - no edits to `howl-vt/src/host/state.zig::State` beyond the typed color field/use rename required above
  - no Kitty protocol behavior changes, stack-depth changes, FFI/render ABI changes, or test rewrites unless compile errors require them
  - no broader control/report redesign
- Verification:
  - `python utils/hygene/style_scan.py "howl-vt/src/control/osc_color.zig" "howl-vt/src/host/state.zig" "howl-vt/src/kitty/color.zig"`
  - `zig build test && zig build check` in `howl-vt`
  - grep gate: no `pub const State = struct` in `howl-vt/src/control/osc_color.zig`
  - grep gate: no `OscColorNs.State` in `howl-vt/src/host/state.zig`
  - grep gate: no `OscColor.State` in `howl-vt/src/kitty/color.zig`
- Stop conditions:
  - stop if any typed consumer beyond those three files appears
  - stop if review insists on `Colors` instead of `TerminalColorState`
  - stop if the rename forces FFI, render, or protocol-matrix/API wording changes
  - stop if the change broadens into splitting palette/dynamic/special owners
