# Render Surface ABI Status Readiness - 2026-06-02

## User Correction

The C ABI is code like the rest. Howl is young and private; there is no years-old downstream foundation to protect. Bad ABI style should be molded while hot. ABI cleanup is in scope. The product boundary still stands: C ABI only, no Zig-shaped host shortcuts, and no compatibility shims unless explicitly required.

The rejected readiness map protected the render header while extracting host validation. This cache integrates render ABI/header/FFI/status shape with host retained/display/context duplication.

## Sources Read In Order

1. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md` lines 90-113, 136-140, 373-429.
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md` lines 189-222, 408-423.
3. Existing `research/*.md` caches via grep terms below.
4. `reference-index.md` lines 7-15, 83-160, 161-193.
5. `howl-render/include/howl_render.h` lines 19-87, 184-314, 481-617.
6. `howl-render/src/ffi/render_surface.zig` lines 4-7, 127-167, 169-187, 325-350.
7. `howl-render/src/ffi/prepared_surface.zig` lines 26-50, 53-80.
8. `howl-render/src/prepared/owner.zig` lines 17-27, 33-72, 114-138, 206-217, 243-255, 306-354, 415-452, 573-668.
9. `howl-render/src/prepared/render_surface_emitter.zig` lines 18-68, 326-386, 423-437, 513-686, 688-760.
10. `howl-render/src/render/render_surface_realizer.zig` lines 17-58, 175-249, 251-490, 619-746.
11. `howl-linux-host/src/terminal/render/retained.zig` lines 66-156, 235-300, 382-548, 550-627, 809-849, 932-1247, 1249-1378.
12. `howl-linux-host/src/display/renderer/render_surface.zig` lines 35-99, 101-234, 236-489, 500-624, 674-742.
13. `howl-linux-host/src/terminal/context.zig` lines 539-719, 721-758.
14. `howl-render/src/test.zig` lines 3-7; `howl-linux-host/build.zig` lines 295-439; `howl-linux-host/src/test/test_entry.zig` lines 1-7; `howl-linux-host/src/test_root.zig` lines 1-13.
15. Alacritty `display/mod.rs` lines 342-400, 775-838; Alacritty `renderer/mod.rs` lines 89-175, 177-255.
16. Ghostty `src/terminal/c/result.zig` lines 1-8; Ghostty `src/terminal/c/terminal.zig` lines 208-237.

## Research-Cache Grep Terms And Leads

Terms: `HowlRenderSurfaceEmitStatus`, `render_surface_emit_status`, `PreparedRenderResourcePlan`, `PreparedUpload`, `RenderResourceStore`, `FailureBucket`, `CommandShapeError`, `ContextSubmitBackend`, `crashOnRenderSurfaceUnavailable`, `renderSurfaceEmitError`.

Leads found:

- `research/cache-2026-06-02-render-surface-validation-owner.md` lines 78-139 identified retained probe/resource-plan/store validation and display `FailureBucket`/`CommandShapeError` duplication, but proposed a host contract owner while leaving ABI cleanup unsettled.
- `research/cache-2026-06-02-hygiene-offenders-a.md` lines 45-65 and 527-540 identified ABI status inflation and mirror structs.
- `research/cache-2026-06-01-render-surface-host-failure-classes.md` lines 44-54 identified `prepared_surface_render_surface()` as the host pointer source and `Owner.create()` as the emit-status source.
- `research/cache-2026-06-01-resize-test-invariants-review.md` lines 87-95 identified retained `RenderResourceStore` vs display `RenderResourceTextures` lifecycle duplication and patch upload policy risk.

Old caches were navigation only; every claim below is re-verified against current source.

## Reference Findings

