# Render-Surface Host Failure Classes Research Cache

## Date

2026-06-01

## Scope

Lane A Slice 1: Render-Surface Trust Boundary Classification.

This cache classifies current Linux host render-surface failure classes only. It does not plan or implement behavior changes.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:104-107`, `:109-113`, `:136-140`, `:213-219`.
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189-222`, `:281-307`.
- `research/2026-06-01-host-sprint.md:34-82`.
- `research/cache-2026-06-01-host-failure-policy.md:75-123`.
- `howl-render/include/howl_render.h:19-31`, `:35-44`, `:46-65`, `:211-314`, `:637-651`.
- `howl-render/src/prepared/owner.zig:39-60`, `:67-80`, `:83-86`, `:123-147`, `:160-165`, `:222-233`, `:262-274`, `:380-428`, `:626-663`, `:690-892`.
- `howl-render/src/prepared/render_surface_emitter.zig:18-34`, `:36-67`, `:176-219`, `:221-307`, `:371-385`, `:422-436`, `:494-511`, `:552-645`, `:647-681`, `:712-750`, `:778-819`, `:830-878`, `:882-901`, `:943-955`, `:983-1008`, `:1033-1075`, `:1258-1357`, `:1395-2203`.
- `howl-render/src/ffi/prepared_surface.zig:23-67`, `:100-118`.
- `howl-render/src/ffi/render_surface.zig:4-7`, `:141-167`, `:169-187`, `:325-347`.
- `howl-render/src/test/ffi.zig:35-58`, `:70-82`, `:305-343`, `:345-446`, `:826-857`.
- `howl-render/src/test/unit/root.zig:1-5`.
- `howl-linux-host/src/terminal/render/retained.zig:78-118`, `:204-262`, `:264-319`, `:344-405`, `:408-488`, `:490-546`, `:751-794`, `:876-940`, `:962-1014`, `:1016-1152`, `:1171-1336`, `:1343-1507`, `:1813-2388`, `:2378-3002`.
- `howl-linux-host/src/window/term_texture.zig:24-97`, `:110-197`, `:199-269`, `:316-340`, `:349-425`, `:489-534`, `:583-779`, `:942-1087`, `:1419-1920`, `:1922-2108`, `:2110-2388`, `:2419-2437`.
- `howl-linux-host/src/terminal/context.zig:82-122`, `:615-769`, `:919-1197`, `:2287-2301`.
- `docs/render-surface.md:1-65`, `:67-85`, `:230-265`, `:267-399`, `:411-435`, `:437-499`, `:523-597`, `:664-691`, `:851-918`.

## TigerBeetle Policy Applied

- Assertions are for programmer errors; operating errors are expected and must be handled (`TIGER_STYLE.md:104-107`).
- Function arguments, return values, preconditions, postconditions, and invariants must be asserted (`TIGER_STYLE.md:109-113`).
- Invalid-boundary transitions need both positive and negative proof (`TIGER_STYLE.md:136-140`).
- Non-fatal operating errors must be handled correctly (`TIGER_STYLE.md:213-219`).

## Trust Boundary Facts

- The public C ABI defines `HowlRenderPreparedSurfaceHandle` as an opaque prepared surface handle, not a host-authored render-surface pointer (`howl_render.h:11-16`).
- The only public function that exposes a render surface is `howl_render_prepared_surface_render_surface(prepared_surface_handle, surface_out)` (`howl_render.h:644-647`).
- The FFI implementation always clears `surface_out` first, rejects null/missing/dead handles, and returns `HOWL_RENDER_CALL_OK` only after assigning `value.* = owner.renderSurface()` (`prepared_surface.zig:43-52`).
- `Owner.fromHandle()` casts opaque handles into render-owned owner objects (`owner.zig:83-86`); this is external C ABI validation, not proof that arbitrary pointers are safe to dereference.
- The Linux host does not accept a host-supplied render-surface pointer in the submit path. It calls `howl_render_prepared_surface_render_surface()` from `probePreparedRenderSurface()` and stores that returned pointer in `PreparedUpload.render_surface` (`retained.zig:769-794`).
- `submitPreparedLockedWith()` asserts the prepared handle is non-null and stable around the unlocked backend upload (`context.zig:788-814`).
- The render-surface contract says render owns command stream, upload bytes, damage, resource IDs, atlas packing, and tokens; the host owns backend resources and presentation (`docs/render-surface.md:36-65`).
- The contract says spans are borrowed from render-owned storage, valid only during the surface lifetime, and render must not mutate live span memory (`docs/render-surface.md:376-399`).
- The ABI layout and constants are asserted in `render_surface.zig` for all public constants and structs (`render_surface.zig:141-167`, `:169-187`, `:325-347`).

