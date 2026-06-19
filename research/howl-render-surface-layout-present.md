# Howl Render Surface Layout Present Research

Status: accepted planning package. Reviewer blockers from `review-2026-06-19-render-surface-layout-present-01` are resolved; product code is authorized only through the exact promoted slice in `sprints/current.txt`.

Orchestrator session id: `orch-2026-06-19-render-surface-layout-present-01`.
Researcher session id: `research-2026-06-19-render-surface-layout-present-01`.
Reviewer session id: `review-2026-06-19-render-surface-layout-present-02` accepted the corrected package.
Planning/root commit receipt: open. Child render commit receipt: `howl-render` `5383bf6 Rename render layout and draw owners`; archival remains blocked until the root receipt is closed.

## Sources Read In Order

1. `loop/flow.md` lines 3-49 and 105-151.
2. `loop/orcestrator.md` lines 29-59.
3. `loop/researcher.md` lines 35-89.
4. `loop/reviewer.md` lines 30-60.
5. `loop/coder.md` lines 29-63.
6. `sprints/current.txt` lines 8-78.
7. `loops/howl-render-surface-layout-present-loop.txt` lines 1-44.
8. Prior `research/howl-render-surface-layout-present.md` lines 1-122, used only as active seed and replaced by this package.
9. `reference-index.md` lines 19-36, 60-69, 148-214, and 215-254.
10. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md` lines 90-104, 109-140, 151-183, 271-352, and 443-454.
11. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md` lines 189-222, 281-327, and 408-423.
12. Current Howl source under `howl-render/include/howl_render.h`, `howl-render/src/geometry.zig`, `howl-render/src/scene.zig`, `howl-render/src/grid/*.zig`, `howl-render/src/text/direct_normal.zig`, `howl-render/src/text/surface.zig`, `howl-render/src/surface/*.zig`, `howl-linux-host/src/display/*.zig`, `howl-linux-host/src/terminal/render_retained.zig`, and `howl-linux-host/src/terminal/surface.zig`.
13. Alacritty reference anchors under `utils/dev_references/terminals/alacritty/alacritty_terminal/src/grid/mod.rs`, `alacritty_terminal/src/term/mod.rs`, `alacritty/src/display/content.rs`, `alacritty/src/display/mod.rs`, `alacritty/src/display/damage.rs`, `alacritty/src/display/window.rs`, `alacritty/src/renderer/mod.rs`, and `alacritty/src/window_context.rs`.
14. SDL docs/source under `utils/dev_references/sdlwiki_md/SDL3/SDL_EGL_GetCurrentDisplay.md`, `SDL_EGL_GetWindowSurface.md`, `SDL_EGL_GetProcAddress.md`, `SDL_GL_SwapWindow.md`, `utils/dev_references/backends/sdl/src/video/SDL_video.c`, `utils/dev_references/backends/sdl/src/video/wayland/SDL_waylandopengles.c`, `utils/dev_references/backends/sdl/include/SDL3/SDL_egl.h`, and EGL extension headers under `utils/dev_references/rendering/egl_registry/api/EGL/eglext.h`. Official docs fetched for Slice 4 sharpening: `https://wiki.libsdl.org/SDL3/SDL_EGL_GetCurrentDisplay`, `https://wiki.libsdl.org/SDL3/SDL_EGL_GetWindowSurface`, `https://wiki.libsdl.org/SDL3/SDL_EGL_GetProcAddress`, `https://wiki.libsdl.org/SDL3/SDL_GL_SwapWindow`, `https://registry.khronos.org/EGL/extensions/KHR/EGL_KHR_swap_buffers_with_damage.txt`, and `https://registry.khronos.org/EGL/extensions/EXT/EGL_EXT_swap_buffers_with_damage.txt`.
15. Kitty/GLFW references under `utils/dev_references/terminals/kitty/glfw/egl_context.c`, `egl_context.h`, `context.c`, and `wl_window.c`.
16. Old Howl nested `howl-linux-host` commits `2ac7580` and `b3f821e`, inspected by `git -C howl-linux-host show --stat`; these are historical navigation/evidence only.
17. Correction pass reread `loops/howl-render-surface-layout-present-loop.txt` line 46 and current source for exact ABI, VT dirty column, host binding, and SDL swap facts: `howl-render/include/howl_render.h` lines 261-334, `howl-render/src/libhowl_render.zig` lines 73-99, `howl-vt/src/screen_set.zig` lines 185-199, `howl-vt/src/render_state.zig` dirty-copy hits, `howl-vt/src/ffi/render_state.zig` lines 17-47, `howl-linux-host/build.zig` lines 97-114 and 157-163, and `howl-linux-host/src/display/display.zig` lines 7-55 and 114-142.

## Reviewer Correction Notes

- Rejection source: `loops/howl-render-surface-layout-present-loop.txt` line 46 rejected the first package because the ABI packet name was unresolved, slices lacked exact allowed files/names/tests, and SDL/EGL damaged-present risk was left to coder-time proof.
- ABI packet name is now fixed: `HowlRenderSurface` must become `HowlRenderSurfaceFrame`. Rationale: the packet is one bounded render frame carrying token, damage, resource creates/uploads/retires, and draw commands; `Frame` matches Alacritty frame damage/present language while `SurfaceFrame` preserves the render-surface product context without claiming an EGL/window surface. This is the only accepted packet noun for Slice 2 unless a reviewer rejects this corrected package.
- Host texture/resource handle name is now fixed: `HowlRenderHostSurface` must become `HowlRenderHostTexture`. Rationale: current host code realizes packets into GL textures in `display/render_surface.zig`; it is not an EGL/window surface.
- Layout/size replacement names are fixed for Slice 1: `howl-render/src/geometry.zig` becomes `howl-render/src/layout.zig`; `Geometry` becomes `RenderLayout`; `GeometryLayout` becomes `RenderLayoutInput`; `GeometryResponse` becomes `RenderLayoutResponse`; `PrepareLayout` becomes `PreparedLayout`; `SurfacePixels` becomes `DrawablePixels`; `SurfaceLayout` becomes `CellGridLayout`; `SurfaceGeometryError` becomes `RenderLayoutError`; `deriveGridForSurface` becomes `deriveCellGridForLayout`; `deriveGridSize` becomes `deriveCellGridSize`.
- Prepared draw owner names are fixed for Slice 1: `howl-render/src/scene.zig` becomes `howl-render/src/text/draw_list.zig`; `grid/scene.zig` becomes `howl-render/src/text/draw_primitives.zig`; `grid/damage.zig` becomes `howl-render/src/text/damage.zig`; `grid/rects.zig` becomes `howl-render/src/text/rect_primitives.zig`. `OwnedTextScene` becomes `OwnedTextDrawList`; `BorrowedTextScene` becomes `BorrowedTextDrawList`; `RetainedScratch` becomes `RetainedDrawScratch`; `BuildOptions` becomes `DrawListOptions`; `SceneAssembly` becomes `DrawListAssembly`; `TextScene` becomes `TextDrawList`; `GridMetrics` becomes `CellGridMetrics`.
- SDL/EGL proof is now its own first display slice before damaged-present implementation. It may add only binding/proof code and fake-C tests. If direct EGL damaged swap would bypass required SDL Wayland behavior that Howl cannot honestly re-enter, permanent plain SDL swap is rejected as the product answer; the next direction is explicit host-present ownership change.
- VT dirty column precision is no longer an open proof gap. Current VT already stores/copies `dirty_cols_start`/`dirty_cols_end` (`howl-vt/src/screen_set.zig` lines 185-199 and grep hits in `howl-vt/src/screen/dirty.zig`/`screen.zig`/`resize.zig`), but the public row-data ABI exposes only row dirty/cells/selection/highlights (`howl-vt/include/howl_vt.h` lines 80-87). Slice 3 must add explicit row dirty-column ABI fields before render can consume partial columns; it must not invent render-side full-row damage as a substitute.