- TigerBeetle: return-type/status dimensionality should be minimized; `void` beats `bool`, `bool` beats wider nullable/error shapes when possible (`TIGER_STYLE.md` lines 426-429). Assertions must cover positive and negative space and function contracts (`TIGER_STYLE.md` lines 104-140). This argues against duplicated public and host-private status taxonomies for the same trusted render-surface invariant.
- TigerBeetle: control plane/data plane separation allows aggressive O(N) validation at the control boundary (`ARCHITECTURE.md` lines 408-423). Render-surface structural validation belongs before submitting a surface across the ABI or immediately at the host/backend realization boundary, not split into three drifting validators.
- Alacritty: `Display` owns renderer, GL surface/context, glyph cache, and damage tracker (`display/mod.rs` lines 342-400). `Display.draw()` collects terminal content, drops the terminal lock early, makes the GL context current, then renders (`display/mod.rs` lines 775-838). This supports keeping true backend resource realization in display/renderer, not retained terminal state.
- Alacritty: `Renderer` owns GL renderer selection and draw calls (`renderer/mod.rs` lines 89-175, 177-255). It does not expose a public ABI status lattice for internal renderer validation. Howl differs because it has an embeddable C render surface, but the reference pressure keeps backend resource state host/display-owned.
- Ghostty C API: C-facing results are a small `enum(c_int)` (`result.zig` lines 1-8), and terminal creation maps Zig errors to that small result while returning an opaque handle (`terminal.zig` lines 208-237). This supports C ABI consequences that are compact and product-level, not mirrors of internal validator names.

## Current Source Map

### Render ABI/Header

- `howl_render.h` defines render-surface maxima and command/resource constants at lines 19-44. These are product C contract facts because the host needs array bounds, command/resource tags, and upload byte limits to consume `HowlRenderSurface` safely.
- `HowlRenderSurfaceEmitStatus` at lines 53-65 is a public taxonomy of render-owned emission failures. Each tag maps to an error in `prepared/owner.zig` lines 243-255.
- `HowlRenderSubmitStatus` and `HowlRenderSubmitDecisionStatus` at lines 73-87 describe render session state transitions consumed by retained host submit orchestration in `retained.zig` lines 743-797.
- `HowlRenderSurface` at lines 302-314 is the product render-surface payload contract. It contains version, token, geometry, damage, creates, uploads, commands, and retires.
- `HowlRenderPreparedSurfaceInfo` at lines 481-495 contains prepared metadata plus `render_surface_emit_status` at line 490.
- `howl_render_prepared_surface_describe()` and `howl_render_prepared_surface_render_surface()` are separate ABI functions at lines 610-617. The split currently lets the host read metadata and then separately request the surface pointer.

### Render FFI

- `ffi/render_surface.zig` mirrors the C surface layout and asserts constants/layout at comptime (`lines 4-7`, `141-167`, `169-187`, `325-338`). It imports `render_surface_realizer.zig` only through a test block at lines 349-350.
- `ffi/prepared_surface.zig` writes `PreparedInfo.render_surface_emit_status` into the ABI info field at lines 53-65. On describe failure it zeroes info and sets emit status to OK at lines 68-80, which means the emit status is only meaningful when `status == HOWL_RENDER_CALL_OK`.
- `ffi/prepared_surface.zig` returns a render-surface pointer or `HOWL_RENDER_CALL_INVALID_ARGUMENT` when owner has no surface at lines 41-50. It does not return the emit failure itself in that call.

### Render Owner And Emitter

- `PreparedInfo` stores `render_surface_emit_status: i32` at `owner.zig` lines 17-27.
- `Owner.create()` allocates/emits a render-surface payload and catches emission errors into `render_surface_emit_status` at lines 58-72. On error, `render_surface_payload` remains null because `emitRenderSurfacePayload()` publishes the payload only after `emitPrepared()` succeeds (`lines 206-217`).
- `Owner.renderSurface()` asserts liveness and returns null when `render_surface_payload` is null (`lines 134-138`). This is the actual availability fact.
- `renderSurfaceEmitStatus()` maps every emitter error to the public `HowlRenderSurfaceEmitStatus` tags at lines 243-255, and tests assert every mapping at lines 415-452.
- Tests assert missing sprite/overflow/allocation failure produce null render surface plus non-OK emit status (`owner.zig` lines 306-354, 573-668).
- `render_surface_emitter.zig` owns bounded static arrays for damage/create/upload/command/glyph/retire payloads (`lines 326-345`) and emits a fully populated `HowlRenderSurface` only after successful append/publication (`lines 357-386`). Its error set at lines 36-46 is the internal source of public emit failures.

### Render Realizer

- `render_surface_realizer.zig` has `ResourceStore` with resource entries and uploaded bytes at lines 17-34.
- `realize()` and `realizeRetained()` produce RGBA pixels from a `HowlRenderSurface` and optional retained resource store (`lines 192-240`).
- It validates the entire render-surface structural and lifecycle contract before drawing (`lines 242-249`, `251-490`). It validates spans, damage, creates, retires, uploads, command shapes, glyph refs, resource visibility, upload coverage, and retained resource lookup.
- Because it has no GL calls and is imported by render tests (`ffi/render_surface.zig` lines 349-350; `owner.zig` lines 467-545), it is a product-side test oracle and render-surface contract validator pressure, not a product backend.