Conclusion: the in-tree Linux host consumes trusted render-produced surfaces. It should not defensively validate hostile arbitrary render-surface pointers as a normal runtime path. External C ABI functions must still handle missing/null/dead handles and invalid arguments.

## No Surface After Emit OK

- `Owner.create()` initializes `render_surface_emit_status` to `HOWL_RENDER_SURFACE_EMIT_OK`, then calls `emitRenderSurfacePayload()`; on emission error it maps the exact error to a non-OK diagnostic status (`owner.zig:67-80`, `:242-259`, `:262-274`).
- `emitRenderSurfacePayload()` creates a payload, emits into it, and assigns `render_surface_payload` only after success (`owner.zig:222-233`).
- `Owner.renderSurface()` asserts the owner is live and returns null only when `render_surface_payload` is null (`owner.zig:143-147`).
- The FFI returns `HOWL_RENDER_CALL_OK` only if `owner.renderSurface()` returns non-null; otherwise it returns `HOWL_RENDER_CALL_INVALID_ARGUMENT` (`prepared_surface.zig:43-52`).
- The FFI tests prove a live prepared handle returns `HOWL_RENDER_CALL_OK` with a borrowed surface pointer (`ffi.zig:388-408`) and that released/consumed handles reject and clear the output pointer (`ffi.zig:373-386`, `:410-446`).
- The owner tests prove emission overflow and missing sprite produce no surface and a non-OK emit diagnostic (`owner.zig:380-428`, `:796-892`).
- The render-surface contract says host presentation fails closed when the sidecar is missing, invalid, unsupported, or cannot be uploaded (`docs/render-surface.md:28-35`).

Conclusion: after `HOWL_RENDER_SURFACE_EMIT_OK`, no surface from `howl_render_prepared_surface_render_surface()` is not a valid operating outcome for the in-tree Linux host. It is an invariant violation if observed with a live trusted prepared handle. The handled FFI states for missing/dead/null handles must remain for external C ABI calls.

## Unsupported Commands And Resources

- Current public command kinds are fixed to clear rect, fill rect, glyph run, and sprite (`howl_render.h:41-44`; `render_surface.zig:163-166`).
- Current public resource kinds include alpha glyph atlas, color glyph atlas, alpha sprite, and color sprite (`howl_render.h:35-38`; `render_surface.zig:157-160`).
- The contract states `GLYPH_ATLAS_COLOR` is reserved and invalid until a later color-glyph slice (`docs/render-surface.md:240-265`, `:523-530`, `:591-597`).
- The contract states unknown command/resource/upload/damage kinds reject the surface (`docs/render-surface.md:261-265`, `:664-691`).
- The emitter currently emits only defined command kinds: clear/fill commands, draw sprite, and draw glyph run (`render_surface_emitter.zig:494-511`, `:552-645`, `:778-819`).
- The emitter currently produces glyph atlas alpha and sprite alpha/color resources, not glyph atlas color (`render_surface_emitter.zig:246-253`, `:292-300`, `:671-681`, `:943-955`).

Conclusion: unsupported commands/resources are not feature negotiation in the in-tree renderer-host path. Unknown command/resource emission is ABI drift or renderer bug. The named color glyph atlas value is an intentionally reserved unsupported product feature that must remain rejected until a later color-glyph product slice defines semantics and tests.

## Classifications

Classification names:

- `invariant`: trusted renderer invariant violation that should assert/crash in the in-tree Linux host.
- `operating`: expected GL/backend/resource operating error that should fail closed.
- `unsupported`: intentionally unsupported host feature needing product decision.
- `defensive`: external/defensive C ABI validation state that must remain handled.

