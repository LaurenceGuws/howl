# Howl

Howl is a native Zig terminal family.

The active projects are:

- `howl-vt`: the embeddable terminal model.
- `howl-headless`: a bounded native PTY host for semantic terminal output.
- `howl-text`: bounded native font loading, shaping, and alpha-mask
  rasterization.

Initialize the family and run every active package check:

```sh
git submodule update --init --recursive
zig build
```
