1. Paths read
Mandatory first reads:
- /home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md
- /home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md
Project/workflow/scratchpads:
- /home/home/personal/projects/howl/AGENTS.md
- /home/home/personal/projects/howl/loop.txt
- /home/home/personal/projects/howl/current.txt
- /home/home/personal/projects/howl/cleanupscratchpad2.md
- /home/home/personal/projects/howl/render-ownership-restart-scratchpad.md
Howl render ABI/source:
- /home/home/personal/projects/howl/howl-render/include/howl_render.h
- /home/home/personal/projects/howl/howl-render/src/libhowl_render.zig
- /home/home/personal/projects/howl/howl-render/src/ffi.zig
- /home/home/personal/projects/howl/howl-render/src/surface_text.zig
- /home/home/personal/projects/howl/howl-render/src/surface_geometry.zig
- /home/home/personal/projects/howl/howl-render/src/publish_slot.zig
- /home/home/personal/projects/howl/howl-render/src/prepare_request.zig
- /home/home/personal/projects/howl/howl-render/src/prepared_surface.zig
- /home/home/personal/projects/howl/howl-render/src/submission.zig
- /home/home/personal/projects/howl/howl-render/src/pending_state.zig
- /home/home/personal/projects/howl/howl-render/src/surface_feedback.zig
- /home/home/personal/projects/howl/howl-render/src/handle.zig
- /home/home/personal/projects/howl/howl-render/src/source/vt.zig
- /home/home/personal/projects/howl/howl-render/src/source/cell.zig
- /home/home/personal/projects/howl/howl-render/src/source/slot.zig
- /home/home/personal/projects/howl/howl-render/src/source/damage.zig
- /home/home/personal/projects/howl/howl-render/src/source/prepare_request.zig
- /home/home/personal/projects/howl/howl-render/src/prepared/surface.zig
- /home/home/personal/projects/howl/howl-render/src/prepared/feedback.zig
- /home/home/personal/projects/howl/howl-render/src/session/submitted.zig
- /home/home/personal/projects/howl/howl-render/src/surface/text.zig
- /home/home/personal/projects/howl/howl-render/src/surface/prepared_owner.zig
- /home/home/personal/projects/howl/howl-render/src/surface/tokens.zig
- /home/home/personal/projects/howl/howl-render/src/surface/input.zig
- /home/home/personal/projects/howl/howl-render/src/surface/submit_feedback.zig
- /home/home/personal/projects/howl/howl-render/src/render/geometry.zig
- /home/home/personal/projects/howl/howl-render/src/render/geometry_contract.zig
Host render ABI call sites:
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/render/abi.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/render/frame_layout.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/surface.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig
- /home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig
Alacritty reference:
- /home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs
- /home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs
- /home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs
2. User choices restated as accepted constraints
Accepted constraints for this research:
- The render C ABI is the product.
- ABI breakage is allowed and preferred over preserving wrong vocabulary.
- Do not keep stale names for stability.
- No compatibility shims or old-name aliases.
- No module-wide wrapper that hides unrelated source/prepare/prepared/submit state.
- Current suspicious names are guilty until proved:
- HowlRenderSurfaceFeedback
- surface_feedback.zig
- Frame vocabulary
- vague object wrappers
- SurfaceText
- PreparedFrame
- PendingState
- broad surface/* bucket names
- Clean the ABI until nouns are owner-true.
- Do not create types.zig.
- Do not introduce manager, controller, runtime, flow, pipeline, or queue buckets.
- Public roots curate exports only.
- Boundary files translate contracts only.
- Real ownership belongs in source/*, render/*, prepared/*, and session/*.
No source-backed pressure conflicts with these choices. Alacritty and TigerBeetle both support breaking wrong vocabulary now.
3. Alacritty facts and TigerBeetle pressure
Alacritty facts
- Terminal source truth is terminal-owned.
- term/mod.rs:268-330: Term<T> owns grid, inactive_grid, selection, colors, cursor style, and damage: TermDamageState.
- Terminal damage is terminal-owned.
- term/mod.rs:216-226: TermDamageState stores full, damaged lines, and last cursor.
- term/mod.rs:447-490: Term::damage() publishes terminal damage and requires reset_damage() after reading.
- Terminal exposes render input, it does not become display/render owner.
- term/mod.rs:635-642: Term::renderable_content() returns terminal content for rendering.
- Display adapts terminal content into renderable cells.
- display/content.rs:24-38: RenderableContent wraps terminal content plus display/config facts.
- display/content.rs:41-88: RenderableContent::new() borrows term.renderable_content().
- display/content.rs:208-299: RenderableCell::new() adapts terminal cell state into display/render cell state.
- Display owns frame damage separately from terminal damage.
- display/damage.rs:12-28: DamageTracker owns display-frame damage.
- display/damage.rs:56-73: swap_damage() advances frame damage.
- display/damage.rs:138-147: FrameDamage is display-frame damage, not terminal/source truth.
- display/damage.rs:215-274: RenderDamageIterator converts terminal line damage into renderer rectangles.
TigerBeetle pressure
- Naming must be exact: TIGER_STYLE.md:271-277 says get nouns and verbs just right.
- Do not overload names: TIGER_STYLE.md:337-347.
- Assert boundaries and invariants: TIGER_STYLE.md:104-139.
- Keep control/data-plane separation and batching explicit: ARCHITECTURE.md:408-423.
- Static/bounded ownership pressure: ARCHITECTURE.md:189-222.
- Avoid fake-simple abstractions: TIGER_STYLE.md:90-94.
Conclusion: feedback, frame, SurfaceText, and PendingState are too vague for a product ABI. Alacritty uses “frame” specifically for display damage, while Howl render’s ABI is about VT source publication, prepared render surfaces, submit execution, and submitted state. Howl should not use Frame as the render ABI identity noun.
4. Complete inventory of howl_render.h, grouped by current vocabulary
Opaque handles / object wrappers
- HowlRenderSurfaceText
- HowlRenderPreparedSurfaceObject
- HowlRenderSurfaceTextHandle
- HowlRenderPreparedSurfaceHandle
Status enums
- HowlRenderCallStatus
- HowlRenderDamageKind
- HowlRenderPrepareStatus
- HowlRenderSubmitStatus
- HowlRenderSubmitDecisionStatus
Geometry/layout
- HowlRenderPixelSize
- HowlRenderCellSize
- HowlRenderGridSize
- HowlRenderGeometry
- HowlRenderGeometryResponse
- HowlRenderFrameLayoutResult
- howl_render_surface_text_derive_frame_layout
- howl_render_surface_text_sync_geometry
Drawing/pixel spans
- HowlRenderRgba8
- HowlRenderColorDraw
- HowlRenderDecorationDraw
- HowlRenderRasterBounds
- HowlRenderColorDrawSpan
- HowlRenderDecorationDrawSpan
- HowlRenderByteSpan
- HowlRenderU16Span
- HowlRenderByteWriteSpan
- HowlRenderU16WriteSpan
Render cell vocabulary currently unused/wrong at ABI surface
- HowlRenderCellFlags
- HowlRenderColor
- HowlRenderCellAttrs
- HowlRenderCell
- HowlRenderCursor
These are suspicious because source publication actually uses HowlVtSurfaceCell, not HowlRenderCell.
Pending/work state
- HowlRenderPendingState
- howl_render_surface_text_pending_state
Prepare/prepared frame vocabulary
- HowlRenderPrepareRequest
- HowlRenderPreparedFrame
- howl_render_surface_text_take_prepare_request
- howl_render_surface_text_publish_prepared
- howl_render_surface_text_take_submit_decision
- howl_render_surface_text_accept_submitted
VT publish/source vocabulary
- HowlRenderVtPublishResult
- HowlRenderVtCellWriteSpan
- HowlRenderPublishSlot
- HowlRenderPublishSlotCommit
- howl_render_surface_text_reserve_publish_slot
- howl_render_surface_text_commit_publish_slot
- howl_render_surface_text_reject_publish_slot
- howl_render_surface_text_cancel_publish_slot
Metrics / host surface / execution / feedback
- HowlRenderSurfaceMetrics
- HowlRenderSurfaceHandle
- HowlRenderSurfaceExecutionInput
- HowlRenderSurfaceFeedback
Text config and text session functions
- HowlRenderSurfaceTextConfig
- howl_render_surface_text_init
- howl_render_surface_text_deinit
- howl_render_surface_text_is_valid_font
- howl_render_surface_text_set_font_size_px
- howl_render_surface_text_set_font_path
- howl_render_surface_text_set_fallback_font_paths
- howl_render_surface_text_set_cursor_blink_visible
Prepared-surface handle API
- HowlRenderPreparedSurfaceInfo
- HowlRenderPreparedSurfaceBuffer
- HowlRenderPreparedSurfaceDiagnostics
- howl_render_surface_text_prepare_handle
- howl_render_prepared_surface_release
- howl_render_prepared_surface_describe
- howl_render_prepared_surface_buffer
- howl_render_prepared_surface_diagnostics
- howl_render_surface_text_publish_prepared_handle
- howl_render_surface_text_take_submit_handle
- howl_render_surface_text_submit
- howl_render_surface_text_submit_handle
5. Findings: wrong/vague ABI nouns and owner-true replacements
SurfaceText / HowlRenderSurfaceTextHandle
Wrong because it sounds like a surface object plus text property, but the object is a render session coordinating source publication, prepare requests, prepared handle lifecycle, submitted state, font config, geometry, and retained pixels.
Replacement:
- HowlRenderTextSession
- HowlRenderTextSessionHandle
- functions prefix: howl_render_text_session_*
Internal owner:
- move public session owner from surface/text.zig toward session/text.zig.
HowlRenderSurfaceFeedback
Wrong because “feedback” is vague. It is not user feedback, not renderer feedback, not host feedback. It is the result of a host execution/submission path: submitted host surface, damage kind, metrics.
Replacement:
- HowlRenderSubmitResult
Internal replacement:
- prepared_feedback.RenderSurfaceFeedback -> prepared_submit.SubmitResult or prepared/submit.zig.
- surface_feedback.zig -> boundary file submit_result.zig.
HowlRenderSurfaceExecutionInput
Wrong because “execution input” hides that the host has already realized/uploads the prepared surface and is asking render to accept the submission.
Replacement:
- HowlRenderSubmitExecution
Fields can remain initially:
- host_surface
- uploads_committed
- render_us
HowlRenderSurfaceHandle
Wrong because “surface handle” sounds like an owned render object, but it is a host-owned backend surface/texture id.
Replacement:
- HowlRenderHostSurface
Frame / HowlRenderPreparedFrame
Wrong because Howl render does not own presentation frames. Alacritty’s FrameDamage is display-frame damage, not prepared render identity. Howl’s struct is a prepared surface identity plus retained-base requirement.
Replacement:
- HowlRenderPreparedSurfaceToken
Internal:
- tokens.PreparedFrame -> PreparedSurfaceToken
- tokens.SubmittedFrame -> SubmittedSurfaceToken
- prepared.pipelineFrame() -> preparedSurfaceToken()
HowlRenderFrameLayoutResult
Wrong because it computes text layout/grid/cell size, not host frame presentation.
Replacement:
- HowlRenderLayoutResult
- function: howl_render_text_session_derive_layout
PendingState
Wrong because “pending” lacks owner and work kind. It exposes session work state.
Replacement:
- HowlRenderSessionWorkState
- function: howl_render_text_session_work_state
PublishSlot
Partly acceptable but too generic. The thing published is VT/source surface input.
Replacement:
- HowlRenderVtSurfaceSlot
- HowlRenderVtSurfaceCommit
- HowlRenderVtSurfacePublishResult
SurfaceMetrics
Too broad. Metrics are render/prepare/resolve/submit metrics, not a surface object.
Replacement:
- HowlRenderMetrics
surface_feedback.zig
Wrong because it is a boundary translator named after a bad ABI noun.
Replacement:
- submit_result.zig
surface/tokens.zig
Wrong location: surface is an umbrella bucket; tokens govern session source/prepared/submitted identities.
Replacement:
- session/snapshot.zig or session/tokens.zig
- Prefer session/snapshot.zig if names become SnapshotToken, PreparedSurfaceToken, SubmittedSurfaceToken.
prepared/feedback.zig
Wrong noun. It contains host surface, metrics, and submit result.
Replacement:
- split:
- prepared/metrics.zig
- prepared/submit.zig
- possibly prepared/host_surface.zig
SurfaceText internal struct
Acceptable only as an implementation-specific text renderer if moved/named as text renderer owner. Better:
- render/text.zig: TextRenderer
- session/text.zig: TextSession
6. Proposed cleaned ABI vocabulary and file layout under howl-render/src
Clean ABI product nouns
Opaque/session:
- HowlRenderTextSession
- HowlRenderTextSessionHandle
- HowlRenderPreparedSurface
- HowlRenderPreparedSurfaceHandle
Geometry/layout:
- HowlRenderPixelSize
- HowlRenderCellSize
- HowlRenderGridSize
- HowlRenderGeometry
- HowlRenderGeometryResult
- HowlRenderLayoutResult
VT source input:
- HowlRenderVtSurfaceSlot
- HowlRenderVtSurfaceCommit
- HowlRenderVtSurfacePublishResult
Prepare:
- HowlRenderPrepareRequest
Prepared output:
- HowlRenderPreparedSurfaceToken
- HowlRenderPreparedSurfaceInfo
- HowlRenderPreparedSurfaceBuffer
- HowlRenderPreparedSurfaceDiagnostics
Submit/submitted:
- HowlRenderSubmitDecisionStatus
- HowlRenderSubmitStatus
- HowlRenderSubmitExecution
- HowlRenderSubmitResult
- HowlRenderSubmittedSurfaceToken
Host-owned resource:
- HowlRenderHostSurface
Metrics:
- HowlRenderMetrics
Work state:
- HowlRenderSessionWorkState
Text config:
- HowlRenderTextConfig
Proposed internal layout
howl-render/src/
  ffi.zig                         # C import only.
  libhowl_render.zig              # Export curation only.
  text_session.zig                # C boundary for session init/font/cursor.
  geometry.zig                    # C boundary for layout/geometry.
  vt_surface.zig                  # C boundary for VT source slot/commit/reject.
  prepare_request.zig             # C boundary for prepare request translation.
  prepared_surface.zig            # C boundary for prepared handle describe/buffer/diagnostics.
  submit.zig                      # C boundary for publish/take/submit/submit result.
  work_state.zig                  # C boundary for session work state.
  handle.zig                      # Opaque handle translation only.
  source/
    vt.zig
    cell.zig
    slot.zig
    damage.zig
    prepare_request.zig
  render/
    geometry.zig
    geometry_contract.zig
    text.zig
    input.zig
  prepared/
    surface.zig
    owner.zig
    buffer.zig
    metrics.zig
    submit.zig
    host_surface.zig
  session/
    text.zig
    submitted.zig
    snapshot.zig
Deletions/renames implied:
- Delete surface_feedback.zig.
- Delete/rename surface/submit_feedback.zig.
- Move surface/text.zig session owner to session/text.zig; text renderer implementation to render/text.zig.
- Move surface/prepared_owner.zig to prepared/owner.zig.
- Move surface/tokens.zig to session/snapshot.zig.
- Move surface/input.zig to render/input.zig.
- Keep surface/* only if it means actual rendered surface contracts; current surface folder is still too broad.
7. Host impact: exact host files/functions that must change for first ABI slice
First slice proposed below targets Feedback / submit-result vocabulary.
Host files/functions impacted:
/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig
- submitPrepared() lines 573-586:
- HowlRenderSurfaceFeedback -> HowlRenderSubmitResult
- HowlRenderSurfaceExecutionInput -> HowlRenderSubmitExecution
- feedback.surface -> result.host_surface or result.surface depending exact field name.
- submit() lines 595-599:
- parameter types updated.
/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig
- State.submit() lines 172-214:
- parameter types updated.
- assertions on feedback.surface.* updated.
- submitHandle() lines 271-279:
- parameter types updated.
- Tests lines 370-375:
- type names updated.
/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig
- ensureSurface() line 5:
- HowlRenderSurfaceHandle -> HowlRenderHostSurface
- uploadPreparedBuffer() line 27:
- HowlRenderSurfaceHandle -> HowlRenderHostSurface
/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/abi.zig
- line 21:
- pub const RenderSurface = c.HowlRenderSurfaceHandle;
- becomes pub const HostSurface = c.HowlRenderHostSurface; or equivalent.
- No prepared buffer/diagnostic changes in first slice.
8. Ordered ABI-breaking slices
Slice 1: Replace submit “feedback/execution/surface handle” vocabulary
Break ABI:
- HowlRenderSurfaceHandle -> HowlRenderHostSurface
- HowlRenderSurfaceExecutionInput -> HowlRenderSubmitExecution
- HowlRenderSurfaceFeedback -> HowlRenderSubmitResult
- surface_feedback.zig -> submit_result.zig
- prepared/feedback.zig -> split or minimally rename internal symbols.
No compatibility aliases.
Slice 2: Delete ABI Frame vocabulary
Break ABI:
- HowlRenderPreparedFrame -> HowlRenderPreparedSurfaceToken
- HowlRenderFrameLayoutResult -> HowlRenderLayoutResult
- function derive_frame_layout -> derive_layout
- internal tokens.PreparedFrame -> PreparedSurfaceToken
- internal tokens.SubmittedFrame -> SubmittedSurfaceToken
- pipelineFrame() -> preparedSurfaceToken()
Slice 3: Rename SurfaceText object to true session noun
Break ABI:
- HowlRenderSurfaceTextHandle -> HowlRenderTextSessionHandle
- HowlRenderSurfaceTextConfig -> HowlRenderTextConfig
- function prefix howl_render_surface_text_* -> howl_render_text_session_*
Internal:
- Move surface/text.zig composition owner to session/text.zig.
- Split renderer implementation toward render/text.zig.
Slice 4: Rename VT source publication ABI
Break ABI:
- HowlRenderPublishSlot -> HowlRenderVtSurfaceSlot
- HowlRenderPublishSlotCommit -> HowlRenderVtSurfaceCommit
- HowlRenderVtPublishResult -> HowlRenderVtSurfacePublishResult
- functions reserve_publish_slot, commit_publish_slot, etc. -> reserve_vt_surface_slot, commit_vt_surface, etc.
Slice 5: Rename pending state to session work state
Break ABI:
- HowlRenderPendingState -> HowlRenderSessionWorkState
- pending_state function/file -> work_state
Slice 6: Clean metrics vocabulary
Break ABI:
- HowlRenderSurfaceMetrics -> HowlRenderMetrics
- split metrics owners internally:
- prepare metrics
- resolve metrics
- submit metrics
Slice 7: Remove dead/wrong render cell ABI structs
Investigate and delete if unused at public boundary:
- HowlRenderCellFlags
- HowlRenderColor
- HowlRenderCellAttrs
- HowlRenderCell
- HowlRenderCursor
Current source publication uses HowlVtSurfaceCell, so these look stale.
9. First worker-ready slice
Goal
Delete vague submit “feedback” vocabulary and replace it with owner-true submit/result/host-surface nouns.
Exact header changes in /home/home/personal/projects/howl/howl-render/include/howl_render.h
Rename types:
HowlRenderSurfaceMetrics -> HowlRenderMetrics
HowlRenderSurfaceHandle -> HowlRenderHostSurface
HowlRenderSurfaceExecutionInput -> HowlRenderSubmitExecution
HowlRenderSurfaceFeedback -> HowlRenderSubmitResult
For this slice, keep fields mostly stable except improve surface field name if desired:
typedef struct {
  uint64_t host_surface_id;
  uint16_t width;
  uint16_t height;
} HowlRenderHostSurface;
typedef struct {
  HowlRenderHostSurface host_surface;
  uint64_t uploads_committed;
  uint64_t render_us;
} HowlRenderSubmitExecution;
typedef struct {
  int32_t status;
  uint8_t damage_kind;
  uint8_t reserved0;
  uint16_t reserved1;
  HowlRenderHostSurface host_surface;
  HowlRenderMetrics metrics;
} HowlRenderSubmitResult;
Update all uses in:
- HowlRenderPreparedSurfaceInfo.prepare_metrics
- HowlRenderPreparedSurfaceDiagnostics.resolve_metrics
- submit functions:
HowlRenderSubmitStatus howl_render_surface_text_submit(
  HowlRenderSurfaceTextHandle surface_text_handle,
  HowlRenderPreparedSurfaceHandle prepared_surface_handle,
  HowlRenderPreparedFrame prepared_frame,
  const HowlRenderSubmitExecution *execution_in,
  HowlRenderSubmitResult *result_out
);
HowlRenderSubmitStatus howl_render_surface_text_submit_handle(
  HowlRenderSurfaceTextHandle surface_text_handle,
  HowlRenderPreparedSurfaceHandle prepared_surface_handle,
  const HowlRenderSubmitExecution *execution_in,
  HowlRenderSubmitResult *result_out
);
No old typedefs. No aliases.
Render source changes
Files:
- /home/home/personal/projects/howl/howl-render/src/surface_feedback.zig
- Rename/delete as boundary file.
- New boundary file: /home/home/personal/projects/howl/howl-render/src/submit_result.zig
- Functions:
- surfaceMetricsOut -> metricsOut
- surfaceFeedbackOut -> submitResultOut
- failedSurfaceFeedback -> failedSubmitResult
- executionInputIn -> submitExecutionIn
- /home/home/personal/projects/howl/howl-render/src/prepared/feedback.zig
- Rename internal nouns:
- RenderSurfaceHandle -> HostSurface
- RenderSurfaceFeedback -> SubmitResult
- RenderMetrics may remain only if slice keeps metrics rename out; preferred first slice includes RenderMetrics -> Metrics.
- /home/home/personal/projects/howl/howl-render/src/surface/text.zig
- Update SurfaceText.RenderSurfaceExecutionInput -> SurfaceText.SubmitExecution.
- submitSurface() returns prepared_submit.SubmitResult, not feedback.
- /home/home/personal/projects/howl/howl-render/src/surface/submit_feedback.zig
- Rename file to /home/home/personal/projects/howl/howl-render/src/prepared/submit.zig if doing full first slice.
- At minimum rename functions:
- renderMetrics remains acceptable only if metrics owner stays.
- no feedback names.
- /home/home/personal/projects/howl/howl-render/src/prepared_surface.zig
- Import submit_result.zig or metrics.zig for metrics output.
- /home/home/personal/projects/howl/howl-render/src/submission.zig
- Replace import surface_feedback with submit_result.
- Parameters:
- execution_in: ?*const c.HowlRenderSubmitExecution
- result_out: ?*c.HowlRenderSubmitResult
- Calls:
- failedSubmitResult()
- submitResultOut()
- submitExecutionIn()
- /home/home/personal/projects/howl/howl-render/src/libhowl_render.zig
- Import updated boundary file if needed.
- Export names can stay for first slice unless function prefix slice is combined. Parameter ABI types still break.
Host source changes
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig
- HowlRenderSurfaceFeedback -> HowlRenderSubmitResult
- HowlRenderSurfaceExecutionInput -> HowlRenderSubmitExecution
- feedback.surface -> result.host_surface
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig
- Same type updates.
- Assertions use result.host_surface.
- /home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig
- HowlRenderSurfaceHandle -> HowlRenderHostSurface.
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/render/abi.zig
- RenderSurface alias becomes HostSurface or is updated to new C type.
Tests/assertions
Required owner tests:
- In prepared submit/metrics file:
- submit result preserves host surface id/width/height.
- submit execution rejects mismatched upload count or dimensions through existing executionMatchesPrepared.
- In host retained tests:
- rendered submit asserts nonzero host_surface_id, width, height using new noun.
- In boundary tests if present:
- null result_out still allowed/handled exactly as before.
- failed submit initializes HowlRenderSubmitResult.status = HOWL_RENDER_CALL_FAILED.
Grep gates
No matches under /home/home/personal/projects/howl/howl-render/src:
- SurfaceFeedback
- surfaceFeedback
- surface_feedback
- RenderSurfaceFeedback
- failedSurfaceFeedback
- executionInputIn
No matches under /home/home/personal/projects/howl/howl-render/include/howl_render.h:
- HowlRenderSurfaceFeedback
- HowlRenderSurfaceExecutionInput
- HowlRenderSurfaceHandle
No old aliases:
- typedef .*HowlRenderSurfaceFeedback
- typedef .*HowlRenderSurfaceExecutionInput
- typedef .*HowlRenderSurfaceHandle
Verification:
- From /home/home/personal/projects/howl:
- zig build check
- zig build test
- git diff --check
10. Risks with bounded mitigations
- Risk: First slice touches host and render ABI simultaneously.
- Mitigation: keep function names stable in this slice; change only submit/result/host-surface type nouns.
- Risk: HowlRenderSurfaceMetrics rename may widen slice.
- Mitigation: include it only if mechanical. If not, leave metrics for Slice 6, but still remove feedback/execution/surface-handle nouns.
- Risk: surface/submit_feedback.zig rename may collide with broader surface folder cleanup.
- Mitigation: allow a direct rename to prepared/submit.zig in first slice; no umbrella replacement.
- Risk: Host compile errors from C type rename are widespread.
- Mitigation: grep output shows exact limited files: terminal/context.zig, terminal/render/retained.zig, terminal/render/abi.zig, window/term_texture.zig.
11. Explicit readiness judgment
Ready.
The first slice is worker-ready: replace feedback/execution/host surface vocabulary with submit-result vocabulary, update the C header, boundary translators, prepared submit internals, and exact host call sites. This is ABI-breaking, source-backed, does not preserve old names, and directly attacks one of the user’s suspicious examples without broadening into the larger Frame/SurfaceText cleanup.
