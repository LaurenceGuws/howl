# Howl

Howl is a small, correct, embeddable native Zig terminal family.

The active projects are:

- `howl-vt`: the embeddable terminal model.
- `howl-text`: bounded native font loading, shaping, and alpha-mask
  rasterization.
- `howl-pty`: bounded native PTY, child process-group, I/O, resize, wake, and
  cleanup ownership.
- `howl-control`: one live PTY/VT owner with immutable frame publication.
- `howl-frame`: immutable terminal-local visual frames and renderer
  acknowledgement.
- `howl-render`: shared text, glyph-mask cache, and terminal-frame draw
  preparation.
- `howl-window`: the native Wayland host with bounded tabs, panes, input,
  shared text/GLES rendering, and terminal composition.

The root package exports `howl_vt`, `howl_text`, `howl_frame`, `howl_render`,
`howl_pty`, and `howl_control`. Native hosts and development proofs remain root
workspace operations.

Compile every active component and proof:

```sh
zig build
```

Run every correctness proof:

```sh
zig build test
```