### `terminal/context.zig`: `render_surface_no_sidecar_*`

- `render_surface_no_sidecar_count` (`context.zig:93`, `:740-741`): aggregate diagnostic only. Classification follows the status below, not a standalone policy class.
- `render_surface_no_sidecar_null_count` (`context.zig:94`, `:742-745`): `invariant` for in-tree trusted handles, because render FFI cannot return OK with null and successful emission should have payload (`prepared_surface.zig:43-52`; `owner.zig:222-233`). `defensive` for external/dead/released handles (`ffi.zig:345-386`, `:410-446`).
- `render_surface_no_sidecar_call_failed_count` (`context.zig:95`, `:746-748`): `invariant` in the in-tree path after `preparedHandleStable` and non-null prepared assertions (`context.zig:788-814`); `defensive` for external C ABI missing/null/dead handle cases (`prepared_surface.zig:43-52`; `ffi.zig:345-386`).
- `render_surface_no_sidecar_unsupported_count` (`context.zig:96`, `:749-751`): `invariant` for unknown command/resource emitted by in-tree renderer; `unsupported` only for reserved color glyph atlas feature (`docs/render-surface.md:240-265`, `:591-597`, `:656-659`).
- `render_surface_no_sidecar_invalid_count` (`context.zig:97`, `:752-761`): `invariant` for in-tree trusted surfaces because render owns spans, resources, command stream, and upload bytes (`docs/render-surface.md:36-65`, `:387-399`, `:664-691`). `defensive` only if validating externally supplied ABI data outside the Linux host normal path.
- `render_surface_no_sidecar_overflow_count` (`context.zig:98`, `:762-764`): `invariant` when resource-plan validation sees an already-returned trusted surface whose upload total exceeds the public max (`retained.zig:1007-1011`; `docs/render-surface.md:67-85`). Render-surface emission bound failures before a surface exists are fail-closed renderer resource/limit outcomes reported by diagnostics (`owner.zig:74-79`, `:262-274`; `ffi.zig:70-82`).
- `render_surface_no_sidecar_other_count` (`context.zig:99`, `:765-768`): `invariant` for `.idle`/`.ok` reaching “no sidecar” in the in-tree path because `.ok` implies a valid surface and `.idle` is not a post-call resource-plan status for a prepared surface (`retained.zig:962-979`; `prepared_surface.zig:43-52`).

### `terminal/context.zig`: `render_surface_unsupported_shape_*`

- `render_surface_unsupported_shape_count` (`context.zig:100`, `:700-711`, `:722-738`): `invariant` if the surface is valid but not realizable by any host shape path. The contract requires normal host presentation to be render-surface-only and forbids full RGBA runtime fallback (`docs/render-surface.md:5-16`, `:28-35`, `:899-918`). Current host shape predicates cover fill, fill patch, sprite, sprite patch, glyph, and glyph patch (`context.zig:659-719`; `term_texture.zig:2110-2285`). A valid in-tree surface outside those shapes means renderer/host ABI drift.
- `render_surface_unsupported_no_full_clear_count` (`context.zig:101`, `:725-727`): `invariant` only when the selected full-surface realization path requires a full clear and no patch path matches. Partial surfaces are valid render-surface inputs (`docs/render-surface.md:376-385`, `:701-707`), and the host has patch paths (`context.zig:669-709`, `:689-709`; `term_texture.zig:2127-2143`, `:2211-2233`, `:2260-2285`).
- `render_surface_unsupported_clear_command_count`, `render_surface_unsupported_fill_command_count`, `render_surface_unsupported_sprite_command_count`, `render_surface_unsupported_glyph_command_count` (`context.zig:102-105`, `:728-735`): aggregate diagnostics for valid command kinds. Classification follows `render_surface_unsupported_shape_count`: `invariant` for a trusted valid surface not consumed by host shape paths.
- `render_surface_unsupported_other_command_count` (`context.zig:106`, `:736-737`): `invariant` for in-tree renderer emission because unknown commands must reject and are not feature negotiation (`docs/render-surface.md:261-265`, `:680-691`). `defensive` for external validation only.

### `terminal/render/retained.zig`: `PreparedRenderResourcePlanStatus`

