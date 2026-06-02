# Hygiene Offenders Research Cache - 2026-06-02

Researcher A. Research only. No product code, scratchpad, `current.txt`, or git edits.

## Sources Read, In Order

1. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
3. Existing `research/*.md` caches via grep only, as navigation index.
4. Current Howl source: `howl-render/src/prepared/render_surface_emitter.zig`
5. Current Howl source: `howl-linux-host/src/display/renderer/render_surface.zig`
6. Current Howl source: `howl-linux-host/src/terminal/context.zig`
7. Current Howl source: `howl-linux-host/src/terminal/render/retained.zig`
8. Current Howl source: `howl-render/src/session/text.zig`
9. Current Howl source: `howl-render/src/ffi.zig`
10. Current ABI headers: `howl-render/include/howl_render.h`, `howl-vt/include/howl_vt.h`, `howl-pty/include/howl_pty.h`
11. Current source scans in `howl-vt/src`, `howl-pty/src`
12. Current Howl source: `howl-vt/src/ffi.zig`, `howl-vt/src/howl_vt.zig`, `howl-vt/src/terminal.zig`
13. Current Howl source: `howl-pty/src/ffi.zig`
14. Current Howl source: `howl-linux-host/src/display/display.zig`

## Existing Research Grep Index

Terms used:

- `(status|result|enum|FFI|ABI|render|host|protocol|validation|execution|probe|manager|engine|controller|types|diagnostic|Context|State|Options|Config|Info|Data|Result)` against `research/*.md`.

Leads produced:

- Render-surface and resize research repeatedly pointed to `howl-render/src/source/prepare_request.zig`, `howl-render/src/session/text.zig`, `howl-render/src/prepared/render_surface_emitter.zig`, `howl-linux-host/src/terminal/render/retained.zig`, `howl-linux-host/src/display/renderer/render_surface.zig`, and `howl-linux-host/src/terminal/context.zig`.
- Prior caches flagged C ABI/render-surface boundary pressure, host texture lifecycle, retained safety, present ack, fake diagnostics, and no `manager/controller/engine` owners.
- Prior caches mention not adding diagnostics-only logging and not bypassing the C ABI, which guided review of ABI/FFI wrappers.
- These leads were used only as navigation. Every finding below was re-verified against current source in this session.

## Ranked Offender List

### Rank 1 - Render Surface ABI Is A Fat Mixed Contract

Path: `howl-render/include/howl_render.h`

Line range: 17-65, 81-93, 184-314, 316-366, 451-507, 515-617

Symbols:

- `HOWL_RENDER_SURFACE_*` constants, `HowlRenderSurfaceEmitStatus`, `HowlRenderSubmitDecisionStatus`, `HowlRenderSurface`, `HowlRenderPreparedSurfaceInfo`, `HowlRenderSubmitExecution`, `HowlRenderSubmitResult`, `howl_render_text_session_*`, `howl_render_prepared_surface_*`.

Breach category: ABI thickness, protocol/state/execution/resource bundling, failure taxonomy inflation, mirror structs.

Source evidence:

- Lines 17-31 define many surface limits in one header: in-flight counts, damage, uploads, commands, glyphs, bytes, atlas pages, resources, creates, retires, host acks.
- Lines 53-65 define ten render-surface emit statuses.
- Lines 81-87 define a separate submit-decision status enum from submit status at lines 73-79.
- Lines 184-314 define token, rect, damage, resource id, upload, create, glyph, command, retire, spans, acks, and full `HowlRenderSurface` in one ABI zone.
- Lines 316-366 define geometry, work state, prepare request, prepared token, and VT surface publish result in the same header.
- Lines 481-507 define prepared info, submit execution, and submit result, including `render_surface_emit_status` inside prepared surface info.
- Lines 515-617 expose session init/config/font/layout/VT slot/prepare/publish/submit/work-state/prepared-surface APIs in one contract.

Why it violates shallow intentional code:

- TigerStyle pushes minimum excellent abstractions, simple signatures, direct nouns, and reduced return-type dimensionality. This header creates one broad product seam that mixes render geometry, VT publication, retained tokens, resource lifecycle, host surface realization, status reporting, and prepared handle lifetime.
- Howl law says hosts embed C ABI contracts, but the ABI must still be accountable. This one is C-shaped but not shallow: a host must understand cross-coupled statuses, spans, resource sequencing, and retained state to call it safely.
- `HowlRenderPreparedSurfaceInfo` carries both prepared-surface facts and render-surface emit failure vocabulary, creating a status mirror that crosses owner boundaries.

