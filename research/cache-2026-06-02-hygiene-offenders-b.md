# Hygiene Offenders B - 2026-06-02

Researcher B cache. Research only. No product code, scratchpad, `current.txt`, or git changes.

## Sources Read, In Order

1. User prompt for Researcher B, including required output shape and offender taxonomy.
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md` lines 90-113, 151-176, 213-229, 271-351, 372-429.
3. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md` lines 189-222, 408-423, 424-435, 467-487.
4. Existing `research/*.md` caches, grep-index only.
5. `loop.txt` lines 97-109, 164-183, 251-267.
6. Current Howl source listed in each offender.

TigerBeetle pressure used for ranking: minimum excellent abstractions, simple explicit control flow, bounded work, assertions on arguments/invariants, smallest variable scope, simpler return types, owner-true nouns, no overloaded names, no duplicated state, no broad result/status dimensionality unless the boundary forces it.

Howl pressure used for ranking: C ABI is the product; FFI translates contracts only; owner files own mutation; no `manager`/`engine`/`controller`/generic bucket owners; no bucket structs; hosts must not bypass C ABI; hosts own backend resource realization, Howl render owns render contracts and retained-frame state.

## Existing Research Grep Index

Terms used against `research/*.md`:

- `offender|hygiene|status|result|enum|FFI|ABI|render|host|protocol|validation|execution|probe|mirror|bundle|responsibility|sprawl|fat`
- Leads produced: `howl-render/src/prepared/render_surface_emitter.zig`, `howl-render/src/session/text.zig`, `howl-render/include/howl_render.h`, `howl-linux-host/src/display/renderer/render_surface.zig`, `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/terminal/render/retained.zig`, `howl-vt/src/ffi.zig`, `howl-vt/src/action/vocabulary.zig`, `howl-vt/src/parser/events.zig`, `howl-pty/src/ffi.zig`.
- Prior proof gaps reused only as navigation: render-surface token/resource-plan proof, resize retained-safety proof, host upload policy proof, ABI language cleanup, terminal context owner pressure. Every claim below was re-verified from current source.

## Ranked Offender List

### 1. Host Retained Render Mirror And Probe Bundle

- Path: `howl-linux-host/src/terminal/render/retained.zig` lines 1-155, 66-86, 88-155, 235-444, 550-610, 612-919, 932-1250.
- Symbols: `PrepareResult`, `PrepareFailure`, `SubmitResult`, `SubmitFailure`, `PreparedRenderResourcePlan`, `PreparedRenderResourcePlanStatus`, `RenderResourceStoreStatus`, `PreparedRenderSurfaceProbe`, `PreparedRenderSurfaceProbeStatus`, `State`, `RenderResourceStore`, `validatePreparedRenderSurfaceProbe`, `validateRenderSurfaceResourcePlan`.
- Breach category: failure taxonomy inflation, mirror structs, boundary thickness, validation/execution/probe/test vocabulary leakage, host/render ownership duplication.
- Source evidence: four result/failure enums appear before the owner state at lines 4-26; `PreparedRenderResourcePlanStatus` has 16 states at lines 88-105; `RenderResourceStoreStatus` has 9 states at lines 131-141; `PreparedRenderSurfaceProbeStatus` has 21 states at lines 563-584; `State` stores last failures, present state, probe counters, resource-plan counters, and the prepared handle at lines 612-628; host code validates render-surface resource plan and software surface layout at lines 932-995 and 1018-1250; `RenderResourceStore` mirrors backend resource lifecycle at lines 235-444.
- Why it violates shallow intentional code: the file is not one true owner. It is a host retained submit owner, a C ABI caller, a render-surface validator, a resource-store simulator, a probe diagnostics owner, and a failure taxonomy owner. TigerBeetle prefers simple return types and clear owner nouns; this file raises call-site dimensionality with many parallel status enums and duplicates resource validation already present in `display/renderer/render_surface.zig` and render emission.
- Smallest true-owner cleanup target: keep retained submit/present sequencing in this file; extract render-surface ABI validation/probe into a narrow render-surface contract/probe owner, and resource-store mirror into a test-only or backend-resource owner if still needed. Collapse mirrored statuses toward one contract result per boundary.
- Tests/verification likely affected: host unit tests through `howl-linux-host/src/test_root.zig`, retained submit tests, render-surface probe/resource-plan tests around lines 1754-1764.
- Risks/stop conditions: stop if cleanup would change public render ABI or host present policy; stop if host tests would need Zig imports into `howl-render` internals instead of C ABI.