## Current Source Facts

### C ABI And Render Packet

- `howl-render/include/howl_render.h` defines bounded render packet capacities directly in the ABI: damage, uploads, commands, glyphs, upload bytes, atlas pages, resources, creates, retires, and host acks are capped at lines 13-26. This is the correct ABI style pressure: packet bounds are explicit.
- The C ABI has `HowlRenderGridSize` at lines 71-74 and uses it in layout/result and render packet structs at lines 123-126, 261-273, and 305-320. The name `grid` currently crosses from VT-sized terminal layout into render packet shape.
- The render packet is named `HowlRenderSurface` at lines 261-273. It carries `render_px`, `cell_px`, `grid`, `damage`, `creates`, `uploads`, `commands`, and `retires`. This is not a host present surface; it is a bounded render command/resource packet.
- `HowlRenderHostSurface` at lines 288-292 is a host resource handle with texture width/height. This is a different owner from `HowlRenderSurface`, even though both use the word surface.
- `HowlRenderGeometryResponse` at lines 275-286 and `HowlRenderTextPrepare` at lines 305-320 carry render/grid/cell pixel facts and geometry epoch. Geometry currently means layout/size synchronization rather than free geometry math.

### `geometry.zig`

- `howl-render/src/geometry.zig` defines `CellSize`, `PixelSize`, and `GridSize` at lines 2-15, `SurfacePixels` at lines 17-38, `GeometryLayout`, `GeometryResponse`, `PrepareLayout`, and `SurfaceLayout` at lines 40-63, and mutable `Geometry` with epoch at lines 65-107.
- `Geometry.sync` increments `geometry_epoch` and stores render/grid/cell pixels at lines 71-91. The owner is layout state, not geometric algorithms.
- `deriveGridSize` and `deriveGridForSurface` at lines 114-127 derive terminal rows/columns from grid pixels and cell pixels; tests at lines 129-149 call this “surface geometry”. This should be renamed toward layout/size because Alacritty calls the equivalent owner `SizeInfo`, not geometry.

### `scene.zig`

- `howl-render/src/scene.zig` imports `grid/scene.zig`, `grid/damage.zig`, and `grid/rects.zig` as `render`, `scene_damage`, and `scene_rects` at lines 2-4, then re-exports `TextScene` at line 10. The file name is broad and the imports prove it is not the sole scene owner.
- `OwnedTextScene` and `BorrowedTextScene` at lines 28-67 own prepared draw-list memory lifetimes, not a terminal scene. `RetainedScratch` at lines 69-109 owns retained draw-list scratch.
- `buildSceneWithOptions`, `buildSceneWithAtlasCacheOptions`, and `buildBorrowedSceneWithAtlasCacheOptions` at lines 111-164 assemble text draw lists from cells, glyph groups, damage, metrics, and cursor. This is prepared text draw-list assembly.
- `DrawCapacities` at lines 198-207 stores `usize` capacities and `SceneAssembly` at lines 209-264 is a bucket-like mutable aggregator. It is currently useful but named too vaguely for TigerBeetle owner truth.
- `SceneAssembly.toOwnedScene` and `toBorrowedScene` publish draw spans at lines 266-310. The plan must preserve this lifecycle but rename the owner toward `text/prepare_scene` or `text/draw_list` rather than a global `scene` noun.
- Generic-ish debt: this file has `usize` capacity fields at lines 198-207 and `count32`/`count16` generic helpers at lines 611-616. These are migration targets because capacities and counts should be explicit draw-count/cell-count values where they cross owner boundaries.

### `grid/scene.zig`

- `howl-render/src/grid/scene.zig` defines render text metrics and draw types, not a terminal grid owner: `CellMetrics` lines 58-63, `GridMetrics` lines 65-68, renderable cells lines 92-111, glyph groups lines 168-176, sprite/background/clear/cursor/decoration draw shapes lines 190-239, raster request lines 258-269, and `TextScene` lines 271-280.
- The path `grid/scene.zig` is wrong against Alacritty source order. Alacritty’s grid owner stores terminal cells and scrollback; Howl’s file stores prepared render model and draw primitives.
- Tests at lines 329-361 verify deterministic defaults and draw span facts, which should move with the renamed prepared-text draw owner.

### `grid/damage.zig`

- `howl-render/src/grid/damage.zig` models dirty rows/columns: `DamageInput` lines 4-9, `NormalizedDamage` lines 11-16, `DirtyRowSpan` lines 18-31, normalization lines 55-68, and row/span checks lines 76-124.
- This is close to Alacritty’s line-damage model but lives under render `grid`, not VT. For this sprint it can stay as render-side damage import shape only if renamed/typed as prepared text damage and explicitly fed from VT dirty rows.
- Generic-ish debt: `count16` and `count32` at lines 126-134 are generic helpers. They should become explicit `row_count_u16`/`item_count_u32` helpers or owner-local asserts where used.

### `grid/rects.zig`

- `howl-render/src/grid/rects.zig` converts renderable cells, damage, cursor, and decoration facts into rect/draw primitives. Public count/append functions are at lines 71-118, 130-169, 254-364, 461-505, and cursor/color helpers at lines 659-817.
- The file is not a grid owner. It is rect primitive preparation for text rendering.
- Generic-ish debt is material: `anytype` is used for cursor/shape/presentation/color helper inputs at lines 83-114, 366-447, 507, 659-762, 771, 798, 811-817, and `count32` at lines 836-839; `usize` count plumbing is visible at lines 71-80, 552-568, and assertion/test uses at lines 771 and 880-941. Some `usize` is legitimate slice length/test expectation, but public counts that cross owner boundaries must become `u32`/typed count facts. The `anytype` cursor helpers are unjustified because `render.CursorPresentation`, `render.CursorShape`, `render.CursorColor`, and `render.Rgb8` exist.
- The correct slice is not “reduce line count”; it is replace generic-ish cursor/color/count leakage with explicit domain types while retaining the current draw primitive behavior and tests.

### `text/direct_normal.zig`

- `howl-render/src/text/direct_normal.zig` owns the fast direct-normal text preparation path: `Product` lines 23-35, `Source` lines 42-49, `Scratch` lines 51-102, `Driver` lines 104-110, and `prepare` lines 112-150.
- It produces direct draw primitives and raster outputs without the complex shaping path, then `finishScene` returns the product at lines 451-470.
- Generic-ish debt is bounded but real: `ScratchCheckpoint` stores `usize` list lengths at lines 175-183; `count32` uses `anytype` at lines 487-490. These are internal list-length facts and may remain `usize` inside scratch bookkeeping, but count conversion helpers must become explicit and owner-local.

