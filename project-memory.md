# Project Memory

Owner: workspace root.

Purpose: canonical, timestamped index for durable scratchpad facts. Older root
scratchpads may remain as archive pointers when their durable facts have been
moved here.

Rules:

- Read `AGENTS.md`, `loop.txt`, and the TigerBeetle references before non-trivial work.
- Preserve source-backed facts, accepted decisions, proof gaps, and follow-up slices.
- Treat stale slice specs as historical unless this file marks them active.

## 2026-05-30 Workflow And Boundary Law

- Product boundary: Howl is a C ABI embeddable terminal.
- Hosts embed `howl-pty`, `howl-vt`, `howl-render`, and `howl-hosts/vendor/*` contracts.
- Hosts own platform UX, event loops, wake policy, presentation cadence, runtime
  orchestration, and backend resource realization.
- `howl-pty` owns PTY variants, child I/O, resize delivery, control signals, and
  transport state.
- `howl-vt` owns parser state, terminal state, selection, input encoding,
  host-facing protocol consequences, and VT-surface truth.
- `howl-render` owns render contracts, geometry policy, retained-frame state,
  prepare/submit scheduling, render-surface contracts, and text shaping.
- Public roots curate exports only. Namespace wrappers aggregate owners only. FFI
  translates contracts only. Owner files own state and mutation.
- Banned owner vocabulary remains banned unless a later accepted scratchpad says
  otherwise: `manager`, `engine`, `controller`, `utils`, `runtime`, `pipeline`,
  `queue`, ownerless `types.zig`, and broad compatibility aliases.
- Design source order: Ghostty, Alacritty, TigerBeetle, official docs, then the
  smallest Howl-specific invention.

## 2026-05-30 Host Canonical Memory

Canonical source scratchpads archived into this section:

- `host-owner-next-scratchpad.md`
- `host-reshape-scratchpad.md`
- `host-alacritty-gap-scratchpad.md`
- `cleanupscratchpad.md` host portions

### Current Host Facts

- `howl-linux-host/src/main.zig` currently owns process bootstrap,
  event-loop admission, terminal input forwarding, tab lifecycle, present
  submission/completion, and tests.
- `howl-linux-host/src/tab_bar/slots.zig` owns bounded tab slot storage/order.
- `howl-linux-host/src/window/pacing.zig` owns frame-pacing state, pending-loop
  input, and present-permission reasons.
- `howl-linux-host/src/terminal/context.zig` currently owns one terminal
  surface/session aggregate: PTY/VT/render lifecycle, text and pointer event
  routing, cursor blink cadence, clipboard OSC 52 writes, render
  prepare/submit/upload, title refresh, scrollbar adaptation, and tests.
- `howl-linux-host/src/terminal/selection.zig` owns host selection gesture
  adaptation over context-owned selection fields.
- `howl-linux-host/src/terminal/links.zig` owns visible-link hover/open behavior
  over context-owned link fields.
- `howl-linux-host/src/input/input.zig` owns SDL event pumping, input queues,
  binding queueing, text chunking, key and mouse translation, redraw request bit,
  geometry/focus pending bits, and tests.
- Production SDL/OpenGL translation is build-owned through `sdl_c` and `gl_c`.
- `window.c_win` has been deleted. Remaining direct `@cImport` sites are explicit
  non-goals from that slice: `window/icon.zig`, `stress/ascii_rain_stress.zig`,
  and `stress/visual_rain_stress.zig`.
- Historical host reshapes are already reflected in current code: old
  `terminal/runtime`, old `terminal/host`, and `terminal_panel.zig` vocabulary
  were superseded by `terminal/context.zig` and owner subfolders.
- Prior host cadence work is already present: `FramePacing.State`,
  `FramePacing.PresentReason`, `PresentPlan`, separate present completion,
  `DrainInputOutcome`, `drainTextInputFastPath`, and `drainPointerAndUiInput`.
- `terminal/c.zig` has been deleted; Howl PTY/VT/render C imports are
  build-owned modules.

### Host Reference Facts

- Ghostty `App` owns the primary GUI run loop and dispatches explicit mailbox
  actions; `Surface` is one terminal widget/session aggregate; `Termio` owns
  terminal state, PTY, subprocess, and byte I/O; its mailbox is explicitly
  bounded.
- Alacritty startup creates window, terminal state, PTY, I/O loop, input
  processor, config monitor, and runs a display loop. `Processor` owns event
  dispatch and windows map. `WindowContext` owns one terminal window aggregate.
  Scheduler topics include selection scrolling, delayed search, blink cursor,
  blink timeout, and frame.