### 2. Host GL Render Surface File Combines Resource Lifecycle, Validation, Upload, Shape Classification, GL State, And Tests

- Path: `howl-linux-host/src/display/renderer/render_surface.zig` lines 1-489, 491-580, 905-1914, 1916-2325.
- Symbols: `RenderResourceTextures`, `RenderResourceTextures.Slot`, `FailureBucket`, `GlStateSample`, `TrustedTextureFailureAction`, `CommandShapeError`, `ensureSurface`, `uploadRenderSurface*`, `renderSurface*` classifiers.
- Breach category: responsibility bundle, hot-path complexity, failure taxonomy inflation, backend policy mixed with test/probe vocabulary.
- Source evidence: GL externs and backend constants start at lines 5-20; texture resource state, counters, failure buckets, GL sample state, mutation, rollback, validation, and upload live in one struct at lines 35-489; command-shape errors are a separate error enum at lines 564-580; tests start mid-file at line 905 and continue through 1914; host surface creation and GL upload paths resume at lines 1916-2120; render-shape classifiers run at lines 2122-2325.
- Why it violates shallow intentional code: the file interleaves three planes: GL backend execution, trusted render-surface validation, and test classifier vocabulary. The shape classifiers and `CommandShapeError` duplicate validation pressure from `terminal/render/retained.zig`. The hot upload function `uploadRenderSurfaceCommands` at lines 2021-2120 owns GL state save/restore, command dispatch, validation panics, resource lookup, and error classification in one zone.
- Smallest true-owner cleanup target: keep GL texture creation/upload/draw execution here; move render-surface shape classification and trusted validation into a render-surface contract owner or a small host submit-boundary validator. Keep tests owner-local only for GL backend consequences after validation is separate.
- Tests/verification likely affected: `render surface textures ...`, `render surface command shape ...`, `render surface fill/sprite/glyph ...`, trusted texture failure tests in this file; host unit test gate.
- Risks/stop conditions: stop if extraction attempts to move GL texture ownership out of display renderer; stop if render ABI semantics change.

### 3. Render Prepared Surface Emitter Owns Emission, Persistent Resource Store, Atlas Packing, Sprite Cache, C ABI Translation, And Tests

- Path: `howl-render/src/prepared/render_surface_emitter.zig` lines 18-46, 48-68, 100-307, 326-920, 923-1116, 1156-1208 and later tests.
- Symbols: `Error`, `Limits`, `SpriteResourceStore`, `SpriteResourceStore.Result`, `AtlasResult`, `Emitter`, `emitPrepared`, `appendPreparedSprites`, `copyPreparedSpriteBytes`.
- Breach category: over-structuring, result/status inflation, resource ownership bundling, hot-path complexity, FFI shape embedded in render owner.
- Source evidence: broad error set at lines 36-46; `Limits` bucket at lines 48-68; `SpriteResourceStore` stores persistent entries, bytes, atlas metadata, and resource ids at lines 100-144; nested `Result` and `AtlasResult` at lines 113-125; `Emitter` owns damage/create/upload/command/glyph/retire buffers and the published C surface at lines 326-346; `emitPrepared` calls clear/background/decoration/sprite/cursor phases at lines 371-386; `appendPreparedSprites` does sprite lookup, visual bounds, upload staging, atlas packing, resource creation/upload/retire, glyph ref creation, and command append at lines 594-686; pixel copy validation is at lines 1074-1116; tests are owner-local in the same file starting line 1156.
- Why it violates shallow intentional code: emission should be a direct data-plane transformation, but this file also owns persistent resource lifecycle and atlas allocation. `SpriteResourceStore.Result` and `AtlasResult` are bucket-like status carriers around one owner. C ABI structs are threaded throughout, making the product boundary thick inside data-plane code.
- Smallest true-owner cleanup target: split atlas/resource allocation from surface command emission. Keep the C ABI surface assembly in an emitter owner; move persistent sprite resource and atlas packing to a resource owner with one small result contract.
- Tests/verification likely affected: `howl-render/src/test.zig` owner-local render surface emitter tests and realizer oracle tests.
- Risks/stop conditions: stop if cleanup changes `HowlRenderSurface` ABI layout or resource id semantics; stop if atlas ownership becomes host-owned.

