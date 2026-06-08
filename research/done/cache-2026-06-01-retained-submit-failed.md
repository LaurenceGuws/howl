# Research Cache: Retained Submit Failed

Date: 2026-06-01

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `howl-render/include/howl_render.h`
- `howl-render/src/prepared/render_surface_emitter.zig`
- `howl-render/src/ffi/prepared_surface.zig`
- `howl-render/src/prepared/owner.zig`
- `howl-render/src/render/tokens.zig`
- `howl-render/src/test/ffi.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/window/term_texture.zig`
- `howl-linux-host/src/terminal/context.zig`

## Runtime Symptom

`zig build run -Doptimize=ReleaseFast` reports repeated submit failures:

- `submit-failed reason=retained_submit_failed`
- `render_surface_emit_status=0`
- `resource_plan_status=unsupported_command`
- `glyph_present` and `fill_patch_present` increase
- `uploads_committed=0`
- repeated `snapshot=5`, `damage_kind=3`

## Findings

### `retained_submit_failed` Producer

`retained_submit_failed` is host context accounting for a render-retained submit failure.

- `howl-linux-host/src/terminal/context.zig:816-825` calls `self.term.render.submit(...)` after backend upload/presentation work.
- `howl-linux-host/src/terminal/context.zig:853-864` maps `SubmitFailure.submit_failed` to `SubmitFailureReason.retained_submit_failed`.
- `howl-linux-host/src/terminal/render/retained.zig:684-687` sets `.submit_failed` when `howl_render_text_session_submit_handle(...)` returns anything other than rendered, stale, needs-prepare, or idle.

### `unsupported_command` Producer

`resource_plan_status=unsupported_command` is host retained resource-plan rejection.

- `howl-linux-host/src/terminal/render/retained.zig:1032-1046` validates render-surface commands for resource planning.
- `HOWL_RENDER_SURFACE_COMMAND_DRAW_GLYPH_RUN` returns `.unsupported_command` at `retained.zig:1044`.

### Triggering Command Shape

The rejected command is a render-surface glyph run.

- `howl-render/include/howl_render.h:264-272` defines `HowlRenderSurfaceCommand` with `kind`, `rect`, `color_rgba`, `resource`, and `glyphs`.
- `howl-render/include/howl_render.h:249-256` defines `HowlRenderGlyphRef` with `atlas_resource`, `atlas_rect`, destination position, glyph id, and color.
- `howl-render/src/prepared/render_surface_emitter.zig:806-818` emits `HOWL_RENDER_SURFACE_COMMAND_DRAW_GLYPH_RUN`.
- `howl-render/src/prepared/render_surface_emitter.zig:588-599` appends glyph refs using atlas resources.
- `howl-render/src/prepared/render_surface_emitter.zig:671-679` creates `HOWL_RENDER_RESOURCE_GLYPH_ATLAS_ALPHA`.
- `howl-render/src/prepared/render_surface_emitter.zig:736-748` uploads atlas bytes with `HOWL_RENDER_UPLOAD_ALPHA8`.

### Damage Kind

Runtime `damage_kind=3` is prepared-surface full damage, not render-surface damage item kind.

- `howl-render/include/howl_render.h:89-93` defines `HOWL_RENDER_DAMAGE_FULL = 3`.
- `howl-render/src/render/tokens.zig:15-19` defines internal `.full = 3`.
- Render-surface damage item `HOWL_RENDER_SURFACE_DAMAGE_FULL = 2` is separate at `howl-render/include/howl_render.h:33-34` and emitted by `howl-render/src/prepared/render_surface_emitter.zig:422-435`.

### Why Presentation Counters Advance Before Submit Failure

Host backend upload/presentation and render submit are separate steps.

