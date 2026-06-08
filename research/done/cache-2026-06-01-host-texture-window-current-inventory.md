# Host Texture/Window Current Inventory - 2026-06-01

## Sources Read In Order

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `howl-linux-host/src/terminal/texture.zig`
- `howl-linux-host/src/terminal/texture/texture.zig`
- `howl-linux-host/src/terminal/texture/present.zig`
- `howl-linux-host/src/terminal/texture/pacing.zig`
- `howl-linux-host/src/terminal/texture/gl_c.h`
- `howl-linux-host/src/sdl_c.h`
- `howl-render/src/libhowl_render.zig`
- `howl-linux-host/src/window/window.zig`
- `howl-linux-host/src/window/layout.zig`
- `howl-linux-host/src/window/draw.zig`
- `howl-linux-host/src/window/scrollbar.zig`
- `howl-linux-host/src/window/icon.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/app/present.zig`
- `howl-linux-host/build.zig`
- `howl-linux-host/src/test/test_entry.zig`
- `howl-linux-host/src/test_root.zig`
- `howl-linux-host/src/test/host.zig`
- `howl-linux-host/src/terminal/scrollbar.zig`
- `howl-linux-host/src/terminal/links.zig`
- `howl-linux-host/src/terminal/render/temporary_debugging.zig`

## Current Imports And Build Paths Still Referencing Old Owners

- `src/terminal/context.zig` imports `../window/window.zig`, `../window/layout.zig`, and `../window/term_texture.zig` at lines 4-6. The `../window/term_texture.zig` path is stale because no `src/window/term_texture.zig` exists in the current tree.
- `src/terminal/render/temporary_debugging.zig` imports `../window/term_texture.zig` at line 3. The path is stale for the same reason.
- `src/main.zig` imports `window/pacing.zig` and `window/window.zig` at lines 13-14. `src/window/pacing.zig` does not exist in the current tree; current pacing code is under `src/terminal/texture/pacing.zig`.
- `src/app/present.zig` imports `../window/pacing.zig` and `../window/layout.zig` at lines 5-6. `../window/pacing.zig` is stale.
- `src/test/host.zig` imports `../window/window.zig` at line 7. This remains valid only while the old `src/window/` path remains.
- `src/terminal/scrollbar.zig` imports `../window/window.zig` and `../window/scrollbar.zig` at lines 4 and 6. These remain valid only while scrollbar behavior remains under `src/window/`.
- `src/terminal/links.zig` imports `../window/window.zig` at line 4 for cursor/open URL host services.
- `build.zig` translates C modules from `src/window/sdl_c.h` and `src/window/gl_c.h` at lines 148-149. These paths are stale: current observed headers are `src/sdl_c.h` line 1 and `src/terminal/texture/gl_c.h` line 1.
- `build.zig` still passes `src/window/stb_image.c` at line 152. That file is still present under `src/window/` in the current tree, but it is tied to window icon decoding via `src/window/icon.zig` lines 3-6.
- `build.zig` roots the term texture test module at `src/window/term_texture.zig` at lines 415-423. That path is stale because current render-surface/texture code is observed in `src/terminal/texture.zig` lines 1-2705.

## Build Blockers Observed

- Command run from `howl-linux-host`: `zig build -p /tmp/opencode/howl-linux-host-check`.
- The build failed in translate-c before Zig source compilation. The failed commands referenced `/home/home/personal/projects/howl/howl-linux-host/src/window/sdl_c.h` and `/home/home/personal/projects/howl/howl-linux-host/src/window/gl_c.h`.
- Line-backed source for those stale paths is `build.zig` lines 148-149.
- Because the first build failure is translate-c, later stale Zig import blockers such as `src/window/term_texture.zig` and `src/window/pacing.zig` are not yet reached by the compiler, but they are line-backed by imports/build roots above.

## Behavior Remaining Under `src/window/`

### Chrome Or Chrome-Adjacent

- `window/window.zig` owns SDL video init/quit through `initVideo()` and `quit()` at lines 214-224.
- `window/window.zig` creates a window, starts text input, applies the icon, and destroys/stops text input at lines 226-236.
- `window/window.zig` stores and updates the title through `current_title` in `State` lines 84-93, title allocation in `State.create()` lines 94-113, title free in `deinit()` lines 116-120, public `setTitle()` lines 183-185, and `setTitleWith()` lines 197-205.
- `window/window.zig` tracks focus in `State.focused` line 92 and `setFocused()` lines 137-141.
- `window/window.zig` controls pointer/default cursor state at lines 8, 219-222, and 287-295.
- `window/icon.zig` loads `assets/icon/howl_window_icon.png` line 8, decodes it via SDL/stb imports lines 3-6, creates an SDL surface, and applies it as the window icon at lines 10-31.