### 4. Render C ABI Header Is Fat And Carries Multiple Product Shapes In One Boundary

- Path: `howl-render/include/howl_render.h` lines 17-65, 67-93, 95-177, 179-327, 329-507, 509-618.
- Symbols: `HowlRenderCallStatus`, `HowlRenderSurfaceEmitStatus`, `HowlRenderPrepareStatus`, `HowlRenderSubmitStatus`, `HowlRenderSubmitDecisionStatus`, `HowlRenderDamageKind`, draw spans, render-surface resource structs, VT source mirror structs, prepared/submit structs, text-session functions.
- Breach category: ABI/FFI offender, boundary thickness, failure taxonomy inflation, mirror structs.
- Source evidence: five status/decision enums before the first core geometry structs at lines 46-93; draw/span structs at lines 117-177; render-surface token/resources/commands at lines 184-314; geometry/work/prepare/publish structs at lines 316-366; VT source cell/color/selection/cursor mirror structs at lines 368-473; prepared info/submit/text config at lines 475-513; text session, geometry, VT-surface, prepare, submit, work-state, prepared-surface functions all share one header at lines 515-617.
- Why it violates shallow intentional code: the C ABI is the product, so some breadth is legitimate. The breach is that the header exposes too many status families and combines text session lifecycle, VT surface publication, render-surface resources, prepared handles, and host surfaces without a shallow contract hierarchy. Mirror structs duplicate VT ABI cell/color vocabulary instead of isolating the render-owned source seam.
- Smallest true-owner cleanup target: do not remove C ABI. Group by true ABI contracts: text session lifecycle, VT source publication, prepared surface lifecycle, render surface resource stream, submit execution. Collapse status families only where behavior is genuinely identical.
- Tests/verification likely affected: `howl-render/src/test/ffi.zig`, host C import wrappers, ABI tests.
- Risks/stop conditions: stop unless an explicit ABI-product slice authorizes public header changes; no compatibility aliases unless user authorizes.

### 5. Terminal Context Is A Host God Object Around PTY, VT, Render, Input, Selection, Scrollbar, Links, Present, Clipboard, And Tests

- Path: `howl-linux-host/src/terminal/context.zig` lines 1-35, 39-108, 110-181, 349-386, 397-429, 431-719, 721-821, 828-958, 960-1115, 1144 onward.
- Symbols: `Context`, `TurnStep`, `TurnResult`, `ContextSubmitBackend`, `RenderSurfaceUploadPolicyError`, `RenderSurfaceEmitError`, `SubmitPreparedResult`, `SubmitFailureReason`, `ContextOps`, `TermInit`.
- Breach category: responsibility bundle, failure taxonomy inflation, host/render sprawl, nested policy owners, test/probe vocabulary leakage.
- Source evidence: 34 imports at lines 1-35; `Context` fields cover PTY progress, terminal texture, resource textures, config, input, event loop, title, geometry, focus, scrollbar, links, selection, cursor blink at lines 80-99; init/deinit own PTY, VT, render session, wait thread, feed record, GL texture deletion at lines 110-181; render turn/present ack at lines 349-386; runtime startup at lines 397-429; `ContextSubmitBackend` handles render-surface resource realization, host texture resize, upload policy, unsupported shape panics, emit error mapping, execution assembly at lines 539-719; submit transaction unlocks and relocks terminal mutex around backend upload at lines 721-758; input/link/scrollbar/selection ops are nested at lines 828-958; tests begin at line 1144.
- Why it violates shallow intentional code: `Context` is a host orchestration owner, but current nested shapes make it also a render-surface upload policy owner, ABI error mapper, terminal input adapter, selection/link/scrollbar test owner, and lifecycle assembler. TigerBeetle rejects broad owner names when they hide mutation and policy.
- Smallest true-owner cleanup target: keep main-thread terminal orchestration here; extract submit backend policy to terminal render submit owner or display renderer boundary; keep input ops in input owners and present ack in present/retained owners.
- Tests/verification likely affected: host terminal context owner-local tests, input/selection/render-turn tests in host unit gate.
- Risks/stop conditions: stop if extraction decentralizes main-thread control flow or bypasses C ABI; stop if host UX/runtime policy changes in a hygiene slice.

