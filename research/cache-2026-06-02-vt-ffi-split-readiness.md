# VT FFI Split Readiness Research Cache - 2026-06-02

Research cache. Research only. No product code edits.

## Sources Read

- TigerBeetle style and architecture.
- `AGENTS.md`, `loop.txt`, `reference-index.md`.
- Existing `research/*.md` via grep only as navigation.
- `howl-vt/src/ffi.zig`.
- `howl-vt/include/howl_vt.h`.
- `howl-vt/src/parser/main.zig`.
- `howl-vt/src/parser/events.zig`.
- `howl-vt/src/action/vocabulary.zig`.
- Related owners: `terminal.zig`, `stream_terminal.zig`, `action/route.zig`, `screen/apply.zig`, `control/mode.zig`, `control/report.zig`, `host/apply.zig`, `kitty/apply.zig`, `howl_vt.zig`, `libhowl_vt.zig`, `build.zig`.
- Ghostty `src/terminal/Parser.zig`, `stream.zig`, `stream_terminal.zig`, `Terminal.zig`, `terminal/c/main.zig`, `terminal/c/terminal.zig`.

## Worker-Ready Slice

Split `howl-vt/src/ffi.zig` into contract-owned FFI files without changing `howl-vt/include/howl_vt.h`, exported symbol names, result layouts, statuses, or behavior.

Allowed files:

- `howl-vt/src/ffi.zig`
- New files under `howl-vt/src/ffi/`
- `howl-vt/src/libhowl_vt.zig` only if Zig export of `ffi.zig` re-export aliases does not compile

Required file shape:

- `src/ffi.zig` becomes a curated C-ABI root only: import contract files, re-export exported function names and ABI structs, and import their tests.
- `src/ffi/status.zig`: `HowlVtCallStatus`.
- `src/ffi/handle.zig`: `HowlVtTerminal`, `VtHandle`, `vtFromHandle`.
- `src/ffi/bytes.zig`: `FfiBytesResult`, byte span helpers, `bytesIn`, `bytesOut`, `copyBytes`.
- `src/ffi/lifecycle.zig`: init/deinit/feed/resize/title/cell-size functions and init option/cursor-style translation.
- `src/ffi/surface.zig`: color/cell/surface/meta structs and surface/meta/hyperlink/ack functions.
- `src/ffi/selection.zig`: selection structs and selection query/mutate/copy functions.
- `src/ffi/host_output.zig`: pending output and clipboard drain/clear functions.
- `src/ffi/runtime.zig`: runtime obligation/progress structs and functions.
- `src/ffi/input.zig`: key/focus/paste/mouse encoding and mouse enum translation.

## Invariants

- No public ABI header edits.
- No exported C symbol rename.
- No behavior change.
- Surface selection overlay behavior remains preserved.
- Existing embedded tests move with their owner or remain reachable through the single `howl_vt.zig` test root.
- `ffi.zig` must not keep behavior helpers after split.

## Verification

- From `howl-vt`: `zig build test:unit`.
- From `howl-vt`: `zig build test:abi`.
- From `howl-vt`: `zig build check`.

## Grep Gates

- `howl-vt/include/howl_vt.h` unchanged.
- `howl-vt/src/ffi.zig` has no `fn ` or `pub fn ` definitions after the split.
- `terminalCopySurface`, `terminalEncodeMouse`, `terminalDrainPendingClipboard`, and `terminalProgressRuntime` exist in `src/ffi/*`, not root `ffi.zig`.
- No new `types.zig`, `utils.zig`, `manager`, `engine`, or compatibility alias files.

## Not Worker-Ready Yet

- Parser event storage/materialization. Need decision whether to keep Howl queued event store or reshape toward direct stream handling.
- Action vocabulary bucket. Needs exact migration plan across xterm, screen, mode, report, host, kitty, and tests.
