# Render Surface Validation Owner Research Cache - 2026-06-02

Researcher cache. Research only. No product code, scratchpad, `current.txt`, or git edits.

## Sources Read, In Order

1. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md` lines 90-176, 213-229, 271-351, 372-429.
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md` lines 189-222, 408-423, 424-435, 467-487.
3. Existing `research/*.md` caches via grep only, as navigation index.
4. `reference-index.md`.
5. `research/cache-2026-06-02-hygiene-offenders-a.md`.
6. `research/cache-2026-06-02-hygiene-offenders-b.md`.
7. `research/cache-2026-06-02-hygiene-offenders-c.md`.
8. Current Howl source: `howl-linux-host/src/terminal/render/retained.zig` lines 1-2350 and symbol greps through tests.
9. Current Howl source: `howl-linux-host/src/display/renderer/render_surface.zig` lines 1-2587.
10. Current Howl test/build wiring: `howl-linux-host/src/test_root.zig`, `howl-linux-host/src/test/host.zig`, `howl-linux-host/build.zig` lines 295-424.
11. Current Howl source: `howl-linux-host/src/terminal/context.zig` lines 500-759, 1900-1989.
12. Current Howl source: `howl-linux-host/src/terminal/texture.zig`.
13. Reference source: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs` lines 26-35, 82-93, 114-175, 177-350.
14. Reference source: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs` lines 17-26, 42-79, 81-318.
15. Reference source: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs` lines 11-70, 72-304.
16. Reference source: `utils/dev_references/terminals/ghostty/src/renderer.zig` lines 1-9, 16-24, 36-54.
17. Foot reference discovery under `utils/dev_references/terminals/foot/**` for `render*.c`, `render*.h`, `sixel*.c`, and `grid*.c`: no files found in this checkout.

## Grep Terms Used Against Existing Caches And Leads Found

Terms used against `research/*.md`:

- `retained|render_surface|RenderSurface|probe|status|validation|validate`

Leads found:

- All three offender caches point to the same first hygiene cluster: `howl-linux-host/src/terminal/render/retained.zig` and `howl-linux-host/src/display/renderer/render_surface.zig` duplicate render-surface validation/status/probe concepts.
- Cache A lines 80-112 name `PreparedRenderResourcePlan`, `PreparedRenderSurfaceProbe`, `RenderResourceStore`, `validatePreparedRenderSurfaceProbe`, `validateRenderSurfaceResourcePlan`, and display `validateSurfaceTransition`/`CommandShapeError` as duplicated validation.
- Cache B lines 28-48 ranks retained and display render-surface validation as the top two current offenders and proposes keeping retained submit/present sequencing while moving render-surface validation/probe to a narrow owner.
- Cache C lines 18-70 confirms retained owns probe/plan/resource-store validation while display owns GL texture lifecycle plus validation, with the first target being the `PreparedRenderSurfaceProbe`/`PreparedRenderResourcePlan` cluster.
- These old caches were used only as navigation. Claims below were re-verified against current source and accepted references.

## Reference Findings

`reference-index.md`:

- Lines 94-160 direct host runtime/display/window/renderer organization to Alacritty for pragmatic renderer organization.
- Lines 161-190 direct bounds, assertions, naming, structure, directness, and test discipline to TigerBeetle.
- Lines 17-93 reserve Ghostty primarily for VT core, embedding seams, and renderer/text seam pressure, not for host GL resource validation ownership.

Alacritty renderer organization:

- `alacritty/src/renderer/mod.rs` lines 26-35 keeps renderer modules under the renderer root: `platform`, `rects`, `shader`, and `text`, with public `GlyphCache` and `LoaderApi` exported from text.
- `alacritty/src/renderer/mod.rs` lines 82-93 defines `Renderer` as the owner of text renderer, rect renderer, and GL robustness facts. Lines 114-175 initialize GL functions, choose backend provider, initialize shaders/renderers, and enable GL debug logging. This supports keeping GL/backend realization in display/renderer, not in retained terminal state.
- `alacritty/src/renderer/mod.rs` lines 177-350 keeps drawing, viewport, resize, GL reset, clear, and renderer execution methods on the renderer owner. It does not put GL resource validation in terminal retained state.
- `alacritty/src/renderer/text/glyph_cache.rs` lines 17-26 defines a `LoadGlyph` trait for copying rasterized glyphs into graphics memory, with `clear` to reset graphics state. Lines 42-79 define `GlyphCache` as rasterizer/cache/font-metric owner. Lines 200-269 have the cache call the loader only when a glyph must enter graphics memory. This supports a boundary where abstract render facts and backend realization are different owners.
- `alacritty/src/renderer/text/atlas.rs` lines 11-70 define atlas size and atlas insert errors near the atlas owner. Lines 72-304 own GL texture creation, glyph insertion, texture upload, atlas row advancement, atlas clear, and GL texture deletion. This supports keeping Howl host GL resource realization in `display/renderer/render_surface.zig` or a display renderer child, not in `terminal/render/retained.zig`.

Ghostty renderer seam:

- `ghostty/src/renderer.zig` lines 1-9 says renderer implementation takes internal screen state and turns it into output, and assumes the windowing system has already prepared backend-specific resources such as an OpenGL context or Vulkan surface. This supports not moving window/context preparation into a render-surface contract validator.
- `ghostty/src/renderer.zig` lines 16-24 exports explicit renderer/backend/state/thread concepts from renderer root. Lines 36-54 choose one renderer implementation and expose shared health status. This supports explicit owner roots and shared status only where API users need one enum; it does not support multiple internal mirrors for the same render-surface validity facts.

TigerBeetle discipline:

- `TIGER_STYLE.md` lines 90-113 require simple explicit control flow, bounded loops, and assertions on arguments/invariants.
- `TIGER_STYLE.md` lines 158-176 require small scopes and clear control-flow splits; validation should not be interleaved with unrelated mutation when it makes the path harder to audit.
- `TIGER_STYLE.md` lines 271-351 require owner-true nouns and simpler signatures/results. Generic `Result`, `State`, `Options`, `Info`, and bucket shapes are pressure points unless forced by the boundary.
- `TIGER_STYLE.md` lines 372-429 warn against duplicated variables/state and broad return-type dimensionality. Current retained/display duplication is semantic duplication: the same C ABI render-surface facts are validated under multiple status vocabularies.
- `ARCHITECTURE.md` lines 408-423 favors control-plane/data-plane separation. A single render-surface contract validation pass is control-plane; GL upload/draw is data-plane/backend realization.

Foot:

- No Foot source was present under `utils/dev_references/terminals/foot` in this checkout, so it cannot prove an owner shape for this slice.

## Current Howl Findings

`howl-linux-host/src/terminal/render/retained.zig`:

- Lines 4-26 define retained prepare/submit result/failure enums: `PrepareResult`, `PrepareFailure`, `SubmitResult`, `SubmitFailure`. These belong to retained prepare/submit sequencing.
- Lines 28-64 define present/layout/work facts: `PresentInFlight`, `WorkState`, `SurfaceLayoutSync`, `SurfaceLayout`. These belong to terminal retained state and geometry/submit scheduling.
- Lines 66-75 define `PreparedUpload`, bundling ABI prepared info, `PreparedRenderSurfaceProbe`, `PreparedRenderResourcePlan`, and the borrowed render-surface pointer. This is the main boundary bundle.
- Lines 77-129 define `PreparedRenderResourcePlan` and 16-case `PreparedRenderResourcePlanStatus`, plus `trustedResourcePlanStatusAction`. This validates and classifies render-surface resource lifecycle facts inside retained state.
- Lines 131-156 define 9-case `RenderResourceStoreStatus` and action mapping for a software resource-store mirror.
- Lines 158-228 define texture operation recorder/state shapes: `TextureResourceOperationKind`, `TextureResourceOperation`, `TextureResourceOperationRecorder`, `RenderSurfaceResourceState`, and `RenderResourceStored`.
- Lines 235-444 implement `RenderResourceStore.applySurface*`, `create`, `upload`, `retire`, command resource validation, glyph validation, and resource visibility validation. This mirrors display renderer texture lifecycle without owning GL textures.
- Lines 550-610 define `PreparedRenderSurfaceProbe`, 21-case `PreparedRenderSurfaceProbeStatus`, and `trustedProbeStatusAction`.
- Lines 612-628 make `State` store present/prepare/submit facts plus last probe/plan and success/failure/byte counters. Retained state is carrying validation telemetry, not just retained prepare/submit/present ownership.
- Lines 720-918 implement retained C ABI prepare/submit handle sequencing. This is retained ownership and should remain.
- Lines 809-850 make `preparedUpload` call `howl_render_prepared_surface_render_surface`, build a resource plan with `validateRenderSurfaceResourcePlan`, build a probe with `validatePreparedRenderSurfaceProbe`, record counters, and return the borrowed C surface pointer.
- Lines 932-996 implement `validatePreparedRenderSurfaceProbe`: C-call/null/version checks, prepared-info geometry comparison, span max/count checks, upload byte max checks, and `validateSoftwareSurface`.
- Lines 1018-1208 implement `validateRenderSurfaceResourcePlan` and resource-plan lifecycle validators for create/retire/upload/command/glyph refs.
- Lines 1227-1563 implement `validateSoftwareSurface` and near-duplicate lifecycle/command validators under `PreparedRenderSurfaceProbeStatus`.
- Lines 1802-1935 test retained layout/present ownership. These should remain with retained.
- Lines 1822-1892 test action mappings for plan/probe/store status enums. These encode the offender statuses.
- Lines 1936-2245 test render-surface probe/validation behavior in retained.
- Lines 2247 onward test probe accounting, resource plan, and resource store behavior in retained.

`howl-linux-host/src/display/renderer/render_surface.zig`:

- Lines 1-20 import GL/render C modules and define GL extern/constants. This is display/renderer backend territory.
- Lines 24-33 define `deleteTexture` and GL panic helper.
- Lines 35-75 define `RenderResourceTextures`, `Slot`, `FailureBucket`, and `GlStateSample`. `RenderResourceTextures` is the true host GL resource realization owner, but `FailureBucket` is a parallel validation taxonomy.
- Lines 81-156 implement `realizeSurface`/`realizeSurfaceLocked`: validate, create GL textures, sample GL state, upload, commit metadata, retire, and rollback.
- Lines 164-234 implement `validateSurfaceTransition`: version, spans, upload byte limits, command validation, order validation, and staged resource transition validation.
- Lines 236-312 implement validation-only staging methods: `validateCreates`, `validateUploads`, `validateRetires`, `noteCreate`, `noteUpload`, `noteRetire`.
- Lines 314-489 implement GL mutation and slot lifecycle: create/upload/commit/invalidate/retire/find/rollback/delete.
- Lines 491-521 define `RenderSurfaceSummary`, `TrustedTextureFailureAction`, and texture failure action mapping.
- Lines 523-742 define pure helpers for surface order, command shape, resource kind/format, upload bounds, rect math, and spans. `CommandShapeError` at lines 564-580 is another detailed taxonomy over command validity.
- Lines 744-818 define summary/probe-like helpers and GL state sampling.
- Lines 905-1914 are owner-local tests for texture validation, command shape, surface shape classification, failure action mapping, and failure buckets.
- Lines 1916-1955 implement host surface texture creation/resizing.
- Lines 1957-2119 implement GL upload of fill/sprite/glyph render-surface classes.
- Lines 2122-2361 implement render-surface shape classifiers: `renderSurfaceFillOnly`, `renderSurfaceFillPatch`, `renderSurfaceSprite`, `renderSurfaceSpritePatch`, `renderSurfaceGlyphs`, `renderSurfaceGlyphPatch`, and command helpers.
- Lines 2372-2587 implement draw helpers, row bound check, sprite/glyph draw, future upload checks, NDC conversion, and RGBA unpacking.

`howl-linux-host/src/terminal/context.zig`:

- Lines 539-570 call retained `PreparedUpload`, realize render-surface resources via `self.render_surface_textures.realizeSurface`, ensure the host surface, and upload commands.
- Lines 556-563 show current context depends on `prepared_upload.render_surface_resource_plan.status` when the render surface is absent. This is why collapsing retained plan status must also adjust context, but context reshaping itself is deferred.
- Lines 572-628 classify render-surface upload shapes/policy by calling `term_texture.renderSurface*` functions. This is related but must be deferred out of the first slice.
- Lines 656-660 take `render_retained.PreparedRenderResourcePlanStatus` directly for trusted unavailable handling. This is an internal status coupling to remove only if the first slice includes the narrow context call-site adjustment.
- Lines 721-758 are the submit transaction: take prepared upload while locked, unlock for backend upload, relock, check handle stability, submit retained render. This orchestration is not the target.
- Lines 1927-1975 tests assert render-surface token/render size consistency in fake resize backends. These tests may need import/name updates if `PreparedUpload` changes, but their behavior should not change.

Test/build wiring:

- `howl-linux-host/src/test_root.zig` lines 1-13 uses `src/test/host.zig` as curated host root.
- `howl-linux-host/src/test/host.zig` lines 1-12 imports current host owner modules; it does not currently import retained or display render-surface tests directly.
- `howl-linux-host/build.zig` lines 295-424 wires unit tests with separate direct test modules for `retained_render` rooted at `src/terminal/render/retained.zig` and `render_surface` rooted at `src/display/renderer/render_surface.zig`, plus terminal context tests rooted at `src/test_root.zig`.
- The separate `retained_render` and `render_surface` test modules are current accepted wiring. A new owner file must be reached through exactly one curated host unit test path; do not add duplicate side-entry test roots unless reviewer accepts test wiring changes.

## Duplicated Concepts Table

| Concept | Retained owner currently | Display renderer currently | Owner finding |
| --- | --- | --- | --- |
| C ABI surface version and span count/max validation | `validatePreparedRenderSurfaceProbe` lines 938-981; `validateResourcePlanTopLevel` lines 1037-1069; `validateResourceStoreSurfaceSpans` lines 494-525 | `validateSurfaceTransition` lines 169-226; `spanCountValid` lines 737-742 | Duplicate. One host render-surface contract validator should own this. |
| Upload byte total/max validation | Retained lines 976-980, 1063-1068, 519-524 | Display lines 219-225, 540-554 | Duplicate. Contract validator should own total/max and per-upload sum checks; GL upload retains backend upload failure checks. |
| Resource create/upload/retire ordering | Retained resource plan lines 1072-1148; software probe lines 1227-1300; resource store lines 528-547 | Display lines 523-562 and staged transition lines 236-312 | Duplicate. Contract validator should own pure ordering/lifecycle. Display texture owner should consume validated surfaces and keep rollback for GL mutation. |
| Command shape validation | Retained `validateResourceStoreCommandShape` lines 446-482; `validatePlanCommand` lines 1150-1165; `validateCommand` lines 1302-1321 | Display `CommandShapeError`/`commandShapeErrorStatic` lines 564-624 and shape classifiers lines 2122-2361 | Duplicate. Pure command validity belongs to contract validator; upload class selection can remain display-side for GL path selection. |
| Glyph ref validity | Retained lines 1181-1208 and 1365-1391 | Display lines 2331-2361 | Duplicate. Contract validator should own glyph ref validity; display draw keeps assertions and texture-slot lookup. |
| Resource state mirror | Retained `RenderResourceStore` lines 235-444 | Display `RenderResourceTextures` lines 35-489 | Responsibility bundling. Display owns realized GL texture state. Retained software store should not mirror backend state in product code unless tests prove a separate non-GL contract owner needs it. |
| Failure/status taxonomy | Retained `PreparedRenderResourcePlanStatus`, `RenderResourceStoreStatus`, `PreparedRenderSurfaceProbeStatus` lines 88-105, 131-141, 563-584 | Display `FailureBucket`, `CommandShapeError`, `TrustedTextureFailureAction` lines 59-68, 500-521, 564-580 | Offender. Collapse duplicated validation status vocabulary into one host contract status. GL failures remain display-specific. |
| Prepared info vs surface geometry consistency | Retained lines 932-945 and tests 1954-1986 | Display does not validate prepared info; it only validates surface self-consistency | Retained/contract boundary. Because this compares C prepared-handle info to surface, it is submit-boundary contract validation, not GL resource realization. |
| Shape classification for upload policy | Retained does not classify upload class directly | Display lines 2122-2361 and context lines 572-628 | Display-side. This is GL upload selection and patch policy, not retained. Do not move in first slice. |

## Proposed Owner Boundary

Concepts that must remain in `howl-linux-host/src/terminal/render/retained.zig`:

- Retained C ABI text-session handle and prepared-surface handle ownership: `State.text_session`, `State.prepared_surface`, `prepare`, `prepareReady`, `acceptPrepared`, `submit`, `submitHandle`, `releasePreparedSurface`, `storePreparedSurface`, `forgetPreparedSurface` lines 612-918.
- Host-owned present in-flight sequencing: `PresentInFlight`, `notePresentSubmitted`, `completePresent`, `presentPending` lines 28-31 and 679-696.
- Surface layout and geometry epoch synchronization: `SurfaceLayout`, `SurfaceLayoutSync`, `surfaceLayoutSync`, `syncSurfaceLayout`, `setGeometryEpoch` lines 52-64 and 642-665.
- Work-state aggregation from C ABI plus present pending: `WorkState` and `workState` lines 33-50 and 667-677.
- Prepare/submit result/failure families that describe retained sequencing only: `PrepareResult`, `PrepareFailure`, `SubmitResult`, `SubmitFailure` lines 4-26.
- `PreparedUpload` as the submit-boundary carrier may remain in retained, but should stop carrying separate probe/resource-plan result structs. It should carry prepared `info`, borrowed `render_surface`, and one contract validation fact/status if reviewer accepts.

Concepts that must remain in `howl-linux-host/src/display/renderer/render_surface.zig`:

- GL texture lifetime and mutation: `RenderResourceTextures`, `Slot`, `realizeSurface`, `realizeSurfaceLocked`, `createTexture`, `uploadTexture`, `commitUploadMetadata`, `invalidateUploads`, `retireTexture`, `deleteSlot`, `retireSlot` lines 35-489.
- Host surface texture realization: `ensureSurface` lines 1916-1955 and `deleteTexture` lines 24-29.
- GL upload/draw execution: `uploadRenderSurfaceFillOnly`, `uploadRenderSurfaceFillPatch`, `uploadRenderSurfaceSprites`, `uploadRenderSurfaceSpritePatch`, `uploadRenderSurfaceGlyphs`, `uploadRenderSurfaceGlyphPatch`, `uploadRenderSurfaceCommands`, draw helpers lines 1957-2587.
- Upload-shape classification used by context/display backend policy may remain here for the first slice: `renderSurfaceFillOnly`, `renderSurfaceFillPatch`, `renderSurfaceSprite`, `renderSurfaceSpritePatch`, `renderSurfaceGlyphs`, `renderSurfaceGlyphPatch`, `renderSurfaceSummary` lines 2182-2361.
- GL-specific failure action mapping may remain here: `TrustedTextureFailureAction`, `trustedTextureFailureAction`, GL/fill row failure handling lines 500-521 and 2413-2422.

Smaller owner file recommended:

- Create `howl-linux-host/src/display/renderer/render_surface_contract.zig`.
- Owner noun: `render_surface_contract` owns host-side validation of the C ABI `HowlRenderSurface` contract before display renderer resource realization and retained submit. It is not `utils`, `manager`, `engine`, `controller`, `types`, or a bucket. It owns behavior: validate a borrowed `HowlRenderSurface` plus optional `HowlRenderPreparedSurfaceInfo` consistency, classify invalid contract facts, count bounded surface facts used by callers, and provide trusted action mapping for invalid contract statuses.
- Why under `display/renderer`: Alacritty keeps backend resource realization and renderer validation pressure under renderer owners; Howl hosts own backend resource realization. This file is host-side C ABI contract validation for render-surface consumption, not internal `howl-render` ABI/emitter ownership and not terminal retained state.
- Why not inside `render_surface.zig`: retained needs validation without importing a GL-heavy file full of externs and upload/draw code. A small sibling avoids forcing retained to depend on GL resource realization just to validate a C ABI surface.
- Why not under `terminal/render`: pure render-surface validity is not retained handle sequencing; it is the contract that the display renderer must trust before GL mutation.

Status/probe/result offenders and collapse target:

- Remove/collapse `PreparedRenderResourcePlanStatus` from `retained.zig` lines 88-105 into `render_surface_contract.RenderSurfaceContractStatus` or equivalent owner-true status.
- Remove/collapse `PreparedRenderSurfaceProbeStatus` from `retained.zig` lines 563-584 into the same contract status. Geometry mismatch statuses can remain in the contract status because they validate prepared-info-to-surface consistency at the submit boundary.
- Remove/collapse `RenderResourceStoreStatus` from `retained.zig` lines 131-141 if `RenderResourceStore` is deleted or moved to contract tests. It mirrors display backend lifecycle and should not remain as product retained status.
- Remove or private-test-only `CommandShapeError` from `render_surface.zig` lines 564-580 after contract tests cover command shape validity. Display should not need a detailed command-shape taxonomy separate from the contract validator; upload classifiers can return bool for GL path selection.
- Keep `TrustedTextureFailureAction` in display because it classifies GL/backend realization failures, not pure render-surface contract failures.
- Keep retained `PrepareFailure`/`SubmitFailure` because they describe retained ABI sequencing and present-pending behavior, not render-surface validation.

## Worker-Ready First Cut Proposal

Readiness: this proposal is ready for reviewer, not worker-ready until reviewer accepts the new owner path and exact status collapse.

Allowed files for the first cut:

- Add: `howl-linux-host/src/display/renderer/render_surface_contract.zig`.
- Edit: `howl-linux-host/src/terminal/render/retained.zig`.
- Edit: `howl-linux-host/src/display/renderer/render_surface.zig`.
- Edit only if required by imports/status names: `howl-linux-host/src/terminal/context.zig`.
- Edit only if required by test module import wiring: `howl-linux-host/build.zig`.
- Do not edit product ABI headers, `howl-render`, `howl-vt`, parser/action, render emitter, or scratchpads/current.

Exact first cut:

- Introduce `display/renderer/render_surface_contract.zig` with one owner-true status enum for C ABI render-surface validation, for example `RenderSurfaceContractStatus`, and one small validation fact shape, for example `RenderSurfaceContract`. Reviewer should approve names before worker implementation.
- Move pure validation helpers out of retained: span count/max, version, upload byte total/max, create/upload/retire lifecycle, command shape, glyph ref validity, resource visibility, rect math, resource format/kind, bytes-per-pixel minimum.
- Move or share equivalent pure validation currently in display: `validateSurfaceOrderStatic`, `commandShapeErrorStatic` behavior, `resourceFormatValid`, `uploadValidForSlot` contract portions, `rectFitsResource`, `destinationOverlaps`, `spanCountValid` where pure.
- Keep GL mutation and upload path in `render_surface.zig`. It may call the contract validator at the top of `RenderResourceTextures.realizeSurface` or `realizeSurfaceLocked`, then proceed with GL create/upload/retire. It should keep rollback and GL sampling locally.
- Change retained `preparedUpload` to call the contract owner after obtaining the borrowed surface. Retained records at most one contract fact/status if still needed by context. Remove separate probe and plan computation in retained.
- Delete retained `RenderResourceStore` product mirror unless reviewer asks to preserve it as contract-owner tests. If preserved, it must not remain in retained product state.
- Convert retained tests for probe/resource-plan validation to contract-owner tests reached through the existing host test gate. Preserve retained tests for layout, present pending, prepare/submit handle sequencing.
- Convert display tests that assert pure command shape/order/span validation to contract-owner tests. Preserve display tests that assert GL texture mutation, rollback, upload metadata, GL/failure action behavior, and upload shape classifiers.

Required tests to preserve or move:

- Retained tests to keep in `retained.zig`: `surface layout sync reports grid and cell changes`, `present in flight contributes host-owned pending state`, `matching complete present returns snapshot once and clears`, `submit is blocked while host present is pending`, `submit is allowed after matching complete present clears pending state` lines 1802-1935.
- Retained tests to move/rename to contract owner: trusted probe/resource plan/store action classification lines 1822-1892; render-surface probe/dimension/span/upload-byte tests lines 1936-2046; software probe tests lines 2070-2245; resource plan tests starting 2266; resource store tests later in file.
- Display tests to keep in `render_surface.zig`: GL texture realization/metadata/failure bucket tests tied to `RenderResourceTextures` mutation, e.g. lines 1401-1427 and 1788-1914, plus upload/draw classifier tests if not duplicated in contract tests.
- Display tests to move/rename to contract owner: invalid top-level/span/order/command shape tests lines 905-1060 and command shape tests lines 1060-1105 where they assert pure contract validity.
- Test wiring should continue to run under `zig build test:unit --summary all` in `howl-linux-host`. If adding a new direct test root is required, stop for reviewer because AGENTS says one curated module test entrypoint per module and current build already has separate retained/render-surface roots.

Verification gates:

- `zig fmt` on touched Zig files.
- `zig build test:unit --summary all` from `howl-linux-host`.
- Targeted filters if available: render-surface contract/retained/render-surface tests through `zig build test:unit --summary all -- <filter>` only after checking this build accepts filters through `b.args`.

Non-goals:

- No C ABI/header changes.
- No `howl-render` internal Zig imports into host as convenience APIs.
- No generic owner names: no `utils.zig`, `types.zig`, `manager`, `engine`, `controller`, `validation.zig`, or `helpers.zig`.
- No broad `Context`/terminal context reshaping beyond minimal status/import adjustment needed by the collapsed contract status.
- No parser/action cleanup.
- No render-surface emitter cleanup.
- No public C header changes or compatibility aliases.
- No broad host/display reshaping or window chrome movement.

Stop conditions:

- Stop if the worker cannot collapse statuses without changing public ABI semantics.
- Stop if retained still needs separate probe and plan facts for behavior not found in current source. Current grep shows only context and tests consume them, but reviewer should confirm.
- Stop if a new test root is needed and cannot be reached through existing curated host unit test wiring without weakening test law.
- Stop if GL-specific failures or texture-slot mutation start moving into the contract owner.
- Stop if the contract owner becomes a bag of helpers with no single validation entrypoint and no owner-local tests.

## Explicit Deferrals

- ABI changes to `howl-render/include/howl_render.h` and any public C header.
- `howl-linux-host/src/terminal/context.zig` render upload policy cleanup beyond minimal status/import adjustment.
- VT parser/action/vocabulary cleanup.
- `howl-render/src/prepared/render_surface_emitter.zig` and render emitter/status cleanup.
- `howl-render/src/prepared/owner.zig`, `howl-render/src/session/text.zig`, and render C ABI mirroring cleanup.
- Public C headers and generated/translated C import wrappers.
- Broad host/display reshaping, window chrome movement, event-loop/runtime changes, or GL backend architecture changes.

## Proof Gaps

- I did not inspect every line after `retained.zig` line 2350, but symbol grep showed the remaining relevant matches are tests for the same probe/plan/store/status cluster.
- I did not run tests or builds because this is research-only.
- I did not inspect every Alacritty renderer text file. The read files are sufficient to prove GL/resource realization belongs under renderer owners, but not to prescribe every Howl function split.
- Foot source was not present in this checkout, so Foot could not provide source-backed proof.
- The exact new names (`RenderSurfaceContractStatus`, `RenderSurfaceContract`) need reviewer acceptance before worker implementation because naming is ownership.

## Readiness Judgment

Ready for reviewer. Not worker-ready until reviewer accepts:

- The new owner file path `howl-linux-host/src/display/renderer/render_surface_contract.zig`.
- The single contract status/fact names.
- Whether retained `RenderResourceStore` is deleted outright or moved as contract-owner test-only coverage.
- Whether minimal `terminal/context.zig` edits are allowed to remove dependence on `PreparedRenderResourcePlanStatus`.
