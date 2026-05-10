# Module Owner Responsibilities

This records the third Ghostty-style layer for Howl modules: after the public root and namespace wrapper, behavior belongs to small owner files with explicit responsibilities.

## Ghostty Pattern

Ghostty separates the layers this way:

- Public export root: `src/lib_vt.zig` imports one namespace wrapper, curates exported names, and root-gates C symbols.
- Namespace wrapper: `src/terminal/main.zig` imports owner files and re-exports selected modules/types. It is an index, not a behavior owner.
- Owner files: `Terminal.zig`, `Screen.zig`, `ScreenSet.zig`, `PageList.zig`, `Parser.zig`, `stream.zig`, `page.zig`, and protocol folders own state, parsing, storage, and mutation.
- C ABI files: `terminal/c/*.zig` wrap owners and are exposed by `terminal.c_api` only when `options.c_abi` is enabled.

Howl follows the same outcome with flatter wrapper names in `src`: public roots import one `*_namespace.zig`, wrappers aggregate owners, and FFI is build-option gated.

## Layer Rules

- Public roots curate exports and register C symbols only.
- Namespace wrappers aggregate owner APIs only. They should not contain `pub fn` behavior.
- Owner files own state, mutation, variant selection, protocol translation, rendering, and runtime loops.
- FFI files translate C ABI to owner calls. They must not import public roots.
- Hosts depend on `howl-term`, not lower modules or lower-module private owner paths.

## Repository Responsibilities

| Repo | Owns | Does Not Own | Key Owners |
|---|---|---|---|
| `howl-session` | PTY transport contract, PTY variants, child session process I/O, session status snapshots, resize/control signal delivery | VT parsing, rendering, host windows, terminal runtime policy | `src/session.zig`, `src/pty.zig`, `src/pty/pty_platform.zig`, `src/pty/pty_unix.zig`, `src/pty/pty_android.zig` |
| `howl-vt-core` | Terminal protocol state, grid state, parser, input encoding vocabulary, snapshots, selection model | PTY lifecycle, render backend, host UI, process runtime | `src/terminal.zig`, `src/grid.zig`, `src/parser.zig`, `src/input.zig`, `src/interpret.zig`, `src/snapshot.zig`, `src/selection.zig` |
| `howl-render-core` | Render contracts, geometry, backend selection, backend runtime, text shaping/raster pipeline, surface frame data | VT/session lifecycle, host event loops, terminal runtime policy | `src/render_core.zig`, `src/renderer.zig`, `src/backend/*/backend.zig`, `src/text_contract.zig`, `src/text_pipeline.zig`, `src/frame_input.zig`, `src/surface.zig` |
| `howl-term` | Terminal runtime orchestration across session, VT, and render; frame preparation; input publication; runtime wake/snapshot semantics; terminal C ABI | PTY variants, render backend internals, host platform UX | `src/terminal.zig`, `src/runtime/*.zig`, `src/render/*.zig`, `src/input/*.zig`, `src/wake/*.zig`, `src/config/*.zig`, `src/ffi.zig` |
| `howl-linux-host` | SDL/Linux UX, window/presentation, input event polling, tab/chrome UI, host config, terminal widget composition | Terminal core semantics, lower module internals, Android runtime proof | `src/main.zig`, `src/terminal/*.zig`, `src/input/*.zig`, `src/window/*.zig`, `src/config/*.zig` |

## Current Open Edges

- `howl-term/src/terminal.zig` is intentionally the broad runtime owner for now. Split only when a sub-owner boundary is already clear.
- `howl-term/src/ffi.zig` is broad because it owns the full terminal C ABI. Split only by ABI domain without changing exported symbols.
- `howl-render-core/src/render_core.zig` is both owner surface and type catalog. This is acceptable until a smaller render contract owner emerges.
- Android runtime proof remains open and explicit: `host_runtime_surface_skip=missing_android_runtime`.

## Movement Rule

When moving behavior, move it toward the smallest owner that owns the state or variant being touched. Do not move behavior upward into public roots or namespace wrappers for convenience.

## Term Embedding Surface

`howl-term` is the end-user embedding package, so its broad public owner must become a stable method table over mature internal owners instead of accumulating behavior itself.

Current internal target shape:

- `terminal.zig`: owns the `HowlTerm` state container, public method names, and compatibility aliases.
- `runtime/lifecycle.zig`: construction, PTY startup, worker thread lifecycle, deinit.
- `runtime/state.zig`: metrics, counters, title/status/surface/scroll state queries.
- `input/input.zig`: bytes, keys, paste, mouse, focus, control signals, and clipboard effects.
- `render/frame.zig`: host frame queue, prepare/render-ready flow, render wake publication.
- `render/render.zig`: direct snapshot prepare/submit/render compatibility paths.
- `render/geometry.zig`: frame geometry synchronization.
- `render/viewport.zig`: scrollback, selection, hyperlinks, and visible/rendered text queries.
- `wake/wake.zig`: snapshot condition waits, signaling, and waiter shutdown.
- `config/fonts.zig`: font size and font path mutation.
- `ffi.zig`: C ABI catalog for `howl_term_*` functions.
- `c_api/constants.zig`: C ABI input constant discovery.
- `c_api/input.zig`: C ABI input publication and input value conversion.
- `c_api/font.zig`: C ABI font configuration and C string conversion.
- `c_api/*.zig`: future domain implementations used by the C ABI catalog.

The ABI rule is strict: moving implementation below `ffi.zig` must not change exported symbol names, numeric return codes, extern struct field order, or `FfiPrepareMetrics.term_us`.