### Not Chrome

- `window/window.zig` imports `present.zig`, `gl_c`, and `sdl_c` at lines 4-6 and defines `PresentC` as a broad SDL/GL presentation adapter at lines 10-66. This exposes GL constants/functions and SDL GL context/swap functions, not only chrome.
- `window/window.zig` aliases `PresentState`, `PresentProofSnapshot`, and `PresentToken` at lines 80-82 and stores `present_state` in window `State` at line 86.
- `window/window.zig` initializes and deinitializes present state from window creation/destruction at lines 110-111 and 116-117, and delegates present submission/proof APIs at lines 167-181.
- `window/window.zig` reports pixel/logical window geometry and content/tab-bar rectangles at lines 122-165 and 187-195. These are host layout/presentation facts, not just chrome.
- `window/window.zig` exposes clipboard and URL services at lines 268-278 and 297-300.
- `window/window.zig` deletes GL textures at lines 280-285. Texture resource deletion is not window chrome.
- `window/layout.zig` defines present/render frame data shapes: `Rect`, `ScrollbarLayout`, and `Frame` at lines 3-27. `Frame` carries `term_texture_id`, `term_texture_rect`, scrollbar, tab count, active tab, and labels at lines 20-27.
- `window/layout.zig` maps mouse event coordinates relative to content and scales logical to pixel coordinates at lines 29-51.
- `window/draw.zig` draws the tab bar using immediate-mode GL at lines 5-48, draws labels/glyphs at lines 50-73, draws scrollbar at lines 75-78, and contains GL quad/NDC helpers at lines 80-104.
- `window/scrollbar.zig` owns scrollbar model/view/mouse state at lines 13-40, layout caching and layout computation at lines 61-88, mouse handling/dragging at lines 90-137, geometry math at lines 170-239, and view modeling/tests at lines 241-275.

## Current Texture/Present/Pacing Contents

### `src/terminal/texture.zig`

- This file is large owner code, not a namespace-only wrapper. It imports `std`, `gl_c`, and `howl_render_c` at lines 1-3 and declares GL externs/constants at lines 5-22.
- It defines `RenderResourceTextures` at lines 24-597. That struct owns texture slots, render resource diagnostics, failure classification, GL texture create/upload/delete, render surface validation, slot diagnostics, and teardown.
- It defines `RenderSurfaceSummary` at lines 599-606 and `TrustedTextureFailureAction` plus failure action functions at lines 608-629.
- It validates render surface ordering/command shape/resource formats/upload bounds through helpers at lines 631-827.
- It samples GL texture state at lines 890-903.
- It contains many owner-local tests beginning at line 990 and continuing through the file, including texture validation, render-surface shape classification, diagnostics, failure action classification, fill host row bounds, resource capacity, and upload metadata.
- It creates/resizes the host surface texture in `ensureSurface()` lines 2049-2079.
- It uploads fill-only and fill-patch render surfaces at lines 2081-2123.
- It uploads sprite/glyph render surface variants at lines 2125-2143 and renders commands into the host texture through FBO setup at lines 2145-2240.
- It classifies render surface shapes through `renderSurfaceFillOnly`, `renderSurfaceFillPatch`, `renderSurfaceSprite`, `renderSurfaceSpritePatch`, `renderSurfaceGlyphs`, and `renderSurfaceGlyphPatch` at lines 2243-2418.
- It draws fill, sprite, glyph, and textured quads at lines 2542-2688 and maps NDC/RGBA at lines 2690-2704.

### `src/terminal/texture/texture.zig`

- This file draws a texture rectangle via `drawRect()` and `drawSubRect()` at lines 1-48.
- It swaps an SDL window in `swapWindow()` at lines 50-52.
- It owns NDC coordinate helpers at lines 54-60.
- It mixes GL drawing and SDL swap behavior in one file; current facts do not show namespace-only behavior here.

### `src/terminal/texture/present.zig`

