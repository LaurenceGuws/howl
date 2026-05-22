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

## Present Focus

### 1. Host runtime aggregate

- Repo owner: `howl-linux-host`
- Control owner today: `src/terminal/runtime/runtime.zig`
- Thread owner: main/UI thread with a wake-only background thread
- C ABI gate: host still stays on `howl_pty_*`, `howl_vt_*`, and `howl_render_*`
- Source-order read: this is now the strongest stale debt against Alacritty-first host shape and TigerBeetle ownership sharpness
- Accepted checkpoint: move per-tab runtime lifetime into `main.zig`
- Closed by: `howl-linux-host` `5dbc565` `host: move tab runtime into main`
- Accepted checkpoint: inline tab startup spine
- Closed by: `howl-linux-host` `e54b127` `host: inline tab startup spine`
- Accepted checkpoint: inline tab shutdown spine
- Closed by: `howl-linux-host` `fb28784` `host: inline tab shutdown spine`
- Accepted checkpoint: inline term construction spine
- Closed by: `howl-linux-host` `27d9c30` `host: inline term construction spine`
- Accepted checkpoint: make panel borrow tab term
- Closed by: `howl-linux-host` `8283ebc` `host: make panel borrow tab term`
- Accepted checkpoint: delete runtime umbrella
- Closed by: `howl-linux-host` `badf8a4` `host: delete runtime umbrella`
- Status: core smell largely reduced; reassess remaining host debt

### 2. Render queue phase protocol

- Repo owner: `howl-render`
- Control owner today: `src/frame/queue.zig`
- Thread owner: host main thread
- C ABI gate: render still stays on `howl_render_*`
- Source-order read: remaining queue/phase shape is partly stale debt and partly `work-not-clear`
- Status: review before next bite

### 3. VT stream parsed-event queue

- Repo owner: `howl-vt`
- Control owner today: `src/stream_terminal.zig`
- Thread owner: host main thread
- C ABI gate: host still stays on `howl_vt_*`
- Source-order read: still stale debt against Ghostty-first VT-core shape, but work-clear
- Status: ready when host/render are not the tighter seam

## Last Closed Checkpoints

- `howl-linux-host` `badf8a4` `host: delete runtime umbrella`
- `howl-linux-host` `8283ebc` `host: make panel borrow tab term`
- `howl-linux-host` `27d9c30` `host: inline term construction spine`
- `howl-linux-host` `fb28784` `host: inline tab shutdown spine`
- `howl-linux-host` `e54b127` `host: inline tab startup spine`
- `howl-linux-host` `5dbc565` `host: move tab runtime into main`
- `howl-linux-host` `617bbdc` `host: make present cadence explicit`
- `howl-render` `7d0a837` `render: let queue own slot intake`
- `howl-vt` `33c4609` `vt: let terminal own feed finalization`

## Acceptance Gate Per Checkpoint

- owner and boundary still true
- control spine simpler, not wider
- no Zig-module-shaped host bypass
- assertions or bounds tightened where the invariant lives
- docs updated in the same change
- proof run and recorded in report

## Open Edge

- Workspace root still has unrelated untracked `design/zig16-release-notes.txt`.
- `howl-linux-host` short-lived child smoke `zig build run -- --duration-ms 1000 --command 'printf ok'` fails on clean
  `main` with `HostTabFailed` after child exit; this is pre-existing host dead-child policy, not a regression from
  `27d9c30`.
- `howl-vt` `zig build fuzz:build` is failing on clean `main` due a pre-existing fuzz error-set mismatch in
  `src/fuzz/protocol.zig`.
- direct `zig test src/ffi.zig` remains blocked in this environment by Zig/libc linker issues unrelated
  to the accepted VT checkpoint.
