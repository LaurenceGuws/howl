# Render VT ABI Decoupling Scratchpad

Owner: workspace root.

Purpose: source-backed research for deleting the `howl-render` public dependency on
`howl-vt` public cell/color/selection types before returning to the host `terminal/c.zig`
release-note migration.

## Current Dirty State

The workspace currently contains an unaccepted failed host translate-C experiment:

- root: `current.txt` modified; `howl-linux-host` submodule dirty.
- host modified: `build.zig`, many `src/terminal/*` imports, `src/window/term_texture.zig`, `src/test/host.zig`.
- host deleted: `src/terminal/c.zig`.
- host untracked: `src/sdl.c.h`, `src/howl_pty.c.h`, `src/howl_vt.c.h`, `src/howl_render.c.h`.

Do not build on top of that dirty host attempt until the user or main agent decides whether
to discard it, preserve it as an experiment, or replace it with a new worker slice. The
experiment failed because split translate-C modules made render and VT copies of the same C
types distinct; that exposed the real problem rather than solving it.

## Problem Statement

`howl-linux-host/src/terminal/c.zig` is a broad C import bucket, but deleting it correctly is
blocked by a deeper ABI lie:

- `howl-render/include/howl_render.h` includes `howl_vt.h`.
- `HowlRenderVtSurfaceSlot` exposes `HowlVtSurfaceCell *`.
- `HowlRenderVtSurfaceCommit` embeds `HowlVtCursor`, `HowlVtRenderColorState`, and
  `HowlVtSelection`.

This makes the renderer public C ABI depend on VT-owned terminal state types. It prevents
owner-scoped translate-C modules because `howl_render.h` reuses VT structs as render structs.

## Reference Findings

### Ghostty

Research agent read TigerBeetle first, then Ghostty references:

- `src/renderer.zig`
- `src/renderer/generic.zig`
- `src/terminal/Terminal.zig`
- `src/terminal/Screen.zig`
- `src/terminal/render.zig`
- `src/terminal/c/render.zig`
- `src/terminal/c/cell.zig`
- `include/ghostty/vt/render.h`
- `include/ghostty/vt/screen.h`
- `include/ghostty/vt/terminal.h`

Findings:

- Terminal owns screen, cell, row, color, selection, dirty truth.
- `src/terminal/render.zig` is explicitly terminal-side render-state adaptation, not renderer
  backend ownership.
- Renderer owns backend rendering and consumes `terminal.RenderState` internally.
- Ghostty C-facing render-state APIs live under `ghostty/vt/render.h`, not under a renderer
  backend ABI.
- Ghostty supports a VT-owned render-state/surface ABI that may expose VT types, but does not
  justify `howl-render` backend public ABI owning/importing VT cell/color/selection truth.

### Alacritty

Research agent read TigerBeetle first, then Alacritty references:

- `alacritty_terminal/src/term/cell.rs`
- `alacritty_terminal/src/grid/mod.rs`
- `alacritty_terminal/src/term/mod.rs`
- `alacritty/src/display/content.rs`
- `alacritty/src/renderer/mod.rs`
- `alacritty/src/renderer/text/mod.rs`
- `alacritty/src/renderer/text/gles2.rs`
- `alacritty/src/renderer/text/glsl3.rs`
- `alacritty/src/renderer/rects.rs`

Findings:

- Terminal owns `Cell`, grid, selection truth, cursor truth, and visible terminal content.
- Display/content adapts terminal cells into `RenderableCell`.
- Renderer consumes `RenderableCell`, glyphs, batches, vertices, rectangles, and atlas state.
- Renderer imports some terminal flags internally, but does not expose raw terminal `Cell` as a
  renderer public API.
- Alacritty supports an adapter split: terminal truth -> display/renderable cell -> renderer.

### Kitty

Research agent read TigerBeetle first, then local kitty references:

- `kitty/screen.h`
- `kitty/screen.c`
- `kitty/line.h`
- `kitty/line.c`
- `kitty/line-buf.h`
- `kitty/data-types.h`
- `kitty/state.h`
- `kitty/shaders.c`
- `kitty/fonts.c`
- `kitty/cell_vertex.glsl`

Findings:

- Kitty is a monolithic private C/Python app, not a public ABI model.
- Screen owns dimensions, parser consequences, line buffers, history, cursor, color profile,
  selection, dirty state, and graphics manager.
- Renderer-private code can reach `Screen *`, but GPU upload consumes packed draw buffers
  (`GPUCell`, selection mask bytes, uniform data), not a public renderer ABI importing terminal
  state structs.
- Kitty does not justify Howl renderer public contracts depending on VT cell/color/selection
  types.