### `text/surface.zig`

- `howl-render/src/text/surface.zig` defines `TextSurface` at lines 29-44. It owns glyph cache, text preparer, sprite resource store, emitter, prepared render product, scratch arrays, font paths, and font size.
- `prepare` at lines 87-125 validates C ABI input, reads VT render state, builds prepare options, prepares text, constructs a `prepared_surface.PreparedSurface`, emits a `HowlRenderSurface`, and returns `HowlRenderTextPreparedUpload`. This is the render ABI entrypoint, not host surface presentation.
- `readRenderState` at lines 160-207 reads VT rows/cells/dirty rows into render-side scratch. It currently uses `usize` for cell indexing at lines 161 and 188-204 because it indexes Zig slices; the plan should add overflow/limit assertions where converting from grid rows/cols to `usize` length.
- `ensurePreparer` and `capacity` at lines 137-158 derive capacities from `grid.cols * grid.rows`; these require explicit overflow assertions because ABI row/col values are u16 but scratch/storage lengths are memory-sized.

### `surface/*.zig`

- `surface/prepared_surface.zig` defines `PreparedSurface` at lines 23-33, carrying render request token, geometry epoch, render/cell/grid size, prepared text surface, resolve observability, and emission failure. Its assertions at lines 90-97 correctly require nonzero render/cell/grid facts.
- `surface/emitter.zig` aliases `Surface = c.HowlRenderSurface` at lines 10-13 and defines bounded `Limits` at lines 66-86. `Emitter` stores fixed arrays and surface storage at lines 88-108, emits by copying through `next` and publishing spans at lines 119-151, and asserts pre/post publish span counts at lines 153-175. This is the render packet emitter owner.
- `surface/emitter.zig` currently always appends full damage at lines 142-145 and 210-224. This blocks Alacritty-style present damage because render packet damage does not yet preserve shaped partial damage rects.
- `surface/realizer.zig` validates and realizes `HowlRenderSurface` packets into pixels at lines 37-85, validates damage/create/upload/command spans at lines 87-110 and 119-260, and uses `anytype` in validation/slice helpers at lines 463-469. This is test/reference realization, not the host GL present owner.
- `surface/compositor.zig` composes a `PreparedSurface` into pixels at lines 6-24, copies retained base on partial updates at lines 71-80, and draws spans/sprites at lines 104-266. Its `anytype` helpers at lines 62 and 104 are generic-ish debt but lower priority than the named sprint files.
- `surface/resource_store.zig` owns sprite resource admission, persistent/transient allocation, and upload byte copying. It is correctly resource-owned and should not be renamed in the first naming slice.

### `howl-linux-host` Display And Present

- `howl-linux-host/src/display/display.zig` wraps SDL and GL calls through `C` at lines 7-55. It exposes `SDL_GL_SwapWindow` but not SDL EGL display/surface/proc APIs at lines 28-38.
- `display.State` currently owns SDL window, GL context, tab texture cache, and present token at lines 57-75. `init` creates the GL context and sets swap interval at lines 82-101.
- `displaySubmitPresentSync` draws the host frame and calls `SDL_GL_SwapWindow` at lines 114-142. This is the exact first damaged-present insertion point.
- `display/present.zig` owns present lifecycle/reasons. It maps terminal and host dirty causes to `Reason` at lines 52-58, submits visual presents at lines 60-76, and synchronously completes terminal presents at lines 78-98. It should stay as present lifecycle owner.
- `display/render_surface.zig` uploads `HowlRenderSurface` packet data into a host GL texture at lines 17-46, creates/deletes textures at lines 48-93, and asserts matching dimensions. This is host resource realization, not the render packet owner.
- `display/render_surface_commands.zig` classifies render packets into full/patch fill/sprite/glyph classes at lines 30-50 and 99-113, uploads fill commands at lines 115-131, uploads command lists into an FBO at lines 133-202, and validates full vs patch coverage at lines 204-320. This is the right host GL resource realization owner.
- `display/render_surface_resources.zig` owns retained GL resource texture slots at lines 7-23, validates/realizes creates/uploads/retires at lines 29-57, and panics on trusted render invariant violations at lines 94-123 and 125-185.
- `display/layout.zig` defines host frame/layout rectangles and sizes at lines 5-35 and derives content/terminal rects at lines 37-91. This should remain host display layout, separate from render layout/size facts.

### `howl-linux-host` Terminal Surface

- `terminal/render_retained.zig` owns retained terminal render state. `SurfaceLayout` at lines 45-51 stores render/grid pixels, columns/rows, and cell pixels; `State` at lines 117-130 stores layout, geometry epoch, prepared surface handle, fallback surface packet, present-in-flight, and cursor cadence.
- Layout sync increments geometry epoch at lines 149-165. Present-in-flight state is asserted and completed at lines 189-204.
- Fallback full-surface preparation builds a `HowlRenderSurface` with full damage and one clear command at lines 272-299.
- Text surface preparation forwards render/grid/cell layout and cursor cadence into the render C ABI at lines 302-327.
- `terminal/surface.zig` is the host terminal runtime surface owner. It stores the host texture and render resource textures at lines 133-138, display/layout state at lines 144-146, and render turn pipeline at lines 498-520. The term “surface” here is runtime terminal surface, not render packet or EGL present surface.

## Reference Facts

### Alacritty

- Alacritty’s terminal `Grid<T>` owns cursor, saved cursor, row storage, columns, visible lines, display offset, and history at `alacritty_terminal/src/grid/mod.rs` lines 110-138. This is terminal/VT state, not renderer draw-list shape.
- Alacritty tracks terminal line damage with `LineDamageBounds` at `alacritty_terminal/src/term/mod.rs` lines 136-174 and `TermDamage`/`TermDamageIterator` at lines 176-214. Damage is row/column terminal truth first.
- `TermDamageState` stores full flag, damaged lines, and last cursor at `term/mod.rs` lines 216-234 and resets full damage on resize at lines 236-247.
- `Term::renderable_content` exposes `RenderableContent` at `term/mod.rs` lines 635-642, and `RenderableContent` contains display iterator, selection, cursor, display offset, colors, and mode at lines 2390-2412.
- Display-side `RenderableContent` is a renderer preparation wrapper at `alacritty/src/display/content.rs` lines 24-38 and initializes from terminal renderable content at lines 40-88. This supports a separate render-preparation owner between terminal grid and renderer.
- Alacritty `SizeInfo` is the display/layout size owner at `alacritty/src/display/mod.rs` lines 143-170, with constructor deriving screen lines and columns from window/cell/padding facts at lines 229-260.
- Alacritty display damage owner is `DamageTracker` at `alacritty/src/display/damage.rs` lines 12-28. It maintains two `FrameDamage` buffers, swaps/resetting frame damage at lines 56-63, resizes and marks full damage at lines 65-73, and shapes frame damage into pixel rects at lines 92-103.
- `FrameDamage` stores full flag, line damage, and extra rects at `damage.rs` lines 138-147; it damages lines/points/viewport rects at lines 149-181 and checks intersects at lines 193-202.
- Alacritty converts line damage to pixel rects and overdamages for wide/near cells at `damage.rs` lines 215-251, then merges overlapping rects at lines 254-299. This is the governing shape for Howl render-packet damage and host present damage.
- Alacritty display draw imports terminal damage into display damage at `display/mod.rs` lines 803-812, resets terminal damage at line 812, draws rectangles/glyphs/UI, calls `pre_present_notify` at lines 1019-1021, calls `swap_buffers` at line 1031, and swaps damage buffers at line 1046.
- Alacritty’s Wayland EGL present path is in `display/mod.rs` lines 607-619: on Wayland EGL and when debug damage is off, it calls `shape_frame_damage` and `surface.swap_buffers_with_damage(context, &damage)`; otherwise it calls normal `swap_buffers`.
- Alacritty `window.pre_present_notify` says it should be called right before presenting with e.g. `eglSwapBuffers` at `display/window.rs` lines 401-405.
- Renderer organization: Alacritty renderer draws cells via `draw_cells` at `renderer/mod.rs` lines 177-190, draw strings via lines 193-230, and draw rects via lines 242-265. Rendering consumes `SizeInfo`; it does not own terminal grid or present cadence.
- Alacritty window context drives `display.draw` from a window draw method at `window_context.rs` lines 365-398, preserving the display/present owner above renderer leaf calls.