- Alacritty processes renderer updates right before drawing, couples grid resize
  with PTY resize and damage tracker resize, collects renderable content while
  holding the terminal lock, then drops the lock before drawing.
- TigerBeetle pressure: explicit bounded control flow, assertions for invariants,
  central control/state mutation, and processing external events at the program's
  own pace.

### Accepted Host Direction

- Keep moving toward an Alacritty/Ghostty split:
- Top-level app/event processor owns event-loop dispatch, tab/window list,
  scheduler/pacing, and routing.
- Per-terminal context owns one embedded terminal widget/session and exposes exact
  effects to the app.
- Window/display/present owners own backend realization and presentation.
- Input owner translates SDL events into host input events but must not own
  terminal widget policy.
- Cross-thread/wake paths must stay bounded and explicit.
- Do not infer a giant target tree. Promote one reference-backed seam at a time.

### Completed Host Slices On 2026-05-30

- `dfa66b5 host: move tab slots owner` and root `2181e7e`.
- `11b21eb host: move frame pacing owner` and root `8beb52d`.
- `742ef69 host: delete window c bucket` and root `313526a`.
- `6477dcb host: split terminal pointer owners` and root `ce87dfb`.

### Active Host Follow-Up Slices

- No promoted host follow-up slice is active after the 2026-05-30 owner cleanup.
- Future work should start from fresh research against current source, not the
  archived pre-cleanup slice specs.

### Host Verification Gates

- Host package: `zig build check`, `zig build test`.
- Root: `zig build check`, `zig build test`, `git diff --check`.
- Preserve ABI boundary: host code consumes PTY, VT, and render only through
  shipped C ABI contracts and build-owned translated modules.

## 2026-05-30 Render And VT ABI Canonical Memory

Canonical source scratchpads archived into this section:

- `render-host-boundary-scratchpad.md`
- `render-vt-abi-decoupling-scratchpad.md`
- `render-ownership-restart-scratchpad.md`
- `cleanupscratchpad2.md`
- `cleanupscratchpad3.md`
- `cleanupscratchpad.md` render portions

### Fixed Render/Host Boundary

- Backend independence is the first priority of the render ABI.
- `howl-render` must never own publication to a backend.
- Hosts own event loops, wake policy, redraw request policy, presentation cadence,
  runtime orchestration, backend resource realization, scheduling, and backend
  publication.
- `howl-render` exposes a C ABI state engine: host-owned data and calls in,
  prepared render data and explicit consequences out.
- `howl-render` must not hide a runtime loop, scheduler, presentation queue,
  swapchain, or backend frame lifecycle.
- `submit` means the host consumed a prepared output and render may update
  retained render-owned state. It must not mean publish or present to a backend.

### Render/VT ABI Decoupling Facts

- `howl-render/include/howl_render.h` previously included `howl_vt.h` and exposed
  VT-owned cell/color/selection/cursor types through render public ABI. This is
  an ownership violation.
- Source-backed verdict: VT owns terminal state truth; render owns render source
  ABI structs, retained prepare state, shaping, caching, prepared surfaces, and
  submit contracts; a boundary adapts VT truth into render source/draw data.
- Ghostty supports VT-owned render-state/surface APIs under VT-facing headers, not
  a renderer backend public ABI importing terminal state structs.
- Alacritty adapts terminal cells into `RenderableCell`; renderer consumes
  renderable cells, glyphs, batches, vertices, rectangles, and atlas state. It
  does not expose raw terminal `Cell` as a renderer public API.
- Kitty is monolithic and private; it does not justify a public renderer ABI
  importing terminal structs.

### Current Render Facts

- `howl-render/src/source/vt.zig`, `source/cell.zig`, `source/slot.zig`,
  `source/damage.zig`, `source/prepare_request.zig`, `render/geometry.zig`,
  and `session/submitted.zig` are the accepted direction after the `flow.zig`
  restart.
- `SurfaceTextOwner` should compose explicit owners: geometry, source slot,
  prepare requests, submitted state, source dirty epoch, and cursor blink phase.
- `source/*` owns VT-derived input snapshots, publication storage, dirty/source
  metadata, source validation, and source publication to text-scene/frame-input
  adaptation.
- `prepared/*` owns prepared render output and prepared-handle lifecycle only.
- `session/*` composes the public render object behind the C handle and owns
  submitted/retained token state and submit mailbox decisions.
- `render/*` owns text rendering and render geometry, not VT source slot storage.
- `surface` is a product term at the ABI boundary, not an umbrella source folder.
- `howl-render/src/source/text_input.zig` owns the final source-to-text adapter
  formerly stored at `surface/input.zig`; do not recreate `howl-render/src/surface/`.