Smallest true-owner cleanup target:

- Split contract ownership conceptually first: render geometry/session calls, VT surface publication calls, prepared-handle lifecycle calls, and render-surface resource stream contract. Do not invent convenience Zig APIs; the target is thinner C ABI owner zones and fewer cross-owner status fields.

Tests/verification likely affected:

- `howl-render/src/test/ffi.zig`, `howl-render/src/test.zig`, host tests using `howl_render_c`, and any compile gates that translate `howl_render.h`.

Risks/stop conditions:

- Stop if cleanup would remove necessary C ABI facts without a replacement C contract.
- Stop if host code starts importing internal Zig render modules to avoid C ABI thickness.

### Rank 2 - Host Retained Render File Combines State Machine, Resource Store, Probe, Validation, FFI Translation, And Tests

Path: `howl-linux-host/src/terminal/render/retained.zig`

Line range: 4-156, 158-444, 550-919, 932-1563, 1565-3125

Symbols:

- `PrepareResult`, `PrepareFailure`, `SubmitResult`, `SubmitFailure`, `WorkState`, `PreparedUpload`, `PreparedRenderResourcePlan`, `PreparedRenderSurfaceProbe`, `RenderResourceStore`, `State`, `validatePreparedRenderSurfaceProbe`, `validateRenderSurfaceResourcePlan`, `validateSoftwareSurface`, tests.

Breach category: failure taxonomy inflation, ownership bundling, duplicate validation, test/probe vocabulary leakage, status/result enum sprawl.

Source evidence:

- Lines 4-26 define four result/failure enums for prepare and submit before the owner state appears.
- Lines 66-105 define `PreparedUpload`, `PreparedRenderResourcePlan`, and a 16-case `PreparedRenderResourcePlanStatus`.
- Lines 131-156 define another 10-case store status and action classifier.
- Lines 158-228 define texture operation recorder/state/store vocabulary inside retained state.
- Lines 235-444 implement a render resource store with create/upload/retire, validation, command validation, and glyph validation.
- Lines 550-584 define another probe struct/status with 19 statuses.
- Lines 612-628 put layout, geometry epoch, text session handle, prepared handle, present token, last failures, probe counters, and resource-plan counters into one `State`.
- Lines 720-918 implement C ABI prepare/submit handle orchestration, retained present state, render-surface probing, resource planning, and prepared handle ownership.
- Lines 932-1563 duplicate render-surface validation and resource-plan validation functions with similar but not identical status enums.
- Lines 1565 onward embed extensive test fixtures and tests in the same file.

Why it violates shallow intentional code:

- The file combines owner state mutation with protocol validation, resource-store simulation, C ABI translation, diagnostic counters, and test harness vocabulary.
- TigerStyle warns against complex return types and viral dimensionality; this file has status enums for prepare, submit, probe, plan, store, and action mapping.
- `State` is a responsibility bundle: retained submit state, geometry state, C handles, present state, probe telemetry, and resource-plan telemetry are not one small domain noun.
- Validation is duplicated against `display/renderer/render_surface.zig`, creating two places where render-surface command/resource truths can drift.

Smallest true-owner cleanup target:

- Separate retained submit/present state from render-surface resource validation/probe/store. The first target should be an owner for render-surface resource validation/probe semantics, leaving `State` with retained prepare/submit/present only.

Tests/verification likely affected:

- `howl-linux-host/src/test_root.zig` host unit tests, terminal context tests using retained fake seams, render retained owner-local tests.

Risks/stop conditions:

- Stop if extraction changes the C ABI boundary or allows host tests to import internal `howl-render` Zig modules.
- Stop if probe/status cleanup removes an assertion that currently guards trusted render surface invariants.

### Rank 3 - GL Render Surface Host File Mixes Resource Realization, Validation, Shape Classification, Upload Policy, Diagnostics, And Tests

Path: `howl-linux-host/src/display/renderer/render_surface.zig`

Line range: 5-75, 81-489, 491-742, 744-818, 820-1914, 1916-2225, 2226-2587

Symbols:

- `RenderResourceTextures`, `FailureBucket`, `GlStateSample`, `RenderSurfaceSummary`, `TrustedTextureFailureAction`, `validateSurfaceTransition`, `CommandShapeError`, `renderSurfaceFillOnly`, `renderSurfaceSprite`, `uploadRenderSurfaceCommands`, tests.

