# Hygiene Offenders Research C - 2026-06-02

## Sources Read, In Order

1. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
3. Existing research caches as grep index only, especially resize/render/host caches under `research/`.
4. Current Howl source: `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/terminal/render/retained.zig`, `howl-linux-host/src/display/renderer/render_surface.zig`, `howl-render/src/prepared/render_surface_emitter.zig`, `howl-render/src/prepared/owner.zig`, `howl-render/src/session/text.zig`, `howl-render/include/howl_render.h`, `howl-render/src/ffi/render_surface.zig`, `howl-render/src/ffi/prepared_surface.zig`, `howl-render/src/test/ffi.zig`, `howl-vt/src/ffi.zig`, `howl-pty/src/ffi.zig`.

## Grep Terms Used Against Existing Research Caches

Terms: `offender`, `hygiene`, `over-struct`, `status`, `result enum`, `Result`, `Status`, `FFI`, `ABI`, `render`, `host`, `mirror`, `bundle`, `probe`, `validation`.

Leads produced: prior caches repeatedly named `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/terminal/render/retained.zig`, `howl-linux-host/src/display/renderer/render_surface.zig`, `howl-render/src/prepared/render_surface_emitter.zig`, `howl-render/src/prepared/owner.zig`, and `howl-render/src/test/ffi.zig` as render-surface/resize/ABI accountability paths. These were used only as navigation. Every claim below was re-checked against current source.

## Ranked Offender List

### Rank 1

Path: `howl-linux-host/src/terminal/render/retained.zig:4-3125`

Symbols: `PrepareResult`, `PrepareFailure`, `SubmitResult`, `SubmitFailure`, `PreparedUpload`, `PreparedRenderResourcePlan`, `PreparedRenderResourcePlanStatus`, `RenderResourceStore`, `PreparedRenderSurfaceProbe`, `PreparedRenderSurfaceProbeStatus`, `State`, `validatePreparedRenderSurfaceProbe`, `validateRenderSurfaceResourcePlan`, `validateSoftwareSurface` family.

Breach category: failure taxonomy inflation, mirror validation, responsibility bundling, test/probe vocabulary leakage.

Source evidence: the file declares multiple result/status enums before ownership state (`PrepareFailure` at lines 6-12, `SubmitFailure` at 16-26, `PreparedRenderResourcePlanStatus` at 88-105, `RenderResourceStoreStatus` at 131-141, `PreparedRenderSurfaceProbeStatus` at 563-584). It owns host-facing retained render state at lines 612-919, but also owns a software render resource store at lines 235-444 and independent render-surface probe/plan validation at lines 932-1200 and beyond. `PreparedUpload` combines ABI prepared info, probe diagnostics, resource plan diagnostics, and borrowed surface pointer at lines 66-75.

Why it violates shallow intentional code: this is the largest style breach because one host retained owner file is also a status taxonomy registry, C ABI submit bridge, render-surface validator, resource-store simulator, probe recorder, and diagnostic counter owner. TigerStyle asks for simple return types, minimal abstractions, bounded control flow, assertions, and true nouns. This file uses status enums and diagnostic structs as extra dimensions around almost every operation. It also duplicates validation concepts that the host renderer validates again in `display/renderer/render_surface.zig`.

Smallest true-owner cleanup target: split by existing true nouns, not by convenience. Keep retained prepare/submit/present state in `terminal/render/retained.zig`; move render-surface probe/plan validation to a render-surface contract owner; move software resource-store simulation to a resource lifecycle owner or delete it if host renderer validation is the true owner. The first cleanup target is the `PreparedRenderSurfaceProbe`/`PreparedRenderResourcePlan` cluster at lines 77-129 and 550-610 plus validators at 932+.

Tests/verification likely affected: `howl-linux-host` unit tests through `src/test_root.zig`; any tests that assert resize retained-safety, resource-plan/probe status, or submit failure details.

Risks/stop conditions: do not remove C ABI boundary checks without preserving host safety. Stop if public ABI status values need to change; that is product-level ABI work.

### Rank 2