### SDL And EGL

- SDL docs expose `SDL_EGL_GetCurrentDisplay` as “Get the currently active EGL display” with signature `SDL_EGLDisplay SDL_EGL_GetCurrentDisplay(void);` at `SDL_EGL_GetCurrentDisplay.md` lines 1-24; it is main-thread only at lines 26-29.
- SDL docs expose `SDL_EGL_GetWindowSurface(SDL_Window *window)` and describe it as returning the EGLSurface associated with the window at `SDL_EGL_GetWindowSurface.md` lines 1-29; it is main-thread only at lines 31-34.
- SDL docs expose `SDL_EGL_GetProcAddress(const char *proc)` at `SDL_EGL_GetProcAddress.md` lines 1-30 and state it returns an EGL function pointer to cast to the appropriate signature; remarks at lines 32-36 say it is useful for EGL APIs/extensions.
- SDL docs expose `SDL_GL_SwapWindow(SDL_Window *window)` at `SDL_GL_SwapWindow.md` lines 1-29 and describe it as double-buffered OpenGL window update at lines 31-39; it is main-thread only at lines 41-44. There is no damage rect parameter.
- SDL source dispatches public `SDL_GL_SwapWindow` through the video device `GL_SwapWindow` callback at `backends/sdl/src/video/SDL_video.c` lines 5607-5619.
- SDL Wayland GLES swap comments explain its Wayland frame-callback control at `SDL_waylandopengles.c` lines 67-80 and its swap interval implementation at lines 81-100.
- SDL Wayland GLES `Wayland_GLES_SwapWindow` calls plain `_this->egl_data->eglSwapBuffers(_this->egl_data->egl_display, data->egl_surface)` in the double-buffer path at `SDL_waylandopengles.c` lines 131-142 and again in the normal path at lines 185-192. It does not call `eglSwapBuffersWithDamageKHR/EXT`.
- SDL’s `SDL_egl.h` includes standard EGL headers at lines 36-38, so extension typedefs/prototypes are available when system headers provide them.
- EGL registry defines `PFNEGLSWAPBUFFERSWITHDAMAGEKHRPROC` and optional `eglSwapBuffersWithDamageKHR` at `eglext.h` lines 425-431, and `PFNEGLSWAPBUFFERSWITHDAMAGEEXTPROC`/`eglSwapBuffersWithDamageEXT` at lines 1012-1018.
- Official Khronos `EGL_KHR_swap_buffers_with_damage` and `EGL_EXT_swap_buffers_with_damage` specs define `eglSwapBuffersWithDamageKHR/EXT` as an alternative to `eglSwapBuffers` that does the same swap while also reporting damage rectangles to the compositor.
- Official Khronos damaged-swap specs state the entire back buffer is still swapped, so applications must keep the entire back buffer consistent; the rectangles are compositor hints.
- Official Khronos damaged-swap specs state damage rectangles are `{x, y, width, height}` groups, relative to the bottom-left of the surface, and overlapping rectangles are allowed.
- Official Khronos damaged-swap specs state `n_rects == 0` ignores `rects` and implicitly damages the entire surface, equivalent to calling `eglSwapBuffers`.
- Official Khronos damaged-swap specs state resize-time forwarded damage rectangle meaningfulness is undefined when the native window has been resized, so Howl must force full damage around resize/layout changes.

### Kitty/GLFW And Old Howl Backend Seam

- Kitty/GLFW’s EGL swap function validates current context and calls plain `eglSwapBuffers(_glfw.egl.display, window->context.egl.surface)` at `kitty/glfw/egl_context.c` lines 194-204.
- Kitty/GLFW loads the plain `eglSwapBuffers` symbol at `egl_context.c` lines 314-331 and requires it at lines 333-349. No damaged-swap symbol is part of the normal path.
- GLFW public `glfwSwapBuffers` calls `window->context.swapBuffers(window)` and then Wayland post-swap handling at `kitty/glfw/context.c` lines 465-483.
- Kitty/GLFW Wayland creates a `wl_surface_frame` callback at `wl_window.c` lines 3088-3104 and separately has many `wl_surface_damage` uses for client-side decorations. This is useful Wayland framework pressure, not a directive to resurrect GLFW.
- Old `howl-linux-host` commit `2ac7580` added a unified host build with backend selection and vendored deps; old commit `b3f821e` added `src/service/gpu/{sdl,glfw}.zig` and `src/service/window/{sdl,glfw}.zig`. These prove a historical seam existed, but the current sprint must not resurrect it unless SDL blocks the EGL damaged-present path and the user approves that explicit direction.

### TigerBeetle

- TigerBeetle requires simple bounded control flow, fixed upper bounds, explicitly-sized types over casual `usize`, and assertions for function arguments/return values/invariants at `TIGER_STYLE.md` lines 90-104 and 109-140.
- TigerBeetle says no hidden unbounded allocation after initialization and external events should not directly own program pace at lines 151-183. For Howl this supports bounded render packets and host-owned presentation cadence.
- TigerBeetle naming law requires exact nouns, no overloaded names, clear units/qualifiers, and options structs where primitive arguments can be mixed up at lines 271-352.
- TigerBeetle warns that index/count/size are distinct concepts and division must be explicit at lines 443-454. This directly applies to `grid`, `rect`, `usize`, and count conversion debt.
- TigerBeetle architecture emphasizes explicit upper bounds at lines 189-222, deterministic/simulation proof at lines 281-327, and control-plane/data-plane separation at lines 408-423. This supports a render packet/present damage split: render commands are data plane, present reason/damage selection is control plane.

## Compact Anchor Map