Breach category: host/render sprawl, duplicate validation, hot-path complexity, failure taxonomy inflation, diagnostics/probe vocabulary leakage.

Source evidence:

- Lines 5-11 declare raw GL externs directly in the render-surface host owner.
- Lines 35-75 define GL texture resource state, last failure buckets, and GL sample diagnostic shape.
- Lines 81-156 perform validate, create textures, sample GL state, upload, invalidate, rollback, retire, and sample again in one flow.
- Lines 164-233 validate full surface transition using spans, commands, ordering, creates, uploads, retires, and returns a staged copy.
- Lines 491-517 define surface summary and trusted failure action mapping.
- Lines 564-580 define `CommandShapeError`, a detailed error taxonomy separate from retained probe statuses.
- Lines 744-818 define churn, created/retired count, persistent resource use, future-upload detection, command resource scans, and GL state sampling.
- Lines 820-1914 are mostly test helpers and tests in the same product file.
- Lines 1916-2120 create host texture, upload fill/sprite/glyph surface classes, allocate framebuffer, manage viewport/blend state, and draw commands.
- Lines 2122 onward classify render surface shapes as fill-only, patch, sprite, glyph, etc.

Why it violates shallow intentional code:

- This file is simultaneously a GL backend, render-surface contract validator, shape classifier, host texture lifecycle owner, diagnostic bucket owner, and test root fragment.
- TigerStyle favors pushing `if`s up and `for`s down with clear owners. Here validation/control policy and GL data-plane upload are tightly interleaved.
- The same render-surface command/resource truth is revalidated here and in retained state, under different enum names.
- Tests and fake helpers consume a large portion of the file, making product owner boundaries hard to see.

Smallest true-owner cleanup target:

- Extract render-surface shape/resource validation away from GL upload. Keep GL texture realization as the host backend owner. Validation target should match the single render-surface contract owner used by retained state.

Tests/verification likely affected:

- Host unit tests for render surface texture validation/upload shape, terminal context submit/upload tests, `zig build test:unit --summary all` under `howl-linux-host`.

Risks/stop conditions:

- Stop if extraction creates a renderer manager/controller abstraction.
- Stop if GL-specific ownership moves into window chrome or terminal context.

### Rank 4 - Terminal Context Is A Broad Host Orchestrator With Embedded Render Upload Policy And ABI Error Translation

Path: `howl-linux-host/src/terminal/context.zig`

Line range: 39-108, 110-181, 349-386, 464-821, 828-958, 960-1109, 1111-1142, 1144 onward

Symbols:

- `Context`, `TurnStep`, `TurnResult`, `InitialRequest`, `ContextSubmitBackend`, `RenderSurfaceUploadPolicyError`, `RenderSurfaceEmitError`, `SubmitPreparedResult`, `SubmitFailureReason`, `ContextOps`, tests.

Breach category: ownership bundling, ABI translation leakage, failure taxonomy inflation, host/render sprawl, context bucket pressure.

Source evidence:

- Lines 39-52 define init buckets `RenderInit` and `VtInitOptions`.
- Lines 54-99 define `Context` with terminal term, wait thread state, liveness, host texture, render-surface textures, config, input, event loop, title buffer, geometry, font size, focus flags, scrollbar, links, selection, cursor blink.
- Lines 349-374 implement render turn orchestration, source publication, prepare/submit drive, and turn result construction.
- Lines 539-719 define `ContextSubmitBackend`, which performs render-surface resource realization, host texture ensure, upload dispatch by render-surface shape, upload policy checks, panic policy, emit-status mapping, and submit execution construction.
- Lines 615-704 define upload policy error and emit error taxonomies inside terminal context.
- Lines 721-758 unlocks terminal mutex, uploads through backend, relocks, checks handle stability, submits retained render.
- Lines 760-793 define `SubmitPreparedResult` and 12-case `SubmitFailureReason` as another mirror over retained submit failures.
- Lines 898-958 define `ContextOps` adapter with cursor blink, terminal bytes/key/mouse, scrollbar, link and selection handling.

Why it violates shallow intentional code:

- Context is expected to orchestrate host runtime, but it has absorbed render-surface upload policy and ABI status translation that should belong to render-retained or display renderer owners.
- TigerStyle warns that broad context/state structs and complex result types increase dimensionality. This file has `Context`, `TurnResult`, `DriveResult`, `SubmitPreparedResult`, `SubmitFailureReason`, upload-policy errors, and emit errors.
- The render-surface shape policy is duplicated with display renderer shape classifiers and retained status actions.