- `howl-linux-host/src/terminal/context.zig:680-705` increments glyph/fill present counters when texture upload/draw succeeds.
- `howl-linux-host/src/terminal/context.zig:816-818` calls render submit only after upload/presentation work.
- `howl-linux-host/src/terminal/context.zig:775-783` builds `HowlRenderSubmitExecution` with `uploads_committed = 0` unconditionally.
- `howl-render/src/prepared/owner.zig:373-377` requires `execution.uploads_committed == uploads_required`.
- `howl-render/src/prepared/owner.zig:255` stores `uploads_required` from the prepared raster plan.

Therefore present counters can be truthful while submit fails because submit receives an invalid upload-commit consequence.

### `uploads_committed=0`

`uploads_committed=0` is the immediate submit rejection cause for prepared surfaces with required uploads.

- `howl-linux-host/src/terminal/context.zig:775-783` always reports zero committed uploads.
- `howl-render/src/prepared/owner.zig:373-377` rejects a mismatch.
- `howl-render/src/test/ffi.zig:586-601` proves wrong upload count is rejected without consuming the prepared handle.

This is not a correct success consequence after backend upload succeeds.

### Host Retained Owns The Observed Fix

The observed failure is host retained integration debt.

- `howl-linux-host/src/terminal/render/retained.zig:1032-1046` rejects glyph-run commands as unsupported in resource planning.
- `howl-linux-host/src/window/term_texture.zig:624-648` validates glyph commands.
- `howl-linux-host/src/window/term_texture.zig:2235-2258` accepts glyph surfaces.
- `howl-linux-host/src/window/term_texture.zig:2008-2015` uploads/renders glyph surfaces.
- `howl-linux-host/src/window/term_texture.zig:2098-2103` draws glyph commands in the command loop.

The host already realizes glyph runs but retained validation rejects them in three places, and submit accounting reports zero uploads after successful upload.

Exact retained blockers:

- `howl-linux-host/src/terminal/render/retained.zig:1032-1046` rejects glyph runs in pure resource-plan command validation.
- `howl-linux-host/src/terminal/render/retained.zig:1150-1165` rejects glyph runs in software-probe command validation.
- `howl-linux-host/src/terminal/render/retained.zig:382-407` rejects glyph runs in store-aware resource command-shape validation before `RenderResourceStore.validateCommandResource(...)` can prove live/uploaded resources.
- `howl-linux-host/src/terminal/render/retained.zig:1215-1231` also rejects glyph atlas creates/uploads because `resourceKindSupported(...)` and `uploadFormatForResource(...)` support only sprite resources, while glyph atlas store support already exists in `resourceKindStorable(...)` and `storeUploadFormatForResource(...)` at `retained.zig:1220-1241`.

Resource liveness belongs to the store-aware path:

- `howl-linux-host/src/terminal/render/retained.zig:336-360` walks commands and glyph refs.
- `howl-linux-host/src/terminal/render/retained.zig:363-378` validates resource kind, create/use order, retained store liveness, visible upload, and retire order.

Persistent glyph atlas resources are valid across surfaces. The pure plan validator must therefore distinguish surface-local proof from retained-store proof:

- If a glyph atlas resource has a same-surface create, pure plan validates create/upload/use/retire order and visible upload containment.
- If a glyph atlas resource has no same-surface create, pure plan must not reject the command solely for missing create; it defers liveness and prior upload proof to the store-aware validator.
- If a glyph atlas upload has no same-surface create, pure plan may validate resource kind, upload format, upload rect against glyph atlas dimensions, byte count, and sequencing, but must defer retained liveness to the store-aware upload path.
- Store-aware validation must be extended because `RenderResourceStored` currently records only `width_px`, `height_px`, `format`, `upload_count`, and `upload_bytes_count` (`retained.zig:178-186`). Match the render realizer's retained model: one latest visible upload per resource. Add explicit retained upload coverage fields to `RenderResourceStored`: `upload_rect: HowlRenderSurfaceRect`, `upload_stride_bytes: u32`, `upload_last_bytes_count: u32`, and `uploaded: bool`. Each accepted upload replaces these coverage fields, while `upload_count` and `upload_bytes_count` remain cumulative accounting. This mirrors `howl-render/src/render/render_surface_realizer.zig:23-33` and overwrite-on-upload behavior at `render_surface_realizer.zig:139-153`.