### 6. Render Text Session Owner Bundles Font Configuration, Text Preparation, Geometry, Source Slot, Prepare Queue, Submitted State, Prepared Handles, Render Resource Store, And FFI Handles

- Path: `howl-render/src/session/text.zig` lines 32-36, 59-87, 65-307, 309-607, 609-846.
- Symbols: `SessionWorkState`, `TextSessionConfig`, `TextSession`, `TextContext`, `PrepareInput`, `TextSessionOwner`, `FontConfigError`, `recordPrepareHandleFailure`.
- Breach category: ownership bundling, bucket structs, dynamic allocation in hot-ish path, debug vocabulary leakage.
- Source evidence: session work/result/config structs at lines 32-87; `TextSession` owns allocator, font/text state, mutex, text preparer, scratch storage at lines 65-71; nested `TextContext` at lines 72-75; provider thunks and raster allocation live at lines 229-306; `TextSessionOwner` fields include geometry, source slot, prepare requests, submitted state, source dirty epoch, config, prepared handles array, font paths, render surface sprite resources, and failure counter at lines 309-325; font config, source publication, prepare, submit, geometry, cursor blink, work-state methods all live at lines 327-607; owner-local tests begin at line 609.
- Why it violates shallow intentional code: `TextSessionOwner` is a lifecycle bucket rather than the smallest owner. It centralizes independent owners and FFI handle cache state. `recordPrepareHandleFailure` prints debug diagnostics at lines 424-439, leaking probe vocabulary into owner code.
- Smallest true-owner cleanup target: keep C ABI text-session handle owner here only as lifecycle coordinator; move font path ownership, prepared handle registry, and render-surface sprite resource store to true owners or reduce to explicitly named fields with narrow methods.
- Tests/verification likely affected: `howl-render/src/test.zig`, text session owner tests at lines 639 onward, FFI text session tests.
- Risks/stop conditions: stop if cleanup alters text-session C ABI handle semantics or thread-safety contract.

### 7. VT FFI File Combines ABI Types, Translation, Terminal Lifecycle, Surface Copy, Selection, Input Encoding, Runtime, And Tests

- Path: `howl-vt/src/ffi.zig` lines 12-228, 230-462, 464-769, 771-1123.
- Symbols: `HowlVtCallStatus`, `Ffi*` extern structs, `terminalInit*`, `terminalFeed`, `terminalCopySurface`, `terminalEncode*`, `terminalCopySelection`, `terminalProgressRuntime`.
- Breach category: ABI/FFI offender, boundary thickness, mirror structs, test vocabulary leakage.
- Source evidence: ABI status and extern mirror structs span lines 24-228; translation helpers and surface selection projection live at lines 230-462; lifecycle/feed/resize/surface/selection/runtime/input encoding functions live at lines 464-769; tests are embedded at lines 771-1123.
- Why it violates shallow intentional code: FFI may translate contracts, but this file owns every VT host seam and many mirror structs. Surface copy also applies selection ranges at lines 451-462, mixing ABI translation with presentation overlay mutation. The repeated result structs widen failure taxonomy across simple C calls.
- Smallest true-owner cleanup target: split FFI by contract: lifecycle/feed, surface publication, selection/clipboard, input encoding. Keep ABI extern structs near their contract, not one universal file.
- Tests/verification likely affected: `howl-vt/src/test/abi.zig`, `howl-vt/src/test.zig` if curated, all FFI tests currently owner-local.
- Risks/stop conditions: public `howl_vt.h` compatibility and symbol exports require explicit ABI slice; do not change C call signatures in hygiene-only work.

### 8. VT Action Vocabulary File Is A Protocol/Event Bucket With Massive Union Duplication

