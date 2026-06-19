# Howl Render Surface Layout Present Research

Status: active planning.

Orchestrator session id: `orch-2026-06-19-render-surface-layout-present-01`.
Researcher session id: open.
Reviewer session id: open.

## User Direction

- Start the sprint for the `surface`/`scene`/`geometry`/`grid` naming and ownership problem.
- Do not freeze APIs or cross-repo contracts merely because they exist.
- Linux Wayland is the first host scope, with KDE Wayland-only and Hyprland as the practical target environments.
- X11 may be kept in mind conceptually, but it must not drive implementation now.
- Keep SDL for the parts we currently use: windowing, input, text input, clipboard, event handling, and convenience surfaces.
- First priority is deeper control of the GPU present surface, especially Alacritty-style Wayland EGL damaged present; minimal diff is second.
- The old host GLFW seam and Kitty's GLFW usage are evidence to inspect, not a directive to resurrect GLFW.

## Required Research Output

- Sources read in order.
- Exact current-source files and line references for each current `surface`, `scene`, `geometry`, and `grid` owner.
- Exact Alacritty anchors for `Grid`, `RenderableContent`, `SizeInfo`, display damage, renderer draw, and Wayland EGL damaged present.
- Exact SDL anchors for EGL display/surface/proc exposure and current Wayland swap behavior.
- Exact Kitty/GLFW anchors for the old alternative framework and whether it exposes damaged present.
- Owner-role map for current Howl and the proposed reference-backed shape.
- Explicit slice plan across `howl-render`, `howl-linux-host`, root docs/accountability, and any C ABI/header changes required.
- Required assertions, tests, and grep gates.
- Risks, proof gaps, and stop conditions.
- Readiness judgment.

## Initial Anchor Map

Reference anchors already established and still need formal line-cited expansion:

- Alacritty terminal grid: `utils/dev_references/terminals/alacritty/alacritty_terminal/src/grid/mod.rs`.
- Alacritty visible content: `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs` and `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`.
- Alacritty display size/layout: `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`.
- Alacritty display damage: `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs`.
- Alacritty renderer draw and present: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs` and `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`.
- SDL EGL docs: `utils/dev_references/sdlwiki_md/SDL3/SDL_EGL_GetCurrentDisplay.md`, `SDL_EGL_GetWindowSurface.md`, `SDL_EGL_GetProcAddress.md`, and `SDL_GL_SwapWindow.md`.
- SDL Wayland EGL swap source: `utils/dev_references/backends/sdl/src/video/wayland/SDL_waylandopengles.c`.
- Old Howl backend seam commits: `howl-linux-host 2ac7580` and `b3f821e`.
- Kitty GLFW/EGL source: `utils/dev_references/terminals/kitty/glfw/egl_context.c`, `egl_context.h`, `wl_window.c`, and `glfw.py`.

Current Howl anchors requiring full inventory:

- `howl-render/include/howl_render.h`.
- `howl-render/src/geometry.zig`.
- `howl-render/src/scene.zig`.
- `howl-render/src/grid/scene.zig`.
- `howl-render/src/grid/damage.zig`.
- `howl-render/src/grid/rects.zig`.
- `howl-render/src/surface/*.zig`.
- `howl-render/src/text/surface.zig`.
- `howl-linux-host/src/display/*.zig`.
- `howl-linux-host/src/terminal/render_retained.zig`.
- `howl-linux-host/src/terminal/surface.zig`.

## Provisional Owner Model To Prove Or Reject

- VT owns terminal grid/cells/dirty spans/render-state truth.
- Render layout owns size/layout facts: render pixels, terminal/grid pixels, cell pixels, derived columns/rows, and epochs.
- Render prepare owns visible cells to prepared text, raster plan, and draw primitives.
- Render ABI owns a bounded render packet: damage, resource creates/uploads, commands, retires, and tokens.
- Host display/present owns SDL window, GL resources, EGL present damage, frame pacing, and swap/present cadence.

## Planning Constraints

- No implementation until the full slice plan is reviewed and accepted.
- No X11 implementation slice.
- No API preservation by default.
- No bucket owners named `scene`, `geometry`, or `grid` may survive unless the research proves they are owner-true against references.
- Any retained Howl-only invention must record why Alacritty, Ghostty, Kitty, SDL, and official docs do not fit.

## Open Proof Questions

- Which current Howl `surface` symbols are ABI render packets, which are host presentation surfaces, and which are stale/misnamed prepared text owners?
- Should `geometry.zig` become `layout`/`size`, and where should `GridSize` live if grid is VT-owned?
- Should `scene.zig` disappear as a public/core noun in favor of prepared draw primitives, raster plan, or render commands?
- Can a minimal SDL-retained EGL damaged-present path safely bypass `SDL_GL_SwapWindow` on Wayland while preserving SDL event/frame assumptions?
- What tests prove damage rect shaping, EGL fallback, and unchanged full-swap behavior without requiring a live KDE/Hyprland compositor in CI?

## Initial Scan Seed

This is not the completed inventory. It records the first grep pass so the researcher starts from current-source facts rather than memory.

Commands run:

- `grep` equivalent over `howl-render/src` for `surface|Surface|scene|Scene|geometry|Geometry|grid|Grid`.
- `grep` equivalent over `howl-render/include` for the same terms.
- `grep` equivalent over `howl-linux-host/src` for the same terms plus `EGL|egl|SwapWindow|swap`.
- `grep` equivalent over `utils/dev_references` for Alacritty, SDL, Kitty/GLFW damaged-present anchors.

Current-source seed facts:

- `howl-render/src/geometry.zig` contains `Geometry`, `GeometryLayout`, `GeometryResponse`, `PrepareLayout`, `SurfaceLayout`, `GridSize`, and tests named around surface geometry/grid derivation.
- `howl-render/src/grid/scene.zig` contains renderable cell, metrics, glyph group, draw primitive, raster request, and `TextScene` shapes; the path/name is suspect because it is not a terminal grid owner.
- `howl-render/src/scene.zig` builds owned/borrowed `TextScene` draw lists and retained scratch; this overlaps with prepared text surface and render command packet terminology.
- `howl-render/src/surface/*.zig` contains ABI packet realization, resource stores, prepared/submitted surface owners, compositor/emitter/preparer code, and stale dormant imports previously identified for future cleanup.
- `howl-render/include/howl_render.h` exposes `HowlRenderGridSize` in layout/result, render packet, and prepare input surfaces.
- `howl-linux-host/src/display/display.zig` currently owns SDL GL context creation and `SDL_GL_SwapWindow`; no EGL damage path exists.
- `howl-linux-host/src/display/render_surface*.zig` consumes `HowlRenderSurface` as host GL resource/command upload input.
- `howl-linux-host/src/terminal/render_retained.zig` stores and publishes `HowlRenderSurface` packets and fills `surface.render_px`, `surface.cell_px`, `surface.grid`, damage, commands, creates/uploads/retires.

Reference seed facts:

- Alacritty anchors found for `SizeInfo`, `RenderableContent`, `DamageTracker`, `LineDamageBounds`, renderer draw methods, and `surface.swap_buffers_with_damage(context, &damage)` under Wayland EGL.
- SDL docs/source anchors found for `SDL_EGL_GetCurrentDisplay`, `SDL_EGL_GetWindowSurface`, `SDL_EGL_GetProcAddress`, and `SDL_GL_SwapWindow`.
- SDL Wayland `Wayland_GLES_SwapWindow` uses plain `eglSwapBuffers` in `utils/dev_references/backends/sdl/src/video/wayland/SDL_waylandopengles.c`.
- SDL headers expose `eglSwapBuffersWithDamageKHR` and `eglSwapBuffersWithDamageEXT` declarations through `SDL3/SDL_egl.h`.
- Kitty's vendored GLFW normal EGL swap path uses plain `eglSwapBuffers` in `utils/dev_references/terminals/kitty/glfw/egl_context.c`; the old Howl GLFW seam is useful history, not a damaged-present solution by itself.

## Readiness

Not ready for coding. Researcher must complete the source-backed inventory and ordered slice plan, then reviewer must accept it.