### Host Retained

- `PreparedUpload` bundles ABI info, `PreparedRenderSurfaceProbe`, `PreparedRenderResourcePlan`, and the borrowed surface pointer at `retained.zig` lines 66-75.
- `PreparedRenderResourcePlanStatus` has 16 tags at lines 88-105. `PreparedRenderSurfaceProbeStatus` has 21 tags at lines 563-584. Both classify trusted ABI surface invalidity.
- Retained `State` stores last probe/plan plus counters at lines 612-627.
- `preparedUpload()` calls describe, then `probePreparedRenderSurface()` to call `howl_render_prepared_surface_render_surface()`, validate plan, validate probe, record both, and return true at lines 809-849.
- `validatePreparedRenderSurfaceProbe()` validates metadata equality and spans, then calls `validateSoftwareSurface()` (`lines 932-995`, `1227-1247`).
- `validateRenderSurfaceResourcePlan()` validates top-level spans, counts resource uses, and validates lifecycle (`lines 1018-1035`, `1037-1208`). This overlaps the render realizer contract and display validation.
- `RenderResourceStore` mirrors software resource lifecycle in retained product code at lines 235-300, with command/resource validation at lines 382-443 and helper validation at lines 446-548.

### Host Display Renderer

- `RenderResourceTextures` owns true GL texture slots, success/failure counters, failure bucket, resource kind, texture creation/upload/retire, and rollback at `render_surface.zig` lines 35-99 and 101-489.
- `validateSurfaceTransition()` validates ABI spans, upload byte bounds, commands, order, creates, uploads, retires before GL mutation (`lines 169-234`). This is host-before-backend-realization validation.
- `FailureBucket` at lines 59-68 and `trustedTextureFailureAction()` at lines 500-516 classify trusted surface failures separately from retained probe/plan statuses.
- `CommandShapeError` and `commandShapeErrorStatic()` at lines 564-624 duplicate command shape validation with a display-private taxonomy.

### Host Context

- `ContextSubmitBackend.upload()` realizes render-surface resources, ensures the host surface, uploads commands, and handles unavailable surface through emit status plus resource-plan status (`context.zig` lines 539-569).
- If `prepared_upload.render_surface == null`, it first maps `prepared_upload.info.render_surface_emit_status` through `renderSurfaceEmitError()` and panics on non-OK (`lines 556-563`, `671-704`). Then it calls `crashOnRenderSurfaceUnavailable()` with retained `PreparedRenderResourcePlanStatus` (`lines 656-669`).
- Upload policy and shape dispatch live inside terminal context (`lines 572-628`), while GL resource realization lives in `RenderResourceTextures.realizeSurface()` (`display/renderer/render_surface.zig` lines 81-99).
- `submitPreparedLockedWith()` drops the terminal mutex for backend upload and relocks before submit (`context.zig` lines 721-758), matching Alacritty's lock-release-before-rendering pressure.

## ABI Decision Table

