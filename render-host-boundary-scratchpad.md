# Render/Host Boundary Scratchpad

Owner: workspace root.

Purpose:

- Record the clarified render/host boundary before reshaping `howl-render` or
  `howl-linux-host`.
- Prevent another fake-small `frame` or FFI split that preserves ambiguous ownership.

## Fixed Boundary

- Backend independence is the first priority of the render ABI.
- `howl-render` must never own publication to a backend.
- Hosts own event loops, wake policy, redraw request policy, presentation cadence,
  runtime orchestration, backend resource realization, queue scheduling, and backend
  publication.
- `howl-render` exposes a C ABI state engine: host-owned data and calls in, prepared
  render data and explicit consequences out.
- `howl-render` does not hide a runtime loop, scheduler, presentation queue, swapchain,
  or backend frame lifecycle.

## Reference Pressure

- Alacritty is the primary pressure for host-owned scheduling:
  - terminal state produces renderable content;
  - display/window/app own redraw requests, frame throttling, scheduler, GL surface, and
    presentation;
  - renderer owns drawing/batching only.
- Ghostty only justifies render-owned queues/frames when render owns a renderer thread,
  backend resources, swapchain/in-flight frame state, and presentation mechanics. That
  does not apply to Howl's backend-independent render ABI.
- Kitty also does not justify a broad `frame` owner; its render preparation and execution
  are attached to screen/window/OS-window/graphics owners.

## Consequences

- A broad `howl-render/src/frame` namespace is presumed wrong until each file proves a
  true owner.
- `frame` is not acceptable as an umbrella for VT surface consumption, render preparation,
  scheduling, geometry, prepared-surface lifetime, and submission policy.
- `pipeline` and `queue` policy inside render are suspect. If they encode host cadence or
  presentation scheduling, move that responsibility to the host or expose it as explicit
  ABI state for the host to drive.
- A render-owned prepared output object may exist only if it owns render data lifetime,
  buffers, metrics, or retained caches. It must not imply backend presentation.
- `submit` must not mean publish or present. At most it can mean the host consumed a
  prepared output and render may update retained render-owned state.
- `ffi.zig` should expose C-callable state-engine functions. It should not duplicate the
  public C type contract or hide scheduling behind private queues.

## Host Inspection Goal

- Inspect `howl-linux-host` for ambiguous ownership before proposing changes.
- Look for duplicated runtime owners, hidden scheduling, backend publication mixed with
  terminal/render state, and Zig convenience paths that bypass the product C ABI boundary.