- `idle` (`retained.zig:89-90`): internal initial state. `invariant` if observed after `probePreparedRenderSurface()` returns for a real prepared upload, because validation always returns a concrete status (`retained.zig:781-785`, `:962-979`).
- `ok` (`retained.zig:90-91`, `:969-978`): success, not failure.
- `call_failed` (`retained.zig:91-92`, `:962-964`): `defensive` for missing/dead/null external C ABI handles; `invariant` in the in-tree trusted host path after stable non-null prepared handle proof (`context.zig:788-814`; `prepared_surface.zig:43-52`).
- `null_surface` (`retained.zig:92-93`, `:963-965`): `defensive` for external ABI misuse; `invariant` for in-tree trusted prepared handles, because FFI returns OK only with non-null surface (`prepared_surface.zig:43-52`).
- `version_mismatch` (`retained.zig:93-94`, `:981-983`): `invariant` for in-tree trusted surfaces because version is fixed and asserted by ABI layout (`howl_render.h:19`, `render_surface.zig:141-167`); `defensive` for external validation.
- `create_span_invalid`, `upload_span_invalid`, `command_span_invalid`, `retire_span_invalid` (`retained.zig:94-99`, `:981-1006`): `invariant` for trusted surfaces; `defensive` for external validation. Span rules are ABI contract (`docs/render-surface.md:387-399`, `:664-672`).
- `upload_bytes_overflow`, `upload_bytes_max_mismatch` (`retained.zig:99-101`, `:1007-1011`): `invariant` for trusted surfaces; `defensive` externally. Public bound is fixed (`howl_render.h:26`, `docs/render-surface.md:80`).
- `unsupported_command` (`retained.zig:101`, `:1094-1108`): `invariant` for in-tree renderer emission; `defensive` externally. Not feature negotiation (`docs/render-surface.md:261-265`, `:680`).
- `unsupported_resource` (`retained.zig:102`, `:1038-1040`, `:1057-1059`, `:1069-1071`, `:1117-1120`, `:1140-1142`): `invariant` for unknown resources from in-tree renderer; `unsupported` for reserved `GLYPH_ATLAS_COLOR` until a color-glyph slice (`docs/render-surface.md:240-265`, `:591-597`).
- `invalid_command`, `invalid_resource`, `invalid_upload` (`retained.zig:103-106`, `:1016-1152`): `invariant` for trusted renderer output; `defensive` externally. Contract requires invalid input reject without lifetime transition (`docs/render-surface.md:664-691`).

### `terminal/render/retained.zig`: `PreparedRenderSurfaceProbeStatus`

- `idle` (`retained.zig:525-527`): internal initial state. `invariant` after a completed probe for a real prepared upload (`retained.zig:781-793`, `:876-940`).
- `ok` (`retained.zig:527`): success, not failure.
- `call_failed`, `null_surface` (`retained.zig:528-530`, `:876-884`): same classification as `PreparedRenderResourcePlanStatus.call_failed/null_surface`: `defensive` externally, `invariant` in-tree.
- `version_mismatch`, `render_mismatch`, `cell_mismatch`, `grid_mismatch` (`retained.zig:530-534`, `:884-889`): `invariant` for trusted surfaces because `Owner` copies prepared render/cell/grid info into the emitted surface (`owner.zig:242-259`; `render_surface_emitter.zig:402-420`); `defensive` externally.
- `damage_span_invalid`, `create_span_invalid`, `upload_span_invalid`, `command_span_invalid`, `retire_span_invalid` (`retained.zig:534-539`, `:890-919`): `invariant` for trusted surfaces; `defensive` externally.
- `upload_bytes_overflow`, `upload_bytes_max_mismatch` (`retained.zig:539-541`, `:920-925`): `invariant` for trusted surfaces; `defensive` externally.
- `unsupported_command` (`retained.zig:541`, `:1246-1264`): `invariant` for in-tree renderer output; `defensive` externally.
- `unsupported_resource` (`retained.zig:542`, `:1193-1195`, `:1207-1209`, `:1219-1221`, `:1275-1285`, `:1324-1326`): `invariant` for unknown resources from in-tree renderer; `unsupported` for reserved `GLYPH_ATLAS_COLOR` until later product slice.
- `invalid_command`, `invalid_resource`, `invalid_upload` (`retained.zig:543-546`, `:1171-1336`): `invariant` for trusted renderer output; `defensive` externally.