- Path: `howl-vt/src/action/vocabulary.zig` lines 6-73, 74-255, 257-403.
- Symbols: `SemanticEvent`, `ScreenAction`, `ReportAction`, `ModeAction`, `KittyAction`, `HostAction`, command structs.
- Breach category: protocol/state/execution vocabulary bundled, over-structuring, ownership bundling.
- Source evidence: mixed Kitty, terminal color, key format, DCS, erase, legacy control structs/enums at lines 6-73; `SemanticEvent` union spans line 75 through 255 with screen actions, mode changes, reports, Kitty actions, host actions, and DCS payloads; narrower unions then repeat subsets at lines 257-403.
- Why it violates shallow intentional code: a vocabulary file is not a true owner. It combines parser semantic events, screen execution actions, mode actions, report actions, Kitty actions, and host actions. This creates duplicate tags across `SemanticEvent` and the split unions, increasing routing complexity and making protocol ownership vague.
- Smallest true-owner cleanup target: move event/action types to the owner that executes or reports them: screen actions near screen apply, mode actions near mode, host actions near host apply, Kitty actions near Kitty owner. Keep only a parser-facing semantic union if required.
- Tests/verification likely affected: action mapping tests, parser CSI behavior, terminal end-to-end tests.
- Risks/stop conditions: stop if extraction requires protocol behavior changes; references should be checked against Ghostty/Kitty for VT shape before broad movement.

### 9. VT Parser Events Store Combines Parser Callback Materialization, Charset State, Rollback, Compaction, DCS Body Reconstruction, And Event Iteration

- Path: `howl-vt/src/parser/events.zig` lines 13-48, 50-157, 159-307, 309-491, 507-520 and rest of event materialization.
- Symbols: `StyleChange`, `DcsEvent`, `Event`, `ParsedEvents`, `EventMeta`, `DcsHookState`, `AppendBatch`, `Iterator`.
- Breach category: hot-path complexity, responsibility bundle, dynamic allocation and compaction in parser path.
- Source evidence: public event unions at lines 13-48; `ParsedEvents` owns event list, bytes, ints, aux, APC/DCS/PM bytes, DCS hook, charset state at lines 64-80; batch rollback stores seven lengths and three charset values at lines 128-140; append path handles parser actions, string-control bytes, DCS body reconstruction, charset mutation, and meta storage at lines 309-491; event materialization slices multiple stores at lines 507 onward.
- Why it violates shallow intentional code: this is a callback store, parser state mirror, string-control buffer, and event iterator in one owner. TigerBeetle hot-path guidance favors bounded simple loops and minimal variables in scope; this file keeps many cursors and stores live across parser phases.
- Smallest true-owner cleanup target: separate parser output storage from charset transition state and string-control payload accumulation. Keep event iteration direct and bounded.
- Tests/verification likely affected: parser behavior tests, stream harness, terminal end-to-end tests.
- Risks/stop conditions: stop if event storage capacity semantics or parser callback ordering become ambiguous.

### 10. Render Prepared Owner Mixes Handle Lifecycle, Prepared Info, Render-Surface Payload Emission, Submit Result, State Machine, And Tests

- Path: `howl-render/src/prepared/owner.zig` lines 15-27, 33-72, 84-120 and remainder through line 836.
- Symbols: `PreparedInfo`, `PreparedBuffer`, `Owner`, `Owner.State`, `Owner.SubmitResult`, `RenderSurfacePayload`, `emitRenderSurfacePayload`.
- Breach category: owner bundling, result/status inflation, ABI handle lifecycle mixed with payload realization.
- Source evidence: `PreparedInfo` mirrors ABI info at lines 17-27; `Owner` stores session owner, prepared surface, render-surface payload pointer, state, token fields, geometry fields, damage, upload count, emit status at lines 33-50; nested `State` and `SubmitResult` at lines 34 and 52-56; `create` registers handle and immediately emits render-surface payload with status mapping at lines 58-70.
- Why it violates shallow intentional code: a prepared handle owner should own lifecycle and invariants. It also owns render-surface payload emission and C status mapping, coupling handle creation to backend payload preparation. `PreparedInfo` duplicates C ABI shape rather than remaining in FFI translation.
- Smallest true-owner cleanup target: keep handle lifecycle/state machine in `prepared/owner.zig`; move payload emission/status mapping into prepared render-surface payload owner or FFI translation.
- Tests/verification likely affected: render FFI prepared handle tests, prepared owner tests, render-surface emitter tests.
- Risks/stop conditions: stop if handle lifetime or borrowed `HowlRenderSurface` pointer semantics change.

### 11. Render Prepare Request Owner Also Classifies Damage, Queues Source, Owns Blink Refresh, Geometry Retained Safety, And Source Slot Refresh

