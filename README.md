# Howl

Howl is a small, correct, embeddable native Zig terminal family.

The active projects are:

- `howl-vt`: the embeddable terminal model.
- `howl-headless`: a bounded native PTY host for semantic terminal output.
- `howl-text`: bounded native font loading, shaping, and alpha-mask
  rasterization.
- `howl-host`: a native Wayland host with bounded terminal, layout, and text
  owners.

The root package exports `howl_vt` and `howl_text`. Native hosts and development
proofs remain root workspace operations.

Compile every active component and proof:

```sh
zig build
```

Run every correctness proof:

```sh
zig build test
```