| ABI item | Decision | Source proof | Rationale |
| --- | --- | --- | --- |
| `HOWL_RENDER_SURFACE_*_MAX` constants | Keep | Header lines 19-31; FFI asserts lines 141-154; emitter limits lines 48-67 | Product C bounds for host-safe spans and static arrays. |
| Render command/resource/upload constants | Keep | Header lines 33-44; FFI asserts lines 155-166; emitter and host switch on them | Product C tags needed to consume surfaces. |
| `HowlRenderSurface` | Keep, sharpen validation | Header lines 302-314; FFI layout asserts lines 325-338 | Core product render payload. Validation should be render-owned before crossing ABI and host-owned before GL realization. |
| `HowlRenderSurfaceEmitStatus` | Reshape | Header lines 53-65; owner mapping lines 243-255; context mapping lines 685-699 | The product fact is render-surface availability/emission failure, but the public name and field placement are stale internal mirrors. Prefer a prepared-surface availability consequence, not an `emit_status` field buried in generic info. |
| `HowlRenderPreparedSurfaceInfo.render_surface_emit_status` | Reshape | Header line 490; FFI writes it lines 53-65; owner stores it lines 17-27, 50, 114-125 | Owner-true as a render-owned consequence today, but not owner-true as a field in metadata. It couples describe info to surface availability and forces host retained plan status as a second unavailable classifier. |
| `HowlRenderPreparedSurfaceInfo.status` | Keep | Header line 482; FFI describe success/failure lines 26-39, 68-80 | Function call status is a C contract fact for the describe call. |
| `HowlRenderPreparedSurfaceInfo` geometry/token fields | Keep | Header lines 481-495; retained validates equality lines 932-945 | Host needs prepared geometry/token to size host surface and submit. |
| `howl_render_prepared_surface_describe()` | Keep | Header lines 610-613; FFI lines 26-39 | C ABI metadata query is product boundary. |
| `howl_render_prepared_surface_render_surface()` | Reshape | Header lines 614-617; FFI lines 41-50; context fallback lines 556-563 | The function should expose one ABI-visible availability result/consequence. Current `INVALID_ARGUMENT` for null surface plus separate info emit status is split and host-host status duplication follows from it. |
| `HowlRenderSubmitStatus` | Keep | Header lines 73-79; retained submit lines 743-797 | Product submit state consequence consumed by host orchestration. It is broader than render-surface validation. |
| `HowlRenderSubmitDecisionStatus` | Keep | Header lines 81-87; retained decision handling lines 750-769 | Product submit decision consequence. |
| `HowlRenderCallStatus` | Keep | Header lines 46-51; FFI describe/renderSurface lines 26-50 | Generic C call result remains useful, but must not be overloaded to hide render-surface emission failure. |
| `HowlRenderHostSurface` / `HowlRenderSubmitExecution` | Keep | Header lines 475-499; context execution lines 710-718; owner submit validation lines 300-304 | Host-owned realized surface dimensions/id passed back to render submit. |
| `HowlRenderSubmitResult` | Keep | Header lines 501-507; retained submit asserts lines 786-790; context consumes lines 747-756 | Render submit result C contract. |

## Status Chain Map

1. Render emission starts in `Owner.create()` (`owner.zig` lines 58-72).
2. `emitRenderSurfacePayload()` allocates an emitter payload and calls `payload.emitPrepared()` (`owner.zig` lines 206-217).
3. Emitter either publishes a valid `HowlRenderSurface` (`render_surface_emitter.zig` lines 371-386) or returns one of the internal errors at lines 36-46.
4. Owner maps internal error to public `HowlRenderSurfaceEmitStatus` (`owner.zig` lines 243-255), stores it in `Owner.render_surface_emit_status`, and leaves `render_surface_payload` null (`owner.zig` lines 65-70, 134-138).
5. `howl_render_prepared_surface_describe()` exposes the stored status through `HowlRenderPreparedSurfaceInfo.render_surface_emit_status` (`ffi/prepared_surface.zig` lines 53-65).
6. Host retained `preparedUpload()` calls describe, then `howl_render_prepared_surface_render_surface()` (`retained.zig` lines 809-849).
7. If the surface is null, retained sets `PreparedRenderResourcePlan.status = .null_surface` or `.call_failed` and records probe/plan counters (`retained.zig` lines 825-849, 862-869).
8. Context upload sees `prepared_upload.render_surface == null`, calls `renderSurfaceEmitError(prepared_upload.info.render_surface_emit_status)`, then calls `crashOnRenderSurfaceUnavailable(prepared_upload.render_surface_resource_plan.status)` (`context.zig` lines 556-563, 660-704).
9. Therefore the same unavailable condition is represented by two status chains: ABI emit status and host-private resource-plan status. The ABI emit status carries the real render-owned cause; the host plan status is a stale mirror for this branch.

## Validation Ownership Table