Path: `howl-linux-host/src/terminal/context.zig:54-958`

Symbols: `Context`, `TurnStep`, `TurnResult`, `ContextSubmitBackend`, `submitPreparedLockedWith`, `SubmitPreparedResult`, `SubmitFailureReason`, `ContextOps`.

Breach category: responsibility bundle, fat host orchestration, failure taxonomy inflation, backend policy in terminal owner.

Source evidence: `Context` fields combine terminal core, wait-thread progress, GL host surface, render resource textures, config, input, event loop, title buffer, geometry, font sizing, focus, scrollbar, links, selection, and cursor blink at lines 80-99. Render-turn orchestration lives at lines 349-374. The submit backend performs resource realization, host texture resize, patch/full policy checks, GL upload dispatch, panic mapping, and submit execution construction at lines 539-719. `SubmitFailureReason` adds a second taxonomy over retained submit failures at lines 760-793.

Why it violates shallow intentional code: the file is a terminal host god-object. It has the main-thread terminal owner, but it also contains backend upload policy and GL-adjacent texture decisions. Howl rules say hosts own backend resource realization, but window chrome/terminal context should not absorb display renderer, C ABI render, PTY, or VT ownership. The nested `ContextSubmitBackend` hides backend policy inside terminal context instead of keeping terminal orchestration shallow.

Smallest true-owner cleanup target: move host render-surface upload decision/policy from `ContextSubmitBackend.uploadRenderSurfaceCommands` and `renderSurfaceUploadPolicy` at lines 572-628 toward `display/renderer/render_surface.zig`, leaving `Context` to orchestrate prepare/upload/submit/present only.

Tests/verification likely affected: host terminal context tests, resize submit-boundary tests, present-pending tests, display renderer upload tests.

Risks/stop conditions: stop if extraction would require importing internal `howl-render` Zig modules into host tests or bypassing C ABI. Preserve main-thread control flow centralization.

### Rank 3

Path: `howl-linux-host/src/display/renderer/render_surface.zig:35-2587`

Symbols: `RenderResourceTextures`, `FailureBucket`, `GlStateSample`, `TrustedTextureFailureAction`, `RenderSurfaceSummary`, `validateSurfaceTransition`, `commandShapeErrorStatic`, test surface helpers.

Breach category: render/host sprawl, validation/execution/test vocabulary in one file, status buckets.

Source evidence: `RenderResourceTextures` stores live GL texture slots and failure diagnostics at lines 35-75. The same owner validates spans, commands, order, creates, uploads, retires at lines 101-234; mutates GL textures at lines 314-388; maps failures to policy at lines 491-517; and defines many test builders directly in production file at lines 820-903 with tests from 905 onward.

Why it violates shallow intentional code: this file has a true owner, host-side render resource textures, but mixes runtime GL mutation, contract validation, failure policy, summarization, and test fixture vocabulary. The validation mirror overlaps `terminal/render/retained.zig` resource/probe validation, increasing the number of places that must agree about the same ABI consequences.

Smallest true-owner cleanup target: keep GL texture lifecycle and upload execution in `RenderResourceTextures`; move pure render-surface command/span validation into a shared host render-surface contract owner or delete duplicated validation once one owner is accepted.

Tests/verification likely affected: display renderer tests embedded in this file, host render-surface upload tests, resize upload failure tests.

Risks/stop conditions: do not weaken host defense against malformed or stale C ABI surfaces. Stop if validation must be public ABI rather than host-local policy.

### Rank 4

Path: `howl-render/src/prepared/render_surface_emitter.zig:36-2581`

Symbols: `Error`, `Limits`, `SpriteResourceStore`, `Fixture`, `Emitter`, `emitPrepared`, `appendPreparedSprites`, atlas/resource helpers, owner-local tests.

Breach category: over-structuring, hot-path complexity, fixture/test leakage, resource lifecycle plus surface emission in one file.

