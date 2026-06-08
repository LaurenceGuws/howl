# Howl

Howl is a C ABI embeddable terminal stack.

The product boundary is the ABI: hosts embed PTY, VT, and render libraries through public C headers, while each host owns platform UX, event loops, wake policy, presentation cadence, runtime orchestration, and backend resources.

## Repositories

- `howl-pty`: PTY-backed child transport, lifecycle, resize, input/output, wait/kick, and control signals.
- `howl-vt`: terminal parser/state, visible-surface truth, selection, input encoding, and host-facing protocol consequences.
- `howl-render`: backend-agnostic render contracts, geometry, text shaping, prepared surfaces, and submit/retire state.
- `howl-linux-host`: reference Linux desktop host using SDL/OpenGL.

