# howl-odin

Experimental polished desktop client in the Howl module family.

The client owns desktop application policy only: windows, tabs, pane layout,
profiles, settings, command palette, keybindings, and OS integration. It must
not duplicate VT, PTY, Session, text shaping, or terminal raster semantics.

The current Linux proof uses Odin + SDL3 + SDL3_ttf. `native/` is a tiny
C-shaped Zig bridge over the existing `howl-client` owner. The bridge exports no
wire layout or client backing structs: Odin receives one bounded visible-text
projection plus scalar metadata and sends semantic input through `howl-client`.
The semantic text surface is intentionally temporary; the accepted Howl render
owners remain the destination for the real terminal renderer.

Current canary:

- native resizable SDL3 window with Windows-familiar tabs, `+`/menu affordance,
  command palette, and Settings surface;
- the `+` action and `Ctrl+T` create additional Home Session views; tabs have
  real selection/close semantics and the dropdown exposes the attach recipe,
  command palette, and Settings actions rather than prototype labels;
- Home tab observes the existing canonical Howl Session at
  `tcp://127.0.0.1:39601` without taking geometry leadership;
- committed text plus named/control keys round-trip through `howl-client`;
- observation and control use independent client connections: a named worker
  blocks on revision-relative observation while the SDL event/render thread
  owns only control delivery; teardown wakes the blocked observer through
  `howl-client`'s duplicate-socket cancellation primitive;
- SDL rendering uses the window-logical coordinate space and lets the renderer
  scale to high-density output, keeping chrome, cursor placement, and converted
  pointer coordinates on one geometry contract;
- profile/session launch policy beyond the current Home attach recipe remains
  deliberately deferred rather than faked.

## Toolchain

This experiment deliberately pins both compilers used by its build:

- Zig follows the repository root `.zigversion`;
- Odin follows `.odinversion` in this module.

## Build

```sh
./howl-odin/build.sh
```

The script runs the native bridge tests, builds the bridge ReleaseSafe, checks
and builds the Odin client, then places the bridge shared object beside the
executable so Odin's `$ORIGIN` runpath resolves it without system installation.
The result is:

```text
howl-odin/zig-out/bin/howl-odin
```