Source evidence: the file defines a wide error set at lines 36-46, a comptime `Limits` bucket at 48-68, `SpriteResourceStore` with persistent resource bytes and atlas state at 100-307, a public `Fixture` at 309-324, and a generic `Emitter(comptime limits: Limits)` owning arrays, counts, surface storage, fixture emission, prepared emission, resource creation/upload/retire, clipping, merge, sprite staging, glyph batching, and publishing at lines 326-920. Tests and helpers continue through line 2581.

Why it violates shallow intentional code: the render-surface emitter is doing too much: resource cache, glyph atlas packing, surface command emission, fixture emission, and ABI storage publication. The `Fixture` and `Limits` shapes are broad option/bucket structs. The generic emitter adds dimensionality where a concrete product limit may be enough. Hot-path `appendPreparedSprites` is long and branchy at lines 594-686.

Smallest true-owner cleanup target: first isolate `SpriteResourceStore`/atlas allocation from command emission, or remove `Fixture` from production vocabulary if it only exists for tests. Do not invent a manager; split by nouns already present: sprite resource store, atlas allocator, surface emitter.

Tests/verification likely affected: `howl-render/src/test.zig`, render surface emitter tests, prepared owner tests, FFI render-surface borrowed surface tests.

Risks/stop conditions: stop if extraction changes C ABI surface layout or resource lifetime semantics. Preserve compile-time bounds and assertions.

### Rank 5

Path: `howl-render/include/howl_render.h:19-622` and mirrors `howl-render/src/ffi/render_surface.zig:9-347`

Symbols: `HowlRenderSurface*` limits and structs, `HowlRenderSurfaceEmitStatus`, `HowlRenderSurface`, `HowlRenderPreparedSurfaceInfo`, mirror extern structs and layout assertions.

Breach category: fat ABI shape, mirror structs, boundary thickness.

Source evidence: render ABI defines many fixed maxima at lines 19-31, several status enums at 46-93, draw/span structures at 117-177, render-surface token/resource/upload/create/glyph/command/retire/ack structures at 184-314, and prepared info with embedded `render_surface_emit_status` at lines 481-495. The Zig FFI mirror re-declares the same ABI structs at `src/ffi/render_surface.zig:9-139` and checks every offset at lines 141-347.

Why it violates shallow intentional code: the C ABI is the product, so this is not automatically wrong. The breach is thickness: the ABI exposes a mini render command protocol, resource lifecycle protocol, status enums, and mirrored layout assertions. It increases every host/render cleanup cost and forces status taxonomy inflation in host code.

Smallest true-owner cleanup target: do not shrink ABI opportunistically. First identify unused or duplicated ABI fields (`resource_epoch`, host acks, status granularity) and record product-level justification before any ABI cut. The immediate cleanup is not changing ABI, but reducing internal mirrors/diagnostic layers around it.

Tests/verification likely affected: ABI layout tests, render FFI tests, host render-surface tests.

Risks/stop conditions: public C ABI changes require explicit user/product approval. Preserve C-only host boundary.

### Rank 6

Path: `howl-render/src/prepared/owner.zig:17-836`

Symbols: `PreparedInfo`, `PreparedBuffer`, `Owner.State`, `SubmitResult`, `Owner`, `ownerBase`, `renderSurfaceEmitStatus`, test helpers.

Breach category: prepared lifecycle plus diagnostics plus render-surface payload bundling; test vocabulary leakage.

Source evidence: `PreparedInfo` exports token, geometry, emit status, and damage at lines 17-27. `Owner` owns session pointer, prepared surface, optional render-surface payload, lifecycle state, token fields, geometry fields, upload count, and emit status at lines 33-51. `create` consumes a prepared surface and immediately emits render-surface payload while converting errors to ABI emit statuses at lines 58-71. Tests and local fixture helpers occupy lines 306-836.

Why it violates shallow intentional code: `Owner` is a real noun, but it stores a flattened copy of facts already inside `PreparedSurface` and adds render-surface emission diagnostics. This risks cache invalidation: duplicated token/geometry/damage values must stay aligned with `prepared`. It also makes prepared lifecycle creation responsible for render-surface emission.