| Validation | Render-before-ABI | Host-before-backend-realization | Source proof / note |
| --- | --- | --- | --- |
| Static ABI layout/constants | Yes | No | `ffi/render_surface.zig` comptime asserts lines 4-7, 141-187, 325-338. |
| Span count/count_max/null pointer validity for emitted surface | Yes | Assert or defensive recheck before GL | Emitter owns counts and pointers; realizer validates spans lines 251-257, 274-280, 337-360, 402-416. Display rechecks spans lines 169-226 before GL. |
| Surface version | Yes | Assert/recheck before GL | Header line 19; realizer line 243; display lines 169-173. |
| Prepared info equals surface geometry/grid | Yes before returning surface pointer | Host may assert at ABI edge if consuming info+surface together | Retained currently validates lines 940-945. Better rendered ABI consequence should avoid separate info/surface drift. |
| Damage item kind/full rect validity | Yes | No GL-specific need except assertion | Realizer lines 251-272. Display renderer does not use damage directly for texture upload. |
| Command shape | Yes | Host shape classifier only for choosing upload path, not validity taxonomy | Realizer lines 402-490. Retained duplicates lines 1302-1378. Display duplicates lines 564-624. |
| Resource create/upload/retire lifecycle inside surface | Yes | Yes where backend resource state is true owner | Realizer validates contract with optional retained store lines 55-109, 242-249, 664-746. Display must validate transition against actual GL slots lines 169-234, 236-489. Retained product mirror should not own it. |
| Upload byte bounds/stride/rect coverage | Yes | Yes before GL upload | Realizer lines 337-400; display lines 674-687. |
| GL texture capacity, GL errors, texture id ownership | No | Yes | Display `RenderResourceTextures` lines 35-99, 314-388, 500-516. |
| Host surface match for patch upload | No | Yes host presentation policy | Context policy lines 620-628; this belongs near display upload shape, not render ABI. |

## Realizer Role Judgment

`render_surface_realizer.zig` is a product-side test oracle and render-surface contract validator pressure, not a product backend.

Proof:

- It has no GL/backend calls and writes RGBA pixels into caller-provided memory (`render_surface_realizer.zig` lines 192-240).
- It validates the full ABI surface contract before drawing (`lines 242-490`).
- It has an optional software `ResourceStore` for retained resource semantics (`lines 17-58`, `196-240`), but this is useful as oracle state for tests and render contract proof, not as a host/backend resource owner.
- Render prepared owner tests compare emitted surfaces to explicit RGBA oracle output (`owner.zig` lines 467-545).

## Retained Resource Lifecycle Mirror Judgment

Retained does not need a product resource lifecycle mirror after display owns true backend resources.

Proof:

- Retained `RenderResourceStore` stores resource lifecycle and upload facts in product code (`retained.zig` lines 235-300, 382-443) while display `RenderResourceTextures` stores true GL lifecycle (`display/renderer/render_surface.zig` lines 35-99, 314-489).
- Retained `RenderResourceStoreStatus` and display `FailureBucket` classify overlapping failures (`retained.zig` lines 131-156; display lines 59-68, 500-516).
- Alacritty keeps renderer/display resources in display/renderer (`display/mod.rs` lines 342-400; renderer lines 89-175). Terminal content preparation does not mirror GL texture lifecycle.
- If a software lifecycle model remains, it belongs in render contract/oracle tests, not retained product state.

## Test Entrypoint And Test Impact Map

- Render module single entrypoint is `howl-render/src/test.zig`, which imports `libhowl_render.zig`, `test/ffi.zig`, and `test/unit/root.zig` (`lines 3-7`). New render ABI/contract owner tests should be reached through this existing entrypoint only.
- Host retained tests are already wired as a dedicated module rooted at `src/terminal/render/retained.zig` in `howl-linux-host/build.zig` lines 338-347 and 405-413. Do not add a new side root for retained cleanup.
- Host display render-surface tests are already wired as a dedicated module rooted at `src/display/renderer/render_surface.zig` in build lines 349-357 and 415-423. Do not add a new side root.
- Terminal context tests are wired through `src/test_root.zig` (`build.zig` lines 359-366, 426-439; `test_root.zig` lines 1-13). Context call-site changes should use existing terminal context test path.
- `src/test/test_entry.zig` currently imports `retained_render` but not `render_surface` despite build imports including it (`test_entry.zig` lines 1-7; build lines 318-325). This is test wiring debt, but not a blocker for using the dedicated `test-render-surface` root already present.

## Answers To Required Questions