- Terminal grid truth: Alacritty `Grid<T>` at `alacritty_terminal/src/grid/mod.rs` lines 110-138; current Howl `grid/scene.zig` is not this owner.
- Terminal dirty-line truth: Alacritty `LineDamageBounds`/`TermDamage` at `term/mod.rs` lines 136-214; current Howl render-side `grid/damage.zig` lines 4-124 approximates this import shape but should not claim terminal grid ownership.
- Renderable content bridge: Alacritty terminal `RenderableContent` at `term/mod.rs` lines 2390-2412 and display `RenderableContent` at `display/content.rs` lines 24-88; current Howl bridge is `text/surface.zig` lines 87-125 and `surface/surface_preparer.zig` lines 80-223.
- Layout/size owner: Alacritty `SizeInfo` at `display/mod.rs` lines 143-170 and 229-260; current Howl render layout is `geometry.zig` lines 40-107 and host display layout is `display/layout.zig` lines 5-91.
- Display damage owner: Alacritty `DamageTracker` at `display/damage.rs` lines 12-103 and merge/overdamage at lines 215-299; current Howl lacks an equivalent host/render packet pixel damage owner and emits full damage in `surface/emitter.zig` lines 142-145 and 210-224.
- Draw owner: Alacritty renderer `draw_cells`/`draw_rects` at `renderer/mod.rs` lines 177-190 and 242-265; current Howl prepared draw owners are `grid/scene.zig` lines 190-280, `scene.zig` lines 111-164, and `grid/rects.zig` lines 71-817.
- Present owner: Alacritty Wayland EGL damaged present at `display/mod.rs` lines 607-619; current Howl present is `display/display.zig` lines 114-142 plus `display/present.zig` lines 52-98.
- SDL EGL escape hatch: SDL docs for EGL display/surface/proc at `SDL_EGL_GetCurrentDisplay.md` lines 1-24, `SDL_EGL_GetWindowSurface.md` lines 1-29, `SDL_EGL_GetProcAddress.md` lines 1-36; current Howl display `C` wrapper lacks these at `display/display.zig` lines 7-55.

## Owner Roles And Proposed Shape

- `howl-vt` remains terminal grid/cell/dirty truth owner. It should expose dirty rows/columns through the existing render state path; render must not create a second terminal grid owner.
- `howl-render` owns render layout/size facts, text preparation, draw primitive preparation, bounded render packet emission, render packet realization tests, and render-packet damage spans.
- `howl-render` layout owner should be named `layout` or `size`, not `geometry`, because the source-backed concept is Alacritty `SizeInfo`: render pixels, grid/content pixels, cell pixels, columns/rows, and epoch.
- `howl-render` prepared text owner should be named around `prepared_text`/`draw_list`/`renderable_content`, not `grid/scene`. Current `scene` may survive only as a short-lived internal alias if a slice explicitly removes public imports and proves no ambiguity remains.
- `HowlRenderSurface` must be renamed in the C ABI to `HowlRenderSurfaceFrame`. Alacritty uses “surface” for EGL/window surface; SDL uses EGL window surface; current `HowlRenderSurface` is a command/resource packet. `SurfaceFrame` states the render-surface product boundary and the frame packet consequence without claiming host/EGL ownership.
- `HowlRenderHostSurface` must be renamed to `HowlRenderHostTexture`, because current host code realizes packets into GL textures (`display/render_surface.zig` lines 17-46 and 55-93).
- `howl-linux-host` owns SDL window/context, host GL texture/resource realization, display layout, present reason/cadence, and EGL damaged present. SDL remains the event/window/input/text-input/clipboard harness.
- `howl-linux-host/src/display/present.zig` remains present lifecycle owner. The EGL proof/implementation owner is `howl-linux-host/src/display/egl_present.zig`; it is called from `display/display.zig` at the existing present point only after Slice 4 proves SDL-retained direct EGL damaged swap preserves required Wayland behavior.
- No umbrella runtime/backend manager is authorized. No X11 implementation is authorized in this sprint.

## Term Classification

- `surface`: split and rename. Keep only where it means external/window/EGL surface or the established host terminal runtime surface. Rename render ABI `HowlRenderSurface` to `HowlRenderSurfaceFrame`. Rename host `HowlRenderHostSurface` to `HowlRenderHostTexture`.
- `scene`: delete as public/core noun for render packet work. Rename prepared text draw-list assembly out of `scene.zig`/`grid/scene.zig` to the fixed Slice 1 names: `text/draw_list.zig` and `text/draw_primitives.zig`. No compatibility alias named `TextScene` may survive Slice 1.
- `geometry`: rename to layout/size. Current `geometry.zig` owns layout synchronization and epoch, not arbitrary geometry. Use `layout.zig`, `RenderLayout`, `RenderLayoutInput`, `RenderLayoutResponse`, `PreparedLayout`, `DrawablePixels`, `CellGridLayout`, and `RenderLayoutError`.
- `grid`: keep only for terminal/VT grid or explicit row/column counts imported from VT. Rename render files under `grid/` that define draw primitives/damage/rects to `text/draw_primitives.zig`, `text/damage.zig`, and `text/rect_primitives.zig`. C ABI `HowlRenderGridSize` becomes `HowlRenderCellGrid` in Slice 2.

## Generic-ish Debt Treatment

- `howl-render/src/grid/rects.zig`: highest priority in this sprint. Replace `anytype` cursor/presentation/color helpers with explicit `render.CursorPresentation`, `render.CursorShape`, `render.CursorColor`, `render.Rgb8`, or small owner-true structs. Replace public `usize` count returns for draw counts with explicit `u32` where counts feed bounded packet capacities; keep `usize` only for Zig slice lengths at allocation/test boundaries with conversion assertions.
- `howl-render/src/scene.zig`: `DrawCapacities` `usize` fields at lines 198-207 are capacity facts tied to ArrayList reservation. Either keep them as internal allocation capacities with a more exact owner name or convert to bounded `u32` draw counts before allocation. Remove `count32`/`count16` generic helpers at lines 611-616 in favor of explicit count helpers.
- `howl-render/src/text/direct_normal.zig`: `ScratchCheckpoint` `usize` fields at lines 175-183 are internal list lengths and acceptable if kept private, but `count32(anytype)` at lines 487-490 should become an explicit slice-count helper. Ensure `sourceLen` at lines 249-255 asserts conversion to u32 before use.
- Generic debt outside the named files, such as `surface/realizer.zig` `spanSlice(anytype)` and `surface/compositor.zig` `drawColorSpan(anytype)`, is recorded as a follow-on proof surface but not allowed to distract from the present/layout sprint unless touched by a slice.

## Ordered Sprint Slice Plan

### Slice 1: Rename Render Layout And Prepared Draw Owners