Smallest true-owner cleanup target: keep lifecycle/handle ownership in `Owner`; push render-surface payload emission status ownership to emitter or ABI prepared-surface describe boundary; reduce duplicated cached fields if `PreparedSurface` remains alive.

Tests/verification likely affected: prepared owner tests and render FFI prepared handle tests.

Risks/stop conditions: stop if removing cached fields changes ABI describe semantics or prepared handle lifetime.

### Rank 7

Path: `howl-render/src/session/text.zig:65-607`

Symbols: `TextSession`, nested `TextContext`, `TextSessionOwner`, `PrepareInput`, `SubmitExecution`, font config ownership, source/geometry/prepare/submitted ownership.

Breach category: ownership bundling, context bucket, font/render/source/submission combined owner.

Source evidence: `TextSession` owns allocator, font/text state, mutex, preparer, and scratch at lines 65-71. Nested `TextContext` bundles session/config at lines 72-75 and is passed through provider thunks. `TextSessionOwner` owns allocator, session, geometry, source slot, prepare requests, submitted state, font paths, prepared handles, sprite resources, config, cursor blink, and failure counts at lines 309-326. It manages font configuration at lines 359-396, render source publication at 510-535, prepare/submit state at 537-579, and work-state aggregation at 581-588.

Why it violates shallow intentional code: `TextSessionOwner` is a bucket around several true owners. Some subowners are already named (`geometry`, `source_slot`, `prepare_requests`, `submitted`), but the owner still centralizes font config, source commit, prepared handle registry, and render resource store. `TextContext` is a generic context bucket.

Smallest true-owner cleanup target: separate prepared handle registry/resource store from font config mutation, or reduce `TextContext` by passing exact owner pointers/values to provider functions.

Tests/verification likely affected: render session tests, font config tests, prepared/source/submitted tests.

Risks/stop conditions: provider callback shape may require a context pointer; if so, document it as external callback pressure rather than inventing more buckets.

### Rank 8

Path: `howl-render/src/test/ffi.zig:1-833`

Symbols: render FFI test root, `PreparedOptions`, `preparedSurface`, repeated handle/session builders.

Breach category: test/probe vocabulary leakage, oversized side test root, fixture buckets.

Source evidence: the test file imports product internals and FFI modules at lines 6-21, tests many distinct FFI concerns from missing handles through render-surface borrowing at lines 35-538, then defines broad helper/factory functions at lines 540-736 and a `PreparedOptions` bucket at lines 769-819.

Why it violates shallow intentional code: tests are important, but this file combines ABI smoke, lifecycle, invalid token validation, surface borrowing, direct submit, handle submit, cross-session behavior, and render oracle verification. The helper bucket repeats the same fixture shape seen in `prepared/owner.zig`, leaking broad test vocabulary across files.

Smallest true-owner cleanup target: keep this as the curated render FFI test entrypoint if project test law requires it, but move owner-local test cases back to owner files where possible and reuse one narrow prepared-surface fixture owner.

Tests/verification likely affected: `howl-render` test root only.

Risks/stop conditions: do not add duplicate test roots. Preserve the single curated module test entrypoint.

### Rank 9

Path: `howl-vt/src/ffi.zig:24-1123`

Symbols: `HowlVtCallStatus`, `Ffi*` extern structs, `terminalCopySurface`, input encoding FFI functions, tests.

Breach category: fat FFI translator, ABI result structs, protocol/state/test vocabulary mixed.

Source evidence: FFI declares many extern result/surface/color/cell/selection structs at lines 24-228. It then translates colors/cells/selection/surface/runtime/input at lines 230-449, owns terminal lifecycle and feed/copy/selection/runtime/input encode calls at lines 464-769, and includes ABI tests through line 1123. `terminalCopySurface` has a large multi-output ABI seam at lines 534-582.

Why it violates shallow intentional code: the file is a boundary translator, so some breadth is expected. The moderate breach is that all VT FFI translations, surface copy validation, input encoding, selection, runtime obligation, and tests sit in one file. Several `Ffi*Result` structs add status/result dimensions.

