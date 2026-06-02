# Resize Flow Compared With Alacritty

Date: 2026-06-01.

Role: Research Agent.

Task: Compare Howl's handling and flow of window resize events through terminal geometry, render prepare/submit, host GL texture/resource realization, and presentation against Alacritty's handling of resize/display/renderer flow. Do not implement.

## Sources Read In Order

Required preload:

- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `/home/home/personal/projects/howl/AGENTS.md`
- `/home/home/personal/projects/howl/loop.txt`
- `/home/home/personal/projects/howl/reference-index.md`

Howl source:

- `/home/home/personal/projects/howl/howl-linux-host/src/main.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/event_loop.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/input/input.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/window_chrome/window.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/display/display.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/display/layout.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/surface_layout.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/app/present.zig`
- `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
- `/home/home/personal/projects/howl/howl-render/src/source/prepare_request.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/submit.zig`
- `/home/home/personal/projects/howl/howl-render/src/render/geometry.zig`
- `/home/home/personal/projects/howl/howl-render/src/ffi/surface_geometry.zig`

Alacritty source:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs`

## Howl Exact Flow

- SDL events are drained in bounded turns by `EventLoop.State.pumpInput`, with `max_sdl_events_per_turn = 256` at `howl-linux-host/src/event_loop.zig:7`, polling/waiting at `event_loop.zig:60-100`, and forwarding non-quit events into `Input.processEvent` at `event_loop.zig:103-117`.
- `Input.processEvent` marks `redraw_requested` and `window_geometry_changed` for `SDL_EVENT_WINDOW_RESIZED`, `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED`, and `SDL_EVENT_WINDOW_DISPLAY_CHANGED` at `input/input.zig:251-257`.
- `main.runLoopTurn` pumps window events, applies host mutations, drives terminal runtime, derives redraw/render intent, then renders/submits if frame pacing permits at `main.zig:272-330`.
- Resize is applied inside `applyHostOwnedMutations`: it forwards terminal input first, then calls `applyWindowResize` at `main.zig:463-470`.
- `applyWindowResize` drains the geometry flag, refreshes the window geometry, and resizes all terminals at `main.zig:562-567`.
- `Window.State.refreshGeometry` reads pixel size with `SDL_GetWindowSizeInPixels` and logical size with `SDL_GetWindowSize`, clamps each dimension to at least `1`, stores `px_w/px_h/logical_w/logical_h`, and returns whether geometry changed at `window_chrome/window.zig:49-61` and `window_chrome/window.zig:115-126`.
- `resizeTerminals` computes terminal content pixel and logical sizes after tab-bar subtraction, then calls `tab.resize(px.width, px.height, logical.width, logical.height)` for every tab at `main.zig:803-807`.
- `DisplayLayout.contentPixelSize` uses `window.px_w` and `window.px_h - tabBarHeight`, clamped to at least `1`, at `display/layout.zig:34-39`; `contentLogicalSize` uses logical dimensions at `display/layout.zig:41-46`; `contentRect` uses pixel content size and pixel tab-bar height at `display/layout.zig:48-56`.
- `TerminalContext.resize` delegates to `surface_layout.resize` at `terminal/context.zig:190-192`.
- `surface_layout.resize` stores render px, logical size, and pending grid px under `context.geometry.mutex`, records `last_resize_ns`, and invalidates the scrollbar at `terminal/render/surface_layout.zig:56-78`. It explicitly keeps terminal grid geometry pixel-owned at `surface_layout.zig:71-75`.
- The grid/PTY/VT/render geometry is not committed immediately by `resize`; it is committed lazily during render. `TerminalContext.renderTurn` locks the terminal, computes work, calls `maybePublishSource`, recomputes work, then prepares/submits if needed at `terminal/context.zig:356-381`.
- `maybePublishSource` first calls `maybeCommitGridResizeLocked`, then publishes a VT source only if bootstrap, no render work was pending, or hover publish is pending at `terminal/context.zig:519-525`.
- `maybeCommitGridResizeLocked` commits pending grid px to grid px, snapshots render/grid layout, derives render layout, resizes PTY and VT if grid changed, updates cell pixel size, and calls `term.render.syncSurfaceLayout` at `terminal/render/surface_layout.zig:93-126`.
- `deriveSurfaceLayoutLocked` calls `howl_render_text_session_derive_layout` with `render_px` and `grid_px`, then computes `SurfaceLayout` with `render_px`, `grid_px`, `cols`, `rows`, and `cell_px` at `terminal/render/surface_layout.zig:172-192`.
- `render_retained.State.syncSurfaceLayout` commits layout and calls `howl_render_text_session_sync_geometry`, asserts successful status, matching cell size, and nonzero `geometry_epoch`, then records it at `terminal/render/retained.zig:655-666`.
- In `howl-render`, `surface_geometry.syncGeometry` derives layout again and calls `owner.syncGeometry` at `howl-render/src/ffi/surface_geometry.zig:17-31`.
- `GeometryOwner.sync` increments `geometry_epoch` when render px, grid px, or cell px changes at `howl-render/src/render/geometry.zig:10-30`.
- `TextSessionOwner.syncGeometry` refreshes retained slot views when geometry changes, and resizes reserved slot capacity using derived cols/rows at `howl-render/src/session/text.zig:524-532`.
- Render work state comes from `howl_render_text_session_work_state`, plus host-side present pending and bootstrap state, at `terminal/render/retained.zig:668-678`.
- Render action is selected in `TerminalContext.driveRenderLocked`: present pending blocks, submit pending submits, otherwise prepare or idle at `terminal/context.zig:490-517`.
- Prepare uses `howl_render_text_session_take_prepare_request`, then `howl_render_text_session_prepare_handle`, describes the prepared surface, asserts snapshot/dirty/geometry token equality, publishes/stores the prepared handle at `terminal/render/retained.zig:721-738` and `terminal/render/retained.zig:881-917`.
- The C render session prepares using `TextSessionOwner.prepareHandle`, consuming a prepare request with `self.geometry.prepareLayout(token.geometry_epoch)` at `howl-render/src/session/text.zig:439-459`. `GeometryOwner.prepareLayout` asserts current geometry epoch equals the token at `howl-render/src/render/geometry.zig:33-45`.
- `PreparedSurface` captures request token, geometry epoch, render px, cell px, and grid at `howl-render/src/session/text.zig:187-205`.
- The render surface emitter writes token geometry epoch, render px, cell px, and grid into `HowlRenderSurface` at `howl-render/src/prepared/render_surface_emitter.zig:402-419`.
- Host submit unlocks the terminal mutex, realizes render-surface resource textures, ensures/recreates the terminal host texture, uploads render-surface commands, relocks, verifies the prepared handle is stable, then calls render submit at `terminal/context.zig:724-765`.
- Host texture size matching is computed before `ensureSurface`: `had_matching_surface` is true only if current host texture id is nonzero and its width/height equal prepared render px at `terminal/context.zig:571-573`.
- `ensureSurface` deletes/recreates the GL texture when id/size differs, creates `GL_RGBA` storage with `glTexImage2D`, then records surface width/height at `display/renderer/render_surface.zig:2056-2094`.
- Full sprite/glyph surfaces can upload after texture recreation, but sprite/glyph patch paths require `had_matching_surface` at `terminal/context.zig:614-643`.
- Render-surface resource realization validates spans/order/commands, creates textures, uploads texture rects, retires resources, and tracks failures at `display/renderer/render_surface.zig:119-145` and `display/renderer/render_surface.zig:147-211`.
- Glyph drawing panics if a trusted glyph command references a missing atlas texture slot at `display/renderer/render_surface.zig:2618-2630`.
- Present plan maps `rendered` to `.terminal_frame`, `blocked_present` to `.terminal_retire`, and host redraw with idle/failed steps to `.host_damage` at `app/present.zig:29-35`.
- `AppPresent.submitWith` submits display only for `.host_damage` and `.terminal_frame`; `.none` and `.terminal_retire` do not swap at `app/present.zig:37-52`.
- Terminal present submission records snapshot/token and marks retained present pending only for `.terminal_frame` at `app/present.zig:54-75`.
- Display present synchronously updates tab cache, sets viewport to current framebuffer size, clears, draws cached tab bar, draws terminal texture rect, draws scrollbar, swaps window, then immediately moves submitted token to completed token at `display/display.zig:203-257`.
- Present completion is drained next turn from display, then matched against `pending_terminal_present` before calling `tab.completePresent` at `app/present.zig:77-85`.