- Path: `howl-render/src/source/prepare_request.zig` lines 8-35, 37-96, 98-127, 143-182, 184-229, 237-307, 309-354.
- Symbols: `PrepareConsume`, `Publication`, `ActivePrepare`, `PrepareRequests`, `acceptSource`, `takePrepareRequest`, `classify`, `refreshRetainedSlotViews`.
- Breach category: responsibility bundle, retained-safety policy mixed with queue owner.
- Source evidence: queue item structs at lines 8-35; `PrepareRequests` owns allocator, pending, active, blink flag at lines 37-42; `acceptSource` canonicalizes dirty metadata, classifies damage, clones retained source, and replaces pending at lines 55-96; `takePrepareRequest` mutates blink refresh into full prepare at lines 98-121; source-slot refresh is at lines 218-229; `classify` owns geometry change, dirty comparison, cursor/color presentation, grid/alt/scroll rules at lines 270-294.
- Why it violates shallow intentional code: queue ownership and damage classification are both legitimate, but together they make the prepare queue own retained safety policy and source storage policy. This increases semantic distance between source truth, damage truth, and prepare scheduling.
- Smallest true-owner cleanup target: keep queue/taken lifecycle in `PrepareRequests`; extract damage/retained-safety classification to a source damage classifier with explicit inputs.
- Tests/verification likely affected: `howl-render/src/source/prepare_request.zig` owner-local tests and retained resize tests.
- Risks/stop conditions: stop if retained reuse rules become under-specified or host needs internal render imports.

### 12. PTY FFI File Is Moderate ABI Thickness With Snapshot/Pump/Read/Transport Limits In One Translator

- Path: `howl-pty/src/ffi.zig` lines 7-48, 54-86, 88-141, 143-253.
- Symbols: `HowlPtyCallStatus`, `FfiSnapshot`, `FfiOutboundPump`, `FfiReadResult`, `FfiTransportPumpLimits`, `sessionInit`, `sessionPumpOutbound`, `sessionRead`, `transportPumpLimits`.
- Breach category: ABI/FFI offender, result struct proliferation, boundary thickness.
- Source evidence: one status enum and four result structs at lines 7-48; byte/span and launch translation at lines 54-86; snapshot/pump/limits/status mapping at lines 88-141; session lifecycle, signal, input, pump, pending, wait, read, limits functions at lines 143-253.
- Why it violates shallow intentional code: less severe than render/VT because PTY is smaller, but FFI still bundles lifecycle, control, transport, and diagnostics. Result structs are mostly ABI-forced, yet each adds call-site status dimensionality.
- Smallest true-owner cleanup target: keep C ABI translation; split lifecycle/control from transport pump/read if the file grows. Do not add more status/result families here.
- Tests/verification likely affected: `howl-pty/src/test/ffi.zig`, `howl-pty/src/test/abi.zig`.
- Risks/stop conditions: public `howl_pty.h` change needs explicit ABI slice.

### 13. VT Terminal Owner Is Moderate Bundle Of Stream, Screen, Modes, Kitty, Host State, Selection, Surface Publication, Runtime Stubs

- Path: `howl-vt/src/terminal.zig` lines 17-37, 38-50, 52-117, 123-166, 168-211, 214-248, 250-260.
- Symbols: `Terminal`, `RuntimeObligation`, `RuntimeProgress`, `InitOptions`, `feed`, `postApply`, `resize`, `surfaceSnapshot`, `visibleMeta`, `visibleCellHyperlinkUri`, selection methods.
- Breach category: ownership bundling, runtime/test vocabulary leakage.
- Source evidence: `Terminal` fields include allocator, stream state, screen set, modes, kitty, checksum flags, host, charset state, dirty generation, surface publication at lines 25-36; lifecycle creates stream/screen/host at lines 52-107; feed/post-apply/resize/surface publication/runtime/selection all live at lines 123-248; runtime methods are idle stubs at lines 190-203.
- Why it violates shallow intentional code: this is a broad terminal owner, which is somewhat source-backed by terminal core shape. The breach is moderate: runtime obligation stubs and host/surface/selection methods are all direct methods on `Terminal`, making the owner less shallow.
- Smallest true-owner cleanup target: keep terminal as aggregate root; move runtime obligation to host/protocol owner if it becomes real, and keep selection/surface publication under their existing subowners with thin delegating methods only.
- Tests/verification likely affected: VT terminal end-to-end, surface, selection tests.
- Risks/stop conditions: stop if cleanup invents a new umbrella runtime layer.

