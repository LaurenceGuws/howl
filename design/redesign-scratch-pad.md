# Redesign Scratch Pad

Owner: workspace root.

Purpose: temporary checkpoint tracker for redesign-scale cleanup.

## Rules

- Use the 4 start questions before each checkpoint.
- Judge acceptable shape by source order only:
  1. Ghostty does it.
  2. Alacritty does it.
  3. TigerBeetle mandates it.
  4. If Howl still has no direct match, invent the smallest possible shape.
- The architect loop stays strict:
  1. review/plan
  2. delegate
  3. review -> accept and commit/push, or reject and return to 1
  4. repeat from 1

## Active Seams

### 1. VT aggregate facade

- Repo owner: `howl-vt`
- Control owner: `src/stream_terminal.zig` and `src/action/route.zig`
- Thread owner: host main thread
- C ABI gate: host must stay on `howl_vt_*`
- Source-order read: Ghostty-shaped first; Alacritty bounded feed shape agrees
- Status: work-clear

### 2. Render queue state machine

- Repo owner: `howl-render`
- Control owner: `src/frame/queue.zig`
- Thread owner: host main thread
- C ABI gate: host must stay on `howl_render_*`
- Source-order read: renderer-owned retained flow is acceptable; novelty must stay minimal
- Status: work-clear

### 3. Host render/present spine

- Repo owner: `howl-linux-host`
- Control owner: `src/main.zig` and `src/terminal/render/frame.zig`
- Thread owner: main/UI thread
- C ABI gate: no direct Zig imports from `howl-vt` or `howl-render`
- Source-order read: Alacritty host/runtime shape first
- Status: work-clear

## Next Review Order

1. VT aggregate facade
2. Render queue state machine
3. Host render/present spine

## Acceptance Gate Per Checkpoint

- owner and boundary still true
- control spine simpler, not wider
- no Zig-module-shaped host bypass
- assertions or bounds tightened where the invariant lives
- docs updated in the same change
- proof run and recorded in report

## Open Edge

- Workspace root still has unrelated untracked `design/zig16-release-notes.txt`.
