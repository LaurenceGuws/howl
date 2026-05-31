# Howl Render Protocol Sprint

Owner: workspace root.

Status: Phase 2 complete. Contract-draft slice may be promoted. No product code
is authorized by this document yet.

## Purpose

Define `howl-render-protocol` as a first-class Howl product boundary.

The current render boundary lets hosts consume a complete prepared RGBA terminal
surface. That shape is backend-agnostic in the weakest sense, but it hides the
real render consequences behind a full CPU surface. Under `rain`, that design
forces full-surface composition and upload work instead of retained, damaged,
batched render work.

This sprint exists to decide and then implement the real boundary, even if that
means deleting large parts of the current renderer shape.

## Non-Negotiable Rule

No fake progress.

The orchestrator owns context and accountability only:

- write scratchpads
- promote one slice to `current.txt`
- seed narrow researchers/workers/reviewers
- reject weak output
- commit accepted slices only when the workflow calls for it

The orchestrator must not keep researching in-session until context evaporates.
Facts go into this scratchpad. Subagents receive exact questions, exact paths,
and exact expected outputs.

## Dirty State At Sprint Start

Root:

- `howl-linux-host` submodule dirty.

`howl-linux-host` dirty files at sprint start:

- `assets/default_config/init.lua`
- `build.zig`
- `src/cli/args.zig`
- `src/main.zig`
- `src/test/test_entry.zig`
- `src/window/pacing.zig`
- untracked `src/app/process_accounting.zig`

`howl-render` is clean at sprint start.

Dirty host work is measurement/pacing/config work from the `rain` performance
investigation. It must not be mixed with render-protocol implementation. Before
any render product code changes, the host dirty state must be accepted and
committed, explicitly set aside, or otherwise resolved by a dedicated slice.

Checkpoint verification performed 2026-05-31:

- Removed stale `terminal_drive_coalesced` accounting left over from a rejected
  behavior experiment.
- Host gates passed from `howl-linux-host`:
  - `zig build test --summary all`
  - `zig build -Doptimize=ReleaseFast`
  - `git diff --check`
- Root gates passed from workspace root:
  - `zig build check`
  - `zig build test`
  - `git diff --check`

Checkpoint committed and pushed 2026-05-31:

- `howl-linux-host` `47dbe56` - `host: add process accounting checkpoints`
- root `12f0f01` - `design: seed render protocol sprint`

Phase 0 is complete. Root and `howl-linux-host` were clean after push.

## Phase 1 Research A: Current Howl Render Truth

Status: accepted as current-state research input. Still no implementation slice.

Research Agent A read TigerBeetle style/architecture first, then this scratchpad,
then the current render ABI, render internals, and Linux host consumption path.

Paths read:

- `howl-render/include/howl_render.h`
- `howl-render/src/ffi.zig`
- `howl-render/src/libhowl_render.zig`
- `howl-render/src/ffi/*.zig`
- `howl-render/src/source/*.zig`
- `howl-render/src/prepared/*.zig`
- `howl-render/src/session/text.zig`
- `howl-render/src/text/*.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/window/term_texture.zig`
- `howl-linux-host/src/window/present.zig`

Current ABI call graph facts:

- `howl-render/src/libhowl_render.zig` exports the C ABI declared in
  `howl-render/include/howl_render.h`.
- Host `initTextSession()` calls `howl_render_text_session_init`, font setters,
  and validation in `howl-linux-host/src/terminal/context.zig`.
- `howl-render/src/ffi/text_session.zig:init()` creates `TextSessionOwner`.
- Host VT publication fills `HowlRenderVtSurfaceSlot` and commits
  `HowlRenderVtSurfaceCommit` from `howl-render/include/howl_render.h`.
- `howl-render/src/ffi/vt_surface.zig` maps reserve/commit calls to
  `TextSessionOwner.reserveVtSurfaceSlot()` and
  `TextSessionOwner.commitVtSurface()`.
- Host render turn calls `self.term.render.prepare()` in
  `howl-linux-host/src/terminal/context.zig`.
- `howl-linux-host/src/terminal/render/retained.zig` calls
  `howl_render_text_session_take_prepare_request()` and
  `howl_render_text_session_prepare_handle()`.
- `howl-render/src/ffi/prepare_request.zig:takePrepareRequest()` calls
  `TextSessionOwner.prepare()`.
- `howl-render/src/ffi/prepared_surface.zig:prepareHandle()` calls
  `TextSessionOwner.prepareHandle()`.
- `TextSessionOwner.prepareHandle()` consumes active source, calls
  `TextSession.prepareSurface()`, then creates `prepared_owner.Owner`.
- Host `submitPreparedLocked()` obtains prepared info/buffer, uploads pixels, then
  calls `self.term.render.submit()` in `howl-linux-host/src/terminal/context.zig`.
- `howl-render/src/ffi/submission.zig:submitHandle()` validates the prepared
  handle and calls `Owner.submitOwned()`.
- `howl-render/src/prepared/owner.zig:performSubmit()` calls
  `TextSession.submitSurface()`, retains RGBA pixels, and consumes the owner.

Current ownership facts:

- `TextSessionOwner` owns render session state, geometry, source slot, prepare
  queue, submitted state, prepared handles, font paths, and retained full-surface
  pixels in `howl-render/src/session/text.zig`.
- `TextSession` owns text backend state, mutex, optional `TextFramePreparer`, and
  retained `cell_input_scratch` in `howl-render/src/session/text.zig`.
- `SourceSlot` owns retained source-cell and dirty-row storage in
  `howl-render/src/source/slot.zig`.
- `PrepareRequests` owns pending/active publication state and damage
  classification in `howl-render/src/source/prepare_request.zig`.
- `prepared_owner.Owner` owns prepared handle payload, lifecycle state, copied
  RGBA pixels, required upload count, metrics, and diagnostics in
  `howl-render/src/prepared/owner.zig`.
- Linux host owns GL texture identity through `Context.term_texture` and
  `howl-linux-host/src/window/term_texture.zig`.

Current allocation/copy/upload facts:

- `SourceSlot.ensureCapacity()` allocates cells, dirty rows, dirty start columns,
  and dirty end columns in `howl-render/src/source/slot.zig`.
- `TextSession.ensureCellInputScratchCapacity()` may allocate or grow
  `cell_input_scratch` in `howl-render/src/session/text.zig`.
- `TextFramePreparer.ensureTextPreparer()` may allocate the preparer and ensure
  scratch capacities in `howl-render/src/session/text.zig`.
- `direct_normal.Scratch.reset()` ensures capacities for renderable, missing,
  draw arrays, cursor, and raster requests in `howl-render/src/text/direct_normal.zig`.
- `scene.RetainedScratch.reset()` ensures draw-list capacities in
  `howl-render/src/text/scene.zig`.
- `prepared_buffer.compose()` allocates `width * height * 4` bytes in
  `howl-render/src/prepared/buffer.zig`.
- `prepared_buffer.compose()` seeds a full surface from retained base or clears it,
  then applies clear/background/decoration/sprite/cursor CPU passes.
- `Owner.copySurfaceBuffer()` always stores the composed RGBA pixels on the
  prepared owner in `howl-render/src/prepared/owner.zig`.
- Host obtains `HowlRenderPreparedSurfaceBuffer.rgba_pixels` through retained
  render wrapper `preparedUpload()`.
- `Context.submitPreparedLocked()` converts `rgba_pixels` into a Zig slice and
  calls `term_texture.uploadPreparedBuffer()`.
- `term_texture.uploadPreparedBuffer()` performs one full `glTexSubImage2D()` for
  `surface.width` by `surface.height`.
- `present.submitPresent()` clears framebuffer, draws cached tab bar, draws the
  terminal texture, draws scrollbar, and swaps.

Exact full-surface assumptions:

- `HowlRenderPreparedSurfaceBuffer` exposes only `rgba_pixels` and
  `uploads_committed`; there is no host-visible rect span, command list, upload
  list, or resource lifetime list.
- `prepared_surface.buffer()` returns the owner's full `rgba_pixels` span and
  upload count.
- `prepared_buffer.compose()` computes and allocates `width * height * 4` pixels.
- `seedSurfacePixels()` says hosts only consume one complete prepared surface and
  asserts the retained base and output pixel lengths match.
- `term_texture.uploadPreparedBuffer()` documents that the prepared buffer is the
  complete realized surface and that the host does one full upload rather than
  reconstructing from render-side damage rectangles.
- Submit validation checks host surface width/height and upload count, not rect
  coverage or command/resource lifetime.

Damage facts available but not host-consumed:

- `HowlRenderVtSurfaceSlot` includes `dirty_rows`, `dirty_cols_start`, and
  `dirty_cols_end` in `howl-render/include/howl_render.h`.
- `howl-render/src/source/damage.zig` preserves dirty row spans and the clean-row
  sentinel.
- Damage classification returns `.none`, `.partial`, or `.full` from source dirty
  metadata.
- Prepare tokens carry `damage_base_seq` and `damage_kind`.
- Prepared tokens carry `required_base_seq` and `damage_kind`.
- Text scene has `full_redraw` plus per-draw `first_cell`/`cell_span` facts for
  clear, background, sprite, decoration, and raster requests.
- `scene.normalizedDamage()` and `direct_scene.Damage.init()` preserve valid row
  spans internally.
- Scene builders can skip or draw by damage spans through `includeSpan()`.
- Linux host consumes none of those damage facts as damage; it only uses prepared
  info for dimensions and prepared buffer for full upload.

Tests that currently lock behavior:

- `howl-render/src/prepared/buffer.zig` has `compose preserves retained content
  outside partial updates`.
- `howl-render/src/session/text.zig` has `retainSurfacePixels adopts full pixels
  for later partial prepares`.
- `howl-render/src/prepared/owner.zig` has `owner validates realized uploads and
  host surface dimensions before submit`.
- `howl-render/src/source/damage.zig` tests canonicalization, sentinel
  preservation, and invalid dirty metadata rejection.
- `howl-render/src/source/text_input.zig` tests threading partial damage into text
  scene input and mapping only dirty ranges.
- `howl-render/src/text/scene.zig` tests explicit clears for transparent default
  backgrounds on partial damage.
- `howl-linux-host/src/terminal/render/retained.zig` tests present in-flight
  gating.
- `howl-linux-host/src/window/present.zig` tests monotonic nonzero present tokens
  and single drain behavior.

Minimal safe deletion candidates after protocol replacement proves equivalent:

- Normal-path `HowlRenderPreparedSurfaceBuffer.rgba_pixels` as the only
  host-visible render consequence.
- `howl_render_prepared_surface_buffer()` as the normal-path render output.
- `prepared_buffer.compose()` full CPU composition.
- `Owner.copySurfaceBuffer()` full RGBA retention.
- `term_texture.uploadPreparedBuffer()` full upload path.
- `Context.submitPreparedLocked()` pixel-slice upload block.

These are not safe to delete before a replacement protocol has exact ABI structs,
bounds, lifetime rules, invalid-input behavior, and equivalence tests.

Required assertions and tests for protocol work:

- ABI size/layout tests for every new frame, upload, command, and damage struct,
  following the existing `assertVtCellLayout()` style.
- Bound tests for max damage items, max uploads, max commands, max glyphs per run,
  max retained snapshots, and max atlas/resources.
- Invalid-input tests mirroring current ABI rejection style in
  `prepareTokenIn()` and `preparedSurfaceTokenIn()`.
- Explicit owner/state lifetime tests equivalent in strictness to current prepared
  handle state transitions.
- Software protocol realization equivalence tests against current
  `prepared_buffer.compose()` for full and partial rows before deletion.
- Host consumption tests proving damage/commands/resources are consumed instead
  of silently falling back to full `glTexSubImage2D()`.

Proof gaps after Research A:

- No current host-consumable damage rectangle/span ABI exists.
- No bounded command/upload protocol structs exist in the current header.
- No test proves full-surface upload is absent; current code proves the opposite.
- Current hot path still allocates or grows multiple buffers after init, including
  full `prepared_buffer.compose()` pixels and several scratch buffers.
- The sprint seed was correct about the full-surface boundary, but understated how
  much source/scene damage exists internally before being collapsed into the full
  host-facing surface.

Readiness judgment:

- Not worker-ready for `howl-render-protocol` implementation.
- Current truth is enough to reject the existing normal path as the final protocol
  boundary.
- Worker readiness requires exact C ABI structs, bounds, owner states,
  invalid-input behavior, equivalence tests, and host-consumption tests.

## Current Measurement Facts

Command shape used for measurement after build behavior was corrected:

- From `howl-linux-host`:
  `zig build -Doptimize=ReleaseFast`
- Direct artifact:
  `./zig-out/harness/howl_term_release_fast --command "rain" --duration-ms 3000 --debug-process-accounting --debug-log-every-ms 1000`

Observed facts:

- `howl-main` burns substantial CPU under `rain`.
- `howl-term-host` reports `0` CPU ticks in samples.
- Initial host spin was dominated by main-loop/present/runtime wake coupling.
- Pacing fixes reduced render/present submissions but did not solve perceived
  performance.
- Unsafe terminal-drive coalescing was rejected because it could acknowledge a
  PTY wake without a normal bounded transport pump.
- After rejecting that unsafe behavior, the remaining structural bottleneck is
  the render boundary itself: Howl prepares and uploads a full terminal surface.

## Current Source Facts To Verify

These are preliminary facts and must be verified by Research Agent A before any
implementation slice depends on them.

Current host render consumption path:

- `howl-linux-host/src/terminal/context.zig`
  - `Context.renderTurn()` publishes source, prepares, submits.
  - `submitPreparedLocked()` consumes a prepared upload and calls host texture
    upload.
- `howl-linux-host/src/window/term_texture.zig`
  - `uploadPreparedBuffer()` binds the terminal texture and calls
    `glTexSubImage2D()` for the complete terminal surface.
  - Comment states the current host treats the prepared buffer as the complete
    realized surface.
- `howl-linux-host/src/window/present.zig`
  - present clears framebuffer, draws cached tab bar, draws terminal texture,
    draws scrollbar, swaps.

Current render full-surface path:

- `howl-render/src/prepared/buffer.zig`
  - `compose()` allocates `width * height * 4` bytes.
  - It seeds/clears a full surface and applies clear/background/decoration/
    sprite/cursor passes into CPU memory.
- `howl-render/src/prepared/owner.zig`
  - `copySurfaceBuffer()` stores the composed RGBA pixels on the prepared owner.
- `howl-render/src/ffi/prepared_surface.zig`
  - exposes the prepared surface buffer through the C ABI.

Working conclusion:

- The current normal path is full CPU surface realization plus full texture
  upload.
- Damage exists inside render, but the host-facing consequence is still a full
  surface.
- This is the wrong product boundary for a high-throughput embeddable terminal.

## Reference Scope

### Ghostty First

Use Ghostty first for terminal/render ownership and backend seam pressure.

Required paths:

- `utils/dev_references/terminals/ghostty/src/renderer.zig`
- `utils/dev_references/terminals/ghostty/src/font/Atlas.zig`
- `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig`
- `utils/dev_references/terminals/ghostty/src/font/sprite/draw/special.zig`
- `utils/dev_references/terminals/ghostty/src/Surface.zig`
- `utils/dev_references/terminals/ghostty/src/apprt.zig`

Questions:

- Who owns glyph atlas lifetime?
- Who owns rasterized glyph cache lifetime?
- What is the backend seam?
- Are render commands/resources explicit, or does the backend own direct state?
- Which parts are unsuitable for Howl's C ABI boundary?

### Alacritty Second

Use Alacritty for pragmatic host/display/render organization and performance
posture.

Important line-count correction:

- Full Alacritty checkout: about `33.7k` Rust lines.
- `alacritty/src`: about `20.9k` Rust lines.
- `alacritty_terminal/src`: about `11.7k` Rust lines.
- The three narrow files previously cited are only about `2.7k` lines.

Required paths:

- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/window.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`

Questions:

- How does damage move from terminal state to display damage?
- How are damaged regions shaped for present/swap?
- How are glyphs cached and uploaded?
- What is batched per frame?
- What is never represented as a full CPU terminal framebuffer?
- Which pieces are coupled to OpenGL and must not leak into Howl's protocol?

### TigerBeetle Third

Use TigerBeetle as law for bounds, assertions, ownership, and directness.

Required paths:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Constraints:

- Every protocol list has a fixed bound.
- Every command/resource lifetime has a named owner.
- No hidden allocation in the hot path unless explicitly bounded and justified.
- No generic scene graph.
- No manager/controller/engine owner names.
- No backend convenience import path through Zig internals.
- Tests must encode the ABI contract, not merely exercise happy paths.

## Product Boundary Rules

Howl is a C ABI embeddable terminal.

The render protocol must be consumable by hosts through C ABI contracts. Hosts
own platform UX, event loops, wake policy, presentation cadence, and backend
resource realization. Howl owns the render consequences exposed by the ABI.

Allowed host-visible concepts:

- protocol version
- surface/resource identifiers
- snapshot/frame tokens
- bounded uploads
- bounded commands
- bounded damage
- explicit retirement/acknowledgement
- software fallback output for tests/debug only

Forbidden as normal-path protocol shape:

- opaque full terminal RGBA surface as the only consequence
- unbounded command vectors
- generic scene graph
- backend-specific GL/Metal/Vulkan objects in Howl-owned ABI
- host reaching into Zig render internals
- hidden resource lifetime ownership

## Things That Probably Need To Die

These are not deletion orders yet. They are suspects that must be proved or
disproved by research.

- Full prepared RGBA surface as the normal render ABI output.
- Full `glTexSubImage2D()` terminal texture upload per frame.
- Per-frame full surface allocation in `prepared/buffer.zig`.
- Render-side damage that cannot be consumed by hosts as damage.
- Host texture path that ignores upload rectangles/resources.
- Prepared surface API that only answers “give me pixels”.

## Candidate Protocol V0

V0 should be small enough to implement and test, but real enough to replace the
full-surface normal path.

Candidate top-level object:

```c
typedef struct HowlRenderFrameV0 {
    uint32_t protocol_version;
    HowlRenderSnapshotToken snapshot;
    HowlRenderDamageSpan damage;
    HowlRenderUploadSpan uploads;
    HowlRenderCommandSpan commands;
} HowlRenderFrameV0;
```

Candidate resource types:

- surface
- glyph atlas
- image/sprite atlas
- fallback pixel buffer

Candidate upload types:

- glyph bitmap upload
- sprite/image upload
- dirty pixel rect upload as fallback only

Candidate command types:

- clear rect
- fill rect
- draw glyph run
- draw sprite/image
- copy rect / scroll rect
- set clip or implicit damage clip

Candidate damage types:

- full
- rect list
- row spans
- scroll/copy region

Required bounds:

- max commands per frame
- max uploads per frame
- max damage rects per frame
- max glyphs per glyph run
- max atlas pages/resources
- max retained snapshots in flight

Open question:

- Should V0 expose glyph atlas management directly, or should render own atlas
  packing and expose backend uploads plus draw references?

Bias:

- Render should own shaping, glyph identity, atlas packing decisions, and the
  protocol command list.
- Host/backend should own realizing resource IDs into backend objects and
  executing commands.

## Required Research Agents

### Research Agent A: Current Howl Render Truth

No implementation.

Must read:

- TigerBeetle style and architecture docs first.
- `howl-render/include/howl_render.h`
- `howl-render/src/ffi.zig`
- `howl-render/src/ffi/*.zig`
- `howl-render/src/source/*.zig`
- `howl-render/src/prepared/*.zig`
- `howl-render/src/session/text.zig`
- `howl-render/src/text/*.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/window/term_texture.zig`
- `howl-linux-host/src/window/present.zig`

Return exactly:

- current ABI call graph
- current ownership graph
- current allocation/copy/upload graph
- exact full-surface assumptions
- exact damage facts currently available but not host-consumed
- tests that lock current behavior
- minimal safe deletion candidates
- proof gaps

### Research Agent B: Alacritty Render Model

No implementation.

Must read required Alacritty paths above.

Return exactly:

- damage model
- glyph cache/atlas model
- draw batching model
- frame/present model
- CPU vs GPU division
- boundedness facts
- what maps to Howl protocol
- what must not be copied because it is GL/window-specific

### Research Agent C: Ghostty Render Model

No implementation.

Must read required Ghostty paths above.

Return exactly:

- renderer owner shape
- font atlas owner shape
- shaping/raster owner shape
- backend seam shape
- resource lifetime facts
- what maps better than Alacritty for an embeddable C ABI
- proof gaps

### Research Agent D: Protocol Challenge

No implementation.

Inputs:

- this scratchpad
- Research A/B/C outputs
- TigerBeetle docs

Return exactly:

- strongest argument against `howl-render-protocol`
- strongest argument for it
- minimum viable V0
- over-abstraction risks
- ABI risks
- test strategy
- first worker-ready implementation slice if, and only if, ready

## Phase 1 Research B: Alacritty Render Model

Status: accepted as constraint input. Not a protocol design.

Research Agent B read TigerBeetle style/architecture first, then this scratchpad,
then the assigned Alacritty render/display paths. Additional batching files were
read for concrete batch bounds: `renderer/text/glsl3.rs` and
`renderer/text/gles2.rs`.

Damage model facts:

- `DamageTracker` owns display damage in `alacritty/src/display/damage.rs`.
- It tracks two `FrameDamage` slots and swaps/reset frames through
  `swap_damage()`.
- `FrameDamage` stores `full`, per-terminal-line `LineDamageBounds`, and extra
  viewport `Rect` damage.
- `Display::draw()` imports `TermDamage::Full` or `TermDamage::Partial`, then
  resets terminal damage.
- UI/cursor/selection/IME/hyperlink/timer consequences add damage, sometimes to
  current and next frames.
- `shape_frame_damage()` converts terminal line damage plus viewport damage into
  pixel rectangles.
- `RenderDamageIterator::overdamage()` expands around damaged cells for wide
  characters and clamps to viewport bounds.
- Important constraint: Alacritty damage is primarily present/swap damage.
  `Display::draw()` still collects and draws all renderable non-empty grid cells
  each frame, then uses shaped damage for Wayland damaged swap.

Glyph cache and atlas facts:

- `GlyphCache` owns CPU rasterizer and glyph map in
  `alacritty/src/renderer/text/glyph_cache.rs`.
- `LoadGlyph` is the seam from rasterized glyph to graphics memory.
- `Glyph` contains backend atlas reference data including GL texture id; that is
  not ABI-safe for Howl.
- `GlyphCache::get()` returns cached glyphs, rasterizes misses, handles fallback,
  and inserts into the cache.
- ASCII glyphs and common font styles are preloaded.
- `Atlas` in `alacritty/src/renderer/text/atlas.rs` is GL-coupled: fixed
  `ATLAS_SIZE = 1024`, `GLuint` texture id, `gl::TexImage2D()`,
  `gl::TexSubImage2D()`, and `Vec<Atlas>` growth on full pages.
- Alacritty supports glyph bitmap uploads into retained atlas pages plus draw
  references, not per-frame full terminal RGBA surfaces.

Draw batching facts:

- `TextRenderer::draw_cells()` iterates renderable cells and calls the render API.
- `TextRenderApi::add_render_item()` flushes when texture changes and when batch
  is full.
- GLSL3 has `BATCH_MAX = 0x1_0000` items.
- GLES2 derives `BATCH_MAX` from the `u16` index range.
- Batches upload instance/vertex data and issue GL draws.
- `Renderer::draw_rects()` batches rectangles to prevent excessive program swaps.
- Howl should preserve bounded glyph-run/command batches and resource-change
  boundaries, not Alacritty's direct GL emission.

Frame/present facts:

- `Display::draw()` owns the frame: collect renderable content, import/reset
  damage, release terminal lock, make GL context current, clear, draw text,
  draw rect/cursor/UI, notify pre-present, swap, finish where required, and
  advance damage frames.
- Wayland can use `swap_buffers_with_damage`; other paths use plain swap.
- `Window::pre_present_notify()` and frame timers are display/window concerns.
- Present cadence and platform swap remain host-owned for Howl.

CPU vs GPU division facts:

- CPU computes renderable cells, cursor/colors/selection/search/hints, damage,
  and rasterizes missing glyphs.
- GPU/backend owns atlas texture creation/upload, buffer uploads, draw calls, and
  swap.
- Alacritty does not expose or build a complete CPU RGBA terminal framebuffer on
  the normal paths inspected.

Boundedness facts and warnings:

- Source-backed bounds include atlas page size, glyph-too-large rejection, GLSL3
  batch max, GLES2 batch max, minimum screen size, and damage-line storage sized
  to viewport lines.
- Do not copy Alacritty's unbounded or hot-path allocations into Howl ABI:
  `Vec<RenderableCell>` each frame, unbounded glyph `HashMap`, unbounded atlas
  `Vec<Atlas>`, `shape_frame_damage() -> Vec<Rect>`, and RGB-to-RGBA upload
  conversion allocation.

Howl mapping constraints from Alacritty:

- Expose host-consumable damage regions if Howl wants Alacritty-like damaged
  present.
- Include terminal and non-terminal render consequences in damage where those
  consequences affect visible output.
- Test overdamage and bounds clamping for wide glyphs.
- Render should own glyph identity/rasterization decisions/atlas packing/upload
  data; host-visible references must not be GL ids.
- Atlas/page growth must be bounded in Howl.
- Text draw consequences should be batched by resource identity and explicit max
  item counts.
- Present, frame timers, platform swap, and backend choice are host-owned.

Alacritty facts not to copy:

- GL/window-specific objects: `glutin::surface::Rect`, `GLuint`, GL function
  calls, winit/glutin present hooks.
- Per-frame `Vec<RenderableCell>` collection as an ABI model.
- Unbounded glyph `HashMap` and atlas `Vec<Atlas>` growth.
- Alacritty damage semantics as proof of damage-limited draw work; it still draws
  all renderable grid cells.
- Renderer selection and shader/backend policy.

Required tests from Alacritty branch:

- ABI layout tests for every public damage/upload/command/resource struct.
- Bound tests for max damage, uploads, commands, glyphs per run, atlas pages,
  resources, and retained frames.
- Damage tests for full damage, partial row spans, wide-glyph overdamage, bounds
  clamping, and current/next-frame consequences.
- Glyph/atlas tests for oversized glyphs, atlas full behavior, upload byte/rect
  correctness, and references to retired/nonexistent resources.
- Command tests for batch splitting, valid resource references, overflow failure,
  and resource-change boundaries.
- Lifetime and negative ABI tests for stale tokens, malformed spans, invalid
  counts, null pointers, and invalid dimensions.

Proof gaps from Alacritty branch:

- Alacritty has no C ABI boundary.
- Alacritty does not prove a damage-limited command stream.
- Atlas and glyph cache growth are not TigerBeetle-bounded.
- Alacritty has no host-independent resource ids, protocol token lifetimes, or
  cross-language layout guarantees.

## Phase 1 Research C: Ghostty Render Model

Status: accepted as constraint input. Not a protocol design.

Research Agent C read TigerBeetle style/architecture first, then this scratchpad,
then the assigned Ghostty paths. Additional seam/lifetime paths were read:
`renderer/generic.zig`, `renderer/backend.zig`, `renderer/Thread.zig`,
`renderer/State.zig`, `font/SharedGrid.zig`, `font/SharedGridSet.zig`,
`apprt/embedded.zig`, and `apprt/runtime.zig`.

Renderer owner facts:

- `ghostty/src/renderer.zig` is a public aggregation/root and comptime backend
  selector, not the owner itself.
- The concrete generic owner is `renderer/generic.zig:Renderer(GraphicsAPI)`.
- It owns render configuration, terminal render state, font shaper/cache, image
  state, swap chain, shader pipelines, backend API state, and draw mutex.
- `Surface.zig` owns the renderer instance per surface and deinitializes renderer
  thread/state in order.
- Render update and draw are split: `renderer.Thread.renderCallback()` calls
  `updateFrame()` then `drawFrame(false)`.
- `updateFrame()` extracts terminal state, rebuilds cells, updates image/upload
  state, and ends the shaper frame; `drawFrame()` syncs buffers/textures and
  emits backend render passes.

Font atlas owner facts:

- `font/Atlas.zig:Atlas` owns CPU atlas bytes, packing nodes, format, and
  `modified`/`resized` counters.
- `Atlas.Region` is an extern rectangle with `x`, `y`, `width`, and `height`.
- `Atlas.set()` asserts region bounds, copies bytes into atlas, and increments
  `modified`.
- `Atlas.grow()` reallocates larger atlas data, preserves old bytes, and bumps
  `modified` and `resized`.
- `font/SharedGrid.zig:SharedGrid` owns grayscale/color atlases and glyph cache.
- `SharedGrid.renderGlyph()` chooses atlas by presentation, renders glyphs into
  atlas, grows on `AtlasFull`, and stores atlas coordinates in the glyph cache.
- Backend texture lifetime is renderer-owned per swap-chain frame, not CPU
  atlas-owned.
- `drawFrame()` observes atlas modification counters and syncs atlas data into
  per-frame textures.

Shaping/raster facts:

- `font/shaper/run.zig:TextRun` is valid only for one `Shaper` instance and until
  the next run is created.
- Runs are row-local and never cross rows.
- `RunIterator.next()` trims empty right side, skips invisible cells, and splits
  on selection, style, cursor, font, and ligature boundaries.
- `generic.Renderer.rebuildRow()` uses `font_shaper.runIterator()`, consults
  `font_shaper_cache`, shapes misses, and caches results.
- `SharedGrid.renderGlyph()` owns glyph raster cache insertion into atlas.
- Special sprite drawing functions are render-owned raster/resource production,
  not backend commands or host policy.

Backend seam facts:

- `renderer/backend.zig:Backend` selects OpenGL, Metal, or WebGL by build target.
- `renderer/generic.zig` documents backend abstraction objects such as
  `GraphicsAPI`, `Target`, `Frame`, `RenderPass`, `Pipeline`, `Buffer`, and
  `Texture`; these stay behind the backend seam.
- `apprt.zig` routes library builds to embedded runtime.
- `apprt/embedded.zig` uses host callbacks for wake/action/clipboard/close.
- `Surface.zig` describes a terminal widget independent of window/tab/split
  policy.
- `renderer/Thread.zig` owns Ghostty renderer wakeup, timers, mailbox, and render
  loop; mailbox capacity is fixed at 64.

Resource lifetime facts:

- `Surface` owns per-surface renderer/thread/PTY/input state and stops threads
  before deinit.
- Font grid lifetime is shared/refcounted through `SharedGridSet.ref()` and
  `SharedGridSet.deref()`.
- Font size changes transfer ownership through renderer mailbox and dereference
  old grids on the renderer side.
- Swap chain owns frame states and uses a semaphore to prevent CPU/GPU data races.
- `SwapChain.deinit()` waits for in-flight frames before freeing.
- CPU atlas `modified`/`resized` counters drive backend texture sync.

Howl mapping constraints from Ghostty:

- CPU atlas ownership plus explicit `Region` and modification counters map well
  to render-owned atlas packing and host-visible bounded uploads/resource ids.
- Backend texture/buffer/pass objects must remain host/backend-owned.
- Howl can borrow the split: render produces cells/glyphs/atlas consequences;
  backend realizes buffers/textures/passes.
- Embedded runtime reinforces that event loop, wake policy, platform UX, and
  presentation cadence are host-owned.
- Row-local shaping runs support bounded glyph-run commands better than full
  framebuffer upload.

Ghostty facts not to copy:

- Zig comptime backend selection into the C ABI.
- Ghostty renderer thread/runtime/mailbox ownership into Howl render.
- Hot-path dynamic growth without protocol bounds: atlas node allocation, atlas
  grow, and atlas doubling on full.
- Backend objects such as `Texture`, `Buffer`, `Target`, `RenderPass`, and
  `Pipeline` in Howl ABI.
- Whole-atlas texture replacement as the only upload shape.
- Ghostty `Surface` as a Howl product boundary; Howl keeps PTY, VT, render, and
  host contracts separate.

Required tests from Ghostty branch:

- ABI size/alignment tests for every frame/resource/upload/command/damage struct.
- Bound tests for commands, uploads, damage spans, glyphs per run, atlas pages,
  resources, and retained snapshots.
- Resource create/update/use/retire/ack ordering tests.
- Tests preventing commands from referencing retired or unknown resources.
- Tests preventing double-submit and out-of-order acknowledge.
- Atlas region bounds tests equivalent to `Atlas.set()` assertions.
- Atlas full behavior tests: bounded failure or explicit new-page/resource event,
  never unbounded growth.
- Tests that dirty glyph upload rects are minimal/bounded and host-visible.
- Glyph-run tests proving runs never cross rows and split on style/font/cursor/
  selection boundaries.
- Software reference realizer equivalence tests against current full-surface
  renderer before deleting fallback.

Proof gaps from Ghostty branch:

- Exact backend command structs were not fully inspected.
- `renderer/OpenGL.zig`, `renderer/Metal.zig`, shader buffer structs, full
  `font/shape.zig`, `font/ShaperCache`, concrete shaper backends, and Kitty image
  upload path need deeper proof if the protocol depends on those details.
- Ghostty atlas sync replaces a full atlas region; whether backend implementations
  optimize internally was not proved.
- Worst-case per-frame allocation bounds in shaping/cache paths were not
  established.

Combined Phase 1 readiness:

- A, B, and C are accepted as research input.
- No implementation slice is worker-ready.
- The protocol challenge is now the next required step.
- Strongest shared constraints so far:
  - render owns shaping, glyph identity, atlas packing, command/upload/damage
    consequences, and explicit protocol lifetimes;
  - host owns backend resource realization, event loop, wake policy, presentation
    cadence, platform UX, and swap;
  - C ABI must expose bounded resources, uploads, commands, damage, and lifetimes;
  - no GL/Metal/Vulkan/Zig runtime objects cross the ABI;
  - full CPU RGBA surface is acceptable only as software fallback/test oracle, not
    normal path.

## Phase 2 Research D: Protocol Challenge

Status: accepted. Boundary accepted only as a narrow C ABI consequence protocol.

Research Agent D read TigerBeetle style/architecture first, then this scratchpad,
then spot-checked current full-surface source paths:

- `howl-render/include/howl_render.h`
- `howl-render/src/prepared/buffer.zig`
- `howl-render/src/prepared/owner.zig`
- `howl-linux-host/src/window/term_texture.zig`

Strongest argument against `howl-render-protocol`:

- The protocol can become a premature generic scene graph.
- The candidate V0 list is broad enough to hide backend policy, resource lifetime,
  allocation, and command semantics behind plausible nouns unless one owner and
  one exact lifetime path are named for every resource.
- TigerBeetle rejects unnamed limits, vague ownership, hidden allocation, and
  happy-path-only tests.
- Current code is not merely missing protocol structs; it is architecturally
  full-surface through `prepared_buffer.compose()`, `seedSurfacePixels()`, and
  host `glTexSubImage2D()`.
- If the protocol means “invent a large renderer ABI now,” it is not ready.

Strongest argument for `howl-render-protocol`:

- The existing ABI is the wrong normal product boundary.
- `HowlRenderPreparedSurfaceBuffer` exposes only `rgba_pixels` and
  `uploads_committed`.
- Dirty metadata already exists at VT input through `HowlRenderVtSurfaceSlot`, but
  the host-visible consequence is still a full CPU framebuffer.
- Research A/B/C converge on retained resources, uploads, damage, and draw
  references rather than a full CPU terminal surface.
- The boundary is justified only as a bounded C ABI description of render-owned
  consequences that hosts realize with backend-owned resources.

Minimum viable V0 constraints:

- One frame object with protocol version, snapshot token, render pixel size, cell
  size/grid size, bounded damage span, bounded upload span, bounded command span,
  and bounded retire/ack span if resources are introduced.
- No backend objects: no GL texture ids, Metal objects, Vulkan handles, shader
  handles, command encoders, windows, or swapchains.
- Render owns shaping decisions, glyph identity, atlas packing decisions, upload
  bytes/rects, command stream, protocol resource ids, and lifetime state.
- Host owns backend resource realization, event loop, wake policy, presentation
  cadence, swap/present, and platform UX.
- Bounds must be named before ABI code: max frames/snapshots in flight, max damage
  items per frame, max uploads per frame, max commands per frame, max glyphs per
  glyph run, max upload bytes per frame, and max atlas pages/resources.
- V0 commands should be limited to clear/fill rect, draw glyph run, and draw
  sprite only if current renderer already requires sprite raster consequences.
- No generic node tree, retained scene graph, arbitrary pipeline state, or backend
  object references.
- Full RGBA surface may exist only as software oracle/debug fallback, not normal
  protocol consequence.

ABI risks to resolve in the contract draft:

- Layout drift for every new public struct.
- Span lifetime ambiguity.
- Stale token and out-of-order frame risk.
- Resource id reuse across create/update/use/retire/ack.
- Compatibility trap where `rgba_pixels` remains the only normal consequence.
- Hidden hot-path allocation in command/upload production.

Required test strategy before product code/deletion:

- ABI layout tests for all V0 frame/resource/upload/command/damage structs.
- Bound tests for damage, uploads, commands, glyphs per run, atlas pages/resources,
  retained snapshots, and upload bytes.
- Invalid ABI tests for null pointers, malformed spans, invalid counts, invalid
  dimensions, stale tokens, unknown/retired resources, and out-of-order
  submit/ack.
- Lifetime tests for create/update/use/retire/ack ordering, double-submit
  rejection, use-after-retire rejection, and ack-before-use rejection.
- Damage tests for full, partial row spans, clamping, and wide-glyph overdamage.
- Software reference realizer equivalence tests against current
  `prepared_buffer.compose()` before deleting current behavior.
- Host tests proving V0 upload/command consumption and preventing silent fallback
  to full `glTexSubImage2D()`.

Accepted next slice:

- Ready for contract-draft slice only.
- Not ready for ABI skeleton, product code, host consumer, or full-surface deletion.

Allowed files:

- this scratchpad
- optional `docs/render-protocol-v0.md`

Non-goals:

- no changes to `howl-render/include/howl_render.h`
- no Zig product code
- no host code
- no deletion of `HowlRenderPreparedSurfaceBuffer`
- no replacement of `prepared_buffer.compose()`
- no GL implementation
- no benchmarks or performance claims

Contract-draft invariants:

- V0 is a C ABI protocol, not a Zig internal import path.
- Render owns protocol resources, command/upload/damage production, shaping,
  glyph identity, and atlas packing decisions.
- Host owns backend object realization, event loop, wake policy, presentation
  cadence, platform UX, and swap.
- Every public list has a named fixed maximum.
- Every resource has explicit create/update/use/retire/ack lifetime rules.
- No backend object crosses ABI.
- No generic scene graph.
- Full RGBA surface is fallback/test oracle only, not normal path.
- Deletion of current full-surface behavior is forbidden until equivalence and
  host-consumption tests exist.

Reviewer refinement while drafting:

- Resource creation must be explicit render output, not implicit through first
  upload or command reference.
- Host acknowledgement must be host-to-render input, not a render-produced frame
  span.

Stop before product code if any remain unresolved:

- max counts are unnamed or `TBD`
- resource lifetime lacks create/update/use/retire/ack ordering
- span pointer lifetime is ambiguous
- protocol includes GL/Metal/Vulkan/backend objects
- command model permits arbitrary scene graph behavior
- full RGBA surface remains the only normal host-visible consequence
- tests are not defined before deletion
- software realizer equivalence is skipped
- host fallback to full `glTexSubImage2D()` is not explicitly tested against
- V0 depends on unresolved Ghostty/Alacritty backend proof gaps

## Phase 4 Slice: ABI Skeleton

Status: implementation under review.

Promoted slice:

- `current.txt` - `Render Protocol V0 ABI Skeleton`

Scope:

- Header constants and C structs only.
- Compile-time Zig mirror layout/offset checks only.
- No exported protocol production functions.
- No host code.
- No behavior changes.
- No prepared-surface deletion.

Implemented files:

- `howl-render/include/howl_render.h`
- `howl-render/src/ffi/protocol_v0.zig`
- `howl-render/src/libhowl_render.zig`

Accepted shape facts to verify in review:

- Header constants match `docs/render-protocol-v0.md` exactly.
- Header declares V0 structs from the contract draft.
- `HowlRenderV0Frame` contains damage/create/upload/command/retire spans.
- `HowlRenderV0Frame` does not contain `HowlRenderV0HostAckSpan`.
- `HowlRenderV0HostAckSpan` remains host-to-render input for a later submit/ack
  function slice.
- `ffi/protocol_v0.zig` mirrors the C structs with `extern struct` definitions.
- Compile-time assertions check constant values, struct size/alignment, and field
  offsets.

Verification performed:

- `zig build check`
- `zig build test`
- `git diff --check`

Reviewer rejection fixes applied:

- C V0 typedefs use named struct tags matching the contract draft.
- `ffi/protocol_v0.zig` now uses direct per-struct `assertLayout` and
  `assertOffset` calls instead of a generic field-list helper.
- `zig fmt` was run on `ffi/protocol_v0.zig`.
- Verification was rerun after fixes with the same passing commands above.

Second reviewer rejection fix:

- Restored existing pre-V0 ABI structs to their original anonymous typedef form
  after an over-broad patch accidentally gave them V0 tags.
- Confirmed only V0 structs use `HowlRenderV0*` struct tags.
- Verification was rerun after the header tag fix with the same passing commands
  above.

## Phase 5 Slice: Render Protocol V0 Pre-Realizer Semantics

Status: document-only worker slice implemented. No product code, headers, Zig files,
host files, build files, tests, or software realizer were changed.

Promoted slice:

- `current.txt` - `Render Protocol V0 Pre-Realizer Semantics`

Allowed files:

- `docs/render-protocol-v0.md`
- this scratchpad

Source facts verified for this slice:

- `prepared_buffer.compose()` seeds a complete RGBA surface, then calls
  `composePreparedSurface()` (`prepared/buffer.zig:7-31`).
- `composePreparedSurface()` pass order is clear, background, decoration,
  sprites, then cursor (`prepared/buffer.zig:69-76`).
- Clear/background/decoration/cursor draws all route through `drawSolidRect()`
  and `blendPixel()` (`prepared/buffer.zig:107-145`, `prepared/buffer.zig:273-315`).
- `blendPixel()` uses integer source-over blending with `dst = (src * a + dst *
  (255 - a)) / 255` for RGB and clamps alpha to `255`
  (`prepared/buffer.zig:297-315`).
- Partial surfaces copy the render-owned retained base before command passes,
  preserving bytes outside later draws (`prepared/buffer.zig:78-87`).
- Sprite lookup first checks current raster outputs, then cached atlas rasters,
  and returns `error.MissingSprite` when no raster exists
  (`prepared/buffer.zig:160-188`).
- Sprite alpha mode multiplies draw color alpha by source alpha and blends draw
  color RGB; color mode blends source RGBA bytes directly
  (`prepared/buffer.zig:232-259`).
- Sprite visual bounds offset the destination origin and cap draw width/height;
  zero visual bounds fall back to the draw rect (`prepared/buffer.zig:205-218`).
- Scene assembly emits transparent-background partial dirty-row clears through
  `appendClearDraws()` and `clearColorForSpan()` (`text/scene.zig:803-842`).
- Current V0 header has struct and bound skeletons but lacks numeric V0 kind
  constants for command, damage, resource, and upload fields
  (`howl-render/include/howl_render.h:19-31`, `howl-render/include/howl_render.h:157-287`).

Contract additions made:

- Numeric command kind values:
  `CLEAR_RECT = 1`, `FILL_RECT = 2`, `DRAW_GLYPH_RUN = 3`, `DRAW_SPRITE = 4`.
- `DRAW_GLYPH_RUN` is reserved and invalid until the source-backed glyph atlas
  semantics slice.
- Numeric damage kind values:
  `DAMAGE_RECT = 1`, `DAMAGE_FULL = 2`.
- Numeric resource kind values:
  `GLYPH_ATLAS_ALPHA = 1`, `GLYPH_ATLAS_COLOR = 2`, `SPRITE_ALPHA = 3`,
  `SPRITE_COLOR = 4`, `FALLBACK_RGBA = 5`.
- `GLYPH_ATLAS_ALPHA` and `GLYPH_ATLAS_COLOR` are reserved and invalid until
  the source-backed glyph atlas semantics slice; they are not valid create,
  upload, or command resources for the pre-realizer semantics slice.
- Numeric upload format values:
  `UPLOAD_ALPHA8 = 1`, `UPLOAD_RGBA8 = 2`.
- `color_rgba` packing fixed as `0xRRGGBBAA`.
- Upload validation fixed by resource kind, format, stride, byte count, resource
  bounds, and lifetime state. `UPLOAD_ALPHA8` is valid only for `SPRITE_ALPHA`;
  `UPLOAD_RGBA8` is valid only for `SPRITE_COLOR` and `FALLBACK_RGBA`.
- Command ordering fixed to current `composePreparedSurface()` pass order.
- Clear/fill semantics fixed to current `drawSolidRect()` and `blendPixel()`
  behavior, including clipping, integer blending, and zero-size rejection.
- Sprite alpha/color semantics fixed to current `lookupSprite()` and
  `drawSpriteInstance()` behavior, including missing-resource rejection, visual
  bounds, alpha blending, and color blending.
- Software-equivalence oracle cases selected against `prepared_buffer.compose()`:
  full redraw with background fill and cursor/decoration fill; partial row
  retained-base preservation; partial dirty row clear for transparent
  backgrounds; source-backed alpha sprite blending; source-backed color sprite
  blending.
- Future software-realizer tests now require exact negative inputs and exact
  rejection outcomes: command/damage/resource/upload `kind = 255`, command rect
  `width_px = 0`, command rect `height_px = 0`, span `count = count_max + 1`,
  `UPLOAD_ALPHA8 = 1` to `SPRITE_COLOR = 4`, `UPLOAD_RGBA8 = 2` to
  `SPRITE_ALPHA = 3`, upload to `{ value = 77, generation = 1, kind = 3 }`
  before create, missing sprite command resource `{ value = 78, generation = 1,
  kind = 3 }`, create `{ value = 79, generation = 1, kind = 3 }` then command
  generation `2`, retired `{ value = 80, generation = 1, kind = 3 }` use, color
  sprite command with `color_rgba = 0x01020304`, sprite command with
  `glyphs.count = 1`, fill command with `resource.value = 1`, glyph atlas create
  with `resource.kind = 1`, glyph atlas upload with `resource.kind = 2`, and
  blocked `DRAW_GLYPH_RUN` even with `glyphs.count = 0`.

Unresolved blockers:

- Direct `HOWL_RENDER_V0_COMMAND_DRAW_GLYPH_RUN` is explicitly blocked. Current
  source proves row-local shaping and sprite-backed glyph consequences, but it
  does not yet prove V0 atlas packing, upload bytes, glyph identity, subpixel
  placement, and alpha/color atlas semantics sufficient for a direct glyph-run
  software realizer.
- Glyph atlas resource values remain reserved, not usable. The pre-realizer
  contract now rejects `GLYPH_ATLAS_ALPHA`, `GLYPH_ATLAS_COLOR`, and uploads to
  those resource kinds until the glyph atlas semantics slice is accepted.
- V0 product-code implementation remains not ready. The next safe step is a
  separate source-backed slice that either closes glyph atlas semantics or keeps
  V0 equivalence on sprite commands until direct glyph runs are specified.

## Phase 6 Slice: Limited Software Realizer

Status: accepted by reviewer after rejection fixes.

Promoted slice:

- `current.txt` - `Render Protocol V0 Limited Software Realizer`

Accepted scope:

- Added V0 kind macros to `howl-render/include/howl_render.h`.
- Extended `howl-render/src/ffi/protocol_v0.zig` compile-time macro assertions.
- Added internal-only `howl-render/src/protocol_v0/realize.zig`.
- Imported realizer tests from `howl-render/src/test/unit.zig`.
- Added narrow unit-test C ABI include/link wiring in `howl-render/build.zig` so
  unit tests consume the shipped C ABI through `ffi.zig`.
- No C ABI export functions.
- No host code.
- No protocol emission.
- No prepared-surface deletion.
- No normal-path replacement.

Reviewer rejections fixed:

- Removed duplicated local ABI structs/macros from the realizer.
- Realizer and tests now use `const c = @import("../ffi.zig").c;` and shipped
  `c.HowlRenderV0*` structs/macros.
- Restored the public header to simple `stdint.h`/`stddef.h` includes.
- Added duplicate create/retire rejection.
- Added upload-to-retired and wrong-generation upload rejection.
- Added checked `bytes_count_total` sum validation.
- Rejected nonzero sprite upload rect origins for the limited visual-resource
  realizer.
- Added checked arithmetic for destination coordinate, pixel length, pixel index,
  upload byte minimum, byte totals, and sprite source index.
- Wired tests so `zig build test:unit -- "protocol v0"` exercises the protocol V0
  tests rather than passing with zero discovered tests.

Verification performed:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

## Phase 6 Slice: Render Protocol V0 Limited Software Realizer

Status: implementation in progress.

Accepted implementation facts:

- Public V0 kind macros are now present in `howl-render/include/howl_render.h`
  with the values documented in `docs/render-protocol-v0.md`.
- `howl-render/src/ffi/protocol_v0.zig` asserts every public V0 kind macro at
  compile time alongside the existing bound and layout assertions.
- The limited realizer is internal-only in `howl-render/src/protocol_v0/realize.zig`.
- The limited realizer supports only clear rect, fill rect, alpha sprite, and
  color sprite commands into caller-provided RGBA bytes.
- The realizer allocates no heap memory, adds no C ABI export, touches no host
  code, emits no protocol frames, and does not replace the prepared-surface path.
- Direct `DRAW_GLYPH_RUN` remains blocked. Glyph atlas alpha/color resources are
  rejected for create, upload, and use until a later source-backed atlas slice.

Reviewer rejection fixes applied:

- `protocol_v0/realize.zig` now consumes `HowlRenderV0*` C structs and
  `HOWL_RENDER_V0_*` C macros from the shipped header instead of duplicate local
  public ABI structs/constants.
- The limited sprite realizer rejects nonzero upload rect origins because V0
  visual resources for this slice start at resource-local `(0, 0)`.
- Resource validation now rejects duplicate creates, duplicate retires, uploads
  to retired resources, wrong-generation uploads, upload byte-total mismatches,
  and checked upload byte-total overflow.
- Pixel length, pixel index, upload row bytes, upload byte totals, and sprite
  source indexes use checked arithmetic and reject overflow.
- The realizer now imports C ABI structs and macros through the existing
  `ffi.zig` ABI owner. Destination coordinate additions for fill and sprite
  drawing are checked before clipping.

## Phase 7 Research: Direct Glyph-Run Unblock

Status: research complete. Direct glyph-run implementation is rejected as not
worker-ready. Next slice must be contract-only glyph atlas semantics.

Research agents:

- A: current Howl glyph/shaping/raster truth.
- B: Ghostty glyph atlas/shaping/backend seam.
- C: Alacritty glyph cache/atlas/batching constraints.

Current Howl facts:

- `TextFramePreparer` owns `OwnedAtlasCache`, shaper, sprite rasterizer,
  glyph lookup, glyph raster, and scene scratch.
- Current glyph consequences are sprite-backed, not direct glyph-run-backed:
  `scene.zig` converts glyph groups into `TextSpriteDraw` plus
  `SpriteRasterRequest`, and `prepared/buffer.zig` draws `scene.sprite_draws`.
- `GlyphInstance` includes `face_id`, `glyph_id`, cluster index, offsets, and
  advance. This is internal identity, not a V0-stable ABI glyph identity.
- `OwnedAtlasCache` is a fixed-entry keyed sprite cache. It is not a packed atlas
  page/resource model and does not expose V0 atlas page IDs, rect packing,
  dirty uploads, creates, retires, or host acknowledgement.
- Current sprite key hashes are internal cache keys, not ABI-safe glyph IDs.
- Current placement is consumed during sprite rasterization. Per-glyph placement
  is not preserved as V0 glyph refs.
- Alpha sprite semantics are source-backed. Color glyph/emoji RGBA production is
  not proved by current Howl source.

Ghostty constraints:

- Ghostty proves render-owned CPU atlas packing and backend-owned texture
  realization, but its CPU atlas can grow dynamically and its backend sync path
  uploads whole atlas regions.
- Ghostty glyph identity is not just `glyph_id`; it is tied to font collection
  index, glyph index, render options, cell metrics, and atlas state.
- Ghostty uses grayscale and BGRA atlases. Howl V0 currently names `ALPHA8` and
  `RGBA8`; color byte order must be explicitly chosen and tested.
- Ghostty placement combines grid position, glyph bearings, and shaper offsets.
  A V0 `x_px/y_px` destination is acceptable only if render precomputes final
  pixel placement and tests equivalence for combining marks, ligatures, wide
  glyphs, and clipping.
- Do not copy Ghostty backend objects, comptime backend selection, renderer
  thread/runtime ownership, dynamic atlas growth, or shared font-grid lifetimes
  into Howl ABI.

Alacritty constraints:

- Alacritty glyph cache identity is `GlyphKey { font_key, character, size }`,
  selected from font style and rasterized by the renderer; this is not a Howl ABI
  type.
- Alacritty atlas packing is GL-coupled shelf packing with fixed page size but
  unbounded `Vec<Atlas>` page growth.
- Alacritty normal glyph atlas semantics are RGB/subpixel-mask based in shaders,
  not obviously `ALPHA8`. Multicolor glyphs use RGBA shader paths.
- Alacritty placement is backend/shader-coupled. Howl must define pixel-coordinate
  placement independently.
- Alacritty supports batching and atlas-change flushes, but its GL texture IDs,
  shader state, and direct draw calls must not cross Howl ABI.

Required contract closure before direct glyph-run code:

- Define render-owned glyph identity: what `HowlRenderV0GlyphRef.glyph_id` means
  and what font/config/generation/render options it is bound to.
- Define glyph atlas resource semantics: page size, page count, resource kind,
  generation, create/update/use/retire/ack ordering, reuse rules.
- Define atlas packing: rect allocation, page-full behavior, oversized glyph
  behavior, and whether V0 uploads whole pages or dirty rects.
- Define upload bytes and formats: alpha/coverage, optional RGB/subpixel, color
  byte order, stride/count rules, and invalid pairings.
- Define placement: whether `x_px/y_px` is final destination pixel top-left and
  how bearings, offsets, combining marks, ligatures, and wide cells are encoded.
- Define run splitting: row-local guarantee, atlas resource changes, style/font
  changes, cursor/selection boundaries, and `GLYPHS_PER_RUN_MAX` overflow.
- Define alpha/color draw semantics: color modulation for alpha glyphs, source
  color for color glyphs, and whether color glyphs remain blocked.
- Define equivalence tests against current sprite-backed full-surface output.

Implementation readiness:

- Not ready for product code.
- Ready for a document-only glyph atlas semantics slice.
- Stop if the slice tries to implement glyph-run before the contract above is
  named, bounded, and testable.

## Phase 7 Slice: Render Protocol V0 Glyph Atlas Semantics

Status: document-only worker slice implemented. No product code, headers, Zig files,
host files, build files, tests, or software realizer were changed.

Promoted slice:

- `current.txt` - `Render Protocol V0 Glyph Atlas Semantics`

Allowed files:

- `docs/render-protocol-v0.md`
- this scratchpad

Source facts verified for this slice:

- Current Howl `GlyphInstance` has `face_id`, `glyph_id`, cluster index, offsets,
  and advance, but these are internal shaping facts and not stable V0 ABI glyph
  identities (`text/contract.zig:165-172`).
- Current Howl `RunFont` binds style, presentation, scale, subscale, multicell,
  and alignment (`text/contract.zig:143-152`).
- Current Howl `GlyphGroup` binds first cell, cell span, glyph slice, placement,
  sprite key, and group kind (`text/contract.zig:189-197`).
- Current Howl scene assembly converts glyph groups into sprite draws and raster
  requests, so current product behavior remains sprite-backed rather than direct
  glyph-run-backed (`text/scene.zig:695-727`).
- Current Howl `OwnedAtlasCache` is a fixed-entry sprite cache keyed by
  `SpriteKey`; it does not provide V0 page resources, rect packing, dirty rect
  uploads, create/update/use/retire/ack, or host acknowledgement
  (`text/raster/cache.zig:32-112`).
- Current Howl raster output exposes alpha/color sprite pixels and visual bounds,
  but color glyph/emoji RGBA production is not proved as direct V0 glyph atlas
  semantics (`text/raster/rasterizer.zig:12-30`, `text/raster/rasterizer.zig:149-151`).
- Ghostty `Atlas` proves render-owned CPU atlas bytes, rect reservation, modified
  counters, and atlas-full errors, but it also supports dynamic growth that V0
  must replace with fixed page-count behavior (`font/Atlas.zig:27-51`,
  `font/Atlas.zig:132-210`, `font/Atlas.zig:313-364`).
- Ghostty `SharedGrid` binds glyph cache identity to font collection index, glyph
  index, render options, presentation, and grayscale/color atlas selection; this
  proves `glyph_id` cannot mean a raw font glyph index alone
  (`font/SharedGrid.zig:253-340`, `font/SharedGrid.zig:348-391`).
- Alacritty uses fixed `ATLAS_SIZE = 1024`, explicit full/glyph-too-large errors,
  and atlas-change batching, but its atlas is GL-coupled and grows with an
  unbounded `Vec<Atlas>` that must not cross Howl's C ABI
  (`renderer/text/atlas.rs:11-70`, `renderer/text/atlas.rs:118-140`,
  `renderer/text/atlas.rs:247-287`).
- Alacritty `GlyphCache` adjusts bearings and zero-width glyph placement before
  load, supporting the V0 choice that `x_px/y_px` are final render-computed pixel
  destinations (`renderer/text/glyph_cache.rs:247-269`).

Contract additions made:

- `HowlRenderV0GlyphRef.glyph_id` is now defined as a render-owned protocol
  identity, not a Unicode scalar, host font glyph index, sprite key, cache slot,
  or backend object.
- `glyph_id` is bound to resolved face/font generation, `RunFont` fields,
  shaper/rasterizer feature generation, source glyph index, cell metrics, render
  options that affect pixels, atlas resource generation, and atlas rect.
- Alpha glyph atlas resources are valid V0 resources with fixed page size
  `1024 x 1024`, format `UPLOAD_ALPHA8`, page-count bound
  `HOWL_RENDER_V0_ATLAS_PAGES_MAX = 64`, and global resource bound
  `HOWL_RENDER_V0_RESOURCES_MAX = 4096`.
- Color glyph atlas resources remain blocked. Creates, uploads, and glyph refs
  using `GLYPH_ATLAS_COLOR` must reject until a later color-glyph slice defines
  and tests color byte order, premultiplication/modulation, and emoji constraints.
- Glyph atlas lifetime uses explicit create/update/use/retire/ack/reuse ordering.
  Numeric resource reuse remains forbidden before host ack and greater generation.
- Atlas rect reuse inside an unretired page is invalid. Render must allocate a new
  rect or retire/recreate after ack to replace glyph bytes.
- Atlas packing is render-owned. Rects are resource-local, non-overlapping, within
  `1024 x 1024`, allocated once per page generation, and include a one-pixel zero
  alpha border.
- Page-full behavior is fixed: create a new alpha page only while fewer than 64
  pages are live; otherwise fail closed to the full RGBA oracle/fallback for that
  frame. No dynamic page growth, unbounded page lists, or in-place live eviction.
- Oversized glyph behavior is fixed: if the glyph plus one-pixel border exceeds
  `1024 x 1024`, do not emit a glyph ref and use full RGBA oracle/fallback for
  that frame.
- Newly allocated glyph rect uploads must be dirty-rect uploads. Whole-page
  uploads are valid only for page creation, full page rebuild, or software-oracle
  setup and must obey upload count and byte-count bounds.
- Upload formats are closed: alpha glyph atlas uses `ALPHA8`; RGB, BGR, LCD, and
  subpixel-mask formats are unsupported; `RGBA8` is not valid for alpha glyph
  atlas and full RGBA remains oracle/fallback only.
- `x_px/y_px` are final destination pixel top-left coordinates for the whole
  `atlas_rect`, after render applies row/cell origin, bearings, shaper offsets,
  baseline, combining mark anchors, ligature placement, wide-cell span, and
  visual-bounds trimming.
- Glyph runs are row-local and split on atlas resource, font/style/presentation/
  generation, shaper feature generation, foreground color, cursor/selection/style
  boundaries, ligature boundaries, dirty damage boundaries, and
  `HOWL_RENDER_V0_GLYPHS_PER_RUN_MAX = 256` overflow.
- Alpha glyph draw semantics use `color_rgba` as `0xRRGGBBAA`, multiply color
  alpha by the `ALPHA8` coverage byte, and then use the existing integer
  `blendPixel()` source-over formula. Render must omit zero-alpha glyph refs
  during emission, and validation must reject them. Color glyph drawing remains
  blocked.
- Equivalence tests are now required for alpha glyph atlas draw, final placement,
  combining mark overlap, ligature/wide-cell placement, and run splitting against
  the current sprite-backed full-surface oracle.
- Negative tests are now required for alpha atlas wrong size, color atlas
  create/upload, wrong upload format, stride/count underflow, upload outside page,
  missing/wrong-generation/retired glyph atlas use, empty glyph runs, zero-alpha
  glyph refs, glyph rect outside page, color glyph refs, oversized glyph fallback,
  and atlas-page exhaustion fallback.

Unresolved blockers:

- Direct `HOWL_RENDER_V0_COMMAND_DRAW_GLYPH_RUN` product code remains not ready.
  The exact next worker slice must be source-backed and testable: update the
  limited software realizer to consume alpha glyph atlas resources and add the
  equivalence/negative tests listed in `docs/render-protocol-v0.md`, without
  protocol emission or host code.
- Color glyphs, RGB/BGR/LCD/subpixel uploads, and `GLYPH_ATLAS_COLOR` remain
  explicitly blocked.
- Full RGBA remains oracle/fallback only. It is not product-code readiness and is
  not a normal V0 glyph atlas path.

## Phase 8 Slice: Render Protocol V0 Alpha Glyph Realizer

Status: accepted and committed in `howl-linux-host`.

Promoted slice:

- `current.txt` - `Render Protocol V0 Alpha Glyph Realizer`

Accepted implementation facts:

- `howl-render/src/protocol_v0/realize.zig` now accepts alpha glyph atlas creates
  only for `1024 x 1024` pages with `UPLOAD_ALPHA8`.
- Color glyph atlas creates, uploads, and glyph refs remain blocked.
- Alpha glyph atlas uploads accept dirty rect origins, require matching live
  unretired resources, require `UPLOAD_ALPHA8`, validate stride/count with checked
  arithmetic, and require the upload rect to fit the fixed page.
- `DRAW_GLYPH_RUN` validates zero command rect/resource/color fields, nonempty
  bounded glyph spans, alpha atlas resources, nonzero glyph alpha, page-local
  nonzero atlas rects, destination overlap, and matching upload bytes before any
  caller-visible pixel mutation.
- Alpha glyph realization draws glyph refs in source order, uses final `x_px/y_px`,
  clips destination and source together, computes source alpha as
  `(color_rgba.a * alpha_byte) / 255`, and reuses the existing integer
  source-over blend semantics.
- The realizer remains internal-only, allocates no heap memory during realization,
  emits no protocol frames, changes no host code, changes no headers, and does not
  replace the normal prepared-surface path.

Verification performed:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

## Phase 9 Slice: Render Protocol V0 Internal Emission

Status: rejected and reverted before commit.

Promoted slice:

- `current.txt` - `Render Protocol V0 Internal Emission`

Rejected implementation facts:

- Worker added internal-only `howl-render/src/protocol_v0/emit.zig`, then the
  reviewer rejected the slice before commit.
- The emitter consumes explicit synthetic fixtures for clear, fill, and sprite
  consequences. It does not read host state, backend objects, GL ids, prepared
  owner storage, or direct renderer glyph atlas production.
- Emitted frames use the shipped C ABI structs and macros through `ffi.zig`.
- Emitter-owned storage is fixed-capacity and bounded at comptime against the
  public V0 maxima for damage, creates, uploads, commands, retires, and upload
  bytes. Tests use smaller fixed capacities to force overflow paths.
- Emission is fail-closed by building into a copy of emitter storage and committing
  only after all bounds and upload-byte checks succeed.
- Command emission preserves the current prepared-buffer pass order for supported
  consequences: clear, background fill, decoration fill, sprite, cursor fill.
- Sprite emission creates render-owned V0 sprite resources, copies upload bytes
  into emitter-owned storage, emits uploads before sprite commands, and uses
  resource IDs without backend state.
- Same-frame retire emission was the rejection. `current.txt` required sprite
  resources to use explicit create/upload/use order and same-frame lifetime, but
  the emitter kept retire spans empty. The dead `appendRetire()` path proved the
  current limited software realizer validates retire spans as frame-global state:
  a resource both retired and used in the same frame rejects as
  `RetiredResource`.

Tests added by rejected worker and reverted with the slice:

- `protocol v0 emitter realizes fill pass order equal to oracle`
- `protocol v0 emitter realizes alpha sprite equal to oracle`
- `protocol v0 emitter realizes color sprite equal to oracle`
- `protocol v0 emitter rejects command bound overflow`
- `protocol v0 emitter rejects upload bound overflow`
- `protocol v0 emitter rejects upload byte total overflow`
- `protocol v0 emitter leaves oracle path independent after emission failure`

Prerequisite slice required before retrying emission:

- Define and implement order-sensitive realizer lifetime validation for same-frame
  create/upload/use/retire so temporary sprite resources can be retired after
  their final command in the same frame.

## Phase 10 Slice: Render Protocol V0 Ordered Retire Validation

Status: rejected and reverted before commit.

Promoted slice:

- `current.txt` - `Render Protocol V0 Ordered Retire Validation`

Rejected implementation facts:

- Worker changed `howl-render/src/protocol_v0/realize.zig` to compare
  `HowlRenderV0Retire.retire_seq` with both `HowlRenderV0Upload.upload_seq` and
  zero-based command span indexes.
- Reviewer rejected this because the ABI contract does not define `retire_seq`,
  `upload_seq`, and command order as one shared sequence domain. Commands do not
  have a sequence field, and the docs only say retire happens after final command.
- The tests used naked `retire_seq = 1`, which encoded the implementation's
  undocumented assumption instead of proving a documented contract.
- The implementation was reverted before commit. Correct ordered retire validation
  requires a document-only contract slice defining the sequence domain first.

Verification performed by rejected worker before review:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

## Phase 11 Slice: Render Protocol V0 Retire Order Contract

Status: document-only worker slice implemented. No product code, headers, Zig files,
host files, build files, tests, or protocol emission were changed.

Promoted slice:

- `current.txt` - `Render Protocol V0 Retire Order Contract`

Allowed files:

- `docs/render-protocol-v0.md`
- this scratchpad

Contract decision:

- The existing ABI can express ordered retire validation without a new field.
- `HowlRenderV0Create.create_seq`, `HowlRenderV0Upload.upload_seq`,
  `HowlRenderV0Retire.retire_seq`, and command span indexes now share one
  documented order domain: the zero-based command-boundary index for the owning
  frame.
- Commands have no sequence field because the command sequence is exactly their
  zero-based index in `HowlRenderV0Frame.commands`.
- `create_seq` names the first command boundary where the resource exists.
- `upload_seq` names the first command boundary where upload bytes are visible to
  commands.
- `retire_seq` names the first command boundary where the resource is retired;
  `retire_seq = commands.count` retires after the final command.
- Sequence values greater than `commands.count` are invalid. A same-frame
  temporary resource must satisfy `create_seq <= upload_seq`,
  `upload_seq <= first_use_command_index`, `final_use_command_index < retire_seq`,
  and `retire_seq <= commands.count`.

Test requirements added:

- Positive same-frame create/upload/use/retire with command `0` and
  `retire_seq = 1`.
- Positive late create/upload/use/retire with `create_seq = 1`, `upload_seq = 1`,
  command `1`, and `retire_seq = 2`.
- Negative upload after retire: `upload_seq >= retire_seq`.
- Negative upload before create: `upload_seq < create_seq`.
- Negative command use before create: `command_index < create_seq`.
- Negative command use before upload: `command_index < upload_seq`.
- Negative command use after retire and retire before final command use:
  `command_index >= retire_seq`.
- Negative duplicate retire for the same `{ value, generation, kind }`.
- Negative create sequence outside the frame: `create_seq > commands.count`.
- Negative upload sequence outside the frame: `upload_seq > commands.count`.
- Negative retire sequence outside the frame: `retire_seq > commands.count`.
- Missing resource and wrong generation remain required ordered-lifetime tests.

Implementation readiness:

- Ready for an ordered lifetime validation retry only if the worker implements the
  documented command-boundary order exactly and adds the required positive and
  negative tests first.
- No ABI/header follow-up is required for this order contract.

## Phase 12 Slice: Render Protocol V0 Ordered Retire Validation

Status: worker implementation complete; verification passed in this turn.

Promoted slice:

- `current.txt` - `Render Protocol V0 Ordered Retire Validation`

Accepted implementation facts:

- `howl-render/src/protocol_v0/realize.zig` now validates `create_seq`,
  `upload_seq`, command indexes, and `retire_seq` in the documented zero-based
  command-boundary domain.
- Creates, uploads, and retires reject sequence values greater than
  `commands.count`.
- Same-frame creates are visible at command indexes `>= create_seq`; uploads are
  visible at command indexes `>= upload_seq`; retires invalidate resources at
  command indexes `>= retire_seq`.
- Upload validation enforces `create_seq <= upload_seq` and, when a same-frame
  retire exists, `upload_seq < retire_seq`.
- Command validation enforces visible create, visible upload, and not-yet-retired
  resource state before any caller-visible pixel mutation.
- Duplicate retire rejection, missing-resource errors, wrong-generation errors,
  sprite behavior, and alpha glyph atlas behavior remain distinct and covered by
  tests.
- Reviewer rejection fix: sprite command validation now uses the same visible
  upload selection as drawing and proves the selected upload covers every source
  byte the limited visual-resource sprite draw can read from resource-local
  origin `(0, 0)`.
- The realizer remains internal-only, allocates no heap memory, emits no protocol
  frames, changes no host code, changes no headers, and does not replace the
  normal prepared-surface path.

Tests added:

- `protocol v0 realizer accepts sprite use before same frame retire`
- `protocol v0 realizer accepts late sprite create upload use retire`
- `protocol v0 realizer rejects upload after same frame retire`
- `protocol v0 realizer rejects upload before same frame create`
- `protocol v0 realizer rejects sprite use before same frame create`
- `protocol v0 realizer rejects sprite use before same frame upload`
- `protocol v0 realizer rejects sprite command outside visible upload before mutation`
- `protocol v0 realizer rejects sprite use after same frame retire`
- `protocol v0 realizer rejects retire before final sprite use`
- `protocol v0 realizer rejects create sequence outside frame`
- `protocol v0 realizer rejects upload sequence outside frame`
- `protocol v0 realizer rejects retire sequence outside frame`
- `protocol v0 realizer accepts glyph atlas use before same frame retire`
- `protocol v0 realizer rejects glyph atlas use after same frame retire`

Verification performed:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

## Phase 13 Slice: Render Protocol V0 Internal Emission

Status: worker implementation complete; verification passed in this turn.

Promoted slice:

- `current.txt` - `Render Protocol V0 Internal Emission`

Accepted implementation facts:

- Added internal-only `howl-render/src/protocol_v0/emit.zig`.
- The emitter consumes explicit synthetic fixtures for clear, background fill,
  decoration fill, sprite, and cursor fill consequences. It does not read host
  state, backend objects, GL ids, prepared owner storage, or direct renderer glyph
  atlas production.
- Emitted frames use shipped `HowlRenderV0*` C ABI structs and
  `HOWL_RENDER_V0_*` macros through `ffi.zig`.
- Emitter storage is fixed-capacity and emitter-owned/test-owned. Tests instantiate
  small fixed capacities to force command, upload, retire, and upload-byte
  overflow paths.
- Emission builds into a copied storage image and commits only after all appends
  and byte-total checks succeed. Failed emission leaves the last accepted frame
  and oracle realization path unchanged.
- Command emission preserves current prepared-buffer pass order for supported
  consequences: clear, background fill, decoration fill, sprite, cursor fill.
- Sprite emission creates render-owned temporary sprite resources, copies upload
  bytes into emitter-owned storage, emits uploads visible before sprite commands,
  emits sprite commands, and retires each temporary resource at
  `final_command_index + 1` in the documented command-boundary domain.
- The emitter checks damage/create/upload/command/retire fixed capacities and uses
  checked arithmetic for per-frame upload byte totals before copying bytes.
- Full RGBA remains oracle/fallback only. These tests use synthetic fixtures and
  do not claim real renderer glyph atlas production, host consumption, or normal
  path replacement.

Tests added:

- `protocol v0 emitter realizes fill pass order equal to oracle`
- `protocol v0 emitter realizes alpha sprite equal to oracle`
- `protocol v0 emitter realizes color sprite equal to oracle`
- `protocol v0 emitter emits sprite retires after final use`
- `protocol v0 emitter rejects command bound overflow`
- `protocol v0 emitter rejects upload bound overflow`
- `protocol v0 emitter rejects retire bound overflow`
- `protocol v0 emitter rejects upload byte total overflow`
- `protocol v0 emitter leaves oracle path independent after emission failure`

Verification performed:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

## Phase 14 Slice: Render Protocol V0 Prepared Emission Proof

Status: rejected and reverted before commit.

Promoted slice:

- `current.txt` - `Render Protocol V0 Prepared Emission Proof`

Rejected implementation facts:

- Worker added internal `emitPrepared()` beside the synthetic fixture emitter, but
  reviewer rejected the proof before commit.
- Prepared emission reads `PreparedSurface.text_frame.scene.scene` consequences in
  the source-backed pass order: clear, background, decoration, sprites, cursor.
- Prepared sprite lookup checks current `raster_plan.outputs` first and then calls
  the supplied session-like `atlasRaster()` fallback.
- Prepared sprite emission trims/copies visual-resource bytes into emitter-owned
  upload storage starting at resource-local `(0, 0)` and offsets the destination
  command rect by sprite visual bounds.
- Temporary sprite resources are created, uploaded, used, and retired in the
  documented command-boundary domain.
- The implementation did not use the real `prepared/surface.zig` `PreparedSurface`.
  It accepted `anytype` and drove tests with a local `TestPreparedSurface`, which
  can drift from the real owner structs.
- The implementation did not compare against the owner oracle
  `prepared_buffer.compose()`. It used a protocol-local `composePreparedOracle()`,
  duplicating clear/fill/sprite/blend behavior and allowing the emitter and local
  oracle to agree while both diverge from `prepared/buffer.zig`.
- The implementation was reverted. No prepared emission product code is accepted.

Blocker requiring prerequisite slice:

- The `howl-render` `test:unit` target currently lacks FreeType/Harfbuzz
  include/library wiring. Importing `prepared_buffer.compose()` through
  `prepared/buffer.zig` pulls `session/text.zig` and `ft_hb/c_api.zig`, causing
  `ft2build.h` translation failure in `zig build test:unit -- "protocol v0"`.
  The next slice must either move exact `prepared_buffer.compose()` oracle tests
  to a target with text backend dependencies or explicitly wire those dependencies
  into the correct test target. Do not weaken the proof with a local oracle.
- Partial retained-base prepared emission was not added for the same reason: the
  exact required oracle is `prepared_buffer.compose(base_pixels, ...)`, but that
  oracle is unavailable in the protocol unit target without broadening build
  ownership.

Verification performed:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

## Phase 15 Slice: Render Protocol V0 Prepared Oracle Test Target

Status: worker implementation complete; verification passed in this turn.

Promoted slice:

- `current.txt` - `Render Protocol V0 Prepared Oracle Test Target`

Accepted implementation facts:

- Added focused render test root `howl-render/src/test_protocol_proof.zig`.
- The proof root imports `prepared/buffer.zig`, `session/text.zig`, and
  `protocol_v0/emit.zig` together.
- The smoke test `protocol v0 prepared proof target imports owner oracle` directly
  references `prepared_buffer.compose`, `TextSession`, and the V0 emitter type so
  the target fails if the owner oracle or text backend import path cannot compile.
- Added `howl-render` build step `test:protocol-proof` and build-only companion
  `test:protocol-proof:build` with explicit FreeType/Harfbuzz include/library
  wiring and `test_font_options` module wiring.
- `howl-render` root `test` and `test:build` aggregates now include the protocol
  proof target.
- The existing `test:unit -- "protocol v0"` path remains unchanged and continues
  to run existing protocol unit tests without adding FreeType/Harfbuzz dependency
  wiring to the fast unit target.
- No product code, headers, ABI exports, host code, prepared owner/storage,
  normal render path, realizer, or prepared emission implementation changed.

Verification performed:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

Reviewer rejection fixes applied:

- `Owner.create()` now takes ownership of the prepared surface by pointer only
  after owner allocation succeeds, replaces the caller slot with an inert
  deinit-safe surface, and consumes the payload on every later success or failure
  path. This makes the `TextSessionOwner.prepareHandle()` `errdefer` safe after
  transfer and preserves cleanup if owner allocation fails before transfer.
- `Owner.protocolV0Frame()` now asserts the handle is live. Released/consumed V0
  cleanup proof uses a test-only emptiness helper instead of exposing plausible
  internal frame storage after release.
- Added an owned prepared-surface failure test that keeps the prepare-handle
  caller `errdefer` shape and proves V0 emission failure registers no handle while
  the owned scene is deinitialized once.

Second reviewer rejection fixes applied:

- Renamed owner V0 frame access to `protocolV0FrameForTest()` and guarded it with
  `builtin.is_test` plus the live-handle assertion, keeping the internal V0 frame
  out of normal product methods.
- Added owner-level partial retained-base proof: retained pixels are seeded on the
  session owner, a partial prepared surface is created through `Owner.create()`,
  owner-owned V0 is realized with the retained base, and every byte is compared to
  `owner.rgba_pixels`.

## Phase 16 Slice: Render Protocol V0 Prepared Emission Proof

Status: worker implementation complete; verification passed in this turn.

Promoted slice:

- `current.txt` - `Render Protocol V0 Prepared Emission Proof`

Accepted implementation facts:

- Added internal `emitPrepared()` in `howl-render/src/protocol_v0/emit.zig`.
- `emitPrepared()` accepts the real `prepared/surface.zig` `PreparedSurface` and
  a real `TextSession`; it does not use `anytype` fake prepared surfaces.
- Prepared emission reads `prepared.text_frame.scene.scene` in current
  `prepared_buffer.compose()` pass order: clear, background, decoration, sprites,
  cursor.
- Prepared sprite lookup checks current `prepared.text_frame.raster_plan.outputs`
  first and then `TextSession.atlasRaster()` for the session cache fallback.
- Prepared sprite emission trims visual-resource upload bytes into emitter-owned
  storage starting at resource-local `(0, 0)` and offsets the destination command
  rect by visual bounds exactly as `prepared_buffer.compose()` does.
- Temporary sprite resources are created, uploaded, used, and retired in the
  documented command-boundary domain.
- Emission remains fail-closed by building through copied emitter storage and
  committing only after all appends and sprite byte copies succeed; missing
  prepared sprites leave the prior accepted frame intact.
- The proof tests live in `howl-render/src/test_protocol_proof.zig`, construct real
  `PreparedSurface` values, realize V0 through `protocol_v0.realize()`, and
  compare byte-for-byte against `prepared_buffer.compose()`.
- Full RGBA remains oracle/fallback only. No headers, C ABI exports, host code,
  prepared owner/surface storage, normal render path, build files, realizer, or
  direct glyph atlas production changed.

Tests added:

- `protocol v0 emitter realizes prepared fill frame equal to full rgba oracle`
- `protocol v0 emitter realizes prepared alpha sprite frame equal to full rgba oracle`
- `protocol v0 emitter realizes prepared color sprite frame equal to full rgba oracle`
- `protocol v0 emitter realizes prepared sprite visual bounds equal to full rgba oracle`
- `protocol v0 emitter rejects missing prepared sprite without mutating accepted frame`
- `protocol v0 emitter realizes partial prepared frame over retained base equal to full rgba oracle`

Verification performed:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

## Phase 17 Slice: Render Protocol V0 Prepared Handle Storage

Status: worker implementation complete; verification passed in this turn.

Promoted slice:

- `current.txt` - `Render Protocol V0 Prepared Handle Storage`

Accepted implementation facts:

- `prepared_owner.Owner` now owns internal V0 payload storage beside the prepared
  surface and full RGBA oracle.
- `Owner.create()` builds the full RGBA oracle first, then emits V0 into
  owner-owned storage before registering the prepared handle.
- Owner-owned V0 frames use the existing `emitPrepared()` path, so span pointers
  and upload byte pointers point into the prepared handle payload and remain stable
  while the handle is live.
- `deinitPayload()` resets V0 payload storage with the same lifetime transition as
  `PreparedSurface` and `rgba_pixels`, preventing released handles from retaining
  stale V0 spans.
- If V0 emission fails, `Owner.create()` returns before handle registration and the
  owner errdefer destroys the prepared surface plus any allocated RGBA/V0 payload.
- V0 remains internal-only. No header, C ABI export, host code, normal render path,
  build file, realizer, or direct glyph atlas production changed.

Tests added:

- `protocol v0 prepared owner frame equals owner rgba oracle`
- `protocol v0 prepared owner releases v0 payload with handle`
- `protocol v0 prepared owner create fails closed when v0 emission fails`

Verification performed:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

## Sprint Phases

## Phase 24 Slice: Linux Host V0 GL Realization Diagnostics

Status: worker implementation complete; verification passed in this turn.

Promoted slice:

- `current.txt` - `Linux Host V0 GL Realization Diagnostics`

Implementation facts to verify:

- `howl-linux-host/src/window/term_texture.zig` records bounded scalar V0 GL
  realization diagnostics in `ProtocolV0Textures`: frame token, span counts,
  upload byte totals, churn/reuse counters, slot counts/maxima, GL side-effect
  counters, GL state samples, and failure buckets.
- `howl-linux-host/src/terminal/context.zig` records submit-owner timing for V0
  realization and full RGBA upload, samples GL state around the full RGBA upload,
  and emits sampled `howl-debug v0 ...` summaries without retaining V0 frame,
  span, or upload byte pointers.
- `howl-linux-host/src/window/present.zig` records SDL main-thread/current-context/
  current-window readiness and `SDL_GL_SwapWindow` timing in the present owner.
- `howl-linux-host/src/window/window.zig` exposes the SDL readiness calls only to
  the present owner adapter.
- Full RGBA upload, submit, and presentation remain the visible path. V0 command
  drawing and presentation replacement are not implemented.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

## Phase 34 Slice: Linux Host V0 Glyph Run Present Path

Status: implementation complete; verification passed in this turn.

Problem:

- V0 fill-only and sprite frames can now present without uploading the full RGBA oracle.
- Normal terminal text frames still require glyph-run command materialization before the host can
  present typical V0 text frames visibly.
- Full RGBA must remain fallback/oracle until V0 normal-frame coverage is proven and a later
  deletion slice is explicitly promoted.

Promoted slice:

- `current.txt` - `Linux Host V0 Glyph Run Present Path`

Required shape:

- Accept frames whose first command is a full-surface clear and whose remaining commands are
  clear/fill/sprite/glyph-run commands.
- Draw glyph runs into the terminal texture through the existing host-owned FBO path.
- Use only realized host-owned atlas textures from `ProtocolV0Textures`.
- Support `HOWL_RENDER_V0_RESOURCE_GLYPH_ATLAS_ALPHA` only.
- Reject/fallback for color atlas glyph resources, missing atlas resources, malformed glyph refs,
  or GL/FBO failure.
- Do not change render ABI, protocol lifetime, or ack/removal semantics.

Current implementation facts:

- `howl-linux-host/src/window/term_texture.zig` has a shared `uploadProtocolV0Commands()` path
  for sprite/glyph-capable frames so command order stays inside one terminal-texture FBO pass.
- `uploadProtocolV0Glyphs()` gates on `protocolV0GlyphFrame()` before using the shared command
  materializer.
- `drawGlyphCommand()` draws each `HowlRenderV0GlyphRef` using its atlas resource, destination
  `x_px/y_px`, glyph atlas rect dimensions, and per-glyph RGBA color.
- Host `ALPHA8` GL storage/upload now uses compatibility `GL_ALPHA` for the fixed-function path,
  so alpha atlas values modulate output alpha instead of only red.
- `commandUsesResource()` now accounts for glyph atlas resource references when recording
  same-frame resource churn and persistent resource use diagnostics.
- `howl-linux-host/src/terminal/context.zig` records `glyph_present` and `glyph_fallback`
  counters in protocol V0 submit diagnostics.
- Host review tightened glyph validation to mirror render oracle safety checks: glyph spans must
  use the ABI max, atlas rects must fit the 1024x1024 alpha atlas contract, and glyph destinations
  must overlap the render surface before the V0 path is considered presentable.
- The draw path rechecks each glyph atlas rect against the realized host texture dimensions before
  issuing the textured quad, so a malformed or mismatched resource falls back to full RGBA instead
  of drawing unchecked texture coordinates.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`
- From `howl-linux-host`: bounded `btop` smoke run with
  `timeout 22s zig build run -Doptimize=ReleaseFast -- --duration-ms 18000
  --debug-process-accounting --debug-log-every-ms 5000 --command btop`

Smoke result:

- `render_step_failed=0` for the sampled intervals.
- `present_submitted` advanced: first interval `9`, then `7`, then `9`.
- First sampled V0 diagnostics still showed `glyph_present=0` and `glyph_fallback=0`; this run
  preserved liveness but did not prove a live glyph V0 present frame was emitted during the
  first diagnostic snapshot.

## Phase 35 Slice: V0 Normal Frame Present Proof

Status: implementation complete; verification passed in this turn.

Problem:

- V0 fill, sprite, and glyph materialization paths now exist, but the smoke run still observed
  `glyph_present=0` and `glyph_fallback=0` in the sampled diagnostic output.
- Before deleting or reducing full RGBA, the host must prove exactly why normal frames are still
  using RGBA fallback or whether V0 present is already being exercised outside the first sample.

Promoted slice:

- `current.txt` - `V0 Normal Frame Present Proof`

Required shape:

- Count prepared submissions with no V0 sidecar.
- Count V0 frames rejected before upload because their command shape is unsupported.
- Count V0 upload/materialization fallback separately for fill-only, sprite, and glyph paths.
- Keep existing present counters for fill-only, sprite, and glyph paths.
- Log the counters through existing debug diagnostics.
- Do not change render ABI, protocol lifetime, host policy, or full RGBA fallback.

Implementation facts:

- `howl-linux-host/src/terminal/context.zig` now records no-sidecar fallback, unsupported V0
  shape fallback, full RGBA fallback, and per-path frame/present/fallback counts.
- Unsupported V0 shapes record bounded command-kind totals and whether the first command was a
  full-surface clear.
- `howl-linux-host/src/window/term_texture.zig` exposes `ProtocolV0FrameSummary` and
  `protocolV0FrameSummary()` for diagnostic-only command-shape accounting.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: bounded `btop` smoke run with
  `timeout 22s zig build run -Doptimize=ReleaseFast -- --duration-ms 18000
  --debug-process-accounting --debug-log-every-ms 5000 --command btop`

Smoke result:

- `render_step_failed=0` and `present_submitted` advanced.
- First V0 diagnostic snapshot: `v0_no_sidecar=0`, `v0_unsupported_shape=1`,
  `rgba_fallback=1`.
- Unsupported shape summary: `no_full_clear=1`, `clear=0`, `fill=53`, `sprite=0`,
  `glyph=0`, `other=0`.
- Current normal-frame blocker is not missing glyph presentation. It is fill-only V0 frames without
  a first full-surface clear. The next product slice should prove and present fully covered fill-only
  frames without weakening RGBA fallback.

## Phase 36 Slice: V0 Fill Coverage Present Path

Status: implementation complete; verification passed in this turn.

Problem:

- Phase 35 proved the current `btop` V0 frame has `clear=0`, `fill=53`, `sprite=0`, `glyph=0`,
  `other=0`, and is rejected only because no first full-surface clear exists.
- The existing fill-only path requires a first full-surface clear for safety. That is correct for
  partial fill streams, but overly conservative if fill rectangles themselves cover every pixel.

Promoted slice:

- `current.txt` - `V0 Fill Coverage Present Path`

Required shape:

- Accept clear/fill-only V0 frames with a first full clear exactly as before.
- Additionally accept fill-only V0 frames without a first clear only when bounded coverage proves
  every pixel is filled.
- Reject/fallback for overlapping ambiguity, gaps, out-of-bounds rectangles, resource-bearing
  commands, or non-fill commands.
- Keep coverage proof bounded by render dimensions and existing upload row limits.
- Do not change render ABI, protocol lifetime, or full RGBA fallback.

Implementation facts:

- `protocolV0FillOnly()` still accepts first-full-clear fill streams exactly as before.
- It also accepts fill-only streams without a first clear only when every fill rect is in bounds,
  every pair of rects is non-overlapping, and the summed fill area equals render surface area.
- The coverage proof uses no allocation and is bounded by the V0 command count.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: bounded `btop` smoke run with
  `timeout 22s zig build run -Doptimize=ReleaseFast -- --duration-ms 18000
  --debug-process-accounting --debug-log-every-ms 5000 --command btop`

Smoke result:

- `render_step_failed=0` and `present_submitted` advanced.
- First V0 diagnostic snapshot still rejected the frame: `v0_unsupported_shape=1`,
  `no_full_clear=1`, `clear=0`, `fill=66`, `sprite=0`, `glyph=0`, `other=0`.
- Therefore the `btop` V0 stream is a partial fill patch, not a full-coverage fill frame. The next
  product slice should present no-clear fill patches only when the host terminal texture already
  contains a matching initialized previous frame.

## Phase 37 Slice: V0 Retained Fill Patch Present Path

Status: implementation complete; verification passed in this turn.

Problem:

- Phase 36 proved `btop` emits partial no-clear fill-only V0 frames.
- Such frames are unsafe for a newly created or resized terminal texture, but safe as retained
  patches when the previous host texture is already initialized at the same size.

Promoted slice:

- `current.txt` - `V0 Retained Fill Patch Present Path`

Required shape:

- Accept partial no-clear fill-only V0 frames only if the terminal texture existed before upload and
  matched the frame size.
- Reject/fallback if the texture was newly created or resized in the current turn.
- Reject/fallback for non-fill commands, resource-bearing commands, malformed spans, or
  out-of-bounds rectangles.
- Preserve existing first-full-clear and full-coverage fill-only paths.
- Log retained-patch present/fallback counts.

Implementation facts:

- `Context` records whether the terminal texture existed and matched the prepared frame dimensions
  before `ensureSurface()` could allocate or resize it.
- `protocolV0FillPatch()` accepts only no-resource in-bounds fill commands with no creates,
  uploads, or retires.
- `uploadProtocolV0FillPatch()` updates the existing terminal texture through the same bounded fill
  upload path as fill-only present.
- Fill patches are presented only when `had_matching_surface` is true; first-frame/resized cases
  fall back to RGBA.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: bounded `btop` smoke run with
  `timeout 22s zig build run -Doptimize=ReleaseFast -- --duration-ms 18000
  --debug-process-accounting --debug-log-every-ms 5000 --command btop`

Smoke result:

- First frame: `fill_patch_frame=1`, `fill_patch_present=0`, `fill_patch_fallback=1`, proving
  first-frame safety fallback worked.
- Later frames were mostly unsupported retained sprite patch shapes: cumulative diagnostics reached
  `sprite=77802`, `glyph=0`, `fill_patch_frame=1`. The next product slice should generalize the
  retained-patch rule to sprite-capable frames with existing matching texture content.

## Phase 38 Slice: V0 Retained Sprite Patch Present Path

Status: implementation complete; verification passed in this turn.

Problem:

- Phase 37 proved later `btop` frames are retained patch frames with many sprite commands and no
  glyph commands.
- Existing sprite presentation requires a first full-surface clear, so retained sprite patches still
  fall back to RGBA even when the terminal texture already has matching initialized content.

Promoted slice:

- `current.txt` - `V0 Retained Sprite Patch Present Path`

Required shape:

- Accept partial no-clear clear/fill/sprite V0 frames only if the terminal texture existed before
  upload and matched the frame size.
- Reject/fallback if the texture was newly created or resized in the current turn.
- Reject/fallback for glyph commands, unsupported command shapes, missing sprite resources, or
  out-of-bounds rects.
- Preserve existing full-clear sprite path.
- Log retained sprite patch present/fallback counts.

Implementation facts:

- `protocolV0SpritePatch()` accepts no-clear clear/fill/sprite frames with at least one sprite
  command and rejects glyph commands.
- Sprite patch presentation is gated by the same `had_matching_surface` proof used for retained
  fill patches.
- `uploadProtocolV0SpritePatch()` reuses the existing FBO command materializer, so command order is
  preserved and drawing still lands in the terminal texture.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: bounded `btop` smoke run with
  `timeout 22s zig build run -Doptimize=ReleaseFast -- --duration-ms 18000
  --debug-process-accounting --debug-log-every-ms 5000 --command btop`

Smoke result:

- `render_step_failed=0` and `present_submitted` advanced.
- `v0_unsupported_shape=0` after retained sprite patch recognition.
- Retained sprite patch presentation occurred: sampled cumulative diagnostics reached
  `sprite_patch_frame=24`, `sprite_patch_present=9`, `sprite_patch_fallback=15`.
- Full RGBA fallback still occurred for no-sidecar, first-frame, and unresolved sprite patch cases;
  RGBA remains the oracle/fallback.

Review/fix note:

- User visual testing found retained sprite patch colors were dark/tinted.
- Host fixes applied after hostile review:
  - V0 command replay is gated on `realizeFrame()` success.
  - Sprite draw validates against committed upload coverage, not allocation size.
  - Sprite texture coordinates use source-local `(0,0,width,height)` rather than destination rect
    coordinates.
  - Sprite and glyph replay reject future same-frame uploads that would make final GL texture state
    disagree with command-time upload visibility.
  - FBO command replay uses source-over alpha blending for alpha and restores viewport/blend state;
    current color and texture binding are reset after replay.
  - Full RGBA upload now fails on GL error and clears surface dimensions on upload failure.
- Render oracle fixes applied after hostile review:
  - Retained resource creates/uploads/retires commit after command replay, so same-frame retire does
    not hide a resource before its valid command use.
  - Upload visibility selects the latest visible upload by `upload_seq`.
  - Decreasing upload sequence order is rejected in render and host validators so retained metadata
    and replay order stay deterministic.
- Acceptance review result: accepted after the above fixes; residual risk is narrower V0 fast-path
  coverage because future-upload frames fall back to full RGBA.

## Phase 39 Slice: V0 Interval Diagnostics

Status: implementation complete; verification passed in this turn.

Problem:

- A run that executes `btop` and then `rain` in the same terminal process produces cumulative V0
  counters. The result is visually good but hard to interpret because `btop` patch-present counts
  and later `rain` no-sidecar/full-RGBA counts are mixed together.

Promoted slice:

- `current.txt` - `V0 Interval Diagnostics`

Required shape:

- Keep existing cumulative diagnostics.
- Add per-log interval deltas for V0 present/fallback/no-sidecar counters.
- Add bounded no-sidecar reason buckets for resource-plan statuses.
- Include a stable label from current title/fallback command when logging.
- Do not change render ABI, protocol lifetime, rendering behavior, or full RGBA fallback.

Implementation facts:

- `Context` keeps a snapshot of the last logged submit diagnostics and prints an interval delta line
  alongside cumulative V0 diagnostics.
- V0 logs include a stable label from terminal title, falling back to configured command/shell.
- No-sidecar fallbacks are bucketed by prepared resource-plan status: null-frame, call-failed,
  unsupported, invalid, overflow, and other.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: bounded `btop` smoke run with
  `timeout 12s zig build run -Doptimize=ReleaseFast -- --duration-ms 8000
  --debug-process-accounting --debug-log-every-ms 3000 --command btop`

Smoke result:

- Logs now include `label='btop'` and `howl-debug v0 interval ...` lines.
- The interval line split recent fallbacks from cumulative totals.
- The observed no-sidecar reason was `call_failed`, not overflow or unsupported command:
  sample interval `no_sidecar=10 no_sidecar_call_failed=10`.
- This points the next product slice at render/prepared V0 frame availability rather than another
  host present path.

## Phase 40 Slice: V0 Prepared Emit Diagnostics

Status: implementation complete; verification passed in this turn.

Problem:

- Host interval diagnostics now prove the dominant no-sidecar bucket in `btop` is
  `no_sidecar_call_failed`.
- Source trace shows `howl-linux-host/src/terminal/render/retained.zig` records `call_failed` when
  `howl_render_prepared_surface_protocol_v0()` does not return `HOWL_RENDER_CALL_OK`.
- Render `howl-render/src/ffi/prepared_surface.zig` returns `HOWL_RENDER_CALL_INVALID_ARGUMENT` when
  `Owner.protocolV0Frame()` returns null.
- Render `howl-render/src/prepared/owner.zig` currently runs `owner.emitV0Payload() catch {};` during
  prepared owner creation, so concrete emit errors are swallowed and the host only sees generic
  no-sidecar call failure.

Promoted slice:

- `current.txt` - `V0 Prepared Emit Diagnostics`

Required shape:

- Add a bounded prepared V0 emit status to `HowlRenderPreparedSurfaceDiagnostics`.
- Map every `protocol_v0.emit.Error` value to a stable ABI status.
- Preserve `protocolV0Frame()` returning null when payload emission fails.
- Host logs must include the prepared V0 emit status when V0 sidecar acquisition fails.
- Do not use diagnostics to change fallback or present policy.

Non-goals:

- Do not make V0 emit failure fail prepare or submit.
- Do not remove full RGBA fallback/oracle.
- Do not add backend objects to the render ABI.
- Do not change V0 protocol lifetime or resource ownership.

Implementation facts:

- `HowlRenderPreparedSurfaceDiagnostics` now exposes `protocol_v0_emit_status`.
- The diagnostics ABI names and zeros its trailing reserved field instead of relying on hidden tail
  padding.
- `Owner.create()` still preserves RGBA fallback when V0 payload emission fails, but records the exact
  `protocol_v0.emit.Error` as a stable ABI status.
- V0 payload allocation failure is also diagnostic-only and maps to
  `HOWL_RENDER_V0_EMIT_ALLOCATION_FAILED`.
- Host `PreparedUpload` fetches prepared diagnostics before probing V0 and includes
  `v0_emit_status` in cumulative V0 logs.
- Host diagnostics fetch failure does not block prepared upload or full RGBA fallback.
- The dominant `btop` no-sidecar call failure now resolves to
  `HOWL_RENDER_V0_EMIT_COMMAND_BOUND_OVERFLOW` (`v0_emit_status=1`).

Verification performed:

- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From `howl-render`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

Smoke result:

- Bounded `btop` smoke showed cumulative V0 logs with `v0_emit_status=1` and interval counters with
  `no_sidecar_call_failed=4` over the sampled interval.
- `v0_emit_status=1` maps to `HOWL_RENDER_V0_EMIT_COMMAND_BOUND_OVERFLOW`, so the next product slice
  should reduce/coalesce command emission pressure or produce a bounded partial V0 payload policy.

Rollback note:

- User visual testing found retained sprite patch presentation corrupted colors in `btop`.
- Retained sprite patch upload was disabled in a follow-up safety fix; `protocolV0SpritePatch()`
  remains diagnostic-only and sprite patch frames fall back to full RGBA.
- Root cause must be handled by a future oracle-comparison slice before retained sprite patches are
  re-enabled.

## Phase 33 Slice: Linux Host V0 Sprite Present Path

Status: worker implementation complete; verification passed in this turn.

Problem:

- Fill-only V0 presentation is committed, but normal terminal frames still use RGBA
  fallback because they contain sprite commands for text/glyph imagery.
- Drawing V0 commands over the RGBA terminal texture would violate protocol order.

Promoted slice:

- `current.txt` - `Linux Host V0 Sprite Present Path`

Required shape:

- Materialize clear/fill/sprite commands into the terminal texture itself in protocol
  order using host-owned GL state.
- Keep glyph-run or unsupported frames on RGBA fallback.
- Keep full RGBA as fallback/oracle.

Implementation facts:

- `term_texture.protocolV0SpriteFrame()` accepts clear/fill plus draw-sprite command
  streams and rejects glyph-run commands.
- Accepted sprite frames are materialized into the terminal texture through a host-owned
  framebuffer bound to the terminal texture, preserving protocol command order.
- Sprite resources remain host-owned GL textures tracked by `ProtocolV0Textures`; render
  still exposes only protocol resource IDs.
- Unsupported frames and GL/FBO failures fall back to full RGBA upload.
- Diagnostics now include `sprite_present` and `sprite_fallback` counters.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`
- Bounded `btop` smoke run showed `render_step_failed=0` and present continued.

## Phase 32 Slice: Linux Host V0 Fill-Only Present Path

Status: worker implementation complete; verification passed in this turn.

Problem:

- V0 frames are produced, resources are realized, and command overflow/memory growth are
  fixed.
- Directly drawing only fills for mixed text/sprite frames would be wrong because fills
  can be backgrounds behind glyph/sprite commands. Drawing those fills after the RGBA
  terminal texture would cover text.

Promoted slice:

- `current.txt` - `Linux Host V0 Fill-Only Present Path`

Required shape:

- Detect frames containing only clear/fill commands with no glyph spans and no sprite
  resource use.
- Use V0 directly for those fill-only frames.
- Keep RGBA fallback for all mixed frames until sprite/glyph drawing is promoted.

Implementation facts:

- `term_texture.protocolV0FillOnly()` accepts frames with no resource mutations and only
  clear/fill commands, requiring the first command to clear the full render surface.
- `term_texture.uploadProtocolV0FillOnly()` materializes accepted fill-only frames into
  the host terminal texture through V0 command consequences.
- `ContextSubmitBackend.upload()` uses the V0 fill-only upload path when eligible and
  otherwise falls back to the full RGBA upload path.
- Diagnostics now include `fill_only_present` and `fill_only_fallback` counters.
- Mixed `btop` frames correctly remain on RGBA fallback for now; smoke run showed
  `render_step_failed=0` and `fill_only_present=0` for mixed frames.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

## Phase 31 Slice: Protocol V0 Prepared Payload Lifetime

Status: worker implementation complete; verification passed in this turn.

Problem:

- User run reported roughly 6 GiB system memory growth in about one minute.
- V0 diagnostics showed continued frame submits and growing live sprite resources, but
  not enough GL texture/resource count to explain the growth.
- `TextSessionOwner.prepared_handles` intentionally retains prepared owner pointers as
  stale handle tombstones until session destroy.
- `prepared_owner.Owner` currently embeds `V0Payload`, whose static arrays include the
  full V0 command/upload/frame storage. `consume()` and `release()` clear logical
  payload state but cannot free embedded bytes. Every submitted frame leaves a large
  tombstone behind.

Promoted slice:

- `current.txt` - `Protocol V0 Prepared Payload Lifetime`

Required shape:

- Keep stale prepared handles safe as small tombstones.
- Move V0 payload storage behind an owned pointer that exists only while live and V0 is
  available.
- Free that payload on release, consume, failed creation, and session destroy.

Implementation facts:

- `prepared_owner.Owner` no longer embeds `V0Payload` directly.
- Live prepared owners allocate V0 payload storage only after V0 emission succeeds.
- `deinitPayload()` destroys the V0 payload pointer, so released/consumed tombstones do
  not retain the large command/upload/frame arrays.
- `protocolV0Frame()` returns null when a live owner has no V0 payload, preserving the
  V0-unavailable fallback from Phase 29.

Memory check:

- Bounded `btop` run after the fix peaked at about 36 MiB RSS over 20 seconds using
  `/proc/<pid>/status` sampling.
- The same user path previously reported roughly 6 GiB system memory growth in about
  one minute.

Verification performed:

- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `git diff --check`
- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

Required GUI review after verification:

- Run with `--debug-process-accounting --debug-log-every-ms 1000` and capture the
  bounded `howl-debug v0 ...`, `howl-debug v0 failures ...`, and
  `howl-debug present ...` lines for `lll`, `l`, `btop` warning mode, and `btop`
  normal draw mode.

GUI evidence captured after diagnostics:

- Startup/simple output frame: `create=0`, `upload=0`, `retire=0`, `command=165`,
  no GL errors, present readiness OK.
- Draw-heavy frame sequence realized 35 V0 sprite resources into host GL textures:
  `glGenTextures=35`, `glTexImage2D=35`, `glTexSubImage2D=35`,
  `glDeleteTextures=35`.
- The realized resources were all same-frame disposable resources:
  `churn_same_frame=35`, `created_not_surviving=35`, `reuse_persistent=0` for the
  first realized batch; later cumulative counters showed the same pattern.
- V0 GL realization time stayed small, roughly `19-28us` after the initial max around
  `297-302us`. Full RGBA upload stayed roughly `824-2122us`. No `glGetError()` was
  reported in V0 phases or full RGBA upload.
- SDL present readiness was OK on the sampled present line: main thread, current
  context, and current window all passed.
- After the first same-frame retire batch, later frames repeatedly failed with
  `tombstone_value_reuse`, increasing from 1 through 8 in the captured logs, while
  retired slots stayed at 35 and live slots stayed at 0.

Interpretation:

- The first diagnostic data does not point at GL error state, SDL context loss, or a
  long V0 realization stall.
- It does point at the known protocol/product mismatch: render emits temporary sprite
  IDs from same-frame sprite indices, the host correctly keeps retired tombstones
  because no ack/removal contract exists, and subsequent frames reuse numeric values
  that the host must reject.
- The current V0 GL path is still disposable per-draw backend texture churn, not the
  persistent resource/atlas shape used by Ghostty or Alacritty.

Reviewer rejection fix applied 2026-05-31:

- Bounded V0 and present diagnostic logs with first-8 new-failure counters plus
  periodic summaries. Latched nonzero failure counters no longer cause per-submit
  or per-present logging forever.
- V0 diagnostics now copy and log the full token: `snapshot_seq`, `frame_seq`,
  `geometry_epoch`, and `resource_epoch`.
- Pure create-transition validation now classifies unsupported kind/format,
  tombstone value reuse, and capacity exhaustion into exact buckets.
- GL state samples now cover V0 create, upload, and retire phases separately, and
  full RGBA upload still has before/after samples without `glFinish`.
- Added pure tests for scalar diagnostic accounting, slot maxima, churn counters,
  GL side-effect counters where pure, bounded log counters, and exact failure
  bucket increments.

Accepted commits:

- `howl-linux-host` `6299ad0` - `host: add protocol v0 gl diagnostics`

## Phase 25 Slice: Render Protocol V0 Resource Lifetime Decision

Status: promoted to `current.txt`; decision recorded.

Promoted slice:

- `current.txt` - `Render Protocol V0 Resource Lifetime Decision`

Decision:

- V0 resources are retained, render-owned protocol identities.
- Host backend objects realize live protocol resources; backend deletion is not
  protocol ack.
- Same-frame create/upload/use/retire remains valid protocol input for bounded
  temporary consequences, but it is not the product path for normal sprite/glyph
  rendering.
- First implementation should move prepared sprite emission to persistent render-owned
  resources with no retire and no numeric reuse.
- Host ack/removal must be specified and implemented before resource retirement for
  reclamation, before numeric value reuse, and before deleting the full RGBA fallback.
- Persistent no-retire/no-reuse sprite emission may proceed before ack/removal because
  it removes the observed same-frame churn and tombstone reuse without pretending
  reclamation exists.

Source-backed facts:

- Diagnostics showed draw-heavy output realizing 35 same-frame disposable sprite
  resources, then later failing on `tombstone_value_reuse` while GL errors and SDL
  readiness stayed clean.
- `howl-render/src/protocol_v0/emit.zig` currently derives prepared sprite resource
  IDs from same-frame sprite index and generation `1`.
- `howl-linux-host/src/window/term_texture.zig` correctly preserves retired tombstones
  and rejects numeric reuse before ack.
- `docs/render-protocol-v0.md` now states backend deletion is not ack and that
  persistent no-retire/no-reuse resources may exist before ack/removal.

First implementation slice after this decision:

- `Render Protocol V0 Persistent Sprite Resource Emission Probe`

Implementation shape for that later slice:

- Add a render-owned bounded V0 sprite resource table in the true protocol/prepared
  owner.
- Allocate opaque nonzero resource values monotonically; use generation `1` only for
  the first lifetime and do not reuse numeric values in that slice.
- Key the table from current render-internal sprite facts only. `SpriteKey` may be an
  internal lookup ingredient, but it must not become a public glyph identity or ABI
  promise.
- Emit create/upload for a sprite resource only on first observation or when the
  source-backed identity/bytes/dimensions require a distinct resource.
- Emit later commands referencing existing live resources with no create/upload/retire.
- Emit no normal retire events for persistent sprites in that slice.
- Fail closed to full RGBA fallback/oracle if capacity or upload bounds are exhausted.
- Retain/extend the V0 software oracle/resource store enough to prove later-frame
  commands can reference earlier-frame resources byte-equivalent to the full RGBA
  prepared buffer.

Required tests for that later slice:

- Frame 1 with a sprite emits create/upload/command and no retire.
- Frame 2 with the same source-backed sprite identity emits command only for the same
  resource ID.
- Different source-backed sprite identity or incompatible bytes/dimensions emits a
  distinct monotonic resource ID, not numeric reuse.
- Resource capacity exhaustion fails closed without mutating accepted V0 payload state.
- Retained software realizer/oracle proves frame 2 byte-equivalent to
  `prepared_buffer.compose()` while using a prior-frame resource.
- Host diagnostics should move toward `reuse_persistent > 0`, reduced same-frame
  churn, and no `tombstone_value_reuse` for repeated sprites.

Rejected alternatives:

- Treat `glDeleteTextures()` as ack: rejected because backend cleanup is not a
  host-to-render protocol message.
- Keep same-frame disposable sprite resources as product path: rejected by diagnostics
  and by Ghostty/Alacritty persistent resource precedent.
- Reuse `{ value, generation = 1 }` per frame: rejected as numeric reuse before ack.
- Implement ack/removal before persistent emission: rejected as unnecessary for the
  first no-retire/no-reuse persistent slice.
- Implement ack plus persistent resources in one slice: rejected as too broad.

## Phase 18 Slice: Render Protocol V0 Prepared ABI View

Status: under review after worker implementation.

Promoted slice:

- `current.txt` - `Render Protocol V0 Prepared ABI View`

Implementation facts to verify:

- Added C ABI export `howl_render_prepared_surface_protocol_v0()` returning a
  borrowed `const HowlRenderV0Frame *` through an output pointer.
- The borrowed frame remains owned by the live prepared handle; the call does not
  transfer ownership and does not transition the prepared lifecycle.
- Missing handles return `HOWL_RENDER_CALL_MISSING_HANDLE` and clear output when
  an output pointer is supplied.
- Null output pointers return `HOWL_RENDER_CALL_INVALID_ARGUMENT`.
- Released or consumed handles return `HOWL_RENDER_CALL_INVALID_ARGUMENT` and
  clear output.
- Full RGBA prepared-buffer ABI remains unchanged.
- Host code, normal render path, backend objects, build files, docs/current, and
  protocol host consumption were not changed.

Tests to verify:

- `render ffi prepared protocol v0 rejects missing handle`
- `render ffi prepared protocol v0 rejects null output`
- `render ffi prepared protocol v0 rejects released handle`
- `render ffi prepared protocol v0 returns borrowed live frame`
- `render ffi prepared protocol v0 does not change prepared lifecycle`
- `protocol v0 prepared ffi borrowed frame realizes owner rgba oracle`

Verification reported by worker before review:

- `zig build check`
- `zig build test`
- `git diff --check`
- From `howl-render`: `zig build test:abi -- "protocol v0"`
- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test:unit -- "protocol v0"`

## Phase 19 Slice: Linux Host V0 Prepared Probe

Status: worker implementation complete; verification passed in this turn.

Promoted slice:

- `current.txt` - `Linux Host V0 Prepared Probe`

Implementation facts:

- `howl-linux-host/src/terminal/render/retained.zig` now calls
  `howl_render_prepared_surface_protocol_v0()` during `preparedUpload()`, after
  prepared info and buffer acquisition and before the existing full RGBA texture
  upload path consumes the handoff.
- The probe is read-only and stores only bounded accounting facts in
  `PreparedProtocolV0Probe`: validity, frame sequence, top-level span counts, and
  upload byte total.
- The probe validates call status, non-null borrowed frame pointer, protocol
  version, prepared/frame render dimensions, cell dimensions, grid dimensions,
  top-level V0 span counts against their public maxima, and upload byte total
  against `HOWL_RENDER_V0_UPLOAD_BYTES_MAX`.
- The borrowed `HowlRenderV0Frame` pointer is never retained beyond the immediate
  validation call.
- Existing full RGBA upload, GL resource realization, submit execution,
  presentation cadence, and backend object lifetime are unchanged.

Tests added:

- `host retained render probes prepared protocol v0 frame`
- `host retained render rejects invalid protocol v0 probe invariants`

Host harness gap:

- No existing host test constructs a live prepared handle through the complete
  Linux host upload/submit path without involving GL texture realization, which is
  out of scope for this slice. The accepted coverage is the narrow pure retained
  validation helper in `retained.zig` plus the existing render ABI tests for the
  borrowed frame call.

Verification performed:

- From `howl-linux-host`: `zig build test`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

Reviewer rejection fixes applied:

- Probe accounting is now retained by `State` rather than only returned through the
  transient prepared-upload stack value.
- `State` records the last bounded `PreparedProtocolV0Probe` and a saturating
  failure count. Invalid probes keep the RGBA upload path unchanged but are no
  longer silent.
- Invalid probe statuses are explicit for call failure, null frame, protocol
  version mismatch, render/cell/grid mismatch, each top-level span bound or max
  mismatch, upload byte overflow, and upload byte max mismatch.
- The borrowed V0 frame pointer still is not retained beyond immediate validation.

Additional tests added:

- OK status with null frame.
- Cell and grid mismatch.
- Damage max mismatch.
- Create, upload, command, and retire span overflow and max mismatch.
- Upload byte max mismatch.
- Owner recording of last probe facts and failure count.

## Phase 20 Slice: Linux Host V0 Software Oracle Probe

Status: worker implementation complete; verification passed in this turn.

Promoted slice:

- `current.txt` - `Linux Host V0 Software Oracle Probe`

Implementation facts:

- `howl-linux-host/src/terminal/render/retained.zig` now realizes the borrowed V0
  frame during `preparedUpload()` only, after prepared info/buffer acquisition and
  before the unchanged full RGBA upload path.
- The host-side software helper supports the subset currently emitted by prepared
  frames for host probing: clear rect, fill rect, alpha sprite, and color sprite.
- The helper validates span pointers/counts, resource create/upload/use/retire
  ordering in the documented command-boundary domain, upload formats, upload byte
  totals, sprite byte coverage, pixel length, and checked arithmetic before
  mutating its temporary software buffer.
- The helper allocates a temporary compare buffer, frees it before returning, and
  never retains the borrowed frame pointer, span pointers, upload byte pointers, or
  prepared RGBA pointer beyond the probe turn.
- Probe failure is accounting-only. Unsupported commands/resources, invalid V0
  bytes, allocation failure, and RGBA mismatch record explicit statuses without
  affecting the existing texture upload, submit result, presentation cadence, GL
  resource realization, or backend object lifetime.
- `State` now records saturating software-probe success count, failure count, last
  failure/status through `last_protocol_v0_probe`, and checked byte count.
- Review fix: host software realization now seeds partial frames from a bounded
  host-owned copy of the previous prepared RGBA oracle. The copy is owned by
  `State`, freed on deinit or size change, and is not a retained V0 frame/span/
  upload pointer.
- Review fix: real software mismatch paths now return and record the full checked
  byte count instead of losing accounting on failure.

Tests added:

- `host retained render software realizes protocol v0 fill frame`
- `host retained render software realizes protocol v0 sprite frame`
- `host retained render software realizes protocol v0 partial frame`
- `host retained render software probe detects rgba mismatch`
- `host retained render software probe rejects unsupported command`
- `host retained render records software probe accounting`

Host harness gap:

- Coverage remains pure retained-helper coverage because constructing a live Linux
  host prepared upload/submit turn requires GL texture realization, which is out of
  scope for this slice. The production hook is still exercised structurally by
  `preparedUpload()` and the pure tests cover the software oracle semantics.

Verification performed:

- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`
- From `howl-linux-host`: `zig build test`
- From `howl-linux-host`: `git diff --check`

Accepted commits:

- `howl-linux-host` `e222002` - `host: add protocol v0 software oracle probe`
- root `d2eff85` - `design: record host software oracle probe`

## Phase 21 Slice: Linux Host V0 Resource Plan Probe

Status: worker implementation complete; verification pending.

Promoted slice:

- `current.txt` - `Linux Host V0 Resource Plan Probe`

Purpose:

- Prove the host can derive a bounded backend-resource work plan from the borrowed
  V0 frame before any GL/backend object realization.
- Keep full RGBA upload as the actual rendering path.
- Preserve the accepted software oracle probe.

Allowed files:

- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/test/test_entry.zig` to execute retained tests
- `howl-linux-host/build.zig` only to wire retained test imports
- this scratchpad

Required shape:

- Host-side resource-plan validation/accounting for creates, uploads, command
  resource uses, and retires.
- Read-only and turn-local planning only. No backend objects, no GL calls, no
  retained V0 frame/span/upload pointers, and no full-RGBA replacement.
- Bounded accounting: success count, failure count, last status,
  create/upload/use/retire counts, and upload byte count.
- Unsupported commands/resources fail the plan probe only and keep the actual RGBA
  upload/submit path unchanged.

Required tests:

- `host retained render plans protocol v0 resource lifecycle`
- `host retained render plan rejects upload before create`
- `host retained render plan rejects use after retire`
- `host retained render records resource plan accounting`

Reviewer rejection fixes applied:

- Resource planning now uses plan-specific upload validation instead of software
  realization validation, so nonzero resource-local upload rect origins are accepted
  when the rect fits the created resource and byte/stride bounds hold.
- Failed lifecycle plans now retain bounded frame accounting after valid top-level
  spans: create count, upload count, resource-use count, retire count, and upload
  byte count.
- Resource-use counting now includes both `command.resource` and bounded glyph-run
  `atlas_resource` references before unsupported glyph-run plans fail.

Additional tests added:

- `host retained render plan accepts nonzero upload rect origin`
- `host retained render plan counts glyph resource uses before unsupported`
- Failed upload-before-create plan keeps create/upload/upload-byte accounting.
- Host unit-test wiring now imports `retained.zig` through `src/test/test_entry.zig`
  and `build.zig`, so retained tests execute under `zig build test:unit`.

Implementation facts:

- `howl-linux-host/src/terminal/render/retained.zig` now records a separate
  `PreparedProtocolV0ResourcePlan` beside the existing software oracle probe.
- Resource planning consumes the borrowed V0 frame only during `preparedUpload()`
  and retains no frame pointer, span pointer, upload byte pointer, command pointer,
  or backend object identity.
- The plan validates top-level V0 resource spans and byte maxima, then checks
  create, upload, command use, and retire ordering with the same command-boundary
  rules used by the software oracle.
- Planning is accounting-only. Unsupported commands/resources and invalid lifetime
  ordering record plan failure without changing full RGBA upload, submit, GL state,
  presentation cadence, or software oracle behavior.
- `State` records the last resource plan plus saturating plan success count,
  failure count, and upload-byte accounting.

Tests added:

- `host retained render plans protocol v0 resource lifecycle`
- `host retained render plan rejects upload before create`
- `host retained render plan rejects use after retire`
- `host retained render records resource plan accounting`

Accepted commits:

- `howl-linux-host` `392a8f2` - `host: plan protocol v0 resources`
- root `36d45a0` - `design: record host resource plan probe`

## Phase 22 Slice: Linux Host V0 Resource Store Skeleton

Status: worker implementation complete; verification pending.

Promoted slice:

- `current.txt` - `Linux Host V0 Resource Store Skeleton`

Purpose:

- Introduce a bounded host-owned V0 resource store for protocol resource IDs.
- Apply create/upload/retire lifecycle consequences to host-owned state in pure
  tests before any GL/backend object realization.
- Keep full RGBA upload as the actual rendering path.

Allowed files:

- `howl-linux-host/src/terminal/render/retained.zig`
- this scratchpad

Required shape:

- Fixed-capacity resource store bounded by `HOWL_RENDER_V0_RESOURCES_MAX`.
- Store protocol identity/state facts only: resource ID, dimensions, format,
  lifecycle state, upload count/bytes, and retire state.
- Apply borrowed-frame create/upload/retire spans during the turn only; retain no
  V0 frame/span/upload pointers.
- No GL calls, backend objects, backend lookup table, V0 drawing, full-RGBA
  replacement, or presentation policy changes.

Required tests:

- `host retained render resource store creates uploads retires resource`
- `host retained render resource store rejects duplicate create`
- `host retained render resource store rejects upload after retire`
- `host retained render resource store rejects missing retire`
- `host retained render resource store reports capacity overflow`

Implementation facts:

- `howl-linux-host/src/terminal/render/retained.zig` now contains
  `ProtocolV0ResourceStore`, a fixed-capacity host-owned table bounded by
  `HOWL_RENDER_V0_RESOURCES_MAX`.
- Store slots retain only protocol resource facts: resource ID, dimensions, format,
  live/retired state, upload count, and upload byte count.
- Store mutation is explicit through create/upload/retire methods and `applyFrame()`;
  it does not retain V0 frame/span/upload pointers and does not create backend
  objects.
- Upload mutation validates resource identity, live state, format, rect bounds,
  byte pointer, byte count, and stride-derived minimum before updating counters.
- Retire marks protocol resource state retired; it does not delete GL/backend state.

Tests added:

- `host retained render resource store creates uploads retires resource`
- `host retained render resource store rejects duplicate create`
- `host retained render resource store rejects upload after retire`
- `host retained render resource store rejects missing retire`
- `host retained render resource store reports capacity overflow`

Reviewer rejection fixes applied:

- `ProtocolV0ResourceStore.applyFrame()` is now fail-closed: it applies the frame to
  a copied store and commits only after all creates, uploads, and retires succeed.
- Store resource-kind validation now accepts alpha glyph atlases, alpha sprites,
  color sprites, and fallback RGBA resources while still rejecting blocked color
  glyph atlas resources.
- Store tests now cover no partial transition after invalid frame application,
  accepted alpha atlas and fallback RGBA facts, blocked color atlas, and generation
  mismatch lookup behavior.
- Retained render tests are now a dedicated `test-retained-render` unit-test artifact
  under host `test:unit`; filtered `resource store` runs execute the store tests
  directly instead of only the aggregate test-entry block.
- `applyFrame()` now validates create/upload/retire spans before slicing or copying,
  and store create rejects numeric resource-value reuse until a later ack/removal
  slice defines safe reuse.

Accepted commits:

- `howl-linux-host` `9e2be80` - `host: add protocol v0 resource store`
- root `7b0ae96` - `design: record host resource store`

## Phase 23 Slice: Linux Host V0 Backend Operation Sink

Status: accepted and committed in `howl-linux-host`.

Promoted slice:

- `current.txt` - `Linux Host V0 Backend Operation Sink`

Purpose:

- Define the narrow host-owned operation boundary that will realize V0 resources in
  a backend without requiring a live GUI/GL context in tests.
- Prove create/upload/retire store consequences can emit bounded backend texture
  operations to a recording sink.
- Keep full RGBA upload as the actual rendering path.

Allowed files:

- `howl-linux-host/src/terminal/render/retained.zig`
- this scratchpad

Required shape:

- Operation sink for create texture, upload texture rect, and retire texture.
- Recording test sink with fixed capacity.
- Resource-store application emits copied operation facts while remaining
  fail-closed: invalid frame leaves store state and operation log unchanged.
- No live GL calls, no backend object creation, no V0 drawing, no full-RGBA
  replacement, and no retained upload byte pointers.

Required tests:

- `host retained render resource store records create upload retire ops`
- `host retained render resource store emits no ops on invalid frame`
- `host retained render resource store stops when operation sink is full`

Implementation facts:

- `ProtocolV0BackendOperationRecorder` records copied operation facts for create,
  upload, and retire consequences with fixed caller-owned capacity.
- `ProtocolV0ResourceStore.applyFrameWithRecorder()` applies frame consequences to a
  copied store and copied recorder, then commits both only after all store mutations
  and operation appends succeed.
- Recorded upload operations store byte counts and protocol rectangles only; they do
  not retain upload byte pointers.
- The slice still contains no live GL calls, backend object creation, V0 command
  drawing, or full-RGBA path replacement.

Tests added:

- `host retained render resource store records create upload retire ops`
- `host retained render resource store emits no ops on invalid frame`
- `host retained render resource store stops when operation sink is full`

Reviewer rejection fixes applied:

- Operation recording is now transactional over the backing operation storage, not
  only the recorder count. `applyFrameWithRecorder()` stages operations in a fixed
  local buffer bounded by create/upload/retire maxima and copies into the caller's
  recorder only at commit.
- Invalid-frame and sink-full tests now prefill recorder storage with sentinel
  operations and prove backing storage remains unchanged on failure.
- Store operation emission now validates the V0 command-boundary lifetime order
  before mutation or operation staging. The create/upload/retire recorder test uses
  a valid command boundary and the negative order test proves invalid ordering
  leaves store and recorder storage unchanged.
- Store operation emission now also validates command resource references against
  create, upload visibility, and retire boundaries before mutation or staging.
  Negative tests cover command use after retire and before upload visibility.
- Command-resource validation now accepts an earlier-frame live resource with no
  prior upload when the current frame provides an upload visible to the command.
  A two-frame regression test covers create-only then upload/use.
- Store command validation now rejects unknown command kinds and invalid command
  payload shapes before store mutation or operation staging. A regression test
  proves valid create/upload spans plus an unknown command leave store and recorder
  storage unchanged.
- Store command-shape validation now rejects zero-size clear/fill/sprite payloads,
  sprite commands without storable resources, glyph payloads on non-glyph commands,
  and nonzero `color_rgba` on color sprite commands. Sentinel tests cover zero fill
  and invalid color sprite payloads.
- Sprite command validation now uses the sprite-only resource allow-list instead of
  the broader storeable-resource allow-list. A sentinel test covers `DRAW_SPRITE`
  with a fallback RGBA resource.

Accepted commits:

- `howl-linux-host` `e414553` - `host: record protocol v0 backend operations`
- root `80c9f1e` - `design: record host backend operation sink`

## Phase 24 Slice: Linux Host V0 GL Resource Realization Probe

Status: worker implementation complete; verification passed in this turn.

Promoted slice:

- `current.txt` - `Linux Host V0 GL Resource Realization Probe`

Purpose:

- Realize V0 backend create/upload/retire operations into host-owned GL textures
  during the existing prepared submit turn.
- Keep full RGBA upload as the visible rendering path.
- Stop before V0 command drawing or presentation replacement.

Allowed files:

- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/window/term_texture.zig`
- `howl-linux-host/build.zig` only to wire term texture validation tests
- this scratchpad

Required shape:

- Host-owned GL texture realization for accepted V0 resource operations.
- Realization runs during `submitPreparedLocked()` after prepared upload acquisition
  and before the unchanged full RGBA terminal texture upload.
- Invalid V0 resource realization is accounting-only and must not affect the actual
  full RGBA upload/submit path.
- No V0 command drawing and no presentation replacement.

Implementation facts:

- `PreparedUpload` now carries a borrowed `protocol_v0_frame` pointer for the submit
  turn only. `deinit()` clears it with the rest of the stack upload wrapper.
- `Context.submitPreparedLocked()` realizes V0 resources only when the existing
  resource-plan probe is valid and a borrowed frame is present; the result is
  accounting-only and the full RGBA upload path remains unchanged.
- `term_texture.ProtocolV0Textures` owns GL texture IDs for V0 resources, creates
  textures for V0 creates, uploads V0 upload rects, retires textures, and deletes
  all live V0 textures on terminal context deinit.
- V0 resource textures are not used for drawing or presentation in this slice.
- Review fix: `ProtocolV0Textures` validates create/upload/retire spans and upload
  rect/stride/byte coverage locally before GL upload calls.
- Review fix: submit no longer gates GL realization on the same-frame-only resource
  plan. Persistent V0 texture state validates earlier-frame resources itself.
- Review fix: newly-created V0 GL textures are rolled back if a later GL operation
  in the same frame fails.
- Review fix: `ProtocolV0Textures` now validates upload byte totals/max, resource
  kind/format pairs, sequence bounds, and same-frame create/upload/retire ordering
  locally. Dedicated `test-term-texture` unit tests cover blocked color glyph atlas,
  wrong alpha format, invalid upload order, and upload byte max mismatch.
- Review fix: retired V0 GL texture slots now keep a protocol tombstone after the
  backend texture is deleted, so numeric resource values cannot be reused before a
  future explicit ack/removal slice. A term texture test covers value reuse after
  retire rejection.
- Accepted: live GL resource realization now runs only when the retained V0 resource
  plan is valid, validates top-level frame spans and command shape locally before GL
  mutation, preserves retired resource tombstones, and keeps full RGBA as the visible
  path. Host gates passed with 55/55 tests; root `zig build check`, `zig build test`,
  and `git diff --check` passed. Manual GUI validation remains the gate before V0
  drawing/presentation work.

Accepted verification:

- `howl-linux-host`: `zig build test --summary all`
- `howl-linux-host`: `zig build test:unit --summary all -- "protocol v0 textures"`
- root: `zig build check`
- root: `zig build test`
- root: `git diff --check`

Accepted commits:

- `howl-linux-host` `b191ce5` - `host: realize protocol v0 gl resources`

## Iteration 2: V0 GL Resource Path As Product Work

Status: diagnostic slice promoted, accepted, and committed in `howl-linux-host`.

Current source state before Iteration 2:

- Current source already has V0 ABI/header structs/accessors, emitter, software
  realizer, host resource-plan/oracle probes, and a live host GL probe.
- The prepared-sprite emitter uses temporary sprite resource IDs from same-frame
  sprite index: `value = sprite_index + 1`, `generation = 1`.
- `HowlRenderV0HostAckSpan` exists as a type, but current flow has no accepted
  host-to-render ack/removal call. Host retired tombstones therefore reject reuse;
  `glDeleteTextures()` is not protocol ack.

Iteration 1 proved that live V0 resource realization can be wired into the host, but
GUI review showed the shape is not yet product-quality. The next work is not a
panic hotfix. It is a slow diagnostic and redesign loop against reference-derived
truths.

User GUI findings after Iteration 1:

- `lll` reports command not found, so basic PTY/VT output and simple rendering still
  work.
- `l` freezes the terminal.
- `btop` works while it displays the terminal-too-small warning, but freezes as soon
  as it draws normally.
- Increasing font size can unfreeze `btop` by returning it to the warning screen.
- GUI behavior is a required review gate; command-line tests are not sufficient.

Reference corpus for Iteration 2:

- `utils/dev_references/backends/sdl`
- `utils/dev_references/rendering`
- `utils/dev_references/sdlwiki_md`
- `utils/dev_references/terminals/alacritty`
- `utils/dev_references/terminals/ghostty`
- `utils/dev_references/zig_maturity/tigerbeetle`
- `zig16-release-notes.txt` only when Zig behavior is directly relevant

Reference-derived truths:

- SDL/OpenGL work must prove current-context, current-window, and main-thread
  ownership in `present.zig`/`window.zig` before raw GL calls are trusted.
- GL texture binding, pixel-store, and error state are mutable context-global state;
  V0 probe work must not poison the full RGBA fallback upload or presentation path.
- Ghostty and Alacritty bias toward persistent atlases/resources, explicit upload
  phases, and clear frame/present boundaries. They do not make every draw consequence
  into disposable backend texture churn.
- Reference frame ownership separates resource synchronization, drawing, submit
  acknowledgement, and present/swap. V0 resource upload success is not frame
  correctness.
- Howl V0 is a consequences protocol: render owns protocol facts, upload bytes, and
  ordering; the host owns backend resource realization and presentation policy.
- Full RGBA remains the visible fallback/oracle until V0 presentation is explicitly
  promoted and accepted.
- The full RGBA oracle proves visible byte-equivalence. Host resource-plan validity
  only proves protocol/resource lifetime shape is realizable.
- The current host V0 GL probe realizes create/upload/retire before the normal full
  RGBA upload. Live GL realization is gated by resource-plan validity, not full-byte
  oracle validity; diagnostics must log both statuses.

Iteration 2 working assumptions to prove or kill:

- Draw-heavy content stresses V0 create/upload/retire counts, upload bytes, backend
  allocation churn, or tombstone reuse far more than simple terminal output.
- The current emitter reuses temporary sprite resource IDs across frames while the
  host keeps retired tombstones. Reuse must remain rejected until an accepted
  host-to-render ack/removal call defines when render may reuse IDs.
- Silent GL errors, GL driver stalls, or global GL state leakage can make the visible
  full RGBA path appear frozen even though V0 resources are not presented.
- If an A/B diagnostic gate disables only live V0 GL realization and the freeze
  disappears, the bug is in backend realization side effects, not the PTY/VT/basic
  full-RGBA path.

### Iteration 2 Research Seeds

Research agents must read TigerBeetle first, then the relevant reference corpus, then
Howl source. They must return exact paths, exact symbols, proof gaps, and ranked
diagnostic value. They must not implement.

Seed A: SDL/OpenGL context and state facts.

- Read SDL backend and SDL wiki references for context currentness, window/current
  ownership, swap rules, and thread restrictions.
- Read rendering/OpenGL references for texture upload, delete, pixel-store state,
  `glGetError`, sync/stall behavior, and allocation failure facts.
- Map facts to `howl-linux-host/src/window/term_texture.zig`,
  `howl-linux-host/src/window/present.zig`, `howl-linux-host/src/window/window.zig`,
  and `howl-linux-host/src/terminal/context.zig`.

Seed B: terminal renderer precedent.

- Read Ghostty and Alacritty renderer/atlas/upload/present paths.
- Identify how they avoid per-draw backend texture churn, how uploads are phased, and
  how frame/present boundaries are owned.
- Map those facts to Howl V0 resource realization and full RGBA fallback ordering.

Seed C: Howl protocol and emitter invariants.

- Read `docs/render-protocol-v0.md`, `howl-render/include/howl_render.h`,
  `howl-render/src/protocol_v0/emit.zig`, `howl-render/src/protocol_v0/realize.zig`,
  `howl-render/src/prepared/buffer.zig`,
  `howl-linux-host/src/terminal/render/retained.zig`, and
  `howl-linux-host/src/window/term_texture.zig`.
- Compare host validation against protocol and render-side realizer semantics.
- Identify whether valid draw-heavy frames can trigger excessive churn, hidden
  failures, tombstone pressure, resource exhaustion, or GL upload assumptions.

### Candidate Slice: Linux Host V0 GL Realization Diagnostics

Purpose:

- Make the live V0 GL resource path observable before changing product behavior.
- Preserve full RGBA as the visible path.
- Give the user bounded GUI-review evidence for `lll`, `l`, `btop` warning mode, and
  `btop` normal draw mode.

Allowed files, if promoted:

- `current.txt`
- this scratchpad
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/window/present.zig`
- `howl-linux-host/src/window/term_texture.zig`
- `howl-linux-host/src/window/window.zig`
- Existing host logging/status owner only if one already exists and is a true owner

No ABI/header changes. No render-side emission changes. No V0 command drawing. No
replacement of full RGBA upload. No unbounded logs.

Required diagnostic counters for this slice:

- V0 frame token: `snapshot_seq`, `frame_seq`, `geometry_epoch`, `resource_epoch`.
- Frame spans: creates, uploads, retires, commands, upload byte total.
- Churn shape: same-frame create/upload/use/retire resource count, persistent-resource
  reuse count, resources created without surviving the next frame, and creates per
  visible command.
- Resource slots: live, retired, empty, max live, max retired.
- Host GL side effects: `glGenTextures`, `glTexImage2D`, `glTexSubImage2D`,
  `glDeleteTextures` counts. Keep these separate from render span counts.
- Failure buckets: invalid spans, invalid command shape, invalid order, unsupported
  resource/format, upload bounds, tombstone value reuse, capacity, GL error.
- Timings: V0 realization microseconds, full RGBA upload microseconds, and
  `SDL_GL_SwapWindow` microseconds. Do not use `glFinish` as a diagnostic timing
  fence.
- GL state samples: `GL_TEXTURE_BINDING_2D`, `GL_UNPACK_ALIGNMENT`,
  `GL_UNPACK_ROW_LENGTH`, plus `glGetError()` around V0 create/upload/retire
  phases and before/after full RGBA upload.
- SDL readiness checks for current context, current window, and main-thread access
  belong to `present.zig`/`window.zig`, not `term_texture.zig`.
- Diagnostics must expose churn shape; they must not validate per-draw disposable
  backend texture churn as a product path.

Logging discipline:

- Bounded output only.
- Log first N failures or first N slow frames.
- Prefer counters stored on the true owner and sampled summaries over per-operation
  spam.
- Copy only scalar diagnostics. Never retain frame/span/upload byte pointers and
  never log borrowed upload byte contents.

Optional A/B diagnostic gate:

- A temporary gate may disable only live V0 GL realization while keeping V0 frame
  production, copied scalar diagnostics, software oracle/resource-plan probes, full
  RGBA upload, and presentation unchanged.
- This is diagnostic evidence, not final product behavior.
- Expected proof: if `l` and normal `btop` stop freezing with only this gate off,
  backend resource realization side effects are implicated.
- If disabling V0 GL realization helps, that is still not the fix. Follow-up must
  redesign ownership, lifetime, upload phasing, and context-state handling.

User GUI review matrix:

- `lll`: should still report command not found if no shell alias/binary exists.
- `l`: must not freeze; record whether V0 counters spike before freeze if it does.
- `btop` warning mode: should remain responsive; record counters.
- `btop` normal draw mode: record whether freeze correlates with creates/uploads,
  upload bytes, tombstones, GL errors, realization time, or swap time.
- Resize/font increase: record whether unfreeze correlates with reduced V0 counts or
  a return to warning-screen rendering.

Stop conditions:

- Stop if diagnostics require changing the render ABI/header.
- Stop if diagnostics require V0 command drawing or replacing full RGBA.
- Stop if the fix depends on treating `glDeleteTextures()` as protocol ack.
- Stop if resource ID reuse needs ack/removal policy; draft that contract first.
- Stop if tombstone retention or removal policy is ambiguous.
- Stop if logs would be unbounded or per-byte/per-cell spam.
- Stop if GL current-context ownership is ambiguous; research SDL ownership before
  adding more GL work.
- Stop if SDL current-window, current-context, main-thread, or GL global-state
  ownership remains ambiguous after reading the SDL/OpenGL references.
- Stop after one diagnostic slice and user GUI review; do not roll directly into a
  fix without a reviewed follow-up slice.

Follow-up families after diagnostics, not yet promoted:

- Replace disposable per-draw/per-sprite backend texture churn with persistent
  resource ownership or atlas-backed reuse.
- Add an explicit host ack/removal contract if resource numeric reuse requires it.
- Separate upload synchronization, drawing, submit acknowledgement, and present/swap
  ownership so resource success cannot masquerade as frame correctness.
- Tighten backend context-state handling across upload, submit, and present boundaries.
- Remove or collapse diagnostic scaffolding once a better owner and lifetime model is
  proven.

The older phase outline below is retained as sprint history. Do not promote one of
those slices without first reconciling it with the current source state above.

### Phase 0: Stabilize Current Dirty Host Work

Question:

- What host measurement/pacing changes are accepted enough to commit or set
  aside before render work?

No render product code changes.

### Phase 1: Research And Scratchpad Fill

Run Research Agents A, B, C. Merge outputs into this scratchpad. Do not promote
an implementation slice.

### Phase 2: Protocol Challenge

Run Research Agent D. If D finds the protocol vague or over-broad, revise this
scratchpad before proceeding.

### Phase 3: Contract Draft Slice

Possible `current.txt` slice:

- `Render Protocol V0 Contract Draft`

Allowed files:

- this scratchpad
- optional `docs/render-protocol-v0.md`

No product code.

### Phase 4: ABI Skeleton Slice

Only after contract draft is accepted.

Possible work:

- add protocol structs to headers
- add compile-time size/constant tests
- no host behavior change
- no full-surface deletion yet

### Phase 5: Software Reference Realizer

Only after ABI skeleton is accepted.

Purpose:

- deterministic tests for command stream semantics
- lets us compare command output to current full-surface renderer while we still
  have both paths

### Phase 6: Emit Protocol Alongside Current Surface

Only after software reference realizer is accepted.

Purpose:

- render emits V0 protocol frame and current full surface
- tests prove equivalence for selected workloads

### Phase 7: Host Backend Consumer

Only after protocol emission is accepted.

Purpose:

- Linux host consumes V0 protocol through backend-owned GL resources
- full-surface path remains fallback/debug

### Phase 8: Delete Full-Surface Normal Path

Only after host backend consumer is accepted and measured.

Purpose:

- remove full RGBA prepared surface from normal path
- keep software fallback only where explicitly justified

## Reviewer Gates

Reject any slice that:

- preserves full-surface upload as the normal path without a dated proof gap
- hides resource lifetime
- lacks bounds
- cannot be consumed through C ABI
- turns into a generic scene graph
- invents host-owned render policy inside Howl
- uses backend-specific GL concepts in the render-owned protocol
- lacks tests for ABI sizes, bounds, and invalid inputs
- claims performance progress without measurement

## Immediate Next Action

Do not implement render code.

The next orchestrator action should be one of:

1. Resolve/checkpoint dirty host measurement work.
2. Seed Research Agent A with this scratchpad and exact output contract.

## Phase 26 Slice: Render Protocol V0 Persistent Sprite Resource Emission Probe

Status: accepted and committed in `howl-render`.

Promoted slice:

- `current.txt` - `Render Protocol V0 Persistent Sprite Resource Emission Probe`

Implementation facts:

- `howl-render/src/protocol_v0/emit.zig` now contains a render-owned
  `SpriteResourceStore` for prepared sprite V0 resources.
- Prepared sprite resources use opaque nonzero values allocated monotonically by the
  render store, generation `1`, and no retire/reuse path.
- Prepared emission keys internal lookup from current render-owned sprite facts:
  sprite key, trimmed visual dimensions, resource format, and trimmed upload bytes.
  `SpriteKey` remains internal and is not exposed as ABI identity.
- First observation or changed identity/bytes/dimensions emits create/upload plus the
  draw command. Later frames for the same source-backed sprite emit the draw command
  only, referencing the existing live resource.
- Normal prepared sprite emission emits no retire spans in this slice.
- Prepared emission still builds into copied payload/resource state first and commits
  only after all bounds and byte copies succeed, preserving fail-closed behavior for
  upload-bound/resource failures.
- Persistent sprite identity now stores exact accepted upload bytes up to the private
  `persistent_sprite_resource_bytes_max` bound and compares bytes byte-for-byte
  before reuse. The hash remains only a prefilter; it is not proof of identity.
- `TextSessionOwner` owns the persistent prepared sprite resource store, while each
  prepared owner still owns only its borrowed-frame V0 payload storage.
- `protocol_v0/realize.zig` now has an internal retained software `ResourceStore` and
  `realizeRetained()` path so tests can realize later-frame commands against prior
  uploaded resource bytes.
- Retained realization now validates frame spans, resource transitions, commands,
  pixel length, and base-pixel length before committing creates, uploads, or retires
  to the retained `ResourceStore`.
- Full RGBA remains the oracle/fallback. No C ABI/header, host, V0 drawing,
  presentation, ack/removal, or full-RGBA deletion was changed.

Tests added:

- `protocol v0 emitter persists prepared sprite resource across frames`
- `protocol v0 emitter allocates distinct monotonic sprite resources`
- `protocol v0 emitter allocates distinct resource for changed sprite bytes`
- `protocol v0 emitter allocates distinct resource for changed sprite dimensions`
- `protocol v0 emitter failure preserves accepted persistent resource state`
- `protocol v0 emitter resource capacity failure preserves accepted state`
- `protocol v0 retained realizer rejects invalid frame without store mutation`

Verification performed:

- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

Accepted commits:

- `howl-render` `f8253d1` - `render: persist protocol v0 sprite resources`

## Phase 27 Research: Linux Host Alacritty Runtime Boundary

Status: durable research accepted as implementation input.

Research files:

- `research/2026-05-31-linux-host-alacritty-runtime-boundary.md`
- `research/2026-05-31-linux-host-lock-wake-graph.md`
- `research/2026-05-31-linux-host-ghostty-lock-wake-sanity.md`

Decision:

- Howl must follow the recorded Alacritty runtime boundary before more V0 resource
  work: collect/copy terminal-render state under the terminal lock, release the
  terminal lock, then perform host/backend GL work and diagnostics.
- Ghostty independently reinforces the same lock/wake invariant: do not block or run
  backend work while holding shared terminal/render state locks.
- The next implementation slice is `Linux Host Submit Backend Outside Terminal Lock`.

Source-backed facts:

- Previous Alacritty research already recorded that `Display::draw()` collects
  renderable terminal content and damage under the terminal lock, then drops the lock
  before GL context work, drawing, present notification, swap, and damage advancement.
- Howl's PTY pump is already directionally Alacritty-like: it reads PTY bytes outside
  the terminal data lock and feeds VT under bounded lock limits.
- Howl's violation is render submit: `Context.renderTurn()` holds `term.mutex` across
  `driveRenderLocked()` and `submitPreparedLocked()`.
- `submitPreparedLocked()` currently performs V0 texture realization, GL state
  sampling, `term_texture.ensureSurface()`, full RGBA texture upload, diagnostics
  printing, and then `term.render.submit()` while `term.mutex` is held.
- The PTY wait thread is wake-only and waits for owner ACK; it does not mutate VT or
  render state. Long render critical sections can delay PTY feed and wake ACK.
- Present/swap itself is already host-owned outside `term.mutex`, but present
  completion can queue behind a long render/upload lock.
- Clipboard host calls under `term.mutex` are another ownership smell, but they are
  not part of the first runtime-boundary implementation slice.

Implementation slice shape:

- Locked phase: publish source if needed, choose render action, prepare if needed,
  take `PreparedUpload`, and copy scalar submit metadata.
- Unlocked phase: realize V0 textures, sample GL state, ensure/create host surface,
  upload full RGBA buffer, and emit backend diagnostics.
- Relocked phase: call `term.render.submit()`, update retained render state and
  `term_texture` submit result, then return the render turn result.

Required invariants:

- No `term_texture.*` calls while `term.mutex` is held.
- No V0 GL realization while `term.mutex` is held.
- No GL state sampling while `term.mutex` is held.
- No diagnostic printing while `term.mutex` is held.
- `term.render.prepare()`, `term.render.preparedUpload()`, and `term.render.submit()`
  remain serialized by `term.mutex`.
- Borrowed prepared frame/span/upload byte pointers are consumed synchronously in the
  same owner turn and are never retained.
- Stop if prepared upload lifetime cannot be proved across the unlock/relock window.

Required tests/probes for implementation:

- A fake/test path proves backend realization/upload callbacks observe the terminal
  mutex unlocked.
- A test proves render submit still happens under lock after backend upload.
- A test proves host upload failure returns a failed submit result without losing or
  leaking the prepared upload wrapper.
- Existing present-pending and present-completion behavior remains unchanged.
- Existing host/root verification gates pass.

## Phase 28 Slice: Linux Host Submit Backend Outside Terminal Lock

Status: accepted and committed in `howl-linux-host`.

Promoted slice:

- `current.txt` - `Linux Host Submit Backend Outside Terminal Lock`

Implementation facts:

- `Context.renderTurn()` no longer holds `term.mutex` across host backend upload work.
- The submit path now extracts `PreparedUpload` under `term.mutex`, unlocks for V0
  texture realization, GL state sampling, `term_texture.ensureSurface()`, full RGBA
  texture upload, and submit-path diagnostics, then relocks for `term.render.submit()`.
- `term.render.prepare()`, `term.render.preparedUpload()`, and
  `term.render.submit()` remain serialized by `term.mutex`.
- `render_retained.State.preparedSurfaceHandle()` exposes a minimal identity check so
  the host can assert the retained prepared handle was not replaced across the
  unlocked backend phase.
- Borrowed prepared frame/span/upload byte pointers remain same-turn only and are not
  retained.
- No render ABI, V0 protocol, present cadence, PTY pump/wake, or V0 resource semantic
  changes were made.

Tests added:

- Backend upload observes the terminal mutex unlocked.
- Render submit observes the terminal mutex locked after backend upload.
- Backend upload failure returns failed without render submit.
- Prepared handle mutation after unlocked upload does not submit.

Verification performed:

- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

Accepted commits:

- `howl-linux-host` `fc9b7fc` - `host: move submit backend outside terminal lock`

## Phase 29 Research: Normal `btop` Submit Failure

Status: diagnostic slice promoted to `current.txt`; implementation in progress.

Observation after Phase 28:

- `ll` no longer freezes after moving host backend upload out of `term.mutex`.
- Normal-size interactive `btop` still freezes after drawing its first border frame.
- Reproduction with process accounting shows the SDL/main loop is not asleep: the owner
  loop spins with `render_pending_count=1`, repeated `render_step_failed`,
  `present_submitted=0`, and `present_reason_none` increasing.
- Therefore the next proof gap is not broad event-loop wake admission. The immediate
  failure is a render turn failing before present submission.
- First submit-only diagnostic produced no `howl-debug submit-failed` line during the
  same reproduction, which proves the repeated failure happens before retained submit.
  The slice is widened narrowly to prepare-or-submit failure reasons.
- Host retained diagnostics now report `prepare_handle_failed`, which still collapses
  the actual renderer error. The slice is widened to allow a bounded render-owned
  diagnostic in `TextSessionOwner.prepareHandle()`, where the Zig error is available.
- Render-owned diagnostic reports `CommandBoundOverflow`. This means bounded sidecar V0
  emission aborts the full RGBA prepared owner. That violates the sprint invariant that
  full RGBA remains the visible oracle/fallback until V0 host rendering is explicitly
  promoted. The fix is to keep the prepared RGBA owner live and make the V0 ABI call
  unavailable for that prepared handle when V0 emission overflows.

Relevant current code facts:

- `howl-linux-host/src/terminal/render/retained.zig:prepare()` can fail while taking a
  prepare request or preparing a retained handle.
- `howl-linux-host/src/terminal/context.zig:submitPreparedLockedWith()` can fail before
  submit if `preparedUpload()` fails, backend upload fails, or the retained prepared
  handle changes across the unlocked backend phase.
- `howl-linux-host/src/terminal/render/retained.zig:submit()` can fail from the submit
  decision boundary or from `submitHandle()` returning a non-rendered status.
- `howl-render/src/prepared/owner.zig:executionMatchesPrepared()` rejects submit when
  `execution.uploads_committed` does not match `uploads_required`, or host surface
  dimensions do not match the prepared surface.
- The host currently passes `prepared_upload.buffer.uploads_committed` and the full RGBA
  host surface dimensions into submit after uploading the full RGBA oracle surface.

Promoted slice:

- `current.txt` - `Linux Host Render Failure Reason`

Non-goals:

- Do not change render ABI.
- Do not change V0 protocol semantics.
- Do not bypass submit validation.
- Do not claim full-RGBA upload commits renderer atlas/resource uploads unless the
  renderer contract says so.

## Phase 30 Slice: Protocol V0 Prepared Fill Command Coalescing

Status: promoted to `current.txt`; implementation pending.

Problem:

- Phase 29 fixed the liveness bug by preserving the full-RGBA oracle when V0 sidecar
  emission overflows `HOWL_RENDER_V0_COMMANDS_MAX`.
- The product path still needs V0 to survive fullscreen TUIs without falling back.
- `btop` overflow comes from too many fill-like commands in a full prepared frame.

Promoted slice:

- `current.txt` - `Protocol V0 Prepared Fill Command Coalescing`

Required shape:

- Coalesce only prepared clear/background/decoration/cursor fill commands.
- Merge only horizontally adjacent rectangles with identical kind, color, `y_px`, and
  `height_px`, and only when merged width fits `u16`.
- Do not reorder consequences or merge across sprite/glyph commands.
- Keep V0 sidecar unavailable fallback intact when the command bound is still exceeded.

Implementation facts:

- `howl-render/src/protocol_v0/emit.zig` now merges prepared fill-like commands when
  the immediately preceding command has identical kind/color/row/height and the new
  rectangle starts exactly at the prior rectangle end.
- Coalescing is order-preserving and only crosses commands already adjacent in the same
  prepared pass; it does not reorder or merge through sprites/glyphs.
- Merged width is checked against `u16`; overflow keeps commands separate and preserves
  the existing bounded failure behavior.
- Protocol proof tests cover successful coalescing and non-coalescing for distinct
  color, row, kind, and non-adjacent rectangles.

Automated reproduction:

- `btop` under host timeout no longer emits render failures.
- First observed V0 frame command count dropped from `131` before coalescing to `66`
  after coalescing in the same automated run shape.
- `present_submitted` advanced and `render_step_failed=0` in accounting output.

Verification performed:

- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `git diff --check`
- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`