Smallest true-owner cleanup target:

- Move render-surface upload policy/status translation out of terminal context toward display render-surface owner or retained render owner. Keep `Context` as orchestration glue: lock, prepare, call backend, submit, present ack.

Tests/verification likely affected:

- Terminal context owner-local tests, host test root, resize/present ack tests, render submit tests.

Risks/stop conditions:

- Stop if cleanup turns into an umbrella runtime layer.
- Stop if `Context` stops centralizing host turn control flow.

### Rank 5 - Render Prepared Surface Emitter Combines Resource Cache, Atlas Packing, Surface Emission, Fixture/Test Helpers, And Tests

Path: `howl-render/src/prepared/render_surface_emitter.zig`

Line range: 18-68, 70-307, 309-920, 923-1116, 1118-2600

Symbols:

- `Error`, `Limits`, `SpriteResourceStore`, `AtlasResult`, `Emitter`, `Fixture`, `appendPreparedSprites`, `stagePreparedUploadBytes`, `publishSurface`, tests.

Breach category: owner bundling, hot-path complexity, resource lifecycle mixed with surface command emission, test vocabulary leakage.

Source evidence:

- Lines 18-34 define persistent sprite, atlas, glyph refs, and compile-time limit relationships.
- Lines 36-46 define a multi-case emitter error taxonomy.
- Lines 100-307 implement `SpriteResourceStore`, persistent resource cache, byte store, atlas state, atlas packing, resource allocation, hash matching, and test fill.
- Lines 309-324 define `Fixture` for tests in the product file before the emitter itself.
- Lines 326-920 define generic `Emitter` with arrays for damage/creates/uploads/commands/glyphs/retires/upload bytes, fixture emission, prepared emission, fill merging, sprite lookup, atlas upload, resource create/upload/retire, glyph run packing, and surface publication.
- Lines 923-1116 provide ABI conversion helpers, sprite lookup, hashing, stride, bounds, byte copy.
- Lines 1118 onward include test helpers and many tests in the same file.

Why it violates shallow intentional code:

- The true owner of atlas/resource lifetime is not the same as the true owner of command emission. Keeping both in one `Emitter` file forces one function zone to reason about cache identity, atlas packing, byte slicing, C spans, surface commands, and tests.
- TigerStyle's hot-loop guidance favors narrow data-plane functions with primitive arguments. `appendPreparedSprites` branches across lookup, bounds, byte staging, atlas-vs-sprite, resource cache, upload, command, and retire.
- Test fixture vocabulary is interleaved with product emission logic.

Smallest true-owner cleanup target:

- Extract sprite resource/atlas ownership from surface command emission. Keep emitter focused on turning prepared text draws into bounded C surface spans.

Tests/verification likely affected:

- `howl-render/src/test.zig`, render-surface emitter owner-local tests, FFI tests that describe prepared render surface.

Risks/stop conditions:

- Stop if extraction weakens bounds assertions on counts or upload bytes.
- Stop if it creates a generic resource manager instead of a sprite/atlas owner.

### Rank 6 - Render Text Session Owner Is A Session Mega-Owner

Path: `howl-render/src/session/text.zig`

Line range: 59-87, 89-307, 309-607, 609-846

Symbols:

- `TextSession`, `TextContext`, `TextSessionOwner`, `PrepareInput`, `SubmitExecution`, `FontConfigError`, `prepareHandle`, `syncGeometry`, `commitVtSurface`, `prepare`, `submit`, `workState`, tests.

Breach category: ownership bundling, context bucket, dynamic allocation pressure, status/result vocabulary, test leakage.

Source evidence:

- Lines 65-87 define `TextSession` with allocator, font/text state, mutex, text preparer, scratch, nested `TextContext`, damage/submit/prepare structs.
- Lines 136-162 prepare and submit surfaces, including scratch allocation, text input conversion, font session, frame preparation, prepared surface ownership, and atlas mark-rendered.
- Lines 171-307 define helpers for owning prepared surfaces, preparer capacity, scratch allocation, provider thunks, glyph rasterization, and font session construction.
- Lines 309-325 define `TextSessionOwner` with allocator, session, geometry, source slot, prepare requests, submitted state, dirty epoch, cursor blink, config, prepared handles, font paths, fallback paths, sprite resource store, and failure count.
- Lines 365-396 manage font path ownership and fallback arrays.
- Lines 402-439 prepare handles and debug-print failures.
- Lines 487-519 sync geometry, reserve VT source capacity, refresh retained slot views, commit VT surface, and accept source.
- Lines 537-579 prepare/publish/submit/accept submitted retained state.