## Alacritty Exact Flow

- Winit resize events are not applied directly to GL. `WindowEvent::Resized(size)` ignores zero dimensions, then records `display.pending_update.set_dimensions(size)` at `alacritty/src/event.rs:1958-1967`.
- Scale-factor changes update pending font through `display.pending_update.set_font(...)` at `alacritty/src/event.rs:1945-1957`.
- `DisplayUpdate.set_dimensions` stores dimensions and marks `dirty = true` at `alacritty/src/display/mod.rs:303-328`.
- Window event processing queues events, drains them on `AboutToWait`/`RedrawRequested`, then if `display.pending_update.dirty`, calls `submit_display_update` and marks window dirty at `alacritty/src/window_context.rs:400-473`.
- `submit_display_update` computes cursor/search positions before resize, calls `display.handle_update`, then adjusts search scrolling if needed at `alacritty/src/window_context.rs:529-560`.
- `Display.handle_update` explicitly must not call OpenGL; comment says renderer updates are performed right before drawing at `alacritty/src/display/mod.rs:647-649`.
- `Display.handle_update` takes pending update, updates font/cell size if needed, computes new `SizeInfo`, reserves message/search lines, updates resize increments, then if rows/cols changed, resizes PTY, terminal, and damage tracker at `alacritty/src/display/mod.rs:661-725`.
- `SizeInfo::new` derives `screen_lines` and `columns` from width/height, padding, and cell size, clamped to minimum rows/columns at `alacritty/src/display/mod.rs:229-261`.
- `SizeInfo` implements `TermDimensions` with `columns()` and `screen_lines()` at `alacritty/src/display/mod.rs:286-301`.
- PTY resize is sent through `Notifier.on_resize`, which sends `Msg::Resize(window_size)` at `alacritty_terminal/src/event_loop.rs:350-353`.
- The PTY event loop drains `Msg::Resize` and calls `self.pty.on_resize(window_size)` at `alacritty_terminal/src/event_loop.rs:88-100`.
- Unix PTY resize issues `ioctl(TIOCSWINSZ)` with line/column and pixel dimensions at `alacritty_terminal/src/tty/unix.rs:406-419`.
- `Term::resize` updates grids, inactive grid, selection/tabs, scroll region, vi cursor, and damage on dimension change at `alacritty_terminal/src/term/mod.rs:654-705`.
- If full display size changed, `handle_update` queues `pending_renderer_update.resize = true` and stores `self.size_info = new_size` at `alacritty/src/display/mod.rs:727-737`.
- `WindowContext.draw` forces `display.process_renderer_update()` before `display.draw(...)` at `alacritty/src/window_context.rs:365-397`.
- `Display.process_renderer_update` resizes the platform surface first when requested, makes the GL context current, clears font cache if requested, and calls `renderer.resize(&size_info)` at `alacritty/src/display/mod.rs:739-768`.
- `Renderer.resize` sets the GL viewport and resizes text renderer uniforms/projection at `alacritty/src/renderer/mod.rs:329-349`.
- `Display.draw` collects renderable content, applies terminal damage, drops the terminal lock, makes GL context current, clears, and draws cells using the current `size_info` at `alacritty/src/display/mod.rs:783-879`.