1. Product-required public ABI facts: surface maxima, command/resource/upload constants, `HowlRenderSurface`, prepared geometry/token info, submit decision/status, submit execution/result, and generic call status. Safe-to-mold stale mirrors: `HowlRenderSurfaceEmitStatus` naming/placement, `HowlRenderPreparedSurfaceInfo.render_surface_emit_status`, and the split `describe()` plus `render_surface()` unavailable consequence.
2. `HowlRenderPreparedSurfaceInfo.render_surface_emit_status` is render-owner-true as a consequence but not ABI-shape-owner-true as a metadata field. Surface availability/emit failure should be exposed through a prepared render-surface ABI consequence, ideally the render-surface retrieval call returns one public availability status and the pointer together.
3. Host validation should consume one ABI-visible availability status for surface retrieval, plus no retained/private status for trusted render-surface validity. Host backend realization may keep a display-private operating/invariant bucket for GL/resource realization failures, but not a retained probe/plan status lattice.
4. Render-before-ABI validation: emitted surface version, spans, pointer/count invariants, geometry/info consistency, damage, command shape, resource lifecycle within the emitted surface, upload coverage. Host-before-backend-realization validation: actual GL texture slot transition, capacity, GL errors, texture id ownership, host patch policy, and fail-closed assertions before `glTex*` calls.
5. `render_surface_realizer.zig` is a product-side test oracle/contract validator pressure. It is not a product backend. Its software `ResourceStore` may support oracle retained-resource tests, but should not justify retained product resource mirrors.
6. Retained needs no product resource lifecycle mirror after display owns true backend resources. Keep retained prepare/submit/present state and borrowed prepared handle only.
7. New render owner tests go through `howl-render/src/test.zig`. Host retained/display/context impacts use existing build roots: retained root `src/terminal/render/retained.zig`, display root `src/display/renderer/render_surface.zig`, context through `src/test_root.zig`.
8. Worker-ready first slice exists only if it includes ABI cleanup. Exact slice below.

## Worker Readiness Judgment

Worker-ready: yes, for a single ABI consequence cleanup slice that removes the split unavailable status chain before host validation extraction.

Exact first worker slice:

- Reshape prepared render-surface retrieval so `howl_render_prepared_surface_render_surface()` exposes one public ABI-visible surface availability consequence instead of overloading generic `HowlRenderCallStatus` plus `HowlRenderPreparedSurfaceInfo.render_surface_emit_status`.
- Keep C ABI only. Do not add Zig-shaped host shortcuts or compatibility aliases.
- Rename/reshape `HowlRenderSurfaceEmitStatus` into an owner-true prepared render-surface availability/status contract, or replace it with the minimal C enum returned by the render-surface retrieval call. Tags must preserve all current render-owned causes: command/create/damage/retire/resource/upload/upload-bytes overflow, invalid/missing prepared sprite, allocation failed, plus OK.
- Remove `render_surface_emit_status` from `HowlRenderPreparedSurfaceInfo` and from `PreparedInfo` after retrieval returns the consequence directly.
- Update `ffi/prepared_surface.zig`, `prepared/owner.zig`, and render tests that currently assert `owner.info().render_surface_emit_status` to assert the new retrieval/status consequence.
- Update host retained `PreparedUpload` to carry `info`, `render_surface`, and the one ABI retrieval status. Remove `PreparedRenderResourcePlan` from the null-surface path and stop calling `crashOnRenderSurfaceUnavailable()` for emission failure.
- Leave broader retained `PreparedRenderSurfaceProbe`, `PreparedRenderResourcePlan`, and `RenderResourceStore` deletion for the next slice only after the ABI consequence is no longer split. This is not deferral; it is the required order because current context panic policy depends on both chains.
- Verification: `zig build test:unit` in `howl-render`; `zig build test:unit -- <filter for retained/context if supported>` or host `zig build test:unit` after host call-site update.

Exact worker constraints:

- No compatibility shim names unless user explicitly requires them.
- No new test roots.
- Do not extract host validation owner in this slice.
- Do not move GL resource ownership out of display.
- Preserve fail-closed panic policy for trusted render emission failure.

## Exact Next Research Questions If Slice Is Challenged

- What exact C enum name and function signature should replace the current retrieval status? Candidate fact to decide: whether `howl_render_prepared_surface_render_surface()` should return the new enum directly, or return `HowlRenderCallStatus` while writing a small `HowlRenderPreparedSurfaceResult` out struct containing `status` and `surface`.
- Whether render-side validation should be exposed as a debug/test-only contract proof or a runtime assertion before every ABI surface return. Current emitter constructs valid surfaces, and realizer validates in tests; the missing fact is performance/panic policy for validating every release build surface before crossing ABI.

## Reviewer Handoff

Reviewer should reject any worker plan that extracts retained/display validation first while leaving `HowlRenderPreparedSurfaceInfo.render_surface_emit_status` and retained `PreparedRenderResourcePlanStatus.null_surface` as a double unavailable-status chain. The first accepted slice must mold the ABI while hot, preserve C-only host integration, and prove the new consequence through existing render and host test entrypoints.
