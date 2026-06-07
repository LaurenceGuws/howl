# Host Window Contract

Sources read:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `current.txt`
- `project-memory.md`
- `loops/bucket-host-window.txt`
- `reference-index.md`
- `howl-linux-host/src/window_chrome/window.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/app/processor.zig`
- Alacritty window references listed in researcher session `ses_15df6de8cffe2Ks4FkQWXekjWw`

Findings:

- The exact owner noun is `Window`.
- Direct typed consumers are limited to `main.zig` and `app/processor.zig`.

Worker-ready contract:

- Allowed files:
  - `howl-linux-host/src/window_chrome/window.zig`
  - `howl-linux-host/src/main.zig`
  - `howl-linux-host/src/app/processor.zig`
- Required shape:
  - rename `pub const State = struct` to `pub const Window = struct` in `howl-linux-host/src/window_chrome/window.zig`
  - update all method signatures/receivers and constructor return types in `window.zig` from `State` to `Window`
  - update the owner-local inline test local in `window.zig` from `State` to `Window`
  - in `main.zig`, change the module import to lowercase `window` and update type/value references to `window.Window`, `window.quit()`, and `window.initVideo()`
  - in `processor.zig`, change the module import to lowercase `window` and update type/value references from `Window.State` and `Window.getClipboardText` to `window.Window` and `window.getClipboardText`
  - keep file path unchanged
  - keep free functions and behavior unchanged
  - do not add aliases such as `pub const State = Window`
- Non-goals:
  - no edits outside those three files
  - no changes to `host_test_root.zig`
  - no window behavior changes in create/destroy, geometry refresh, title updates, focus, clipboard, cursor, or URL handling
  - no folder rename, `window_chrome` boundary redesign, or display/presentation/renderer ownership movement
- Verification:
- `python utils/hygene/style_scan.py "howl-linux-host/src/window_chrome/window.zig" "howl-linux-host/src/main.zig" "howl-linux-host/src/app/processor.zig"`
- `zig build test && zig build check` in `howl-linux-host`
- grep gate: no `pub const State = struct` in `howl-linux-host/src/window_chrome/window.zig`
- grep gate: no `const Window = @import("window_chrome/window.zig")` in `howl-linux-host/src/main.zig`
- grep gate: no `Window.quit` in `howl-linux-host/src/main.zig`
- grep gate: no `Window.initVideo` in `howl-linux-host/src/main.zig`
- grep gate: no `Window.State` in `howl-linux-host/src/main.zig`
- grep gate: no `Window.Window` in `howl-linux-host/src/main.zig`
- grep gate: no `const Window = @import("../window_chrome/window.zig")` in `howl-linux-host/src/app/processor.zig`
- grep gate: no `Window.getClipboardText` in `howl-linux-host/src/app/processor.zig`
- grep gate: no `Window.State` in `howl-linux-host/src/app/processor.zig`
- grep gate: no `Window.Window` in `howl-linux-host/src/app/processor.zig`
- grep gate: `pub const Window = struct` appears in `howl-linux-host/src/window_chrome/window.zig`
- Stop conditions:
  - stop if any file beyond those three needs edits
  - stop if another direct `Window.State` consumer appears
  - stop if the slice broadens into changing window ownership, SDL policy, display integration, or presentation behavior
  - stop if the worker proposes any noun other than `Window`
