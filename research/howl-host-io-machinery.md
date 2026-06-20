# Howl Host I/O Machinery Scoped Index

Owner: host I/O machinery scoping.

Status:

- First research pass: rejected by `review-2026-06-20-host-io-machinery-01`.
- Current task: build the elephant definition with the user before additional code cuts.
- This is a scoped index, not a strict sprint plan or worker-ready slice queue.

## Current Rejection Summary

Reviewer rejected the first pass because:

- Dirty FairMutex extraction was treated as passive context instead of a slice that must be sealed or explicitly rejected.
- The plan used vague `typed facts` language without exact owners, names, queues, bounds, drain order, or consequences.
- Proposed owners like `terminal/surface` and `termio/termio` risked preserving bucket ideology under new names.
- The plan did not fully model key/text, mouse/pointer, window/focus/resize, wake, clipboard, PTY child bytes/status, VT damage/metadata/replies, render frames, and present actions through one ideology.
- Active sprint/root state was stale and had to be reconciled before more work.

## Required Scoped Index Output

The scoped index must define:

- Exact named owners.
- Exact fact and consequence names.
- Queue/buffer bounds.
- Drain order.
- Conversion points.
- Dependency direction.
- Slice order.
- Required assertions.
- Required tests.
- Grep gates that prove old shapes are gone.

The scoped index must not use placeholder names like `typed facts` as a substitute for ownership.

## Closed FairMutex Slice

FairMutex extraction is implemented, verified, committed, and clean in `howl-linux-host`.

Files:

- `src/sync/fair_mutex.zig`
- `src/buckets that must die/bucket4.zig`
- `src/pty/pump.zig`
- `src/buckets that must die/bucekt2_test.zig`

Commit:

- `4d999a3 Extract host fair mutex owner`

Verified before commit:

- `zig build check`
- `zig build test:unit`
- `git diff --check`

This slice is closed. Larger I/O machinery cuts may proceed only after the next owner move is source-backed and exact.

## Reference Anchors To Re-Prove In Corrected Research

Alacritty:

