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
- Hosts depend on `howl-term` as the umbrella package/root, but runtime behavior must come from the
  owner-true lower modules instead of a `howl-term` wrapper runtime.
- OS thread loops live in domain-local `thread.zig` owners with `threadMain`-style entrypoints. `loop.zig` is not an owner name; `job` is reserved for queued async work payloads.

## Repository Responsibilities

| Repo | Owns | Does Not Own | Key Owners |
|---|---|---|---|
| `howl-session` | PTY transport contract, PTY variants, child session process I/O, session status snapshots, resize/control signal delivery | VT parsing, rendering, host windows, terminal runtime policy | `src/session.zig`, `src/pty.zig`, `src/pty/pty_platform.zig`, `src/pty/pty_unix.zig`, `src/pty/pty_android.zig` |
| `howl-vt-core` | Terminal protocol state, grid state, parser, input encoding vocabulary, snapshots, selection model | PTY lifecycle, render backend, host UI, process runtime | `src/terminal.zig`, `src/grid.zig`, `src/parser.zig`, `src/input.zig`, `src/interpret.zig`, `src/snapshot.zig`, `src/selection.zig` |
| `howl-render-core` | Render contracts, geometry, backend selection, backend runtime, text shaping/raster pipeline, surface frame data | VT/session lifecycle, host event loops, terminal runtime policy | `src/render_core.zig`, `src/renderer.zig`, `src/backend/*/backend.zig`, `src/text_contract.zig`, `src/text_pipeline.zig`, `src/frame_input.zig`, `src/surface.zig` |
| `howl-term` | Compile-time package composition, umbrella export curation, and cross-host equality enforcement over owner-true lower-module surfaces | Any runtime lifecycle, PTY runtime, VT runtime, render runtime, host event loops, scheduling cadence, platform wake policy, render backend internals, host platform UX | `src/howl_term.zig`, `src/term_namespace.zig`, compile-time assertion files, umbrella headers only when they add no new runtime semantics |
| `howl-linux-host` | SDL/Linux UX, window/presentation, input event polling, tab/chrome UI, host config, terminal widget composition | Terminal core semantics, lower module internals, Android runtime proof | `src/main.zig`, `src/terminal/thread.zig`, `src/terminal/*.zig`, `src/input/*.zig`, `src/window/*.zig`, `src/config/*.zig` |

## Current Open Edges

- `howl-term` still has implementation residue that must be deleted until it becomes compile-time-only for real.
- `howl-render-core` needs a broader owner-true C ABI than its current geometry-only surface.
- Android runtime proof remains open and explicit: `host_runtime_surface_skip=missing_android_runtime`.

## Movement Rule

When moving behavior, move it toward the smallest owner that owns the state or variant being touched. Do not move behavior upward into public roots or namespace wrappers for convenience.

## `howl-term` Surface Rule

`howl-term` remains the umbrella package name, but its root and namespace wrapper must stay
behavior-free.

Allowed `howl-term` responsibilities:
- curate exports
- root-gate umbrella C symbols if they are pure pass-through surfaces
- install compile-time equality assertions over lower-module status values, widths, and shared
  vocabulary

Disallowed `howl-term` responsibilities:
- owning runtime state
- owning runtime threads
- wrapping lower-module runtime behavior into a broad convenience API

Boundary rule for later work:
- delete behavior from `howl-term` instead of moving it sideways into new wrapper files
- move runtime behavior to the smallest lower module that truly owns it
- do not move behavior upward into `src/howl_term.zig` or `src/term_namespace.zig`
