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
- OS thread loops live in domain-local `thread.zig` owners with `threadMain`-style entrypoints. `loop.zig` is not an owner name; `job` is reserved for queued async work payloads.

## Repository Responsibilities

| Repo | Owns | Does Not Own | Key Owners |
|---|---|---|---|
| `howl-session` | PTY transport contract, PTY variants, child session process I/O, session status snapshots, resize/control signal delivery | VT parsing, rendering, host windows, terminal runtime policy | `src/session.zig`, `src/pty.zig`, `src/pty/pty_platform.zig`, `src/pty/pty_unix.zig`, `src/pty/pty_android.zig` |
| `howl-vt-core` | Terminal protocol state, grid state, parser, input encoding vocabulary, snapshots, selection model | PTY lifecycle, render backend, host UI, process runtime | `src/terminal.zig`, `src/grid.zig`, `src/parser.zig`, `src/input.zig`, `src/interpret.zig`, `src/snapshot.zig`, `src/selection.zig` |
| `howl-render-core` | Render contracts, geometry, backend selection, backend runtime, text shaping/raster pipeline, surface frame data | VT/session lifecycle, host event loops, terminal runtime policy | `src/render_core.zig`, `src/renderer.zig`, `src/backend/*/backend.zig`, `src/text_contract.zig`, `src/text_pipeline.zig`, `src/frame_input.zig`, `src/surface.zig` |
| `howl-term` | Terminal embedding contract, `HowlTerm` state and lifecycle rules, host input publication, snapshot and frame-preparation contract, Zig facade, terminal C ABI, and the current terminal-state implementation path that lives behind that contract | Host event loops, scheduling cadence, platform wake policy, PTY variants, render backend internals, host platform UX | `src/howl_term.zig`, `src/term_namespace.zig`, `src/terminal.zig`, `src/runtime/contract.zig`, `src/runtime/*.zig`, `src/render/*.zig`, `src/input/*.zig`, `src/wake/*.zig`, `src/config/*.zig`, `src/ffi.zig`, `src/c_api/*.zig` |
| `howl-linux-host` | SDL/Linux UX, window/presentation, input event polling, tab/chrome UI, host config, terminal widget composition | Terminal core semantics, lower module internals, Android runtime proof | `src/main.zig`, `src/terminal/thread.zig`, `src/terminal/*.zig`, `src/input/*.zig`, `src/window/*.zig`, `src/config/*.zig` |

## Current Open Edges

- `howl-term/src/terminal.zig` is still the current broad owner for `HowlTerm` state and methods. This is an implementation fact, not permission for roots or wrappers to take behavior.
- `howl-term/src/ffi.zig` is still broad because it owns the flat terminal C ABI catalog. Split only by ABI domain without changing exported symbols.
- `howl-term/src/runtime/*` still carries the current stateful terminal path, but the default execution contract is now host-driven through explicit progress calls rather than a library-owned thread.
- `howl-render-core/src/render_core.zig` is both owner surface and type catalog. This is acceptable until a smaller render contract owner emerges.
- Android runtime proof remains open and explicit: `host_runtime_surface_skip=missing_android_runtime`.

## Movement Rule

When moving behavior, move it toward the smallest owner that owns the state or variant being touched. Do not move behavior upward into public roots or namespace wrappers for convenience.

## Term Embedding Surface

`howl-term` is the embedder-facing package. The root and namespace wrapper stay behavior-free. The broad owner beneath them may be large today, but its role is explicit and bounded: it owns `HowlTerm` state and delegates behavior to owner files below it.

Current `howl-term` file roles:

- `src/howl_term.zig`: public root; curates exports and C symbols only.
- `src/term_namespace.zig`: namespace wrapper; indexes owner surfaces only.
- `src/terminal.zig`: current broad owner for `HowlTerm` state and public methods.
- `src/runtime/contract.zig`: shared contract types used by owner files and the C ABI.
- `src/ffi.zig`: `howl_term_*` symbol catalog and handle conversion only.

Current owner map:

- `terminal.zig`: owns the `HowlTerm` state container, public method names, and compatibility aliases.
- `runtime/lifecycle.zig`: construction, PTY startup, canonical lifecycle start/stop, deinit.
- `runtime/io_tick.zig`: bounded host-driven transport progress and bounded VT apply progress.
- `runtime/terminal_reply.zig`: VT-generated reply drain into session outbound input.
- `runtime/query.zig`: locked metrics, counters, title/status, surface, and scroll readouts.
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
- `c_api/viewport.zig`: C ABI scrollback, selection, link, text query, and clipboard buffer contracts.
- `c_api/metrics.zig`: C ABI metric conversion and renderer diagnostic readouts.
- `c_api/surface.zig`: C ABI surface, lifecycle, title, and sequence readouts.
- `c_api/*.zig`: future domain implementations used by the C ABI catalog.

Boundary rule for later work:
- move behavior downward from `terminal.zig` or `ffi.zig` into smaller owners when the state boundary is clear
- do not move behavior upward into `src/howl_term.zig` or `src/term_namespace.zig`

The ABI rule is strict: moving implementation below `ffi.zig` must not change exported symbol names, numeric return codes, extern struct field order, or `FfiPrepareMetrics.term_us`.