Pure resource-plan validation can prove only surface-local lifecycle, visibility within creates/uploads/retires, span validity, and command shape. It cannot prove retained-store liveness for persistent resources.

## ABI Finding

Current ABI asks the host to echo `uploads_committed` in `HowlRenderSubmitExecution`.

- `howl-render/include/howl_render.h:524-528` includes `uploads_committed`.
- `howl-render/src/prepared/owner.zig:255` render owns the required upload count.
- `howl-render/src/prepared/owner.zig:373-377` render validates the echoed count.

This shape is weak because the host echoes render-owned prepared upload count. However the immediate observed failure does not require ABI replacement to prove/fix: host has the prepared upload count in `prepared_upload.info.prepare_metrics.uploads` and must report it only after backend upload succeeds.

If this ABI shape becomes the product problem, replace it directly with a no-compatibility sidecar commit consequence such as committed surface/resource fields validated against `HowlRenderSurface.token` and resource plan truth. That must be a separate ABI-product slice touching header, FFI, render owner validation, host consumer, docs, tests, and layout assertions together.

## Proposed Owner-True Slice

Owner: `howl-linux-host` retained render integration.

Required changes:

- In `howl-linux-host/src/terminal/render/retained.zig`, accept `HOWL_RENDER_SURFACE_COMMAND_DRAW_GLYPH_RUN` in pure resource-plan validation instead of returning `.unsupported_command`.
- In `howl-linux-host/src/terminal/render/retained.zig`, update pure lifecycle validation to support `HOWL_RENDER_RESOURCE_GLYPH_ATLAS_ALPHA` creates/uploads with `HOWL_RENDER_UPLOAD_ALPHA8` before command validation runs.
- Update pure lifecycle validation with explicit persistent glyph behavior:
  - `validatePlanUpload(...)` accepts glyph atlas uploads without a same-surface create only as deferred-to-store candidates after validating kind, format, rect within glyph atlas dimensions, bytes, and upload sequence.
  - `validatePlanCommand(...)` accepts glyph refs without same-surface creates only as deferred-to-store candidates after validating glyph command shape and glyph field invariants.
  - When multiple same-surface glyph atlas uploads are visible at a command, validation selects the latest visible matching upload, not the first. This must match `howl-render/src/render/render_surface_realizer.zig:794-805`.
  - Sprite resources keep their current same-surface create requirements unless a separate source-backed slice broadens sprite persistence.
- Add a pure glyph-plan helper for `validatePlanCommand(...)` that validates glyph span shape, requires non-empty glyph refs, requires zero direct command resource, requires every glyph resource kind to be `HOWL_RENDER_RESOURCE_GLYPH_ATLAS_ALPHA`, and proves each glyph resource is visible at the command through creates/uploads/retires in the same surface when applicable.
- In `howl-linux-host/src/terminal/render/retained.zig`, accept glyph runs in software-probe validation instead of returning `.unsupported_command`.
- Add a glyph-probe helper for `validateCommand(...)` that matches texture realization rules for shape. Because software probe has no retained store, it must validate same-surface glyph atlas uploads with the same latest-visible upload rule, and defer persistent glyph atlas refs with no same-surface upload after validating glyph command shape, atlas dimensions, destination overlap, and alpha. It must not reject a persistent glyph ref merely because there is no same-surface create/upload.
- In `howl-linux-host/src/terminal/render/retained.zig`, accept glyph runs in store-aware resource command-shape validation instead of returning `.invalid_resource`.
- Extend `RenderResourceStored` and `RenderResourceStore.upload(...)` so retained resources remember latest upload coverage required for later glyph refs. Keep retained-store liveness proof in `RenderResourceStore.validateCommandResource(...)`: glyph refs must pass create/use order, retained live slot, latest visible upload or prior retained upload coverage, and retire order.
- Ensure retained validation matches existing texture/realizer rules:
  - command rect and command color are zero
  - direct command resource is zero
  - glyph span is non-empty and within bounds
  - glyph atlas kind is `HOWL_RENDER_RESOURCE_GLYPH_ATLAS_ALPHA`
  - glyph atlas rect has area and is contained by the selected visible upload
  - glyph destination overlaps the render surface
  - glyph color alpha is nonzero
  - source references: `howl-linux-host/src/window/term_texture.zig:2316-2337`, `howl-render/src/render/render_surface_realizer.zig:456-489`, and `howl-render/src/render/render_surface_realizer.zig:794-813`.