Smallest true-owner cleanup target: keep public C ABI functions here, but move pure translation helpers by true noun if the file grows further: surface cell/color projection, input encoding, selection copy. Do not create a generic FFI manager.

Tests/verification likely affected: `howl-vt` ABI tests.

Risks/stop conditions: ABI structs and status codes are shipped boundary; changing them requires product approval.

### Rank 10

Path: `howl-pty/src/ffi.zig:7-253`

Symbols: `HowlPtyCallStatus`, `FfiSnapshot`, `FfiOutboundPump`, `FfiReadResult`, `FfiTransportPumpLimits`, `session*` exports.

Breach category: ABI result structs, boundary thickness.

Source evidence: PTY FFI declares status enum and several result structs at lines 7-48, converts launch config and status at lines 77-141, and exports session lifecycle/control/read/pump functions at lines 143-253.

Why it violates shallow intentional code: this is moderate, not severe. It is small and mostly translation-only. The status/result struct pattern is still a style pressure point because it mirrors the wider failure taxonomy habit, but the file is comparatively shallow.

Smallest true-owner cleanup target: preserve as C ABI translator. Avoid adding more result structs unless the ABI forces them; keep new PTY behavior in `session`/`pty` owners.

Tests/verification likely affected: PTY ABI and session tests.

Risks/stop conditions: C ABI compatibility.

## Cross-Cutting Patterns

Failure taxonomy inflation: Render and host layers have stacked statuses: ABI statuses in `howl_render.h`, emitter errors/status, retained prepare/submit failures, retained probe/resource plan statuses, host texture failure buckets, and local submit failure reasons. This increases call-site dimensionality and makes simple failure paths hard to audit.

Boundary thickness: The render C ABI exposes a full render-surface protocol, not just a thin call seam. That may be product-required, but internal code has grown multiple layers around it instead of one accountable translation/validation path.

Mirror structs: `howl-render/src/ffi/render_surface.zig` mirrors the header layout field-by-field. This is acceptable as ABI proof, but it highlights how much layout is being exposed and re-modeled. Host retained/resource validators also mirror render-surface rules.

Ownership bundling: `Context`, `TextSessionOwner`, `RenderResourceTextures`, and `terminal/render/retained.State` are all real owners that have accreted adjacent responsibilities. The largest breaches are not vague subsystems; they are concrete files where multiple true nouns live together.

Hot-path complexity: `render_surface_emitter.appendPreparedSprites`, host `ContextSubmitBackend.uploadRenderSurfaceCommands`, and retained render-surface validators combine branching, bounds, resource state, and policy in single paths.

Test/probe vocabulary leakage: `Fixture`, `PreparedOptions`, `Probe`, `Plan`, `FailureBucket`, and broad helper factories appear in production or oversized test files. Tests sometimes create new vocabulary instead of exercising the smallest true owner.

## Explicit Non-Findings

`howl-render/src/ffi.zig`: acceptable. It is only a three-line `@cImport` root and does not own behavior.

`howl-pty/src/ffi.zig`: moderate only. It is a compact translator with clear status conversion and does not currently combine PTY protocol execution with validation/test fixtures.

`howl-vt/src/ffi.zig`: not a top offender despite size because FFI boundary breadth is partly forced by C ABI. Its issue is growth risk and mixed translators, not obvious wrong ownership yet.

`howl-render/src/ffi/prepared_surface.zig`: acceptable to moderate. It is thin and translates prepared handle operations only. Its evidence points more strongly to `prepared/owner.zig` and the ABI shape than to this translator itself.

## Proof Gaps

I did not read every Zig file in `howl-render/src/text/**`, `howl-vt/src/parser/**`, or `howl-linux-host/src/display/**`; additional moderate offenders may exist outside the render-surface/host/ABI path.

I did not compare against Alacritty/Ghostty source in this pass because the prompt prioritized comprehensive current-source offender discovery and the strongest offenders were already source-provable.

I did not run tests or builds; this is research-only.

I did not inspect git status or modify product code, scratchpads, `current.txt`, or git.