- Coder session id: open.
- Reviewer session id: open.
- Allowed files: `howl-render/src/geometry.zig` -> move to `howl-render/src/layout.zig`; `howl-render/src/scene.zig` -> move to `howl-render/src/text/draw_list.zig`; `howl-render/src/grid/scene.zig` -> move to `howl-render/src/text/draw_primitives.zig`; `howl-render/src/grid/damage.zig` -> move to `howl-render/src/text/damage.zig`; `howl-render/src/grid/rects.zig` -> move to `howl-render/src/text/rect_primitives.zig`; `howl-render/src/libhowl_render.zig`; `howl-render/src/text/direct_normal.zig`; `howl-render/src/surface/surface_preparer.zig`; `howl-render/src/text/surface.zig`; `howl-render/src/benchmark_main.zig`; existing owner-local tests embedded in moved files; direct import updates in files that fail solely because of these moves.
- Required shape: perform exactly these name outcomes: `Geometry` -> `RenderLayout`; `GeometryLayout` -> `RenderLayoutInput`; `GeometryResponse` -> `RenderLayoutResponse`; `PrepareLayout` -> `PreparedLayout`; `SurfacePixels` -> `DrawablePixels`; `SurfaceLayout` -> `CellGridLayout`; `SurfaceGeometryError` -> `RenderLayoutError`; `deriveGridForSurface` -> `deriveCellGridForLayout`; `deriveGridSize` -> `deriveCellGridSize`; `OwnedTextScene` -> `OwnedTextDrawList`; `BorrowedTextScene` -> `BorrowedTextDrawList`; `RetainedScratch` -> `RetainedDrawScratch`; `BuildOptions` -> `DrawListOptions`; `SceneAssembly` -> `DrawListAssembly`; `TextScene` -> `TextDrawList`; `GridMetrics` -> `CellGridMetrics`. No C ABI/header names change in this slice.
- Tests/gates: `zig build test` or the existing package test command for `howl-render`; grep gate for no `@import("grid/scene.zig")`, no `@import("grid/damage.zig")`, no `@import("grid/rects.zig")`, no public `TextScene`, no `GeometryLayout`, no `GeometryResponse`, and no `SurfaceGeometryError` outside historical docs. Existing scene/damage/rect tests must move with their owner.
- Non-goals: no C ABI/header rename in this slice; no SDL/EGL code; no behavior change to draw primitives.
- Stop conditions: if moving files requires changing C ABI/header names, stop; if tests require duplicate roots, stop; if any required replacement name proves impossible without a new owner concept, stop for reviewer correction rather than inventing an alias.
- Nested repo/root commit receipt rules: changes are inside `howl-render`, a nested repo if applicable; coder must report child repo status and root repo status, reviewer must identify child commit hash or explicit uncommitted handoff, and orchestrator must close both root and child receipts before accepting.

### Slice 2: C ABI Packet And Host Texture Rename

- Coder session id: open.
- Reviewer session id: open.
- Allowed files: `howl-render/include/howl_render.h`; `howl-render/src/libhowl_render.zig`; `howl-render/src/surface/emitter.zig`; `howl-render/src/surface/emitter_test.zig`; `howl-render/src/surface/realizer.zig`; `howl-render/src/surface/realizer_test.zig`; `howl-render/src/surface/realizer_resource_store.zig`; `howl-render/src/surface/resource_store.zig`; `howl-render/src/text/surface.zig`; `howl-linux-host/src/howl_render_c.h`; `howl-linux-host/build.zig` only if translate-C include behavior breaks; `howl-linux-host/src/display/render_surface.zig`; `howl-linux-host/src/display/render_surface_commands.zig`; `howl-linux-host/src/display/render_surface_resources.zig`; `howl-linux-host/src/display/render_surface_test.zig`; `howl-linux-host/src/terminal/render_retained.zig`; `howl-linux-host/src/terminal/surface.zig`; `howl-linux-host/src/host_test_root.zig` only if test root imports require renaming.
- Required shape: rename `HowlRenderSurface` -> `HowlRenderSurfaceFrame`; `HowlRenderHostSurface` -> `HowlRenderHostTexture`; `HowlRenderSurfaceToken` -> `HowlRenderSurfaceFrameToken`; `HowlRenderSurfaceRect` remains `HowlRenderSurfaceRect` because it is a render-surface coordinate rect used by frame damage and commands; `HowlRenderSurfaceDamageItem/Span` -> `HowlRenderSurfaceFrameDamageItem/Span`; `HowlRenderSurfaceCommand/Span` -> `HowlRenderSurfaceFrameCommand/Span`; constants with `HOWL_RENDER_SURFACE_*` remain only when they describe product-wide surface frame limits or commands, otherwise rename to `HOWL_RENDER_SURFACE_FRAME_*`. Rename C ABI `HowlRenderGridSize` -> `HowlRenderCellGrid`. Update Zig imports/usages directly; no compatibility typedefs or aliases.
- Tests/gates: render and linux-host tests/builds; grep gate for old C ABI names `HowlRenderSurface`, `HowlRenderHostSurface`, `HowlRenderGridSize`, `HowlRenderSurfaceToken`, `HowlRenderSurfaceDamageItem`, `HowlRenderSurfaceDamageSpan`, `HowlRenderSurfaceCommand`, `HowlRenderSurfaceCommandSpan` except explicit historical notes inside this research file; compile gate for both nested repos. ABI assertions must still prove packet bounds and span counts.
- Non-goals: no EGL damaged present implementation; no X11; no GLFW resurrection.
- Stop conditions: if translate-C generated bindings cannot be refreshed by normal build/test, stop; if another repo outside allowed files depends on old names, stop for orchestrator expansion; if any old-name alias seems necessary, stop because current product direction says APIs are not frozen and no downstream exists.
- Nested repo/root commit receipt rules: this crosses `howl-render` and `howl-linux-host`; accepted execution requires separate child commit receipts or an explicit multi-repo uncommitted handoff receipt for each nested repo plus root receipt.

### Slice 3: VT Dirty Column ABI And Render Packet Damage Rects

- Coder session id: open.
- Reviewer session id: open.
- Allowed files: `howl-vt/include/howl_vt.h`; `howl-vt/src/ffi/render_state.zig`; `howl-vt/test/abi.zig`; renamed render layout/damage/rect owners from Slice 1; `howl-render/src/surface/emitter.zig`; `howl-render/src/surface/emitter_test.zig`; `howl-render/src/surface/realizer.zig`; `howl-render/src/surface/realizer_test.zig`; `howl-render/src/text/surface.zig`; `howl-render/src/surface/prepared_surface.zig`; `howl-render/include/howl_render.h` only if Slice 2 packet names require damage constant updates.
- Required shape: extend VT row-data ABI with exact fields `HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_START` and `HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_END`, backed by existing dirty column arrays copied through `screen_set.copyDirtyRows`. Then implement Alacritty-style shaped damage rects for render packets: full damage remains one full rect; partial damage converts dirty rows/cols to pixel rects, overdamages for neighboring/wide cells, clamps to render bounds, and merges overlapping rects. Preserve command stream behavior; damage is a present/update hint and packet validation fact, not a retained partial render command stream.
- Tests/gates: VT ABI tests for dirty row start/end columns after single-cell edit, full-screen dirty, scroll-exposed row, and hover highlight dirty; render unit tests for full damage, one dirty row, dirty col span, overdamage clamp at edges, merge overlapping adjacent rows, no zero-area damage, and packet damage count bound overflow. Realizer tests must reject invalid damage spans and accept shaped partial damage.
- Non-goals: no host EGL call yet; no optimizing draw command generation beyond existing behavior.
- Stop conditions: if current VT dirty column arrays cannot be exposed without changing VT ownership/lifecycle, stop; if damage count can exceed ABI max under realistic terminal sizes without deterministic full-damage fallback, stop.
- Nested repo/root commit receipt rules: crosses `howl-vt` and `howl-render`; accepted execution requires separate child repo receipts or explicit multi-repo uncommitted handoff receipts plus root receipt.

### Slice 4: SDL EGL Damaged-Present Feasibility Proof

