# Howl

Howl is a small, correct, embeddable native Zig terminal family.

The active projects are:

- `howl-vt`: the embeddable terminal model.
- `howl-pty`: bounded native PTY, child process-group, I/O, resize, wake, and
  cleanup ownership.
- `howl-control`: optional ID-addressable PTY and VT composition.
- `howl-render`: selectable terminal projection, native text, and generated
  terminal-glyph capabilities.
- `howl-host`: the first-party single-terminal Wayland and GLES executable.

Each `howl-*` directory is an independent Zig package and owns its module,
dependencies, proofs, and executable steps. The repository root is only the
`howl_workspace` development curator: it exports no product modules or
artifacts.

Compile every active component and validate the workspace:

```sh
zig build
```

Run every correctness proof:

```sh
zig build test
```
