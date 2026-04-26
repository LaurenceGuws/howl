# Howl MVP Quality Review

## Purpose

This document records the single-agent review after the first `howl-sdl-host` shell became visibly usable.
It compares current implementation reality against the parent architecture direction and the frozen Zide reference lessons.

## Current Verdict

The Linux host is useful as a live proving ground, but the MVP is not architecturally complete.

Do not treat current `howl-sdl-host` as the final MVP boundary until the issues below are closed.

## What Held Up

| Decision | Review |
| --- | --- |
| `howl-vt-core` as portable terminal engine | Correct. It matches the `libghostty-vt` lesson: the VT package must be a real terminal engine, not parser glue. |
| `howl-session` owns PTY/process lifecycle | Correct direction. Host code should not hand-roll PTY loops. |
| SDL host owns window/input/present | Correct. SDL must remain platform shell work. |
| Plain frame model between surface and renderer | Correct. It keeps renderer backends replaceable. |
| Checked-in defaults/assets | Correct for MVP repeatability. |

## What Was Wrong or Incomplete

| Finding | Severity | Reason |
| --- | --- | --- |
| Host still composes session and surface directly | High | Parent rule says host should call surface; surface/session composition should not be duplicated per host. |
| GL draw execution still lives in `howl-sdl-host` | High | Renderer ownership is split: render planning is in `renderer.zig`, but GL execution is still host code. |
| Glyph rendering is SDL_ttf-based in host repo | High | Good enough for visual proof, not best-in-class renderer architecture or performance. Target renderer should own glyph atlas/shaping/raster policy. |
| `howl-term-surface` surface config still uses `?*anyopaque` session | Medium | This is an MVP placeholder shape. It hides coupling instead of modeling it cleanly. |
| `howl-render-gl` remains scaffold while host has local renderer code | Medium | Module map says GL renderer repo owns GL backend implementation. Current implementation lives in host. |
| `main.zig` is still larger than ideal | Low | Improved by extracting ops and text rendering, but event loop, GL execution, and runtime composition remain mixed. |

## Reference Lessons

From Zide freeze:
- Copy ideas, not architecture debt.
- Do not preserve old naming or accidental coupling.
- Avoid terminal runtime APIs that mix host policy with terminal/session state.

From embeddable terminal references:
- VT core should expose terminal semantics cleanly.
- Host layer should own windows, input, lifecycle, and app-level multiplexing.
- Renderer and glyph systems must be reusable across hosts where possible.

## Required Correction Sequence

1. `surface` becomes the canonical embeddable terminal object.
2. `howl-sdl-host` stops owning `Session` directly.
3. `howl-render-gl` receives the renderer implementation currently local to the SDL host.
4. Glyph rendering moves out of host-local SDL_ttf code into renderer-owned text/atlas policy.
5. Host `main.zig` becomes only SDL lifecycle, input translation, selected surface calls, selected renderer calls, and present.

## MVP Completion Criteria

Linux MVP is complete only when:

1. A shell runs visibly and accepts normal text input.
2. SDL host does not import session directly except through an explicitly reviewed temporary bridge.
3. Renderer implementation is not local-only host code.
4. Glyph rendering is renderer-owned or explicitly documented as a temporary proof layer with a removal milestone.
5. Build/test/package all pass.
6. Parent dependency rules and child repo docs agree with actual imports.

## Immediate Next Work

The next work is not new feature scope.
It is an MVP architecture correction pass:

- Move reusable renderer work to `render/howl-render-gl`.
- Promote `howl-term-surface` from frame model holder to the real embeddable terminal surface.
- Reduce `howl-sdl-host` to platform shell responsibilities.