- This file imports `draw.zig`, `layout.zig`, and `texture.zig` at lines 2-4.
- It defines present proof/stat/snapshot/delta data shapes at lines 7-37 and present diagnostics at lines 39-52.
- It defines a generic `State(comptime c: type)` with window, GL context, tab texture cache, proof capture, present tokens, and diagnostics at lines 65-82.
- It defines window flags, GL context init/deinit, present submission, completion draining, and proof APIs at lines 84-196.
- `submitPresent()` performs readiness checks, framebuffer sizing, tab-bar cache update, viewport/clear, cached tab bar draw, terminal texture draw, scrollbar draw, SDL swap, diagnostics, and token state transitions at lines 126-180.
- It caches the tab bar in a GL texture using `glCopyTexImage2D`/`glCopyTexSubImage2D` at lines 283-343.
- It captures proof/readback data with heap allocation and GL readback calls at lines 388-535.
- It carries a `FakeC` test adapter and present tests at lines 549-655.

### `src/terminal/texture/pacing.zig`

- This file defines a fixed `frame_interval_ns` for 60 Hz at line 4.
- It defines `Pending`, `PresentReason`, and `Submission` at lines 6-16.
- It defines pacing `State` fields for redraw, render work, frame permit, present in-flight/completion/drain, and deadline at lines 18-26.
- It initializes, refreshes frame permit, computes wait time, records redraw/render work, records present completion, determines wait/render/terminal wake/present-submission permissions, and notes submission at lines 27-151.
- It contains frame pacing tests at lines 153-330.

### Root `src/texture.zig`

- `src/texture.zig` was requested but is not present in the current tree. Direct read returned file-not-found, and globbing `howl-linux-host/src/**/texture.zig` found only `src/terminal/texture.zig` and `src/terminal/texture/texture.zig`.

## Is `src/terminal/texture.zig` Namespace-Only?

- No. `src/terminal/texture.zig` contains imports, externs/constants, owner structs, mutation methods, render-surface validation, GL resource realization, GL upload/draw routines, helper functions, and tests across lines 1-2705.
- The comparison file `howl-render/src/libhowl_render.zig` imports FFI modules at lines 1-8 and uses a `comptime` block to reference/export ABI functions at lines 10-39. It does not define owner state, mutation, tests, GL calls, or render algorithms in that root file.
- Therefore current `src/terminal/texture.zig` is not namespace-only in the same structural sense as `howl-render/src/libhowl_render.zig` lines 1-39.

## Exact Stale Paths That Block Or Will Block Build After Move/Rename

- `src/window/sdl_c.h`: stale build translate-C path at `build.zig` line 148; build failure observed at this path. Current observed SDL header is `src/sdl_c.h` line 1.
- `src/window/gl_c.h`: stale build translate-C path at `build.zig` line 149; build failure observed at this path. Current observed GL header is `src/terminal/texture/gl_c.h` line 1.
- `src/window/term_texture.zig`: stale import at `src/terminal/context.zig` line 6, stale import at `src/terminal/render/temporary_debugging.zig` line 3, and stale test module root at `build.zig` line 417.
- `src/window/pacing.zig`: stale import at `src/main.zig` line 13 and `src/app/present.zig` line 5. Current observed pacing file is `src/terminal/texture/pacing.zig` lines 1-330.
- `src/window/present.zig`: `window/window.zig` imports `present.zig` at line 4 relative to `src/window/`; no `src/window/present.zig` exists in current `src/window/`. Current observed present file is `src/terminal/texture/present.zig` lines 1-655.
- `src/window/layout.zig`, `src/window/draw.zig`, `src/window/scrollbar.zig`, `src/window/window.zig`, `src/window/icon.zig`, and `src/window/stb_image.c` still exist today, but user direction requires `src/window/` rename to `window_chrome/`; after that rename, all imports/build paths listed above that still name `window/` become stale unless moved/repointed in the same slice.

## Current Tests And Import Test Entrypoints Affected