Why it violates shallow intentional code:

- `TextSessionOwner` is a broad lifecycle bucket with font config, geometry, VT source slot, retained prepare/submit, prepared handles, sprite resources, and debug counters.
- `TextContext` is a generic context bucket passed through provider thunks instead of narrow owner-specific data.
- Runtime allocation (`allocator.alloc`, `std.ArrayList`, `dupeZ`) is present in operational paths. Howl may not be TigerBeetle-static, but TigerStyle still pressures bounded upfront state and explicit limits.
- Debug print at lines 428-438 is diagnostics leakage in product owner code.

Smallest true-owner cleanup target:

- Separate font configuration/lifetime from retained source/prepare/submit ownership, then isolate provider context from session lifecycle. Keep the C ABI session owner but reduce the fields and responsibilities it owns directly.

Tests/verification likely affected:

- Render session tests, FFI text session tests, font path tests, retained submit tests.

Risks/stop conditions:

- Stop if cleanup changes public C ABI handles or adds host-facing Zig convenience APIs.
- Stop if font fallback ownership is moved to a vague config bucket.

### Rank 7 - VT FFI Mirrors Terminal Surface And Result Shapes Too Broadly

Path: `howl-vt/src/ffi.zig` and `howl-vt/include/howl_vt.h`

Line range: `ffi.zig` 24-228, 261-449, 464-769; `howl_vt.h` 21-28, 82-229, 231-262, 264-399

Symbols:

- `HowlVtCallStatus`, `FfiSurfaceCell`, `FfiBytesResult`, `FfiFeedResult`, `FfiRuntimeObligationResult`, `FfiSurface`, `FfiSurfaceResult`, `terminalCopySurface`, `HowlVtSurfaceCell`, `HowlVtSurfaceResult`, `HowlVtBytesResult`.

Breach category: mirror structs, ABI/FFI thickness, result struct proliferation, protocol/state surface leakage.

Source evidence:

- `ffi.zig` lines 24-31 define call statuses; lines 33-88 mirror color, RGB, cell flags, cell attrs, and full surface cell layout.
- `ffi.zig` lines 90-121 define four result/obligation result structs.
- `ffi.zig` lines 177-228 define `FfiSurface`, `FfiVisibleMeta`, `FfiVisibleMetaResult`, and `FfiSurfaceResult`.
- `ffi.zig` lines 374-413 builds a full surface result with cells, dirty rows, cursor, colors, selection, metadata.
- `ffi.zig` lines 534-581 validates buffers and copies visible cells, selection ranges, dirty rows in one FFI function.
- `howl_vt.h` lines 82-229 mirror the same surface/cell/meta/result shapes in C.
- `howl_vt.h` lines 231-262 define bytes/feed/runtime result structs.
- `howl_vt.h` lines 264-399 expose many copy/encode/query calls with repeated result patterns.

Why it violates shallow intentional code:

- FFI should translate contracts only. This FFI file owns copying policy, surface projection, selection projection application, result construction, input encoding, runtime obligation translation, and tests.
- The ABI exposes many result structs with `status` plus payload, spreading failure dimensionality.
- Surface cell mirror duplicates render-source cell vocabulary in `howl_render.h`, creating cross-ABI mirror pressure.

Smallest true-owner cleanup target:

- Narrow FFI translation to direct terminal owner calls and one result pattern per copy/query family. Keep surface projection semantics in VT surface/publication owner, not FFI.

Tests/verification likely affected:

- `howl-vt/src/ffi.zig` tests, ABI tests, host VT surface integration.

Risks/stop conditions:

- Stop if C ABI compatibility requirements require keeping existing structs for persisted/external consumers. This is private/young, but ask before deleting shipped ABI names.

### Rank 8 - Host Display State Mixes Presentation, Tab Cache, GL Context, Proof Capture, Diagnostics, And Tests

Path: `howl-linux-host/src/display/display.zig`

Line range: 8-64, 66-158, 165-257, 275-357, 360-624, 626-732

Symbols:

- `C`, `State`, `PresentProofStats`, `PresentProofSnapshot`, `PresentDiagnostics`, `GenericState`, `displaySubmitPresent`, `capturePresentProof`, `observeTexture`, tests.

Breach category: host/display sprawl, diagnostics/probe vocabulary leakage, ownership bundling, test fake leakage.