## Current Howl Facts

Files read:

- `howl-render/include/howl_render.h`
- `howl-vt/include/howl_vt.h`
- `howl-render/src/vt_surface.zig`
- `howl-render/src/source/vt.zig`
- `howl-render/src/source/cell.zig`
- `howl-render/src/source/slot.zig`

Important facts:

- `howl-render/include/howl_render.h:6` includes `howl_vt.h`.
- `HowlRenderVtCellWriteSpan` uses `HowlVtSurfaceCell *`.
- `HowlRenderVtSurfaceCommit` embeds `HowlVtCursor`, `HowlVtRenderColorState`, and
  `HowlVtSelection`.
- `howl-render/src/source/vt.zig` already defines render-owned extern structs:
  - `SourceRgb`
  - `SourceColor`
  - `SourceColors`
  - `SourceCellFlags`
  - `SourceCellAttrs`
  - `SourceCell`
  - `SourceSelectionPoint`
  - `SourceSelection`
- `howl-render/src/vt_surface.zig` currently asserts `source_vt.SourceCell` layout equals
  `c.HowlVtSurfaceCell` and casts render-owned slots to VT cell pointers.
- The render side already has most of the render-owned source machinery. The bad piece is the
  public ABI naming/dependency and layout-identical coupling to VT C types.

## Verdict

The user is right: `howl-render/include/howl_render.h` depending on `howl_vt.h` must go before
the host `terminal/c.zig` release-note migration can be correct.

No strong reference supports render backend public ABI importing VT-owned cell/color/selection
types. The source-backed shape is:

- VT owns terminal state truth.
- A boundary adapts VT truth into render source/draw data.
- Render owns render source ABI structs, retained prepare state, shaping, caching, prepared
  surfaces, and submit contracts.

## Proposed Worker Slice

Name: `Split Render Source ABI From VT Types`.

Scope:

- `howl-render/include/howl_render.h`
- `howl-render/src/vt_surface.zig`
- `howl-render/src/source/vt.zig`
- `howl-render/src/source/slot.zig` only if naming demands it
- render ABI tests under `howl-render/src/test/*`
- host call site `howl-linux-host/src/terminal/vt/surface.zig` after root render ABI changes

Required shape:

- Remove `#include "howl_vt.h"` from `howl-render/include/howl_render.h`.
- Add render-owned public ABI structs matching current render source data, with render names, for example:
  - `HowlRenderSourceRgb`
  - `HowlRenderSourceColor`
  - `HowlRenderSourceCellFlags`
  - `HowlRenderSourceCellAttrs`
  - `HowlRenderSourceCell`
  - `HowlRenderSourceColors`
  - `HowlRenderSourceSelectionPos`
  - `HowlRenderSourceSelection`
  - `HowlRenderSourceCursor`
- Replace `HowlRenderVtCellWriteSpan` pointer element with `HowlRenderSourceCell`.
- Replace `HowlRenderVtSurfaceCommit` embedded VT types with render-owned source cursor,
  colors, and selection types.
- Keep behavior equivalent for now: host VT adapter copies/converts VT ABI values into
  render source ABI values before commit.
- Remove layout assertions against VT C types in `howl-render/src/vt_surface.zig`.
- Replace them with render ABI layout assertions against `source_vt` owner structs.
- Rename C ABI names away from `Vt` only if the worker slice is explicitly promoted that way.
  Otherwise keep function names stable for the first decoupling slice and only change payload
  types. No compatibility aliases.

Non-goals:

- Do not migrate host `terminal/c.zig` in this slice.
- Do not change render prepared surface semantics.
- Do not change VT public structs in `howl-vt/include/howl_vt.h` unless a later slice moves a
  VT-owned render-state ABI there.
- Do not introduce combined translate-C modules as a workaround.
- Do not add compatibility aliases.

Required tests/gates:

- `howl-render/include/howl_render.h` has no `howl_vt.h` include.
- `howl-render/include/howl_render.h` has no `HowlVt` references.
- `howl-render/src` has no layout assertions against `c.HowlVt*` types.
- Render C ABI layout tests for every new `HowlRenderSource*` struct.
- Existing render tests still pass.
- Host builds against converted source structs after host call site update.
- Root and submodule verification:
  - `zig build check`
  - `zig build test`
  - `git diff --check`

## Follow-Up Slice

After render/VT ABI coupling is removed:

- Revisit `howl-linux-host/src/terminal/c.zig`.
- Use Zig 0.16 `b.addTranslateC` modules with owner-scoped headers/import names.
- SDL/OpenGL can be separate from Howl ABI modules.
- Howl render translate-C no longer needs VT headers merely to parse `howl_render.h`.