- Coder session id: open.
- Reviewer session id: open.
- Allowed files: `howl-linux-host/src/display/display.zig`; new `howl-linux-host/src/display/egl_present.zig`; `howl-linux-host/src/display/display_test.zig` if an existing display test split exists, otherwise tests may remain owner-local in `display.zig`/`egl_present.zig`; `howl-linux-host/src/sdl_c.h`; `howl-linux-host/build.zig` only if SDL EGL symbols are not visible through existing translate-C; `howl-linux-host/src/host_test_root.zig` only if a new test file must be imported.
- Required shape: keep SDL window/event/input harness and do not replace `SDL_GL_SwapWindow` in production behavior yet. Add a display-owned proof seam that binds `SDL_EGL_GetCurrentDisplay`, `SDL_EGL_GetWindowSurface`, and `SDL_EGL_GetProcAddress`, resolves `eglSwapBuffersWithDamageKHR`/`EXT`, validates main-thread/current-window/current-context preconditions, converts damage rect coordinates, and returns an explicit decision. The decision must choose one of the options below and record why the others are rejected for this product slice. This slice must not introduce a custom Wayland/backend seam.
- Option A, SDL-retained direct damaged swap proof: use SDL's public EGL display/window-surface/proc APIs to prove that a future direct `eglSwapBuffersWithDamageKHR/EXT` call can be made at the current `display.zig` present point. Source support: SDL docs expose the EGL display, EGL window surface, and proc lookup as main-thread APIs; Khronos defines `eglSwapBuffersWithDamageKHR/EXT` as an alternative to `eglSwapBuffers` that does the same swap while passing compositor damage hints; Alacritty calls Wayland EGL `swap_buffers_with_damage` from its display-owned `swap_buffers` path after drawing. Tradeoff: this preserves SDL window/input/text/clipboard/event ownership and gives the desired damage hook, but Howl must explicitly own any SDL Wayland behavior it bypasses.
- Option B, SDL-retained plain-swap fallback during proof only: bind and test the EGL proof seam, but keep `SDL_GL_SwapWindow` as the runtime fallback only when KHR/EXT is unavailable. Full damage with KHR/EXT available must use damaged-swap semantics with `n_rects == 0`, not plain SDL swap. Source support: Khronos says `n_rects == 0` is equivalent to `eglSwapBuffers`, and SDL `Wayland_GLES_SwapWindow` owns hidden-window skip, optional swap-interval frame-callback waiting, plain `eglSwapBuffers`, and display flush. Tradeoff: acceptable as a capability fallback, not as the product answer if SDL prevents damaged present.
- Option C, Howl-owned Wayland/EGL present owner with SDL retained only for higher-level host services: mandatory next direction if Option A fails because SDL prevents correct damaged present. Source support: Alacritty/glutin and Kitty/GLFW show host/backend-owned EGL swap paths; GLFW calls Wayland after-swap hooks after `eglSwapBuffers`. Tradeoff: larger host display boundary change, but vendor limitations do not define Howl internals.
- Option D, replace the host window/backend seam more drastically: only if Option C cannot preserve required Wayland correctness while retaining SDL for input/window services. Source support is secondary only: old Howl once had a backend seam and Kitty vendors GLFW, but Kitty's normal GLFW EGL swap still uses plain `eglSwapBuffers`. Tradeoff: highest churn, but preferable to accepting a vendor limitation that blocks Howl's render/present contract.
- Tests/gates: fake-C tests proving KHR preferred over EXT, EXT fallback, plain swap fallback when extension unavailable, zero/full damage fallback, rect coordinate conversion for EGL bottom-left damage coordinates, resize forces full damage because Khronos leaves resize damage meaningfulness undefined, token monotonicity unchanged, main-thread/current-window/current-context assertions, and explicit handling of the SDL Wayland behaviors bypassed by direct damaged swap. If SDL-retained direct damaged swap cannot be made honest, Slice 5 must not degrade to permanent plain swap; the next promoted work must be Option C or D host-present ownership change. No live compositor CI requirement.
- Non-goals: no X11 implementation; no GLFW; no custom Wayland event loop; no bypass of SDL input/text/clipboard/event handling.
- Stop conditions: if SDL EGL functions cannot be bound through the current SDL headers/build, stop; if bypassing `SDL_GL_SwapWindow` skips SDL Wayland frame-callback behavior needed for KDE/Hyprland correctness, stop for user/orchestrator decision; if damaged present would make completion asynchronous, stop.
- Nested repo/root commit receipt rules: `howl-linux-host` child repo receipt required; if build bindings in vendor/root are touched, root receipt required too.

### Slice 5: SDL-Retained EGL Damaged Present Owner

- Coder session id: open.
- Reviewer session id: open.
- Allowed files: `howl-linux-host/src/display/display.zig`; `howl-linux-host/src/display/present.zig`; `howl-linux-host/src/display/egl_present.zig`; `howl-linux-host/src/display/render_surface.zig`; `howl-linux-host/src/display/render_surface_commands.zig`; `howl-linux-host/src/display/render_surface_test.zig`; `howl-linux-host/src/terminal/render_retained.zig` only if present damage needs packet damage access; direct tests for `egl_present.zig`; binding files already accepted by Slice 4.
- Required shape: implement damaged present only if Slice 4 returns feasible. Keep SDL window/event/input harness. Use KHR if available, EXT if KHR unavailable, and use `n_rects == 0` for full-surface damage when the damage extension is available. Use plain `SDL_GL_SwapWindow` only when neither damaged-swap extension is available. Call damaged present only at the existing present point after drawing and before token completion. Preserve main-thread assertions and synchronous completion semantics. If Slice 4 was blocked, this slice is not promotable.
- Tests/gates: fake-C tests from Slice 4 remain; add integration-level display submit tests proving damaged-present decision calls the expected backend and preserves monotonic nonzero tokens. No X11 or live compositor CI requirement.
- Non-goals: no X11 implementation; no GLFW; no custom Wayland event loop; no bypass of SDL input/text/clipboard/event handling.
- Stop conditions: any Slice 4 blocker, any requirement to create an umbrella backend manager, or any need for asynchronous present completion.
- Nested repo/root commit receipt rules: `howl-linux-host` child repo receipt required; if build bindings in vendor/root are touched, root receipt required too.

### Slice 6: Generic-ish Debt Hardening In Named Files

- Coder session id: open.
- Reviewer session id: open.
- Allowed files: `howl-render/src/text/rect_primitives.zig`, `howl-render/src/text/draw_list.zig`, `howl-render/src/text/direct_normal.zig`, their owner-local tests, and any direct import path updates caused only by this cleanup.
- Required shape: remove unjustified `anytype` from cursor/color/shape/count helpers; replace generic count helpers with explicit typed helpers; keep `usize` only where it is a Zig slice length/allocation length and pair conversions with assertions. Do not chase generic-ish debt in unrelated files.
- Tests/gates: owner-local tests plus grep gate for `anytype` in these three files. Remaining `anytype` requires a reviewer-recorded line-by-line justification. Grep gate for public count functions returning `usize` from draw/cell counts unless they are test-only or allocator-only.
- Non-goals: no behavioral changes; no broad style sweep; no generated special glyph/raster cleanup.
- Stop conditions: if removing `anytype` requires new bucket structs without reference pressure, stop; if public tests weaken or are deleted, stop.
- Nested repo/root commit receipt rules: `howl-render` child repo receipt required.

