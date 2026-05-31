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

Status: worker implementation complete; verification passed in this turn.

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

## Sprint Phases

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
