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
- Accepted checkpoint: remove repo-local `vtHandler` terminal forwarder
- Closed by: `howl-vt` `851306b` `vt: remove handler forwarder`
- Accepted checkpoint: inline stream-turn `Handler` wrapper
- Closed by: `howl-vt` `074abf1` `vt: inline stream turn handler`
- Accepted checkpoint: collapse title feed-turn signal to bool
- Closed by: `howl-vt` `600a450` `vt: collapse title feed turn signal`
- Accepted checkpoint: let terminal own feed finalization
- Closed by: `howl-vt` `33c4609` `vt: let terminal own feed finalization`
- Status: four narrowing checkpoints closed

### 2. Render queue state machine

- Repo owner: `howl-render`
- Control owner: `src/frame/queue.zig`
- Thread owner: host main thread
- C ABI gate: host must stay on `howl_render_*`
- Source-order read: renderer-owned retained flow is acceptable; novelty must stay minimal
- Accepted checkpoint: queue owns prepare-consume handshake
- Closed by: `howl-render` `b7af7a8` `render: let queue own prepare consume`
- Accepted checkpoint: stage publish-slot ABI cells at the FFI seam
- Closed by: `howl-render` `b07eb24` `render: stage publish slot abi cells`
- Accepted checkpoint: remove stale prepare wrapper
- Closed by: `howl-render` `694cad6` `render: remove stale prepare wrapper`
- Accepted checkpoint: let owner drive prepare handle
- Closed by: `howl-render` `106de9c` `render: let owner drive prepare handle`
- Accepted checkpoint: let queue own slot intake
- Closed by: `howl-render` `7d0a837` `render: let queue own slot intake`
- Status: five narrowing checkpoints closed

### 3. Host render/present spine

- Repo owner: `howl-linux-host`
- Control owner: `src/main.zig` and `src/terminal/render/frame.zig`
- Thread owner: main/UI thread
- C ABI gate: no direct Zig imports from `howl-vt` or `howl-render`
- Source-order read: Alacritty host/runtime shape first
- Accepted checkpoint: `frame.zig` owns one bounded pre-present render turn
- Closed by: `howl-linux-host` `38f0147` `host: let frame own render turn`
- Accepted checkpoint: `frame.zig` owns active-tab turn interest query
- Closed by: `howl-linux-host` `ee32728` `host: let frame own turn interest`
- Accepted checkpoint: `frame.zig` owns post-present seam entry
- Closed by: `howl-linux-host` `dbff1fe` `host: let frame finish present`
- Accepted checkpoint: make host present cadence explicit
- Closed by: `howl-linux-host` `617bbdc` `host: make present cadence explicit`
- Status: four narrowing checkpoints closed

## Next Review Order

1. Return to render queue state machine
2. Return to host render/present spine
3. Return to VT aggregate facade

## Acceptance Gate Per Checkpoint

- owner and boundary still true
- control spine simpler, not wider
- no Zig-module-shaped host bypass
- assertions or bounds tightened where the invariant lives
- docs updated in the same change
- proof run and recorded in report

## Open Edge

- Workspace root still has unrelated untracked `design/zig16-release-notes.txt`.
- `howl-vt` `zig build fuzz:build` is failing on clean `main` due a pre-existing fuzz error-set mismatch in
  `src/fuzz/protocol.zig`.
- direct `zig test src/ffi.zig` remains blocked in this environment by Zig/libc linker issues unrelated
  to the accepted VT checkpoint.
