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

## Current Known Dirty Slice

FairMutex extraction is already implemented but uncommitted in `howl-linux-host`.

Files:

- `src/sync/fair_mutex.zig`
- `src/buckets that must die/bucket4.zig`
- `src/pty/pump.zig`
- `src/buckets that must die/bucekt2_test.zig`

Verified before this artifact was created:

- `zig build check`
- `zig build test:unit`
- `git diff --check`

This slice must be closed before larger I/O machinery cuts proceed.

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

1. Seal dirty FairMutex extraction.
2. Write the complete event/consequence contract in this artifact.
3. Split raw platform event pump from input mutation.
4. Move host input translation to true owners.
5. Split terminal byte admission from host UI pointer handling.
6. Define and extract the term runtime owner.
7. Extract wake handoff owner.
8. Extract terminal surface/widget owner only after termio and input are split.
9. Move link owner out of render.
10. Make resize/layout consequences explicit.
11. Delete bucket directory after imports/tests are gone.