### Slice 7: Documentation And Accountability Closure

- Coder session id: open.
- Reviewer session id: open.
- Allowed files: root active loop/research/sprint artifacts as directed by orchestrator, repo README or architecture docs only if current workflow requires them, and nested repo docs only for changed public ABI names.
- Required shape: record final owner model, ABI rename decision, damaged-present behavior, fallback behavior, test gates, and commit receipts. Archive active planning artifacts only after orchestrator updates `sprints/current.txt`.
- Tests/gates: documentation grep gate for no stale old ABI names except historical notes; orchestrator receipt check for root and nested repos.
- Non-goals: no product code.
- Stop conditions: missing commit hash, missing reviewer/coder session id, stale active artifacts, or unreviewed API name left in docs.
- Nested repo/root commit receipt rules: root commit receipt required for accountability/docs; child repo receipts referenced from root artifact.

## Required Assertions

- Render/layout sizes: render width/height, grid/content width/height, cell width/height, rows, and columns are nonzero at every C ABI ingress, layout sync, prepare, packet emission, host upload, and present-damage conversion.
- Epoch/token: geometry/layout epoch is never zero after initialization; present token is never zero; submitted present snapshot sequence is never zero for terminal frame presents.
- Damage: full damage is exactly one full render rect; partial damage rects have positive width/height, are within render bounds after clipping, and count never exceeds ABI bound. If count would overflow, the deterministic fallback is one full damage rect with a recorded assertion/test.
- Damage coordinate conversion: render packet damage coordinates and EGL damage coordinates have a single documented conversion point with positive-space assertions for height and rect bounds.
- SDL/EGL: damaged present path asserts main thread, current SDL window/context when available, non-null EGL display, non-null EGL surface, and non-null KHR/EXT function before direct call. Fallback path asserts it used plain `SDL_GL_SwapWindow`.
- Host texture: packet render dimensions must match host texture dimensions before patch upload or patch present; patch class requires existing matching host texture as current code asserts at `display/render_surface_commands.zig` lines 109-113.
- Resource spans: packet span pointers are non-null when count is nonzero; counts are <= max; upload byte totals match sum; create/upload/retire sequencing remains validated.
- Generic cleanup: every conversion from slice length/`usize` to `u16`/`u32` asserts max before cast; every index/count/size distinction is explicit in names.

## Required Tests

- `howl-render` owner rename tests: moved draw primitive tests from `grid/scene.zig`, damage normalization tests, rect generation tests, and direct-normal fast path tests still pass from one curated root.
- C ABI rename tests/builds: `howl-render` and `howl-linux-host` compile with `HowlRenderSurfaceFrame`, `HowlRenderHostTexture`, and `HowlRenderCellGrid`; no compatibility typedefs remain.
- Damage shaping tests: VT row dirty-column ABI, full damage, partial row, dirty columns, edge overdamage clamp, overlapping merge, non-overlapping no merge, max damage fallback, zero-area rejection, and render-packet validation.
- Host present tests: Slice 4 feasibility decision tests for KHR possible, EXT possible, plain SDL swap fallback when extension unavailable, SDL-retained blocked semantics escalated to host-present ownership change, selected option reporting, no damage/full damage fallback, EGL bottom-left rect coordinate conversion, resize/full-damage behavior, failed EGL call fallback/error behavior as chosen by slice, and present token completion unchanged. Slice 5 implementation tests are promotable only if Slice 4 selects Option A as feasible with source-backed semantics; otherwise Slice 5 must be replaced by an Option C/D host-present slice.
- Retained render tests: patch packet requires existing host texture; full packet can bootstrap texture; geometry/layout change forces full damage or matching safe reset.
- Generic-ish debt tests/gates: grep `anytype` in `text/rect_primitives.zig`, `text/draw_list.zig`, and `text/direct_normal.zig`; remaining hits must be reviewed and recorded. Grep `usize` public count returns in the same files; remaining hits must be allocator/test-local.
- Integration/build gates: run nested repo test/build commands for every repo touched; do not rely on a live KDE/Hyprland compositor in CI.

## Risks

- Direct `eglSwapBuffersWithDamageKHR/EXT` would bypass SDL’s Wayland `Wayland_GLES_SwapWindow` hidden-window skip, optional frame-callback wait, plain `eglSwapBuffers`, and flush behavior at `SDL_waylandopengles.c` lines 113-194 unless Howl re-enters the required semantics elsewhere. Slice 4 must prove which semantics matter for Howl's current `SDL_GL_SetSwapInterval(0)` path. If SDL prevents an honest damaged-present path, the answer is host-present ownership change, not accepting permanent plain swap.
- SDL docs expose EGL handles/proc lookup, but the current Howl SDL C wrapper may not bind those functions yet. Binding work may be needed inside allowed files.
- C ABI rename crosses nested repos and generated bindings; missing a consumer will cause compile breakage. This is acceptable, but it must be caught by tests and receipts.
- Damage rect coordinate conventions differ between render packet, OpenGL viewport, Wayland/EGL damage, and host layout. A single conversion owner is mandatory.
- Current render packet emitter always emits full damage. Partial damage support could expose hidden assumptions in host patch upload classification.
- Generic cleanup can become fake style churn if it changes behavior or invents bucket structs. Keep it tied to named owner seams and tests.

## Proof Gaps

- Slice 4 proof result: SDL-retained direct damaged swap can resolve the EGL damage entry points, but the current public SDL-retained path does not preserve SDL Wayland hidden-window skip or Wayland display flush. Howl's current `SDL_GL_SetSwapInterval(0)` path means SDL's optional frame-callback wait is not required for this proof, but the hidden-window and flush gaps block honest Option A promotion. The next implementation direction must be Option C/D host-present ownership change, not permanent plain SDL swap.
- Generated binding inventory is now exact enough for checked-in paths: `howl-linux-host/src/howl_render_c.h` includes `<howl_render.h>` and `howl-linux-host/build.zig` lines 111-114 translate it with render/vt includes. Additional generated output is build-cache only and must be regenerated by normal build/test, not edited.
- ABI packet name is fixed as `HowlRenderSurfaceFrame`; reviewer/orchestrator acceptance of this corrected package authorizes that name for coding.
- Need current test command receipts for `howl-render` and `howl-linux-host`; this research pass did not run tests because it is planning-only.
- VT dirty column storage exists, but row-data ABI must expose `DIRTY_COL_START`/`DIRTY_COL_END` before render consumes it. Slice 3 includes that ABI work explicitly.

## Readiness Judgment

Accepted for execution through promoted slices only. The source-backed direction is executable without worker invention: exact names are fixed, allowed paths are explicit, VT dirty-column ABI work was assigned to Slice 3, and SDL/EGL damaged present is split into an honest proof-first Slice 4 and implementation-only-if-feasible Slice 5. Alacritty governs the owner split and damaged-present shape; SDL remains the host harness only if it does not block Howl-owned present correctness; Kitty/GLFW and old Howl backend seams are fallback evidence for a host-present ownership change if SDL cannot support the contract.
