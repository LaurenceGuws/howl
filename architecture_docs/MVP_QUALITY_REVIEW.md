# Howl MVP Quality Review

## Purpose

This document records the single-agent review after the first `howl-sdl-host` shell became visibly usable.
It compares current implementation reality against the parent architecture direction and the frozen Zide reference lessons.

## Current Verdict

The Linux host is useful as a live proving ground, but the MVP is not architecturally complete.

Do not treat current `howl-sdl-host` as the final MVP boundary until the remaining issues below are closed.

## What Held Up

| Decision | Review |
| --- | --- |
| `howl-vt-core` as portable terminal engine | Correct. It matches the `libghostty-vt` lesson: the VT package must be a real terminal engine, not parser glue. |
| `howl-session` owns PTY/process lifecycle | Correct direction. Host code should not hand-roll PTY loops. |
| SDL host owns window/input/present | Correct. SDL must remain platform shell work. |
| Plain frame model between surface and renderer | Correct. It keeps renderer backends replaceable. |
| Checked-in defaults/assets | Correct for MVP repeatability. |

## Closed Findings

| Finding | Resolution |
| --- | --- |
| GL draw planning/execution lived in `howl-sdl-host` | Moved draw planning and immediate GL execution to `render/howl-render-gl`; SDL host now calls the renderer module. |
| Host composed session and surface directly | Added `TerminalSurface` in `howl-term-surface`; SDL host now delegates terminal orchestration to the surface module. |
| `SurfaceConfig` carried `?*anyopaque` session placeholder | Removed the opaque session field; session ownership is explicit in `TerminalSurface`. |
| `howl-render-gl` remained scaffold while host had local renderer code | `howl-render-gl` now owns the draw plan and GL execution surface used by the Linux host. |
| Glyph rendering was SDL_ttf-based in host repo | `howl-render-gl` now owns FreeType glyph rasterization, GL texture upload, and text drawing; SDL_ttf was removed from the host. |
| Rectangle rendering used `glBegin`/`glEnd` immediate mode | Replaced with retained CPU vertex batches submitted through GL client arrays. |

## Open Findings

| Finding | Severity | Reason |
| --- | --- | --- |
| `main.zig` still owns too much runtime glue | Medium | Improved, but it still owns text renderer setup and PTY/surface/renderer sequencing in one file. |
| Glyph rendering is renderer-owned but per-glyph texture cached | Medium | SDL ownership is fixed, but the text path still needs atlas batching, shaping, and system font fallback before performance work can be called mature. |
| Renderer uses CPU-retained client arrays, not VBO batches | Medium | Immediate-mode calls are removed, but the renderer still needs GPU buffer ownership and atlas-backed text batching for best-in-class performance. |

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

1. Reduce `main.zig` to SDL lifecycle, input translation, selected surface calls, selected renderer calls, and present.
2. Replace client-array submission with renderer-owned VBO batches.
3. Replace per-glyph texture cache with atlas-backed glyph batches.
4. Add renderer text/atlas tests that prove output planning without requiring an SDL window.

## MVP Completion Criteria

Linux MVP is complete only when:

1. A shell runs visibly and accepts normal text input.
2. SDL host does not import session directly except for explicitly host-owned transport construction.
3. Renderer implementation is not local-only host code.
4. Glyph rendering is renderer-owned and contains no SDL dependency.
5. Build/test/package all pass.
6. Parent dependency rules and child repo docs agree with actual imports.

## Immediate Next Work

The next work is not new feature scope.
It is the remaining MVP architecture correction pass:

- Shrink `howl-sdl-host/src/main.zig` around the stable surface/renderer seams.
- Move GL execution from client arrays to VBO batches and atlas-backed text drawing.
- Re-check Zide text-stack lessons before adding HarfBuzz/fontconfig boundaries.