- The render C translator lane is complete in current source: `libhowl_render.zig`
  is an export table importing `ffi/*` translator nouns, with `ffi.zig` as the
  shared C import/boundary entry. Do not promote old roadmap slices that move
  root translator files unless fresh source shows root translators returned.
- The render text `pipeline.zig` proof gap is complete in current source:
  `howl-render/src/text/pipeline.zig` no longer exists and no render Zig source
  contains `pipeline`, `text_pipeline`, or `text_flow` owner vocabulary.

### Accepted Render Direction

- No `howl-render/src/surface/flow.zig` and no `Flow` owner.
- No generic mixed `surface/types.zig` by the end of the restart.
- No new umbrella `screen`, `surface`, `pipeline`, `queue`, `manager`,
  `controller`, or `runtime` bucket.
- Input/source and output/prepared/submitted owners must be separate files and
  separate fields in the session owner.
- Render still does not own backend presentation or host cadence.
- Host continues through the shipped C ABI.

### Render ABI Vocabulary Decisions

- ABI breakage is allowed and preferred over preserving wrong vocabulary.
- No compatibility shims or old-name aliases.
- Suspicious/wrong nouns from prior research:
  `HowlRenderSurfaceFeedback`, `surface_feedback.zig`, frame vocabulary,
  vague object wrappers, `SurfaceText`, `PreparedFrame`, `PendingState`, and broad
  `surface/*` bucket names.
- Owner-true replacement direction:
  `HowlRenderTextSession`, `HowlRenderTextSessionHandle`,
  `HowlRenderPreparedSurface`, `HowlRenderPreparedSurfaceHandle`,
  `HowlRenderLayoutResult`, `HowlRenderVtSurfaceSlot`,
  `HowlRenderVtSurfaceCommit`, `HowlRenderVtSurfacePublishResult`,
  `HowlRenderPreparedSurfaceToken`, `HowlRenderSubmittedSurfaceToken`,
  `HowlRenderSubmitExecution`, `HowlRenderSubmitResult`,
  `HowlRenderHostSurface`, `HowlRenderMetrics`, and
  `HowlRenderSessionWorkState`.
- First ABI vocabulary slice from research remains worker-ready if chosen:
  replace submit feedback/execution/surface handle vocabulary.
  Header renames: `HowlRenderSurfaceMetrics -> HowlRenderMetrics`,
  `HowlRenderSurfaceHandle -> HowlRenderHostSurface`,
  `HowlRenderSurfaceExecutionInput -> HowlRenderSubmitExecution`,
  `HowlRenderSurfaceFeedback -> HowlRenderSubmitResult`. Update render boundary
  translators and host call sites in `terminal/context.zig`,
  `terminal/render/retained.zig`, `terminal/render/abi.zig`, and
  `window/term_texture.zig`. No old typedefs or aliases.

### Render Source Publication Slice

Accepted no-header-change shape from `cleanupscratchpad2.md`:

- Source owner stores the writable publication cell span directly. FFI casts and
  returns the stable C span, then delegates commit/validation/cancel policy to
  source/session owners.
- `source/vt.zig` owns `SourceCell`, `SourceCellFlags`, `SourceCellAttrs`,
  `SourceColor`, `SourceColors`, `SourceSelection`, and `SourceSelectionPoint`;
  it validates source cells, colors, underline style, and `ReservedSourceMeta`.
- `source/slot.zig` owns retained `[]source_vt.SourceCell`, reserves the source
  span, validates source cells and dirty metadata during commit, and preserves
  retained storage behavior.
- `ffi.zig` must not own global publication scratch or source policy. It owns only
  C pointer casts, span translation, C status mapping, and layout assertions.
- Grep gates in `ffi.zig`: no `PublishScratch`, `ScratchMutex`, `publish_scratch`,
  `reservePublishScratch`, `copyPublishScratch`, `removePublishScratch`,
  `validatePublicationCellValue`, `reservedSource`, or `owner.source_slot`.

### Render Verification Gates

- Root: `zig build check`, `zig build test`, `git diff --check`.
- If root taxonomy blocks package-specific verification, run in `howl-render`:
  `zig build check`, `zig build test`.
- ABI gates: `howl-render/include/howl_render.h` must not expose `HowlVt*` types
  from the render public ABI after the decoupling slice; render source must not
  layout-assert against `c.HowlVt*` except at explicit FFI translation seams.

## 2026-05-30 Feature Gap Backlog

Canonical source scratchpad archived into this section:

