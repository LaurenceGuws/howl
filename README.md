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

Each `howl-*` directory is an independent Zig package and owns its module,
dependencies, proofs, and executable steps. The repository root is only the
`howl_workspace` development curator: it exports no product modules or
artifacts. `consumer-vt` proves isolated use of the standalone VT package.

Compile every active component and validate the workspace:

```sh
zig build
```

Run every correctness proof:

```sh
zig build test
```
