# Howl

Howl is a native Zig terminal family.

The active projects are:

- `howl-vt`: the embeddable terminal model.
- `howl-headless`: a bounded native PTY host for semantic terminal output.

`howl-render` is retained unchanged while its text work is evaluated. It still
targets the retired ABI and is outside the active build.

Initialize the family and run every active package check:

```sh
git submodule update --init --recursive
zig build
```