## Divergences Relevant To Repeated `render_surface` Glyph Failures After Resize

- Alacritty has a two-phase resize: non-GL terminal/display state is updated in `handle_update`, while GL surface/renderer resize is deferred to immediately before draw. Howl commits PTY/VT/render geometry inside `renderTurn`, and GL texture realization/recreation happens later inside submit upload. Source: Alacritty `display/mod.rs:647-649`, `display/mod.rs:739-768`; Howl `terminal/context.zig:356-381`, `terminal/context.zig:724-765`.
- Alacritty forces renderer resize before draw every time `pending_renderer_update.resize` is set. Howl can produce a host-damage present with the old terminal texture after a resize if render does not produce a terminal frame. Source: Howl present maps idle + host redraw to `.host_damage` at `app/present.zig:29-35`, submits the tab texture id regardless at `app/present.zig:37-49`, and display draws the texture rect at `display/display.zig:237-248`.
- Howl's resize path updates geometry but does not itself force a full render source. The source classifier decides publication from VT source differences and does not include `geometry_epoch`, render px, grid px, or cell px in `classify`; it returns `.none` for identical publication source before considering rows/cols at `howl-render/src/source/prepare_request.zig:262-284`.
- If a pixel resize changes `render_px`/`geometry_epoch` but preserves cols/rows and VT source content, Howl can classify no source publication, leaving no terminal prepare for the new texture size. Source: geometry epoch changes on render px at `howl-render/src/render/geometry.zig:10-30`; source publication can be suppressed by `samePublicationSource` at `prepare_request.zig:271-276`.
- A later partial glyph frame after the resize can fail host upload if the existing host texture size no longer matches the prepared render size. `had_matching_surface` is computed before `ensureSurface`; glyph patch upload requires `had_matching_surface` at `terminal/context.zig:571-573` and `terminal/context.zig:634-643`.
- When `ensureSurface` sees a size mismatch, it deletes/recreates the host texture at `display/renderer/render_surface.zig:2056-2094`. That is correct for full surfaces, but patch paths intentionally reject upload on a fresh/mismatched texture because they depend on retained previous pixels.
- Full glyph surfaces require the first command to be a full clear at `display/renderer/render_surface.zig:2383-2406`; glyph patch accepts bounded clear/fill/glyph commands without requiring full-surface coverage at `display/renderer/render_surface.zig:2408-2433`.
- Render-surface resource state is retained separately in `RenderResourceTextures`; texture slots survive host surface recreation. A glyph command panics if its atlas resource is missing at `display/renderer/render_surface.zig:2618-2630`, while realization can return false for capacity, invalid ordering, upload bounds, tombstone reuse, unsupported resource, or GL error at `display/renderer/render_surface.zig:119-145`, `display/renderer/render_surface.zig:147-211`, and `display/renderer/render_surface.zig:617-631`.
- Alacritty has no separate host terminal texture with patch rejection on resize in the same shape; it updates viewport/projection before direct draw. Howl's embeddable render surface requires a host texture/resource realization seam, but the resize policy around retained texture validity is Howl-specific and must be explicitly accounted for.

