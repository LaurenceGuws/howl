# Sprint: Linux Host Display, Renderer, And Window Chrome Ownership

Accepted research caches:

- `research/cache-2026-06-01-alacritty-display-render-window-shape.md`
- `research/cache-2026-06-01-host-texture-window-current-inventory.md`

Reviewer decision:

- Accepted for scratchpad planning with caveats.
- Not accepted as a direct worker contract.

## User Direction

- `howl-linux-host/src/terminal/texture/texture.zig` is a fake owner. Redesign its contents according to Alacritty.
- `howl-linux-host/src/terminal/texture.zig` must be a namespace-only root structurally like `howl-render/src/libhowl_render.zig`.
- `howl-linux-host/src/window/` may define window chrome only. Rename the folder to `window_chrome/` and redesign whatever else is hiding in its files.
- No fake small cuts. Broad redesign is required when ownership is wrong.
- Alacritty owns host/runtime/display/window/input/presentation/render organization unless it directly fights the user-owned C ABI or embeddable render boundary.
- TigerBeetle keeps Zig clean. Ghostty and Kitty are selective pressures only.

## Accepted Decisions

- Host-side render-surface consumption belongs under a Display/Renderer-shaped owner, not `window_chrome/` and not `terminal/texture/texture.zig`.
- `window_chrome/` is user-directed. Alacritty's source-backed concept is `display/window.rs`; the folder name differs, but the boundary must match Alacritty's window wrapper/chrome responsibilities.
- `terminal/texture.zig` becomes namespace-only. It may curate exports only and must not own state, mutation, GL calls, tests, validation, or policy.
- Current `terminal/texture.zig` owner behavior moves to display/renderer ownership. The exact render-surface owner name is `display/renderer/render_surface.zig` because the Howl C ABI render-surface contract has no direct Alacritty equivalent, while Alacritty places backend GL draw resources under Renderer.
- Current `terminal/texture/texture.zig` is deleted as an owner after its responsibilities move: drawing belongs to renderer rect/surface helpers; swap belongs to display presentation.
- Frame pacing moves to `display/frame_timer.zig`, following Alacritty `FrameTimer` under display.
- Present state and SDL GL context/swap/token/proof behavior moves to `display/display.zig`, following Alacritty `Display`.
- Rect/tab-bar/scrollbar drawing moves to `display/renderer/rects.zig`, following Alacritty `renderer/rects.rs`.
- SDL window wrapper/chrome behavior moves to `window_chrome/window.zig`; icon handling moves to `window_chrome/icon.zig`; `window_chrome.zig` is namespace-only.
- `window_chrome` must not import display renderer owners or own GL texture/resource/present/frame pacing/render-surface behavior.

## Non-Goals

- No public C ABI changes.
- No compatibility aliases at old `window/*` paths.
- No `window/` folder after the cut.
- No new generic `manager`, `engine`, `controller`, `utils`, `types`, or bucket structs.
- No renderer algorithm modernization beyond owner movement unless required to preserve behavior. Replacing immediate-mode GL with buffered rendering is a future renderer-quality slice.
- No weakening, filtering, or deleting tests. Test roots must stay curated through existing module gates.

## Known Dirty Baseline

Before this sprint contract, `howl-linux-host` intentionally contained moved/renamed user work:

- Old-path deletes reported by git for `src/window/gl_c.h`, `src/window/pacing.zig`, `src/window/present.zig`, `src/window/sdl_c.h`, `src/window/term_texture.zig`, `src/window/texture.zig`, and `src/terminal/render_surface_submit_diagnostics.zig`.
- New paths reported by git for `src/sdl_c.h`, `src/terminal/texture.zig`, `src/terminal/texture/*`, and `src/terminal/render/temporary_debugging.zig`.
- Treat these as intentional moved/renamed baseline, not accidental deletion.

Because this baseline is uncommitted and unpushed, the orchestrator must not hand new implementation work to a worker until the first accepted host cut is committed and pushed.

## Cut 1: Display/Renderer/Window Chrome Ownership Integration

Owner: orchestrator direct implementation, then reviewer. No worker until the dirty baseline becomes an accepted pushed tree.

Purpose: finish the user-started broad owner move so the host builds from Alacritty-shaped display/renderer/window_chrome boundaries.

Allowed host files and paths:

- `howl-linux-host/build.zig`
- `howl-linux-host/src/main.zig`
- `howl-linux-host/src/app/present.zig`
- `howl-linux-host/src/test/host.zig`
- `howl-linux-host/src/test_root.zig`
- `howl-linux-host/src/sdl_c.h`
- `howl-linux-host/src/display.zig`
- `howl-linux-host/src/display/`
- `howl-linux-host/src/display/renderer/gl_c.h`
- `howl-linux-host/src/window_chrome.zig`
- `howl-linux-host/src/window_chrome/`
- `howl-linux-host/src/window/` only for removing the old directory after moves.
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/scrollbar.zig`
- `howl-linux-host/src/terminal/links.zig`
- `howl-linux-host/src/terminal/render/temporary_render_surface_debugging.zig` for deletion;
  removed later in `howl-linux-host` commit `58acf28`.
- `howl-linux-host/src/terminal/texture.zig`
- `howl-linux-host/src/terminal/texture/` only for moving `gl_c.h` to `src/display/renderer/gl_c.h` and deleting moved fake owners after their contents move.

Required shape:

- Create `src/display.zig` as a namespace root only.
- Create `src/display/display.zig` for display/present owner behavior currently in `terminal/texture/present.zig`.
- Create `src/display/frame_timer.zig` for frame pacing behavior currently in `terminal/texture/pacing.zig`.
- Create `src/display/renderer.zig` as a renderer namespace root only.
- Create `src/display/renderer/rects.zig` for current immediate rect/tab-bar/scrollbar draw behavior from `window/draw.zig` and simple draw helpers from `terminal/texture/texture.zig` where appropriate.
- Create `src/display/renderer/render_surface.zig` for current render-surface GL resource realization and upload behavior from `terminal/texture.zig`.
- Rename `src/window/` to `src/window_chrome/` and leave only chrome/window-wrapper/icon behavior there.
- Create `src/window_chrome.zig` as namespace root only.
- Update imports away from `window/` to `window_chrome/`, `display/`, or `display/renderer/` according to ownership.
- Update `build.zig` translate-C paths to `src/sdl_c.h` and `src/display/renderer/gl_c.h`.
- Update dedicated render-surface/texture test wiring to `src/display/renderer/render_surface.zig`, not stale `src/window/term_texture.zig`.
- Make `src/terminal/texture.zig` namespace-only like `howl-render/src/libhowl_render.zig`.
- Remove `src/terminal/texture/texture.zig` as an owner; do not leave an empty fake owner unless it is a namespace with useful exports.
- Temporary render debugging must be clearly named and bannered as temporary/removable. It must not masquerade as a product diagnostics owner.

Reviewer caveats to enforce:

- `terminal/texture/present.zig` currently imports absent relative `draw.zig` and `layout.zig`; the cut must resolve that stale state.
- The current `terminal/texture/gl_c.h` must move to `src/display/renderer/gl_c.h` because the GL C surface belongs to the renderer backend, not terminal texture.
- Do not use `display/renderer/atlas.zig` unless the data shape is proven atlas-like. Current `RenderResourceTextures` is render-surface resource realization, not automatically an atlas.
- Add grep gates forbidding GL/present/render-surface ownership under `window_chrome/`.
- Add grep gates forbidding mutable owner state in `terminal/texture.zig`.

Required verification:

- From `howl-linux-host`: `zig build check`.
- From `howl-linux-host`: `zig build test --summary all`.
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`.
- From `howl-linux-host`: `git diff --check`.
- From workspace root: tracked `.zig` line scan reports zero lines over 190 chars.
- From workspace root: `./status.sh` after accepted host/root commits shows no unpushed accepted work.

Grep gates:

- No `src/window/` directory remains.
- No imports of `window/` remain in `howl-linux-host/src/**/*.zig` or `howl-linux-host/build.zig`.
- No `glBegin`, `glEnd`, `GL_QUADS`, `SDL_GL_SwapWindow`, `glGenTextures`, `glDeleteTextures`, `glTexImage2D`, `glTexSubImage2D`, `glBindFramebuffer`, `HOWL_RENDER_SURFACE`, `PresentState`, `RenderResourceTextures`, `realizeSurface`, `uploadRenderSurface`, or `ensureSurface` under `src/window_chrome/`.
- `src/terminal/texture.zig` contains no `struct`, `extern`, `fn`, `test`, `gl`, `render_c`, or mutable owner state.
- No stale build paths to `src/window/sdl_c.h`, `src/window/gl_c.h`, `src/window/term_texture.zig`, `src/window/pacing.zig`, or `src/window/present.zig`.

Stop conditions:

- Stop if Alacritty directly fights the user-owned C ABI/render-surface boundary.
- Stop if implementation needs a public C ABI change.
- Stop if `window_chrome` must own display, renderer, GL context, GL texture resources, frame pacing, present tokens, swap, or render-surface upload to make the build pass.
- Stop if a compatibility alias at an old path becomes necessary.
- Stop if tests would need to be weakened, filtered, duplicated, or moved to a second module entrypoint.
- Stop if a worker would need to choose an owner name or test root.

## Follow-Up Cuts

- Replace immediate-mode GL drawing with Alacritty-like buffered renderer paths.
- Revisit render-surface resource realization data shapes after the owner move, especially whether any subshape maps to Alacritty atlas/batch concepts.
- Continue splitting `terminal/context.zig` once display/renderer/window_chrome boundaries are stable.

## Signoff

- Research cache accepted: yes, with reviewer caveats.
- Scratchpad reviewer status: accepted.
- Cut 1 implementation status: accepted and pushed in `howl-linux-host` commit `c43f1d5`.
- Follow-up owner cuts accepted and pushed in `howl-linux-host` commits `4eb628b`, `2b314db`, and `4b8a4e8`.
- Temporary render-surface debugging owner removed in `howl-linux-host` commit `58acf28`.
- Verification status: passed during accepted host/root commits.