- `feature-gap-scratchpad.md`

Active gaps to preserve:

1. Hyperlink targets stop at `link_id`.
   VT interns OSC 8 URIs and stamps visible cells with `link_id`, but the product
   ABI needs a lookup/lifetime contract so host hover/open can resolve IDs to URIs.
   Important paths: `howl-vt/src/host/state.zig`, `howl-vt/src/ffi.zig`,
   `howl-vt/include/howl_vt.h`, `howl-render/include/howl_render.h`,
   `howl-linux-host/src/terminal/context.zig`.
2. VT-owned selection has no complete product boundary above VT.
   Need a C ABI selection contract across viewport/history coordinates and
   render/host presentation/copy behavior, or an explicit out-of-scope decision.
   Important paths: `howl-vt/src/selection.zig`, `howl-vt/src/selection/state.zig`,
   `howl-vt/include/howl_vt.h`, `howl-render/include/howl_render.h`,
   `howl-linux-host/src/terminal/context.zig`.
3. OSC 52 clipboard requests need host-owned policy completion.
   VT exposes pending clipboard drain; host must drain after VT feed and apply
   platform clipboard policy. Clipboard read/query still needs request/reply ABI
   if supported.
4. Dynamic terminal color state must become render truth.
   VT implements OSC 4/10-19 dynamic colors. Render must consume ABI-visible
   color state instead of fixed render-local defaults.
5. Kitty graphics export is closed.
   VT graphics truth is now exportable above VT through shipped ABI and consumed
   by host/render.
6. PTY child exit/transport-stop truth is closed.
   PTY ABI now carries typed lifecycle/result truth, including active-tab
   exit/failure distinctions used by host.
7. PTY resize success does not prove child-visible size was applied.
   Need ABI-visible applied-vs-requested resize state or typed resize result/error.
8. PTY control-signal ABI lacks foreground-process identity truth.
   Need process identity or foreground-group truth and explicit signal-target semantics.
9. VT cell style and visibility attrs must survive render scene prep.
   Render intake sees style/visibility/link attributes; scene prep must preserve
   bold, dim, italic, inverse, invisible, and link metadata.
10. Dynamic VT title should reach SDL window title if host policy wants active-tab
    title ownership.
11. Cursor blink state is lost at VT surface/render seam.
    Carry VT cursor `blink` truth through ABI while keeping cadence host-owned;
    host config should seed default/reset policy without overriding DECSCUSR truth.

## 2026-05-30 VT Hygiene Decisions

Canonical source scratchpads archived into this section:

- `research/2026-05-30-hygiene-audit/vt-host-consequence-capacity.md`
- `research/2026-05-30-hygiene-audit/vt-screen-owner-seams.md`
- `research/2026-05-30-hygiene-audit/vt-runtime-obligation-vocabulary.md`

Accepted decisions:

- `runtime` is accepted ABI and host scheduling vocabulary when it names a VT
  scheduling obligation or host wake/admission fact.
- `runtime` remains banned as an owner or module name. Do not add `runtime.zig`,
  `RuntimeManager`, or a VT runtime owner.
- VT host consequence storage is bounded but heap-backed today. Pending output,
  retained payloads, retained metadata, titles, hyperlink target count, and parser
  event count have explicit owner constants; static storage conversion still needs
  product capacity proof.
- Screen dirty state is the first accepted deeper screen seam. History authority,
  resize temporary storage, cursor, margins, and tabs require later scratchpads or
  promoted slices before movement.
- VT protocol scalar vocabulary Slice A is complete in current source for its
  originally promoted scope: `xterm/c0.zig` has a typed `C0` enum and
  `action/vocabulary.zig` carries erase operations as `EraseMode`, not raw `u2`.
  Future scalar work must start from fresh source-backed research, not the stale
  Slice A checklist.

## 2026-05-30 Build/Test Architecture Blocker

Canonical source scratchpad archived into this section:

- `build-test-architecture-blocker-scratchpad.md`

Blocker:

- Repo-wide verification surface and build/entrypoint contracts are fragmented.
- There is no clearly documented strategy for test taxonomy, build-step taxonomy,
  install/default-step behavior, package ownership of verification surfaces, or
  auditability of what each step proves.

Consequence:

- Adding more tests, tools, fuzzers, harnesses, and run/build entrypoints without
  a governing plan increases confusion and review cost.

Research goal:

- Produce a comprehensive repo-wide plan covering current inventory,
  classification, gaps, normalization targets, migration order, and acceptance
  criteria.

Constraint:

- Planning only until a follow-up review loop accepts a code/build change slice.
