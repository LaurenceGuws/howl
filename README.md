# Howl

Howl is a small, correct, embeddable native Zig terminal family.

The active projects are:

- `howl-vt`: the embeddable terminal model.
- `howl-text`: bounded native font loading, shaping, and alpha-mask
  rasterization.
- `howl-pty`: bounded native PTY, child process-group, I/O, resize, wake, and
  cleanup ownership.
- `howl-control`: one live composition of `howl-pty` and `howl-vt`.
- `howl-frame`: immutable terminal-local visual frames and renderer
  acknowledgement.
- `howl-host`: a native Wayland host with bounded terminal, layout, and text
  owners.

The root package exports `howl_vt`, `howl_text`, `howl_frame`, `howl_pty`, and
`howl_control`. Native hosts and development proofs remain root workspace
operations.

Compile every active component and proof:

```sh
zig build
```

Run every correctness proof:

```sh
zig build test
```
