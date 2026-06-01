# Alacritty Display/Renderer/Window Shape Cache

Date: 2026-06-01.
Role: Researcher.
Task: source-backed owner cache for the Linux host display/render/window sprint. No product code edited.

## Sources Read In Order

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/gles2.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glsl3.rs`
- Current Howl paths listed under Current-Code Facts.

## TigerBeetle/Howl Law Loaded

- TigerStyle says safety/performance/developer experience are the style goals, in that order, and style is design, not surface readability (`TIGER_STYLE.md:14-23`).
- TigerStyle requires simple explicit control flow, bounds on loops/queues, and assertions for arguments/invariants (`TIGER_STYLE.md:90-113`).
- TigerStyle says variables belong at smallest possible scope, control flow/state mutation should be centralized, and leaf helpers should not own policy (`TIGER_STYLE.md:158-175`).
- TigerStyle naming requires exact nouns/verbs and warns against overloaded names (`TIGER_STYLE.md:273-289`, `TIGER_STYLE.md:337-347`).
- TigerBeetle architecture describes explicit upper bounds as the source of static allocation/backpressure (`ARCHITECTURE.md:189-222`).
- Howl product law says hosts own platform UX, event loops, wake policy, presentation cadence, runtime orchestration, and backend resource realization (`AGENTS.md:12-18`, `AGENTS.md:128-136`).
- Howl product law says window chrome must not own render-surface consumption, backend resource realization, GL texture ownership, presentation pacing, or render policy (`AGENTS.md:16-18`).
- Alacritty is the source of truth for host runtime, display, window, input, presentation, and most renderer organization unless it directly fights the C ABI or embeddable render boundary (`AGENTS.md:21-43`, `loop.txt:22-50`).
- Researcher role returns cache evidence only, not implementation or scratchpads (`AGENTS.md:90-98`, `loop.txt:97-105`).

## Alacritty Facts

### Display Boundary

- `display/mod.rs` documents the display subsystem as including window management, font rasterization, and GPU drawing (`display/mod.rs:1-2`).
- The `display` module exports `color`, `content`, `cursor`, `hint`, and `window`, while keeping `bell`, `damage`, and `meter` private (`display/mod.rs:60-68`).
- `Display` is documented as wrapping a window, font rasterizer, and GPU renderer (`display/mod.rs:341-342`).
- `Display` fields include `window: Window`, `size_info`, `pending_update`, `pending_renderer_update`, `frame_timer`, `damage_tracker`, `renderer`, `surface`, `context`, and `glyph_cache` (`display/mod.rs:341-400`).
- `Display::new` creates the GL surface, makes the GL context current, creates `Renderer`, initializes glyph cache, resizes/clears renderer, swaps once for non-Wayland, sets resize increments, shows the window, initializes damage tracking, and configures swap interval (`display/mod.rs:402-517`).
- `Display` owns context-loss recovery: it recreates the GL context and `Renderer`, resizes, resets glyph cache, and marks full damage (`display/mod.rs:550-605`).
- `Display::swap_buffers` chooses Wayland damage-aware swap or normal `surface.swap_buffers(context)` (`display/mod.rs:607-623`).
- `Display::handle_update` is explicitly forbidden from OpenGL work; renderer updates are deferred (`display/mod.rs:647-650`).
- `Display::process_renderer_update` applies surface resize, makes the GL context current, clears font cache, and resizes the renderer immediately before drawing (`display/mod.rs:739-768`).
- `Display::draw` collects `RenderableContent`, drains cells, handles terminal damage, makes the GL context current, clears the renderer, draws cells, draws rects/UI overlays, calls `pre_present_notify`, swaps buffers, finishes on X11, schedules the next frame, and swaps damage (`display/mod.rs:770-1047`).
- `Display::request_frame` derives a vblank interval from the monitor refresh rate and schedules `EventType::Frame` through the scheduler (`display/mod.rs:1439-1458`).
- `Display::drop` makes the GL context current before dropping renderer/context/surface (`display/mod.rs:1461-1471`).
- `RendererUpdate` exists because platform-specific resize/OpenGL operations must be applied just before rendering to avoid buffer locking and flicker (`display/mod.rs:1543-1554`).
- `FrameTimer` computes frame pacing state from timestamps and refresh intervals (`display/mod.rs:1556-1601`).

### Window Boundary

- Alacritty's window file is `display/window.rs`, not a top-level `window/` folder (`display/mod.rs:60-65`, `display/window.rs:1-48`).
- `Window` is documented as a wrapper around the underlying windowing library providing a stable API (`display/window.rs:100-103`).
- `Window` fields are windowing/chrome/input integration state: `has_frame`, `scale_factor`, `requested_redraw`, `hold`, underlying `WinitWindow`, title, X11 flag, cursor, mouse visibility, and IME inhibitor (`display/window.rs:100-125`).
- `Window::new` builds platform `WindowAttributes`, applies title/theme/visibility/transparency/blur/maximized/fullscreen/window level, creates the window, configures cursor, IME, transparency, scale factor, icon/visual/embed/platform attributes, and returns a `Window` (`display/window.rs:127-218`).
- `Window` exposes raw handle, size, visibility, title, redraw request, cursor state, window attributes, urgency, id, transparency, blur, maximize/minimize/fullscreen, resize increments, monitor, IME inhibitor, and IME position (`display/window.rs:220-468`).
- `Window::pre_present_notify` only informs the windowing system right before presentation; it does not swap buffers or own render policy (`display/window.rs:401-406`).
- `Window` owns platform-specific chrome decorations through `get_platform_window`, including X11 names/icons/decorations, Windows icons/decorations, and macOS titlebar modes (`display/window.rs:288-359`).
- Mac-specific `set_has_shadow` manipulates the platform view/window shadow, which is chrome/window integration (`display/window.rs:470-484`).

### Renderable Content

- `RenderableContent` is the object that turns terminal state into renderable cursor and non-empty cells (`display/content.rs:24-38`).
- `RenderableContent::new` derives search matches, terminal renderable content, cursor shape, viewport cursor point, hints, colors, and size from `Display` plus terminal state (`display/content.rs:40-88`).
- Its iterator skips empty cells and wide-char spacers, applies cursor rendering, and returns `RenderableCell` items (`display/content.rs:153-185`).
- `RenderableCell` contains character, point, foreground/background, alpha, underline, flags, and optional extra storage for zero-width and hyperlink fields (`display/content.rs:187-207`).
- `RenderableCursor` stores shape, cursor color, text color, width, and point (`display/content.rs:399-445`).

### Renderer Boundary

- `renderer/mod.rs` exports `platform` and `rects`, keeps `shader` and `text` private, and re-exports `GlyphCache`/`LoaderApi` from text (`renderer/mod.rs:26-34`).
- `Renderer` contains a `TextRendererProvider`, `RectRenderer`, and robustness flag (`renderer/mod.rs:82-93`).
- `Renderer::new` loads GL functions after context current, queries GL strings, chooses GLES2 vs GLSL3 text renderer, creates `RectRenderer`, and enables GL debug logging (`renderer/mod.rs:114-175`).
- `Renderer::draw_cells` delegates to the selected text renderer (`renderer/mod.rs:177-191`).
- `Renderer::draw_string` builds temporary `RenderableCell`s and delegates to `draw_cells` (`renderer/mod.rs:193-230`).
- `Renderer::draw_rects` prepares GL state, draws rects through `RectRenderer`, restores blending and viewport (`renderer/mod.rs:242-265`).
- `Renderer::clear`, `was_context_reset`, `finish`, `set_viewport`, and `resize` own GL renderer operations (`renderer/mod.rs:267-349`).
- Text rendering owns `TextRenderer`, `TextRenderBatch`, `TextRenderApi`, `TextShader`, and `LoaderApi` concepts (`renderer/text/mod.rs:49-197`).
- Text rendering flushes batches when the texture changes or the batch fills (`renderer/text/mod.rs:111-132`).
- `update_projection` checks width/height against padding bounds before computing projection uniforms (`renderer/text/mod.rs:199-221`).

### Texture, Atlas, Glyph, Quad, Rect Drawing

- Alacritty does not have a generic `terminal/texture/texture` owner. Texture ownership appears under renderer text atlas and renderer rect/text batches.
- `Atlas` manages a single texture atlas and explicitly stores `id`, dimensions, row packing fields, and GLES context flag (`renderer/text/atlas.rs:14-61`).
- `Atlas::new` creates the GL texture, allocates an RGBA texture, sets clamp/linear parameters, and unbinds (`renderer/text/atlas.rs:72-110`).
- `Atlas::insert` checks glyph dimensions, row room, advances row if needed, and returns either inserted glyph or a full/too-large error (`renderer/text/atlas.rs:118-140`).
- `Atlas::insert_inner` uploads glyph pixels with `glTexSubImage2D`, updates row extent/tallest, and computes glyph UV coordinates (`renderer/text/atlas.rs:142-222`).
- `Atlas::load_glyph` creates a new atlas when full and recurses only after advancing to a new atlas (`renderer/text/atlas.rs:247-287`).
- `Atlas::drop` deletes the GL texture (`renderer/text/atlas.rs:298-304`).
- GLES2 text renderer owns GL buffers, atlas vector, batch, current atlas, active texture, and blending mode (`renderer/text/gles2.rs:26-37`).
- GLES2 setup creates VAO/EBO/VBO, precomputes quad indices, enables attributes, initializes one `Atlas`, and creates `Batch` (`renderer/text/gles2.rs:55-157`).
- GLES2 `Batch` is bounded by `BATCH_MAX`, the largest `u16`-indexable multiple of 4, and stores text vertices (`renderer/text/gles2.rs:221-231`).
- GLES2 `Batch::add_item` pushes four vertices per glyph/cell quad with cell coords, glyph coords, UVs, foreground/background colors, and flags (`renderer/text/gles2.rs:275-336`).
- GLES2 `RenderApi::render_batch` uploads batch vertices, binds texture if changed, draws background and text passes with `glDrawElements`, then clears the batch (`renderer/text/gles2.rs:372-423`).
- GLSL3 text renderer owns shader program, VAO/EBO/VBO instance, atlas vector, current atlas, active texture, and batch (`renderer/text/glsl3.rs:29-39`).
- GLSL3 setup stores a single quad index buffer and uses per-instance data for glyph quads (`renderer/text/glsl3.rs:50-144`).
- GLSL3 `RenderApi::render_batch` uploads instances, binds texture if needed, and draws two instanced passes (`renderer/text/glsl3.rs:223-260`).
- GLSL3 `Batch` stores one `InstanceData` per rendered glyph/cell, not raw immediate-mode quads (`renderer/text/glsl3.rs:282-403`).
- Rect rendering owns `RenderRect`, `RenderLine`, `RenderLines`, `RectRenderer`, `RectShaderProgram`, and `Vertex` (`renderer/rects.rs:19-28`, `renderer/rects.rs:36-52`, `renderer/rects.rs:158-162`, `renderer/rects.rs:233-255`, `renderer/rects.rs:409-435`).
- `RectRenderer::new` creates VAO/VBO and shader programs for normal, undercurl, dotted, and dashed rects (`renderer/rects.rs:257-318`).
- `RectRenderer::draw` groups rect vertices by kind, uploads vertex data, and draws triangles with `glDrawArrays` (`renderer/rects.rs:320-370`).
- `RectRenderer::add_rect` converts rects to NDC, builds a four-vertex quad, then appends six vertices for two triangles (`renderer/rects.rs:372-397`).
- Alacritty's quad drawing is retained/batched GL buffer drawing, not immediate-mode `glBegin(GL_QUADS)`.

### Window Context/Event/PRESENTATION

- `WindowContext` is documented as the event context for one individual Alacritty window (`window_context.rs:47-70`).
- `WindowContext::initial` bootstraps GL display/config before creating the window on non-Windows, creates the GL context, creates `Display`, and constructs the terminal window context (`window_context.rs:72-119`).
- `WindowContext::additional` creates additional windows using the existing GL config/display, then creates `Display` (`window_context.rs:121-166`).
- `WindowContext::new` creates terminal state, PTY, PTY IO thread, event proxy, notifier, and the per-window context state (`window_context.rs:168-258`).
- `WindowContext::draw` clears requested redraw, skips occluded windows, processes pending renderer updates, handles visual bell redraw, locks terminal, and calls `display.draw` (`window_context.rs:365-398`).
- `WindowContext::handle_event` queues events, processes queued events through input processor, submits display updates, updates hint highlights, and requests redraw when dirty and frame-eligible (`window_context.rs:400-494`).
- `Processor` stores `windows: HashMap<WindowId, WindowContext>` and a shared GL config (`event.rs:83-101`).
- `Processor::create_initial_window` creates the first `WindowContext`, stores `gl_config` from `display.gl_context().config()`, and inserts the window (`event.rs:147-166`).
- `Processor::create_window` creates additional windows from the stored GL config (`event.rs:169-194`).
- On redraw events, `Processor::window_event` delegates event handling then calls `window_context.draw` for redraw (`event.rs:249-283`).
- Before creating a new window, `Processor::user_event` makes all existing displays not current to avoid backing-buffer lock issues (`event.rs:372-380`).
- `EventType::Frame` marks a window frame-eligible and requests redraw if dirty (`event.rs:443-449`).
- `about_to_wait` dispatches `AboutToWait` to every window then updates scheduler/control flow (`event.rs:466-490`).
- `exiting` clears windows before terminating EGL display so renderer/context destructors run first (`event.rs:492-511`).

## Current-Code Facts

- `howl-linux-host/src/terminal/texture.zig` is not a namespace; it owns `RenderResourceTextures`, GL texture creation/upload/retire, diagnostics, failure buckets, GL state samples, and render-surface validation (`terminal/texture.zig:1-112`, `terminal/texture.zig:140-204`, `terminal/texture.zig:212-281`, `terminal/texture.zig:362-400`).
- `howl-linux-host/src/terminal/texture/texture.zig` owns immediate-mode textured rectangle drawing and `SDL_GL_SwapWindow` (`terminal/texture/texture.zig:1-60`). This has no matching Alacritty owner shape.
- `howl-linux-host/src/terminal/texture/pacing.zig` owns frame/present pacing state and tests (`terminal/texture/pacing.zig:1-151`, `terminal/texture/pacing.zig:153-330`). Alacritty places comparable frame timing in `Display::frame_timer` and schedules frame events from `Display::request_frame` (`display/mod.rs:379-383`, `display/mod.rs:1439-1458`, `display/mod.rs:1556-1601`).
- `howl-linux-host/src/terminal/texture/present.zig` owns SDL GL context creation, window presentation, tab cache texture, proof capture, cached tab-bar drawing, terminal texture draw, scrollbar drawing, and swap (`terminal/texture/present.zig:65-180`, `terminal/texture/present.zig:283-343`, `terminal/texture/present.zig:388-547`). Alacritty places GL context/surface/renderer/presentation under `Display`, not window chrome (`display/mod.rs:391-400`, `display/mod.rs:428-439`, `display/mod.rs:1019-1047`).
- `howl-linux-host/src/window/window.zig` currently imports `layout.zig` and `present.zig`, aliases present types, owns `PresentState`, creates/destroys SDL window, initializes/deinitializes present, submits presents, drains present completion, deletes textures, clipboard, cursor, and URL opening (`window/window.zig:1-83`, `window/window.zig:84-206`, `window/window.zig:214-301`). This exceeds Alacritty's `display/window.rs` wrapper boundary.
- `howl-linux-host/src/window/draw.zig` draws tab bars, glyph labels, scrollbars, and solid rects through immediate-mode GL (`window/draw.zig:1-104`). Alacritty places rect drawing under `renderer/rects.rs`, not window chrome (`renderer/rects.rs:19-28`, `renderer/rects.rs:247-255`, `renderer/rects.rs:320-397`).
- `howl-linux-host/src/window/layout.zig` owns `Rect`, `ScrollbarLayout`, `Frame`, and event coordinate translation (`window/layout.zig:1-51`). Alacritty places terminal `SizeInfo` in display and renderable geometry in display/renderer, while `Window` only exposes sizes and window operations (`display/mod.rs:143-301`, `display/window.rs:220-239`).
- `howl-linux-host/src/window/scrollbar.zig` owns scrollbar model/view/mouse/layout behavior and tests (`window/scrollbar.zig:1-275`). Alacritty has no standalone window-chrome scrollbar owner in the specified references; terminal scroll/selection is handled through event/input/display concepts.
- `howl-linux-host/src/window/icon.zig` applies the window icon through SDL/stb image (`window/icon.zig:1-47`). This maps to window/chrome setup in Alacritty's `Window::get_platform_window` icon/decorations path (`display/window.rs:288-359`).
- `howl-linux-host/src/terminal/context.zig` imports `../window/window.zig`, `../window/layout.zig`, and `../window/term_texture.zig`; `window/term_texture.zig` was not present in the workspace glob, while `terminal/texture.zig` exists (`terminal/context.zig:4-6`; current grep found no `howl-linux-host/src/window/term_texture.zig`). This is a planning blocker or dirty-tree state to reconcile before implementation.
- `Context` owns terminal lifecycle, PTY/VT/render handles, render-surface texture realization, surface submit diagnostics, input, event loop, geometry, focus, scrollbar, links, selection, cursor blink, render turn, submit/complete present ACKs, and host upload backend (`terminal/context.zig:54-109`, `terminal/context.zig:394-431`, `terminal/context.zig:587-804`). This partially overlaps Alacritty `WindowContext`, but host-side GL rendering still should map to Display/Renderer concepts.
- `howl-render/src/libhowl_render.zig` is a pure namespace/export root: it imports FFI owner files and exports ABI functions in comptime, with no owner state (`libhowl_render.zig:1-39`). The requested `howl-linux-host/src/terminal/texture.zig` namespace-only shape is consistent with this exact Howl namespace precedent.

## Direct Answers

### 1. Relevant Alacritty Concepts/Folders/Files/Symbols

- Window chrome/windowing wrapper: `display/window.rs`, `Window`, `Window::new`, `Window::get_platform_window`, title/cursor/IME/decorations/fullscreen/visibility/size APIs (`display/window.rs:100-125`, `display/window.rs:127-218`, `display/window.rs:288-359`).
- Display owner: `display/mod.rs`, `Display`, `SizeInfo`, `DisplayUpdate`, `RendererUpdate`, `FrameTimer`, `Ime`, `Preedit` (`display/mod.rs:143-339`, `display/mod.rs:341-400`, `display/mod.rs:1543-1601`).
- Renderable content: `display/content.rs`, `RenderableContent`, `RenderableCell`, `RenderableCursor` (`display/content.rs:24-38`, `display/content.rs:187-207`, `display/content.rs:399-445`).
- Renderer owner: `renderer/mod.rs`, `Renderer`, `TextRendererProvider`, `Renderer::new`, `draw_cells`, `draw_rects`, `clear`, `resize`, `finish` (`renderer/mod.rs:82-93`, `renderer/mod.rs:114-175`, `renderer/mod.rs:177-265`, `renderer/mod.rs:267-349`).
- Texture/atlas owner: `renderer/text/atlas.rs`, `Atlas`, `Atlas::new`, `insert`, `load_glyph`, `Drop` (`renderer/text/atlas.rs:14-61`, `renderer/text/atlas.rs:72-140`, `renderer/text/atlas.rs:247-304`).
- Text batching: `renderer/text/gles2.rs` and `renderer/text/glsl3.rs`, `Batch`, `RenderApi`, `TextVertex`, `InstanceData` (`renderer/text/gles2.rs:221-231`, `renderer/text/gles2.rs:275-423`, `renderer/text/glsl3.rs:209-403`).
- Quad/rect drawing: `renderer/rects.rs`, `RenderRect`, `RenderLine`, `RenderLines`, `RectRenderer`, `RectShaderProgram`, `RectRenderer::add_rect` (`renderer/rects.rs:19-28`, `renderer/rects.rs:36-52`, `renderer/rects.rs:158-162`, `renderer/rects.rs:247-255`, `renderer/rects.rs:372-397`).
- Per-window orchestration: `window_context.rs`, `WindowContext`, `initial`, `additional`, `new`, `draw`, `handle_event` (`window_context.rs:47-70`, `window_context.rs:72-166`, `window_context.rs:168-258`, `window_context.rs:365-494`).
- Runtime/event orchestration: `event.rs`, `Processor`, `EventType::Frame`, `ApplicationHandler` callbacks (`event.rs:83-101`, `event.rs:147-206`, `event.rs:230-283`, `event.rs:443-490`).

### 2. Alacritty Owners Howl Should Map To For Host-Side Render-Surface Consumption

- Primary owner: Alacritty `Display`. It owns GL context/surface, renderer, glyph cache, damage tracker, frame timer, and presentation (`display/mod.rs:341-400`, `display/mod.rs:428-439`, `display/mod.rs:739-768`, `display/mod.rs:770-1047`).
- Backend draw owner: Alacritty `Renderer` plus `renderer/text/*` and `renderer/rects.rs`. It owns GL draw resources, texture atlases, batches, rect drawing, shader programs, viewport, clear, finish, and resize (`renderer/mod.rs:82-93`, `renderer/mod.rs:114-175`, `renderer/text/atlas.rs:14-61`, `renderer/rects.rs:247-255`).
- Per-terminal coordinator: Alacritty `WindowContext`. It owns when to draw a window, per-window terminal state, and event batching, but delegates actual presentation to `Display` (`window_context.rs:47-70`, `window_context.rs:365-398`, `window_context.rs:400-494`).
- Non-owner for host-side render-surface consumption: Alacritty `Window`. It wraps the windowing library and exposes chrome/window operations only (`display/window.rs:100-125`, `display/window.rs:220-468`).

For Howl, host-side render-surface consumption should map to a Display/Renderer split, not `window/` and not `terminal/texture/texture.zig`.

### 3. Does Alacritty Match `terminal/texture/texture.zig`?

No.

- Alacritty has no `terminal/texture/texture` concept, folder, or file in the specified source set.
- Its texture concept is the text glyph `Atlas` under `renderer/text/atlas.rs` (`renderer/text/atlas.rs:14-61`).
- Its textured quad concept is represented by GLES2/GLSL3 text batches and GL buffer uploads/draw calls (`renderer/text/gles2.rs:275-423`, `renderer/text/glsl3.rs:223-260`, `renderer/text/glsl3.rs:282-403`).
- Its untextured quad/rect concept is `renderer/rects.rs`, where `add_rect` emits triangles and `RectRenderer::draw` uploads/draws them (`renderer/rects.rs:320-397`).
- Therefore Howl's `terminal/texture/texture.zig` immediate-mode `drawRect`/`drawSubRect` should map to renderer/display backend drawing, probably an owner like `display/renderer/rects.zig` or `display/renderer/surface.zig` if the C ABI render-surface command stream requires a host-specific surface consumer. `display/renderer/surface.zig` is a proof gap because Alacritty does not have an embeddable render-surface ABI equivalent.

### 4. Does Alacritty Have A Window-Only/Chrome Boundary?

Yes, functionally, but its path/name is `display/window.rs`, not `window_chrome/`.

- `display/window.rs` wraps winit and provides a stable window API (`display/window.rs:100-103`).
- It owns window creation attributes, decorations, title, cursor, visibility, fullscreen/maximize/minimize, transparency/blur, IME, resize increments, monitor, raw handles, and platform-specific titlebar/icon/shadow/tab operations (`display/window.rs:127-218`, `display/window.rs:220-468`, `display/window.rs:470-514`).
- It does not own GL context creation, renderer creation, texture atlas, render-surface resource realization, drawing command consumption, swap-buffer policy, or frame pacing. Those are in `Display`, `Renderer`, `WindowContext`, and `Processor` (`display/mod.rs:428-439`, `display/mod.rs:607-623`, `display/mod.rs:739-768`, `display/mod.rs:770-1047`, `window_context.rs:365-398`, `event.rs:443-490`).

Howl user direction says rename `window/` to `window_chrome/`. That exact name is not Alacritty-derived. It is user-directed and should remain a proof gap in planning, but it narrows the boundary in the same direction as Alacritty's `display/window.rs` by preventing render/presentation ownership from living under window chrome.

### 5. Proposed Howl Owner Layout

Source-backed names:

- `howl-linux-host/src/display.zig`: namespace only. Alacritty has `display/mod.rs` as the display module root (`display/mod.rs:60-68`).
- `howl-linux-host/src/display/display.zig`: true owner for host-side display state: SDL GL context, present surface/window association, renderer instance, frame timer/pacer, pending renderer updates, presentation readiness, and swap/present completion. Source-backed by Alacritty `Display` (`display/mod.rs:341-400`, `display/mod.rs:402-517`, `display/mod.rs:607-623`, `display/mod.rs:739-768`, `display/mod.rs:770-1047`, `display/mod.rs:1439-1601`).
- `howl-linux-host/src/display/renderer.zig`: namespace only for host renderer backend. Source-backed by Alacritty `renderer/mod.rs` (`renderer/mod.rs:26-34`).
- `howl-linux-host/src/display/renderer/renderer.zig`: true owner for GL renderer backend state and command submission. Source-backed by Alacritty `Renderer` (`renderer/mod.rs:82-93`, `renderer/mod.rs:114-175`).
- `howl-linux-host/src/display/renderer/rects.zig`: owner for solid rect/quad drawing such as tab bar and scrollbar primitives. Source-backed by Alacritty `renderer/rects.rs` (`renderer/rects.rs:19-28`, `renderer/rects.rs:247-255`, `renderer/rects.rs:320-397`).
- `howl-linux-host/src/display/renderer/atlas.zig`: owner for GL texture resources if the host keeps glyph/sprite atlas-like texture management. Source-backed by Alacritty `renderer/text/atlas.rs` (`renderer/text/atlas.rs:14-61`, `renderer/text/atlas.rs:72-140`, `renderer/text/atlas.rs:247-304`).
- `howl-linux-host/src/display/content.zig`: owner for host-side renderable content adaptation only if Howl needs to adapt C ABI render surfaces into host render commands. Source-backed name from Alacritty `display/content.rs`, but the render-surface ABI adaptation is a Howl-specific proof gap (`display/content.rs:24-38`, `display/content.rs:187-207`).
- `howl-linux-host/src/terminal/context.zig`: remains the per-terminal coordinator analogous to Alacritty `WindowContext`, but must delegate display/render/presentation work to display/renderer owners rather than importing a fake `window/term_texture.zig`/`terminal/texture.zig` owner. Source-backed by `WindowContext` (`window_context.rs:47-70`, `window_context.rs:365-494`).
- `howl-linux-host/src/terminal/texture.zig`: namespace only, structurally like `howl-render/src/libhowl_render.zig`: imports subowners and re-exports/forces references only. This is user-directed and Howl-precedent-backed by `libhowl_render.zig:1-39`, not Alacritty-derived.

User-directed/proof-gap names:

- `howl-linux-host/src/window_chrome.zig`: namespace only for chrome/window wrapper files. `window_chrome` is not Alacritty-derived; Alacritty's name is `display/window.rs`. The user explicitly required this folder rename.
- `howl-linux-host/src/window_chrome/window.zig`: SDL window wrapper only: create/destroy window, title, icon, cursor, clipboard/URL if accepted as platform window integration, size/geometry accessors, focus. Source-backed concept by Alacritty `Window`, but folder/name is user-directed proof gap (`display/window.rs:100-125`, `display/window.rs:127-218`, `display/window.rs:220-468`).
- `howl-linux-host/src/window_chrome/icon.zig`: icon application. Source-backed by Alacritty icon/decorations under `Window::get_platform_window`, but exact file split is Howl-local/user-directed (`display/window.rs:288-359`).
- `howl-linux-host/src/window_chrome/layout.zig`: proof gap unless limited to window chrome geometry only. Current `layout.zig` contains presentation frame layout (`window/layout.zig:20-27`), which maps better to Display/Renderer, not window chrome.

Rejected/probably moved from current locations:

- Move GL context creation, `PresentState`, swap, present proof, tab cache texture, render-surface draw, and frame pacing out of `window/`/`window_chrome/`. Alacritty maps this to `Display`/`Renderer`, not `Window` (`display/mod.rs:402-517`, `display/mod.rs:607-623`, `display/mod.rs:739-768`, `display/mod.rs:770-1047`).
- Move immediate-mode rect drawing out of `window/draw.zig`; it maps to renderer rects (`renderer/rects.rs:320-397`).
- Move `RenderResourceTextures` out of `terminal/texture.zig`; texture/resource realization maps to renderer/display backend. If the C ABI render-surface resource store has no direct Alacritty equivalent, use the smallest host renderer owner and record the proof gap.
- Delete or empty `terminal/texture/texture.zig` as a fake owner after moving its draw/swap responsibilities to renderer/display. Alacritty has no matching owner and does not use immediate-mode `GL_QUADS`.

## Required Tests And Assertions

- Keep one curated `howl-linux-host` test entrypoint. Do not add side-entry test roots; Howl law says test wiring is ownership (`AGENTS.md:158-164`).
- Namespace roots should have no state/mutation tests; test the true owner files reached from the single module test entrypoint.
- Display/presentation tests should preserve and extend existing token/present-completion invariants from `terminal/texture/present.zig` (`terminal/texture/present.zig:616-655`) after owner move.
- Frame pacing tests should move with the display frame timer/pacer owner and keep the invariants around no redraw without frame permit, one completion drain turn, and deadline rounding (`terminal/texture/pacing.zig:153-330`).
- Renderer rect tests should cover NDC conversion and two-triangle quad emission if moved from immediate mode to a buffered shape. Alacritty emits six triangle vertices from four quad corners (`renderer/rects.rs:372-397`).
- Texture/resource realization assertions must retain bounds on resource spans, upload bytes, resource reuse, upload rect fit, and create/upload/retire order (`terminal/texture.zig:212-281`, `terminal/render/retained.zig:243-301`, `terminal/render/retained.zig:303-445`).
- GL context/readiness assertions should stay with Display/Present owner, not window chrome. Existing readiness facts are main thread/current context/current window (`terminal/texture/present.zig:198-224`).
- Window chrome tests should cover title update, icon decode failure tolerance if kept, focus/cursor changes, and geometry accessors only (`window/window.zig:303-342`, `window/icon.zig:33-47`).
- Assertions must enforce that `window_chrome` cannot import display renderer/presentation owners if the rename is intended as a hard boundary. Use grep gates in planning.
- Grep gates for planning: no `glBegin`, `glEnd`, `GL_QUADS`, `SDL_GL_SwapWindow`, `glGenTextures`, `glDeleteTextures`, `PresentState`, or render-surface upload symbols under `window_chrome/`; no mutable owner state in `terminal/texture.zig` namespace root.

## Risks And Proof Gaps

- `window_chrome` is user-directed, not Alacritty-derived. Alacritty's equivalent concept is `display/window.rs`. This is not a direct fight with Alacritty if the boundary is narrowed to chrome/windowing wrapper only, but the exact folder name remains a proof gap.
- Howl's C ABI render-surface consumption has no direct Alacritty equivalent. Alacritty renders terminal state directly through `RenderableContent`; Howl consumes `HowlRenderSurface` from `howl-render`. The smallest acceptable invention is a Display/Renderer backend surface consumer, not a `terminal/texture` or `window_chrome` owner.
- Current imports reference `../window/term_texture.zig`, but no such file was found in the workspace glob. This must be reconciled before planning/worker seeding; otherwise a worker will be forced to guess whether a dirty rename or stale import exists.
- Current `window/window.zig` combines chrome, present, GL function aliasing, texture deletion, and app/platform helpers. Splitting this may touch many imports. Broad movement is source-backed; preserving the current shape for a small diff would preserve wrong ownership.
- Alacritty's renderer is modern buffered GL; current Howl uses compatibility GL 2.1 and immediate mode. If the sprint includes replacing immediate mode, that is a renderer backend slice and must be tested separately. If the sprint only reshapes owners, avoid changing GL behavior beyond moving code.
- Current `window/scrollbar.zig` is not clearly Alacritty-backed as a window chrome owner. It appears to be terminal UI/overlay behavior; likely maps to display content/renderer overlay or terminal context, not window chrome.
- Current `window/layout.zig` contains `Frame` with terminal texture id/rect and scrollbar layout. That is presentation/display layout, not chrome. Only pure window geometry helpers should remain in `window_chrome` if any.

## Stop Conditions For Planning

- Stop if planning requires `window_chrome` to own GL context, GL texture resources, render-surface realization, swap/presentation, frame pacing, or renderer policy.
- Stop if planning proposes a Howl-only owner name where `Display`, `Renderer`, `Window`, `WindowContext`, `RenderableContent`, `Atlas`, `RectRenderer`, or `FrameTimer` has a source-backed mapping.
- Stop if planning keeps `terminal/texture/texture.zig` as an owner for draw/swap because Alacritty has no matching concept.
- Stop if planning changes the C ABI or bypasses `howl-render` with Zig-shaped host conveniences.
- Stop if the missing `window/term_texture.zig` import indicates a dirty/stale tree conflict that changes the intended source paths.

## Readiness Judgment

Ready for orchestrator planning with caveats.

- The source-backed owner direction is strong: Display owns host-side render-surface consumption and presentation; Renderer owns GL draw resources/texture/rect batching; Window/window_chrome owns only window wrapper/chrome.
- The exact `window_chrome` name is user-directed and must be accepted as a proof gap or renamed only after user review. It does not directly fight Alacritty if its contents match Alacritty's `display/window.rs` boundary.
- A worker must not be seeded until the orchestrator resolves the missing `window/term_texture.zig` import and writes exact allowed file moves/import rewrites/tests in `current.txt`.

## Handoff

Next researcher/reviewer should read this cache, the role preload, `AGENTS.md`, `loop.txt`, and the exact current sprint question. Next orchestrator should convert this evidence into a scratchpad and one `current.txt` slice before any product-code edits.