Source evidence:

- Lines 8-64 create a `C` wrapper exporting SDL and GL constants/functions.
- Lines 70-113 define present proof and diagnostics structs with many fields.
- Lines 126-158 define generic display state with window/context, tab texture cache, proof capture fields, present tokens, and diagnostics.
- Lines 203-257 submit present: token state, readiness recording, framebuffer size, tab cache update, clear/draw terminal/scrollbar, proof capture, swap, diagnostics logging, completion token.
- Lines 275-357 own readiness and diagnostic logging policy.
- Lines 465-624 own proof capture, clipping, texture/framebuffer observation, RGBA allocation, pixel comparison, and tab bar hashing.
- Lines 626-732 define fake C and tests in same file.

Why it violates shallow intentional code:

- Display present owner has absorbed tab cache realization, present proof probes, readiness diagnostics, GL observation, and tests.
- TigerStyle asks code to run at its own pace and separate control/data plane. This present path has diagnostic/probe allocation and framebuffer reads mixed into the presentation owner, guarded by `builtin.is_test` but still in product file.
- `PresentDiagnostics` and `PresentProof*` are probe vocabulary, not display state needed for normal operation.

Smallest true-owner cleanup target:

- Extract present proof/test observation from display presentation state. Keep production display owner focused on GL context, bounded present token, and drawing/swap.

Tests/verification likely affected:

- Host display tests, present proof tests, integration tests that request proof capture.

Risks/stop conditions:

- Stop if extraction hides main-thread/context readiness assertions.
- Stop if tab cache ownership is moved to chrome or generic renderer manager without Alacritty-backed shape.

### Rank 9 - Render/Host Surface Validation Is Duplicated Across Three Zones

Path: multiple concrete zones

Line ranges:

- `howl-linux-host/src/terminal/render/retained.zig` 932-1563
- `howl-linux-host/src/display/renderer/render_surface.zig` 164-233, 523-742, 2122-2225
- `howl-render/src/prepared/render_surface_emitter.zig` 423-920, 1024-1116

Symbols:

- `validatePreparedRenderSurfaceProbe`, `validateRenderSurfaceResourcePlan`, `validateSoftwareSurface`, `validateSurfaceTransition`, `commandShapeErrorStatic`, `renderSurfaceFillOnly`, `renderSurfaceSprite`, `appendPreparedSprites`.

Breach category: duplicate validation, cache invalidation risk, boundary thickness, source-of-truth split.

Source evidence:

- Retained validates surface version, dimensions, spans, upload byte max, resource lifecycle, command shapes, glyph refs, visible uploads, and destination overlap.
- Display renderer validates surface version, spans, order, creates/uploads/retires, command shape, upload bounds, resource formats, future upload visibility, and surface shape classes.
- Emitter also enforces command/upload/resource bounds while constructing the surface.

Why it violates shallow intentional code:

- TigerStyle warns against duplicated variables/aliases because state gets out of sync. Here the duplicate is semantic: three zones encode what a valid render surface means.
- The C ABI boundary requires validation, but not three independent status vocabularies and shape checks.

Smallest true-owner cleanup target:

- Establish one render-surface contract validator owner shared by retained and display renderer. Keep emitter construction assertions local, but avoid status taxonomy duplication.

Tests/verification likely affected:

- Render emitter tests, host retained tests, display renderer tests.

Risks/stop conditions:

- Stop if shared owner becomes a vague `utils` or `types` file.
- Stop if GL-specific checks are mixed into pure render-surface contract validation.

### Rank 10 - PTY FFI Is Mostly Direct But Still Has Result Mirror And Bucket Launch Translation

Path: `howl-pty/src/ffi.zig` and `howl-pty/include/howl_pty.h`

Line range: `ffi.zig` 7-48, 77-141, 143-253; `howl_pty.h` 13-57, 59-93, 95-130

Symbols:

- `HowlPtyCallStatus`, `FfiSnapshot`, `FfiOutboundPump`, `FfiReadResult`, `FfiTransportPumpLimits`, `launchConfigIn`, `sessionInit`, `HowlPtySnapshot`, `HowlPtyOutboundPump`, `HowlPtyReadResult`.

Breach category: moderate FFI mirror structs, result proliferation, config bucket at ABI seam.

Source evidence:

- `ffi.zig` lines 14-48 define four FFI result structs.
- `ffi.zig` line 77 has a long `launchConfigIn` signature translating shell, command, and start path pointer/len pairs into `pty.Launch`.
- `ffi.zig` lines 127-141 map specific start/resize errors into broad call statuses.
- `howl_pty.h` lines 13-57 define multiple status/outcome/control/pump enums.
- `howl_pty.h` lines 59-93 define snapshot/outbound/read/limits result structs.

Why it violates shallow intentional code:

- Compared with render and VT, PTY FFI is direct and owner-true, but it still mirrors multiple result structs and broad statuses.
- The launch initializer has many primitive pointer/len parameters that are easy to mix up; TigerStyle recommends named option structs when primitive arguments can be confused. C ABI constraints explain some of this, but the cleanup target is still to keep translation narrow.

Smallest true-owner cleanup target:

- Keep PTY FFI as translation only. If touched, reduce result family proliferation and keep launch translation in a single ABI contract zone.

Tests/verification likely affected:

- `howl-pty/src/test/ffi.zig`, `howl-pty/src/test/abi.zig`, PTY integration tests.

Risks/stop conditions:

- Stop if cleanup adds Zig-shaped host shortcuts around the C ABI.

### Rank 11 - VT Terminal Is Reasonably Owner-True But Still Bundles Protocol Families

Path: `howl-vt/src/terminal.zig`

Line range: 17-50, 52-117, 123-203, 205-263

Symbols:

- `Terminal`, `RuntimeObligation`, `RuntimeProgress`, `InitOptions`, `surfaceSnapshot`, `visibleMeta`, `progressRuntime`, `VisibleMeta`.

Breach category: moderate ownership bundling, option/result structs.

Source evidence:

- Lines 17-37 define `Terminal` with allocator, stream parser state, screen set, modes, kitty state, checksum flags, host state, charset designation, dirty generation, and surface publication state.
- Lines 38-50 define runtime obligation/progress/init option structs.
- Lines 123-203 cover feed, post-apply, resize, cell pixel size, reset, ack surface, surface snapshot, visible meta, runtime obligation/progress.
- Lines 205-263 cover hyperlink lookup, selection operations, surface publication result, and visible meta result.

Why it violates shallow intentional code:

- The file is much more intentional than the render offenders, but `Terminal` owns parser, screen, modes, kitty, host protocol state, selection consequences, dirty generation, and publication.
- `RuntimeObligation`/`RuntimeProgress` are currently empty/default behavior shapes that may be premature unless future protocol obligations are active.

Smallest true-owner cleanup target:

- Keep terminal as host-neutral VT owner, but move publication/visible metadata and runtime obligation shapes to smallest existing owners when they gain real behavior.

Tests/verification likely affected:

- VT terminal tests, snapshot behavior tests, surface tests.

Risks/stop conditions:

- Stop if cleanup fragments Ghostty-backed VT shape into Howl-only tiny files without owner proof.

### Rank 12 - Benchmark/Simulation Test Vocabulary Uses Generic Options/Result Buckets

Path: `howl-vt/src/test/terminal_benchmark.zig`, `howl-vt/src/simulation/protocol.zig`

Line range: grep-verified zones `terminal_benchmark.zig` 8-59, 239-581; `simulation/protocol.zig` 35-91, 151-189, 222-381

Symbols:

- `WorkloadResult`, `OutputFormat`, `Options`, `ReplayFixture`, `RunObservation`, `CountingAllocator`, `protocol.Options`, `Harness`, `VtDigest`, `ParserOutput`.

Breach category: test/probe vocabulary leakage, generic bucket naming, moderate over-structuring.

Source evidence:

- Grep showed benchmark file defining `WorkloadResult`, `Options`, fixtures, observations, counting allocator, summarization and run functions.
- Grep showed simulation protocol defining `Options`, feed/op enums, harness, digest and parser output structures.

Why it violates shallow intentional code:

- These are test/simulation zones, so lower severity. Still, generic `Options`/`Result`/`Harness` vocabulary is exactly the style pressure called out by AGENTS.md unless source-backed and owner-true.
- Benchmark and simulation code can infect product vocabulary if used as a pattern.

Smallest true-owner cleanup target:

- Rename/split only if these files become active cleanup targets. Prefer workload-specific nouns and keep simulation state bounded and explicit.

Tests/verification likely affected:

- VT benchmark/simulation tests if wired; regular VT tests only if these are imported by root.

Risks/stop conditions:

- Stop if cleanup spends sprint time on low-risk test names before major render/ABI offenders.

## Cross-Cutting Patterns

Failure taxonomy inflation:

- Render has `HowlRenderCallStatus`, `HowlRenderSurfaceEmitStatus`, `HowlRenderPrepareStatus`, `HowlRenderSubmitStatus`, `HowlRenderSubmitDecisionStatus`, host retained `PrepareFailure`, `SubmitFailure`, `PreparedRenderResourcePlanStatus`, `PreparedRenderSurfaceProbeStatus`, `RenderResourceStoreStatus`, display `FailureBucket`, `CommandShapeError`, terminal context `RenderSurfaceUploadPolicyError`, `RenderSurfaceEmitError`, `SubmitFailureReason`.
- Many statuses classify the same underlying facts: invalid spans, invalid commands, invalid resources, invalid uploads, stale/needs-prepare/failed.

Boundary thickness:

- `howl_render.h` is the thickest boundary. It exposes text session config, VT surface slots, render-surface resource streams, prepared handles, submit decisions, host surfaces, and emit statuses.
- VT and PTY ABIs are thinner but still repeat status-plus-payload result shapes.

Mirror structs:

- `HowlRenderSourceCell` and `HowlVtSurfaceCell` mirror similar terminal cell vocabulary across ABIs.
- `FfiSurfaceCell` mirrors `HowlVtSurfaceCell` in Zig.
- Host retained `PreparedRenderSurfaceProbe` and `PreparedRenderResourcePlan` mirror render surface info plus validation counters.
- Display `RenderResourceTextures.Slot` and retained `RenderResourceStored` mirror live/retired resource state.

Ownership bundling:

- `TextSessionOwner` owns font config, geometry, source slots, prepare requests, submitted state, prepared handle lists, font paths, sprite resources, and debug counters.
- `Context` owns terminal runtime, host texture, render resources, input, event loop, layout, focus, scrollbar, links, selection, cursor blink, render submit backend, and ABI error translation.
- `display.State` owns GL context, tab cache, present token lifecycle, proof capture, and diagnostics.

Hot-path complexity:

- `appendPreparedSprites` in render emitter branches across sprite lookup, bounds, upload bytes, atlas resource, persistent/transient resources, commands, and retires.
- `RenderResourceTextures.realizeSurfaceLocked` validates and mutates GL resources with rollback and GL sampling.
- `displaySubmitPresent` does token state, readiness diagnostics, tab cache, proof capture, terminal draw, scrollbar draw, swap, and logging.

Test/probe vocabulary leakage:

- Large product files contain extensive owner-local test fixtures and tests, especially `render_surface_emitter.zig`, `display/renderer/render_surface.zig`, and `terminal/render/retained.zig`.
- Probe/diagnostic structs (`PresentProof*`, `PreparedRenderSurfaceProbe`, `GlStateSample`, `PresentDiagnostics`) live in product owner files and influence naming/shape.

## Explicit Non-Findings

- `howl-render/src/ffi.zig` lines 1-3 looked acceptable: it only imports `howl_render.h` through `@cImport`; the offender is the header and wrappers, not this file.
- `howl-vt/src/howl_vt.zig` lines 1-46 looked acceptable as a curated root and test entrypoint: it mainly re-exports/publicly curates and imports tests.
- `howl-vt/src/libhowl_vt.zig` lines 1-32 looked acceptable as a C export root: it only maps exported names to FFI functions.
- `howl-pty/src/ffi.zig` is moderate, not major: despite result mirrors, it mostly translates C handles, pointer/length buffers, launch config, and statuses directly to `session.Session` owner calls.
- `howl-vt/src/terminal.zig` is moderate, not major: terminal has a broad but plausible VT owner role, with clear host-neutral state and no host integration imports.

## Proof Gaps

- I did not read all 3125 lines of `howl-linux-host/src/terminal/render/retained.zig`; the high-risk zones and tests were sampled through line 2208 plus grep evidence. Later tests may contain additional moderate naming/test-shape offenders.
- I did not read all 2587 lines of `howl-linux-host/src/display/renderer/render_surface.zig`; high-risk product and test zones were read through line 2225. Later helper/upload/classification functions may contain more detail, but ranking is already supported.
- I did not read all of `howl-render/src/prepared/render_surface_emitter.zig` after line 1208, but product owner zones through line 1116 and the start of tests were enough to classify the file.
- I did not fetch Alacritty/Ghostty references because the task is style offender discovery and current source/TigerBeetle/Howl law were sufficient for ranking. Reference comparison may be needed before implementing host/render reshapes.
- I did not run tests or build commands because this is research-only offender discovery, not implementation.