## Source-Backed Owner Boundaries

- Project law: hosts own platform UX, event loops, wake policy, presentation cadence, runtime orchestration, and backend resource realization at `AGENTS.md:12-18` and `AGENTS.md:135-136`.
- Project law: `howl-render` owns render contracts, geometry policy, retained-frame state, prepare/submit scheduling, render-surface contracts, and text shaping at `AGENTS.md:133-134`.
- Project law: `howl-pty` owns PTY resize delivery at `AGENTS.md:130`; `howl-vt` owns terminal state and VT-surface truth at `AGENTS.md:131-132`.
- Project law: hosts depend on C ABIs only; no Zig-shaped host shortcuts at `AGENTS.md:119-126`.
- Howl host currently owns SDL event drain and geometry refresh in `event_loop.zig`, `input.zig`, and `window.zig`; it also owns GL texture realization in `display/renderer/render_surface.zig`.
- Howl `terminal/render/surface_layout.zig` straddles orchestration: it derives render layout through C ABI, delivers PTY/VT resize, and commits render geometry.
- Howl `howl-render` owns geometry epoch and prepare/submit validity through `GeometryOwner`, `TextSessionOwner`, `PrepareRequests`, and retained submitted state.
- Alacritty owner split: event processing records pending display updates; display owns size info, PTY/terminal resize dispatch, and queued renderer update; renderer owns viewport/projection; PTY event loop owns actual ioctl delivery.

## Proof Gaps

- No runtime log was inspected showing the exact repeated failure bucket after resize. This proof gap was
  closed by later resize/render-surface cuts; the temporary diagnostics owner and
  `RenderResourceTextures.Diagnostics` were removed in the metrics/diagnostics cleanup.
- Need a concrete resize case proving cols/rows unchanged while render px changes, followed by suppressed publication. Source permits this, but runtime confirmation needs logs or a test.
- Need to inspect whether SDL emits both `WINDOW_RESIZED` and `WINDOW_PIXEL_SIZE_CHANGED` in the failing environment and whether `refreshGeometry` sees logical-only, pixel-only, or both changes.
- Need to inspect `vt_surface.publishSourceLocked` and source snapshot equality to prove whether resize-only publication is suppressed in the failing path.
- Need to confirm whether failures are glyph patch rejection from `had_matching_surface == false`, missing atlas resource, GL error, or render-surface resource-plan validation.
- Need to confirm whether the failure repeats because retained prepared/source state remains active after backend upload failure or because later frames keep producing partial glyph surfaces.
- Need a test or log proving whether `geometry_epoch` changes without a forced full prepare when cols/rows remain stable.

## Recommended Next Orchestration Slice

- Create a narrow research-to-worker slice focused only on resize invalidation semantics across `surface_layout`, `PrepareRequests.classify`, retained submit, and host texture patch gating.
- The slice should not redesign presentation. It should prove or reject this invariant: any `render_px`, `grid_px`, `cell_px`, or `geometry_epoch` change that invalidates the host terminal texture must force a full terminal render before patch surfaces are accepted.
- Exact files for the slice: `howl-linux-host/src/terminal/render/surface_layout.zig`, `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/display/renderer/render_surface.zig`, `howl-render/src/source/prepare_request.zig`, `howl-render/src/session/text.zig`, `howl-render/src/render/geometry.zig`, plus focused tests through existing module test entrypoints.
- Required evidence before coding: capture a failing resize diagnostic showing `render_surface` shape, `had_matching_surface`, prepared `render_px`, current `term_texture.width/height`, `geometry_epoch`, and resource failure bucket.

## Stop Conditions

- Stop if the proposed fix requires host import of internal `howl-render` Zig modules instead of C ABI.
- Stop if fixing resize requires changing public ABI semantics without an explicit ABI-product slice.
- Stop if the failure bucket is GL/context readiness rather than retained geometry/patch invalidation.
- Stop if rows/cols do change and `classify` already returns full, but failures still repeat; that points away from resize-only damage classification.
- Stop if the slice needs a new runtime/manager/controller layer.
- Stop if tests would need duplicate test roots or weakened existing gates.
