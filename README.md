# Howl

Howl is a C ABI embeddable terminal stack.

The product boundary is the ABI: hosts embed PTY, VT, and render libraries through public C headers, while each host owns platform UX, event loops, wake policy, presentation cadence, runtime orchestration, and backend resources.

## Repositories

- `howl-pty`: PTY-backed child transport, lifecycle, resize, input/output, wait/kick, and control signals.
- `howl-vt`: terminal parser/state, visible-surface truth, selection, input encoding, and host-facing protocol consequences.
- `howl-render`: backend-agnostic render contracts, geometry, text shaping, prepared surfaces, and submit/retire state.
- `howl-linux-host`: reference Linux desktop host using SDL/OpenGL.

See `libs.yaml` for the owner tree and `project-memory.md` for timestamped project memory.

## Build

Run the repo-wide gates from the workspace root:

```sh
zig build check
zig build test
```

Package-specific gates can also be run from each subrepo:

```sh
zig build check
zig build test
```

## Boundary

- Hosts depend on `howl-pty`, `howl-vt`, `howl-render`, and vendored host contracts only.
- PTY owns process transport, not terminal semantics.
- VT owns terminal truth, not backend presentation.
- Render owns backend-agnostic render contracts, not host upload or present.
- Hosts own platform integration.

## Status

Howl is a young private product. Public C ABI clarity is prioritized over compatibility shims or preserving stale names.