### 14. Render Text Frame Preparer Tests And Options Leak `engine` Vocabulary Into Text Preparation

- Path: `howl-render/src/text/frame_preparer.zig` lines 543-567, 569-869.
- Symbols: `mergeRasterPlans`, `PrepareOptions`, tests using `engine` locals.
- Breach category: moderate over-structuring, test/probe vocabulary leakage.
- Source evidence: `PrepareOptions` is a one-field wrapper around `scene.BuildOptions` at lines 565-567; tests repeatedly name `var engine = TextFramePreparer...` at lines 570, 589, 610, 629, 647, 674, 717, 740, 751, etc.; tests assert internal counters and routes.
- Why it violates shallow intentional code: AGENTS forbids `engine` owners, and tests reinforce a non-owner noun for `TextFramePreparer`. `PrepareOptions` is a bucket wrapper around another options bucket. This is moderate because the implementation owner may still be reasonable.
- Smallest true-owner cleanup target: replace test vocabulary with `preparer`; remove or justify `PrepareOptions` if it remains a one-field wrapper.
- Tests/verification likely affected: text frame preparer owner-local tests.
- Risks/stop conditions: low, unless option shape is exposed through public render module APIs.

## Cross-Cutting Patterns

- Failure taxonomy inflation: render has `HowlRenderCallStatus`, `HowlRenderSurfaceEmitStatus`, prepare/submit/decision statuses, host retained `PrepareFailure`, `SubmitFailure`, probe statuses, resource-plan statuses, texture failure buckets, and context submit failure reasons. This violates TigerBeetle's simpler return-type pressure and spreads dimensionality across call chains.
- Boundary thickness: render and VT C ABIs carry large mirror structs plus many status-bearing result structs. ABI breadth may be product-required, but FFI files should translate contracts only; current files also own mutation, validation, and tests.
- Mirror structs: `howl_render.h` mirrors VT source cell/color/selection/cursor; `howl-vt/src/ffi.zig` mirrors screen cells; host retained `RenderResourceStore` mirrors display renderer texture lifecycle; prepared info mirrors ABI info.
- Ownership bundling: `Context`, `TextSessionOwner`, `Terminal`, `RenderResourceTextures`, `PrepareRequests`, and `ParsedEvents` each aggregate multiple independent domains. The most severe bundles own validation and execution together.
- Hot-path complexity: render upload, render emission, parser event materialization, and VT stream processing carry many counters/cursors/status values. Some bounds are asserted, but owner shape makes it hard to verify positive and negative space locally.
- Test/probe vocabulary leakage: probe/status/failure/test helper vocabulary is embedded in product files (`retained.zig`, `render_surface.zig`, `context.zig`, `session/text.zig`, `ffi.zig`). Tests are often owner-local, but the owner is too broad.

## Explicit Non-Findings

- `howl-render/src/ffi.zig` lines 1-3 looked acceptable: it only imports the shipped C header and exposes `c`; no behavior or ABI translation is hidden there.
- `howl-vt/src/stream_terminal.zig` lines 38-94 looked mostly acceptable as a direct stream loop: it parses, materializes events, applies them, pops events, and returns a small summary. The offender is the event store it uses, not this stream wrapper.
- `howl-render/src/source/prepare_request.zig` has useful assertions and bounded owner-local tests; it is not a top-tier offender by itself. The issue is classification policy bundled with queue/source ownership.
- `howl-pty/src/ffi.zig` is moderate rather than major: it is compact and mostly translates ABI calls, but should not grow further in its current shape.

## Proof Gaps

- Did not run tests or git commands by instruction; this is research only.
- Did not inspect every Zig file in the repository. I prioritized grep-identified offender clusters and current source line evidence.
- Did not re-read Alacritty/Ghostty/Kitty references because this task asked for offender discovery, and TigerBeetle/Howl style pressure was sufficient to rank concrete breaches. Reference comparison is still needed before authorizing broad host/render/VT reshaping.
- Did not verify generated C import wrappers under `howl-linux-host/src/howl_*_c.h` beyond glob discovery; public headers were used as ABI evidence.
