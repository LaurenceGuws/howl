# Howl Render Protocol Sprint

Owner: workspace root.

Status: sprint seed. No product code is authorized by this document yet.

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

Checkpoint remains uncommitted pending an explicit commit decision.

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