### `terminal/render/retained.zig`: `RenderResourceStoreStatus`

- `ok` (`retained.zig:108-109`): success, not failure.
- `capacity_overflow` (`retained.zig:109-111`, `:264-283`): `invariant` for trusted in-tree renderer if it exceeds `HOWL_RENDER_SURFACE_RESOURCES_MAX` without fail-closed emission; `defensive` externally. The ABI bound is fixed (`howl_render.h:28`; `docs/render-surface.md:82`, `:294-297`).
- `operation_capacity_overflow` (`retained.zig:110-112`, `:136-169`, `:216-248`): `invariant` for trusted surfaces because operation capacity is derived from create/upload/retire maxima (`retained.zig:192-195`); `defensive` externally.
- `duplicate_create` (`retained.zig:112-113`, `:264-283`): `invariant` for trusted renderer; `defensive` externally. Resource reuse before ack is invalid (`docs/render-surface.md:277-297`, `:371-374`).
- `missing_resource`, `retired_resource` (`retained.zig:113-115`, `:285-319`, `:380-405`): `invariant` for trusted renderer unless it is a persistent resource that truly exists in the store. Missing/retired references from a surface are invalid input (`docs/render-surface.md:326-374`). `defensive` externally.
- `invalid_resource`, `invalid_upload`, `invalid_retire` (`retained.zig:115-118`, `:264-319`, `:344-405`, `:408-488`, `:490-510`): `invariant` for trusted renderer output; `defensive` externally.

### `window/term_texture.zig`: `RenderResourceTextures.FailureBucket`

- `invalid_spans` (`term_texture.zig:88-90`, `:199-261`): `invariant` for trusted surfaces; `defensive` externally. Span shape is ABI contract (`docs/render-surface.md:387-399`).
- `invalid_command_shape` (`term_texture.zig:90`, `:489-499`, `:624-660`, `:2301-2337`): `invariant` for trusted surfaces; `defensive` externally.
- `invalid_order` (`term_texture.zig:91`, `:489-493`, `:583-621`): `invariant` for trusted renderer output; `defensive` externally. Lifetime order is render-owned (`docs/render-surface.md:267-374`).
- `unsupported_resource_format` (`term_texture.zig:92`, `:316-321`, `:701-708`): `invariant` for trusted alpha/sprite resources with wrong format; `unsupported` for reserved color glyph atlas feature; `defensive` externally.
- `upload_bounds` (`term_texture.zig:93`, `:254-261`, `:286-299`, `:711-724`, `:2419-2437`): `invariant` for trusted surface metadata; `defensive` externally.
- `tombstone_value_reuse` (`term_texture.zig:94`, `:316-324`, `:349-357`): `invariant` for trusted renderer until an ack/reuse ABI exists; `defensive` externally. Reuse before ack is invalid (`docs/render-surface.md:286-297`, `:371-374`).
- `capacity` (`term_texture.zig:95`, `:316-324`, `:358-361`): `invariant` for trusted renderer exceeding fixed resource bound; `defensive` externally.
- `gl_error` (`term_texture.zig:96`, `:193-197`, `:349-397`, `:399-425`, `:2018-2108`): `operating`. GL texture/FBO generation, framebuffer completeness, and GL error state are host/backend operating failures and should fail closed.

## ABI Consequences

- No render ABI semantic change is required by this classification.
- Existing C ABI defensive behavior for null output, missing handle, released/consumed handle, invalid arguments, and external invalid surfaces must remain handled (`prepared_surface.zig:23-67`; `ffi.zig:345-446`).
- In-tree Linux host runtime behavior can be tightened in a later worker slice only at the host side: trusted renderer invariant violations should assert/crash; GL/backend failures should fail closed; reserved color glyph atlas should remain rejected until a product slice defines semantics.

## Readiness Judgment

Ready for planning, with one explicit product boundary: color glyph atlas is intentionally reserved and unsupported by current contract. A worker must not add color glyph support or feature negotiation; it may only preserve rejection/fail-closed behavior unless a separate color-glyph product slice is promoted.
