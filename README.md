# Howl

Howl is a small, correct, embeddable native Zig terminal family.

The active projects are:

- `howl-vt`: the embeddable terminal model.
- `howl-pty`: bounded native PTY, child process-group, one-shot nonblocking I/O,
  resize, observation, and cleanup ownership.
- `howl-render`: selectable terminal projection, native text, and generated
  terminal-glyph capabilities.
- `howl-host`: the first-party Wayland, Vulkan, DMA-BUF, and explicit-sync
  foundation.

Each `howl-*` directory is an independent Zig package and owns its module,
dependencies, proofs, and executable steps. The repository root is only the
`howl_workspace` development curator: it exports no product modules or
artifacts.

Resolve and verify the tracked compiler pin:

```sh
version=$(cat .zigversion); mkdir -p .zig; ln -sfn "$HOME/.local/share/zigup/$version/files/zig" .zig/zig; test "$(./.zig/zig version)" = "$version"
```

Compile every active component and validate the workspace:

```sh
./.zig/zig build
```

Run every correctness proof:

```sh
./.zig/zig build test
```

Child-local commands use `../.zig/zig`.