- `build.zig` creates `unit_test_mod` from `src/test/test_entry.zig` at lines 298-326 and injects module imports including `term_texture` at lines 319-325. `src/test/test_entry.zig` itself refAllDecls only `cli_args`, `config_env`, `process_accounting`, `retained_render`, and `tab_bar` at lines 1-7, so the injected `term_texture` module is not referenced by that entrypoint.
- `build.zig` creates a dedicated `test-term-texture` root using `termTextureTestModule()` at lines 349-357. `termTextureTestModule()` roots at stale `src/window/term_texture.zig` and imports `gl_c`/`howl_render_c` at lines 415-423.
- `build.zig` creates `test-terminal-context` from `src/test_root.zig` at lines 359-366 and `terminalContextTestModule()` roots at `src/test_root.zig` at lines 426-440.
- `src/test_root.zig` exports `Host.Window` at lines 1-9 and has a test that references `Host` at lines 11-13.
- `src/test/host.zig` exports `Main`, `TerminalContext`, and `Window` at lines 4-7, so `test-terminal-context` reaches `src/main.zig`, `src/terminal/context.zig`, and `src/window/window.zig` through that test root.
- `src/terminal/texture.zig` contains many tests beginning at line 990, but those tests are currently stranded from the dedicated term texture test because `build.zig` line 417 still roots `src/window/term_texture.zig`.
- `src/terminal/texture/present.zig` contains present tests at lines 616-655, and `src/terminal/texture/pacing.zig` contains pacing tests at lines 153-330. Current build/test wiring still imports `window/pacing.zig` from `src/main.zig` line 13 and `src/app/present.zig` line 5, not the observed `terminal/texture/pacing.zig` path.

## Worker-Ready Movement Categories From Observed Facts Only

- C header path repair: update build/module ownership for `sdl_c.h` and `gl_c.h` based on observed current locations (`src/sdl_c.h` line 1 and `src/terminal/texture/gl_c.h` line 1) and stale build paths (`build.zig` lines 148-149). Do not add compatibility aliases without explicit approval.
- Window chrome rename: move chrome facts under `src/window/` into the eventual `window_chrome/` owner only for chrome behavior observed in `window/window.zig` lines 214-236, 183-205, 287-295 and `window/icon.zig` lines 8-31. Repoint imports that still name `window/` only after the new owner path is explicit.
- Non-chrome extraction inventory: presentation adapter/state/delegation in `window/window.zig` lines 4-6, 10-66, 80-82, 110-117, and 167-181 must not remain hidden under a chrome-only directory.
- Layout/draw/scrollbar separation inventory: `window/layout.zig` lines 3-51, `window/draw.zig` lines 5-104, and `window/scrollbar.zig` lines 13-275 contain present frame data, immediate GL drawing, and scrollbar model/input behavior. These are movement candidates, but this cache does not choose their final owner.
- Texture owner split inventory: `src/terminal/texture.zig` lines 24-597 own render resource textures, lines 2049-2240 own host surface/FBO upload, and lines 2243-2418 own shape classification. `src/terminal/texture/texture.zig` lines 1-60 owns simple textured-quad draw and swap. These should not be preserved as fake `texture` buckets without a source-backed owner decision.
- Present/pacing owner inventory: `src/terminal/texture/present.zig` lines 65-180 and `src/terminal/texture/pacing.zig` lines 18-151 currently own host presentation state/cadence. Movement must preserve tests at `present.zig` lines 616-655 and `pacing.zig` lines 153-330 or explicitly rewire them.
- Test wiring repair: `build.zig` line 417 must stop pointing at absent `src/window/term_texture.zig`; `build.zig` lines 349-357 define the dedicated term texture test executable that should continue to reach the owner-local tests now observed in `src/terminal/texture.zig` lines 990-2705 if that owner remains testable.

## Readiness Judgment

- Ready for scratchpad planning of a movement/redesign sprint: stale paths are concrete and line-backed, current owners and mixed responsibilities are inventoried, and the first build failure is reproduced.
- Not ready for a worker to choose final architecture from this cache alone: the cache intentionally avoids choosing owner names/paths beyond observed current facts and the user-provided `window_chrome/` rename direction.
- A worker can be seeded only after the orchestrator promotes one exact slice with allowed files, target paths, final owner names, tests to run, and stop conditions.

## Stop Conditions

- Stop if a worker needs to decide where non-chrome presentation, layout, draw, scrollbar, GL texture realization, or pacing should live without an accepted scratchpad/current slice.
- Stop if a compatibility shim or alias is proposed for `src/window/term_texture.zig`, `src/window/pacing.zig`, `src/window/present.zig`, `src/window/sdl_c.h`, or `src/window/gl_c.h` without explicit approval.
- Stop if test roots are moved, dropped, or weakened without preserving the dedicated test wiring facts from `build.zig` lines 349-357 and 415-423.
- Stop if a proposed fact cannot be tied to a line in the current tree or to an observed tool result recorded above.