- `utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/sync.rs`
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/input/mod.rs`

Ghostty:

- `utils/dev_references/terminals/ghostty/src/Surface.zig`
- `utils/dev_references/terminals/ghostty/src/termio/Termio.zig`
- `utils/dev_references/terminals/ghostty/src/termio/stream_handler.zig`
- `utils/dev_references/terminals/ghostty/src/termio/mailbox.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/Terminal.zig`

Current Howl hot paths:

- `howl-linux-host/src/buckets that must die/*`
- `howl-linux-host/src/input/input.zig`
- `howl-linux-host/src/events/event_loop.zig`
- `howl-linux-host/src/events/event.zig`
- `howl-linux-host/src/pty/*`
- `howl-linux-host/src/vt/*`
- `howl-linux-host/src/render/links.zig`
- `howl-linux-host/src/render/surface_layout.zig`
- `howl-linux-host/src/window/*`
- `howl-linux-host/src/tab_bar/tab_slots.zig`
- `howl-linux-host/src/host_test_root.zig`

## Scoped Contract Skeleton

The user and agent will fill this table with exact symbols and owners:

| Class | Source owner | Fact name | Conversion owner | Consequence name | Consumer owner | Bounds/tests |
|---|---|---|---|---|---|---|
| key/text | TBD | TBD | TBD | TBD | TBD | TBD |
| mouse/pointer | TBD | TBD | TBD | TBD | TBD | TBD |
| window/focus/resize | TBD | TBD | TBD | TBD | TBD | TBD |
| wake/timer/frame | TBD | TBD | TBD | TBD | TBD | TBD |
| clipboard | TBD | TBD | TBD | TBD | TBD | TBD |
| PTY child bytes | TBD | TBD | TBD | TBD | TBD | TBD |
| PTY child status | TBD | TBD | TBD | TBD | TBD | TBD |
| VT damage/title/metadata/replies | TBD | TBD | TBD | TBD | TBD | TBD |
| render frame/present | TBD | TBD | TBD | TBD | TBD | TBD |

## Initial Bite Order Sketch

This is not a worker-ready slice queue. It is the starting bite order to refine with the user.

1. Write the complete event/consequence contract in this artifact.
2. Split raw platform event pump from input mutation.
3. Move host input translation to true owners.
4. Split terminal byte admission from host UI pointer handling.
5. Define and extract the term runtime owner.
6. Extract wake handoff owner.
7. Extract terminal surface/widget owner only after termio and input are split.
8. Move link owner out of render.
9. Make resize/layout consequences explicit.
10. Delete bucket directory after imports/tests are gone.

## First Multiplexing Shape Attempt

This is a first attempt, not a prediction of the final architecture. The user and agent will refine it together before product-code moves.

Plain goal:

- One host instance can own many terminal instances.
- One host instance can own many window instances.
- A window can present one or more terminal instances through tabs and splits.
- A terminal instance must not own or imply an OS window.
- A terminal instance can move between windows without changing PTY, VT, or session identity.
- Dragging a tab out should create or attach a new window view over the same terminal instance, not recreate the terminal.
- The current tab bar owner is provisional until proved correct.
- Splits and tabs are layout/view relationships over terminal instances, not terminal lifetime owners.

Directory rule:

- Do not create a nested `host/` directory inside `howl-linux-host/src`.
- `howl-linux-host/src` is already the host source boundary.
- Follow Ghostty-style neat `src` ownership pressure: top-level directories should name real owners directly.

Reference pressure:

- Alacritty is useful for disciplined host/runtime/render pragmatism, but its per-window terminal coupling is wrong for Howl multiplexing.
- Kitty is useful as a multiplexing/child-monitor/screen stand-in, but not naming law.
- `Boss` is rejected as a symbol model; names must say what the owner is.
- Ghostty is strongest for VT/termio/portability seams, not automatically for host/window/app architecture.
- Foot is valuable for directness and honest nouns, but must be pressured by Ghostty portability and Howl's embeddable ABI boundary.

Likely boundaries:

- Terminal instance: PTY session identity, VT handle, terminal-private runtime state, and terminal-content retained state that survives movement between windows.
- Window instance: OS window/backend resources, platform presentation cadence, and input source plumbing.
- View/layout/tab/split: binding between terminal instances and rectangular presentation slots inside a window.
- Source-root owner for terminal lifetime: a direct `src` owner to be named before moving the aggregate bucket. Do not use `boss` or a framework/business noun.

Likely terminal-instance-owned facts from `bucket4.zig`:

- PTY launch facts.
- PTY lifecycle state.
- PTY session handle.
- VT handle.
- VT scratch/title/consequence cache.
- Retained render state only if it is terminal-content retained state, not backend/window resource state.
- Synchronization only if required for sharing a terminal instance across host/window/pump threads.

Likely not terminal-instance-owned facts:

- OS window pointers or resources.
- Tab bar slot ownership.
- Split layout ownership.
- GL/EGL/backend resources.
- Presentation pacing.
- Platform seat state.
- Focus source policy. Terminal may cache protocol focus consequence state, but window/layout decide focus source routing.

Open naming problem:

- Define the stable identity/lifetime owner before moving `bucket4.zig` as a whole.
- Avoid `boss`, `manager`, `engine`, `controller`, generic `context`, and nested `host` directories.
- Candidate vocabulary must be tested against multiplexing: terminal instance ID/slot ownership, window view attachment, tab/split layout, and terminal movement between windows.

Immediate collaboration step:

- Do not move `Term` yet.
- First accepted piece completed: PTY launch/lifecycle/state moved to `src/pty/session.zig` in `howl-linux-host` commit `5aea76f Move PTY state to session owner`.
- Next piece must be chosen together from the remaining quarantined facts: VT title cache, VT input/output scratch, scrollback/focus consequence state, render-state handle, or terminal instance identity.
