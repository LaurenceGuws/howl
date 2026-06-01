# Sprint: Retained Submit Failed

Accepted research cache:

- `research/cache-2026-06-01-retained-submit-failed.md`

## Decision

The active product failure is host-retained integration debt:

- Host retained pure resource-plan validation rejects glyph-run commands and glyph atlas resources.
- Host retained software probe rejects glyph-run commands.
- Host retained store-aware command-shape validation rejects glyph-run commands before store liveness can prove the atlas.
- Host submit execution reports `uploads_committed = 0` even after backend upload succeeds.

The render ABI `uploads_committed` echo is weak, but ABI replacement is not part of this slice. If the ABI itself becomes the product problem, promote a separate no-compatibility ABI slice.

## Slice 1: Host Retained Glyph Submit Consequence

Owner: `howl-linux-host` retained render integration.

Allowed files:

- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/terminal/context.zig`

Required shape:

- In `retained.zig`, edit only these retained owner functions or new helpers called directly by them:
  - `resourceKindSupported(...)`
  - `uploadFormatForResource(...)`
  - `validatePlanUpload(...)`
  - `validatePlanCommand(...)`
  - `findUploadVisible(...)` or a glyph-specific latest-visible helper
  - `validateCommand(...)`
  - `validateResourceStoreCommandShape(...)`
  - `RenderResourceStore.upload(...)`
  - `RenderResourceStore.validateCommandResource(...)`
  - `RenderResourceStored`
- In `context.zig`, edit only `ContextSubmitBackend.execution(...)` and test scaffolding needed to capture its output.
- Support `HOWL_RENDER_RESOURCE_GLYPH_ATLAS_ALPHA` in pure lifecycle validation with `HOWL_RENDER_UPLOAD_ALPHA8` by updating `resourceKindSupported(...)` and `uploadFormatForResource(...)` without broadening sprite semantics.
- Sprite resources keep current same-surface create requirements. Do not generalize persistent-resource behavior beyond glyph atlases in this slice.
- Accept `HOWL_RENDER_SURFACE_COMMAND_DRAW_GLYPH_RUN` in `validatePlanCommand(...)` through a glyph-plan helper.
- Accept glyph runs in `validateCommand(...)` through a glyph-probe helper.
- Accept glyph runs in `validateResourceStoreCommandShape(...)` without proving liveness there; liveness remains owned by `RenderResourceStore.validateCommandResource(...)`.
- Extend `RenderResourceStored` with latest upload coverage fields matching render realizer retained state:
  - `upload_rect: HowlRenderSurfaceRect`
  - `upload_stride_bytes: u32`
  - `upload_last_bytes_count: u32`
  - `uploaded: bool`
- Each accepted upload replaces latest coverage fields; `upload_count` and `upload_bytes_count` remain cumulative.
- `RenderResourceStore.upload(...)` must replace latest upload coverage fields after validating rect, stride, bytes, format, resource liveness, and retained dimensions.
- Pure glyph validation must select the latest visible matching same-surface glyph atlas upload, matching `howl-render/src/render/render_surface_realizer.zig`.
- `validatePlanUpload(...)` accepts glyph atlas uploads without same-surface create only as deferred-to-store candidates; sprite uploads still require same-surface create.
- `validatePlanCommand(...)` accepts persistent glyph refs with no same-surface create/upload only as deferred-to-store candidates after validating command/glyph field shape.
- `validateCommand(...)` accepts persistent glyph refs with no same-surface create/upload as shape-only deferred candidates because the software probe has no retained store.
- `RenderResourceStore.validateCommandResource(...)` must prove persistent atlas liveness and latest upload coverage before accepting glyph refs.
- `ContextSubmitBackend.execution(...)` must report `prepared_upload.info.prepare_metrics.uploads` after successful `Backend.upload(...)`, not hardcoded zero.

Glyph command invariants, copied into the slice from the accepted cache:

- `command.rect.x_px == 0`, `command.rect.y_px == 0`, `command.rect.width_px == 0`, and `command.rect.height_px == 0`.
- `command.color_rgba == 0`.
- `command.resource` is the zero resource.
- `command.glyphs.count > 0` and `command.glyphs` span is valid against `HOWL_RENDER_SURFACE_GLYPHS_PER_RUN_MAX`.
- Every glyph ref uses `HOWL_RENDER_RESOURCE_GLYPH_ATLAS_ALPHA`.
- Every glyph atlas rect has nonzero width/height and fits the glyph atlas dimensions.
- When a same-surface upload is visible, every glyph atlas rect must be contained in the latest visible matching upload.
- When only retained-store coverage is available, every glyph atlas rect must be contained in retained latest uploaded coverage.
- Every glyph destination overlaps `surface.render_px`.
- Every glyph color alpha is nonzero.
- Source anchors: `howl-linux-host/src/window/term_texture.zig:2316-2337`, `howl-render/src/render/render_surface_realizer.zig:456-489`, and `howl-render/src/render/render_surface_realizer.zig:794-813`.

Tests required:

- Replace current tests that encode wrong glyph rejection:
  - `host retained render software probe rejects unsupported command`
  - `host retained render plan counts glyph resource uses before unsupported`
- Add positive tests in `retained.zig` for:
  - `validateRenderSurfaceResourcePlan(...)` accepts same-surface glyph atlas create/upload/use
  - `validateRenderSurfaceResourcePlan(...)` accepts persistent glyph ref as deferred-to-store when no same-surface create/upload exists
  - `validatePreparedRenderSurfaceProbe(...)` accepts same-surface glyph run
  - `validatePreparedRenderSurfaceProbe(...)` accepts persistent glyph ref as shape-only deferred proof
  - `RenderResourceStore.applySurface(...)` accepts same-surface glyph atlas create/upload/use
  - `RenderResourceStore.applySurface(...)` accepts persistent glyph atlas reuse from retained store
  - `RenderResourceStore.applySurface(...)` accepts persistent glyph atlas upload without same-surface create into retained live atlas
- Add positive tests in `context.zig` or existing context test owner for:
  - `ContextSubmitBackend.execution(...)` reports `prepared_upload.info.prepare_metrics.uploads` after successful backend upload
- Add negative tests assigned to exact layers with exact expected consequences:
  - Pure plan/lifecycle:
    - glyph atlas upload with wrong format -> `PreparedRenderResourcePlanStatus.invalid_upload`
    - glyph atlas create/upload with unsupported resource kind -> `PreparedRenderResourcePlanStatus.unsupported_resource`
    - same-surface glyph atlas upload before create -> `PreparedRenderResourcePlanStatus.invalid_upload`
    - same-surface glyph atlas use after retire -> `PreparedRenderResourcePlanStatus.invalid_resource`
    - invalid glyph span -> `PreparedRenderResourcePlanStatus.command_span_invalid`
    - nonzero direct command resource -> `PreparedRenderResourcePlanStatus.invalid_resource`
    - nonzero command rect or command color -> `PreparedRenderResourcePlanStatus.invalid_command`
    - empty glyph span -> `PreparedRenderResourcePlanStatus.invalid_command`
    - zero atlas rect -> `PreparedRenderResourcePlanStatus.invalid_command`
    - atlas rect outside selected same-surface upload -> `PreparedRenderResourcePlanStatus.invalid_upload`
    - transparent glyph color -> `PreparedRenderResourcePlanStatus.invalid_command`
    - offscreen glyph destination -> `PreparedRenderResourcePlanStatus.invalid_command`
  - Software probe:
    - nonzero command rect or command color -> `PreparedRenderSurfaceProbeStatus.invalid_command`
    - nonzero direct command resource -> `PreparedRenderSurfaceProbeStatus.invalid_resource`
    - empty glyph span -> `PreparedRenderSurfaceProbeStatus.invalid_command`
    - invalid glyph span -> `PreparedRenderSurfaceProbeStatus.command_span_invalid`
    - glyph ref with non-glyph or unsupported glyph atlas resource kind -> `PreparedRenderSurfaceProbeStatus.unsupported_resource`
    - zero atlas rect -> `PreparedRenderSurfaceProbeStatus.invalid_command`
    - atlas rect outside selected same-surface upload -> `PreparedRenderSurfaceProbeStatus.invalid_upload`
    - transparent glyph color -> `PreparedRenderSurfaceProbeStatus.invalid_command`
    - offscreen glyph destination -> `PreparedRenderSurfaceProbeStatus.invalid_command`
  - Store-aware:
    - missing atlas resource -> `RenderResourceStoreStatus.missing_resource`
    - retired atlas resource -> `RenderResourceStoreStatus.retired_resource`
    - use before same-surface create -> `RenderResourceStoreStatus.invalid_resource`
    - use after retire -> `RenderResourceStoreStatus.invalid_retire`
    - unuploaded atlas resource -> `RenderResourceStoreStatus.invalid_upload`
    - glyph ref with non-glyph or unsupported glyph atlas resource kind -> `RenderResourceStoreStatus.invalid_resource`
    - persistent glyph atlas rect outside retained latest uploaded coverage -> `RenderResourceStoreStatus.invalid_upload`

Stop conditions:

- Stop if `render_surface.uploads.count` and `prepared_upload.info.prepare_metrics.uploads` diverge for a valid glyph/sprite prepared surface.
- Stop if implementing the host fix proves `uploads_committed` ABI cannot express the required consequence.
- Stop if persistent glyph atlas reuse requires more than latest upload coverage and needs a bounded multi-rect ownership design.
- Stop if texture realization and retained validation cannot be made to agree without changing render ABI semantics.

Verification:

- From `howl-linux-host`: `zig build check`
- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`
- From workspace root: tracked `.zig` line scan must print `TOTAL 0` for lines over 190 chars.
- Runtime reproduction after build/test gates: `zig build run -Doptimize=ReleaseFast`

Result:

- Implemented in `howl-linux-host` commit `f059c90 host: accept retained glyph surfaces`.
- The final host gate passed with `zig build test --summary all`: 118/118 tests.
- Runtime reproduction no longer reports `retained_submit_failed`, `resource_plan_status=unsupported_command`, `uploads_committed=0`, or `submit-failed`.

## Follow-Up Slice

Separate ABI-product slice only if needed: replace weak `uploads_committed` echo with a render-surface/resource commit consequence. No aliases or compatibility shims.
