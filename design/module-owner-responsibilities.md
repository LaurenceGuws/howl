# Module Owner Responsibilities

This file records the current owner table for Howl.

It is not a migration note. It is the boundary reference for deciding where behavior belongs.

## Layer Rules

- Public roots curate exports only.
- Namespace wrappers aggregate owners only.
- Owner files own state, mutation, and runtime policy.
- FFI files translate contracts only.
- Hosts depend on lower owners directly; they do not recreate an umbrella runtime layer.

## Repository Owner Table

| Repo | Owns | Does Not Own | Key Owners |
|---|---|---|---|
| `howl-pty` | PTY transport contract, PTY variants, child I/O, pending outbound input, resize delivery, control signals, transport lifecycle | VT parsing, render scheduling, host windows, host event loops | `src/session.zig`, `src/pty.zig`, `src/pty/pty_platform.zig`, `src/pty/pty_unix.zig`, `src/pty/pty_android.zig` |
| `howl-vt` | Parser state, terminal state, grid mutation, selection, snapshots, host-facing protocol consequences, input encoding | PTY ownership, render backend state, windowing, presentation cadence | `src/terminal.zig`, `src/grid.zig`, `src/parser.zig`, `src/input.zig`, `src/interpret.zig`, `src/snapshot.zig`, `src/selection.zig` |
| `howl-render` | Render contracts, geometry policy, retained publication state, prepare/submit scheduling, renderer variants, text shaping, backend-neutral frame data | PTY lifecycle, VT state ownership, host event loops, host wake policy | `src/render.zig`, `src/renderer.zig`, `src/frame_queue.zig`, `src/frame_pipeline.zig`, `src/text_contract.zig`, `src/text_pipeline.zig`, `src/surface.zig` |
| `howl-linux-host` | SDL/Linux UX, main-thread event loop, wake policy, window/presentation, tabs/chrome, terminal widget composition, runtime orchestration | Terminal semantics, PTY internals, render internals, Android proof | `src/main.zig`, `src/input/*.zig`, `src/window/*.zig`, `src/terminal/*.zig`, `src/config/*.zig` |
| `howl-android-host` | Android UX/runtime ownership, Android proof, platform wake and presentation policy | Linux/SDL UX, terminal semantics, lower-module internals | Android host owners and proof docs |

## Boundary Rules

### `howl-pty`

- Session owns transport state.
- Hosts may queue input or ask for progress.
- Hosts do not own PTY error policy.

### `howl-vt`

- VT terminal owns terminal meaning.
- Hosts and session do not interpret protocol privately.
- Renderers consume VT consequences through stable surfaces only.

### `howl-render`

- render owns publication, prepare, submit, and retained-frame rules.
- Hosts decide when to wake, poll, and present.
- VT does not own render scheduling policy.

### Hosts

- Hosts own the control spine.
- Hosts poll or wait for platform events.
- Hosts decide bounded work per turn.
- Hosts render and present the latest accepted surface.

## Movement Rule

When moving behavior, move it toward the smallest owner that already owns the state and invariant.

Do not move behavior:

- upward into public roots
- sideways into convenience wrappers
- outward into hosts when a lower module already owns the invariant

## Work Clarity Gate

If a change does not fit this table cleanly, stop and mark `work-not-clear`.