- In `howl-linux-host/src/terminal/context.zig`, build submit execution with committed prepared upload count after backend upload succeeds, not hardcoded zero.
- Because `submitPreparedLockedWith(...)` constructs execution only after `Backend.upload(...)` returns true (`context.zig:801-818`), `ContextSubmitBackend.execution(...)` must report `prepared_upload.info.prepare_metrics.uploads` for successful backend upload.
- Add host retained tests proving glyph-run surfaces return `.ok`, not `.unsupported_command`, in both pure resource-plan validation and software-probe validation.
- Replace existing tests that encode wrong behavior:
  - `howl-linux-host/src/terminal/render/retained.zig:1792-1802` currently expects the software probe to reject glyph commands.
  - `howl-linux-host/src/terminal/render/retained.zig:1894-1917` currently expects resource planning to count glyph uses but return `.unsupported_command`.
- Add layer-specific host retained negative tests:
  - Pure plan/lifecycle: wrong glyph atlas upload format, unsupported glyph atlas kind, upload before create, use after retire, invalid glyph span, malformed nonzero direct command resource, nonzero command rect/color, empty glyph span, zero atlas rect, atlas rect outside surface-local visible upload, transparent glyph color, and offscreen glyph destination.
  - Software probe: nonzero command rect/color, nonzero direct command resource, empty/invalid glyph span, wrong atlas kind, zero atlas rect, atlas rect outside selected visible upload, transparent glyph color, and offscreen glyph destination.
  - Software probe persistent behavior: glyph ref with no same-surface create/upload is accepted as deferred shape-only proof when command/glyph fields are otherwise valid.
  - Store-aware validation: missing atlas resource, retired atlas resource, use before create, use after retire, unuploaded atlas resource, and wrong atlas kind.
  - Store-aware persistent validation: persistent glyph atlas reuse succeeds, persistent glyph atlas upload without same-surface create succeeds only when the retained resource is live, latest upload replaces retained coverage, and persistent glyph atlas rect outside retained latest uploaded coverage fails.
- Add context submit-accounting test that captures the `HowlRenderSubmitExecution` passed to submit and proves `uploads_committed == prepared_upload.info.prepare_metrics.uploads` after successful backend upload.

## Required Tests

- Host retained resource-plan glyph-run acceptance test.
- Host retained software-probe glyph-run acceptance test.
- Host retained store-aware glyph-run command-shape acceptance test.
- Host retained pure lifecycle tests for glyph atlas create/upload support.
- Host retained persistent glyph atlas tests: reuse from retained store, upload without same-surface create into retained live atlas, and reject glyph rect outside retained uploaded coverage.
- Host retained negative tests assigned to the exact layers above.
- Host context/render submit execution test for upload count propagation after successful backend upload.
- Existing render FFI wrong-upload-count regression remains the render-side guard.

## Risks

- Glyph resource-plan validation must match texture realization rules or diagnostics diverge again.
- Persistent atlas resources may be reused across surfaces; validation must account for retained resources and creates in the same surface.
- `uploads_committed` remains a weak ABI echo until an explicit ABI-product slice replaces it.

## Stop Conditions

- Stop if `render_surface.uploads.count` and `prepared_upload.info.prepare_metrics.uploads` diverge for a valid glyph/sprite prepared surface.
- Stop if glyph commands can reference persistent atlas resources the retained store cannot prove live.
- Stop if the correct fix becomes ABI replacement; promote a separate no-compatibility ABI slice instead of mixing host and ABI changes casually.
