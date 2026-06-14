# Six-Target Pragmatic Shape Plan

Status:

- Active research artifact for planning.
- Orchestrator session id: `orch-2026-06-14-six-target-pragmatic-shape-01`.
- Researcher session id: `research-2026-06-14-six-target-pragmatic-shape-01`.
- Reviewer session id: `review-2026-06-14-six-target-pragmatic-shape-01`.
- Reviewer accepted planning.
- No implementation is authorized from this file until the orchestrator seeds execution slices.
- Acceptance receipt: pending orchestrator commit.

Sources read in order:

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` reread
7. `sprints/current.txt`
8. `loops/six-target-pragmatic-shape-live-loop.txt`
9. `research/2026-06-14-six-target-pragmatic-shape-plan.md`
10. `reference-index.md`
11. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
13. Current target files:
    - `howl-linux-host/src/terminal/surface.zig`
    - `howl-render/src/text/ft_hb/support.zig`
    - `howl-render/src/text/shape/cluster.zig`
    - `howl-render/src/surface/emitter.zig`
    - `howl-render/src/text/raster/special_legacy_computing.zig`
    - `howl-vt/src/parser.zig`
14. Governing current seams and proof roots:
    - `howl-render/src/render_session.zig`
    - `howl-render/src/text/ft_hb/support_test.zig`
    - `howl-linux-host/src/terminal/surface_test.zig`
15. Governing references:
    - `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
    - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
    - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
    - `utils/dev_references/terminals/ghostty/src/Surface.zig`
    - `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig`
    - `utils/dev_references/terminals/ghostty/src/font/sprite/draw/special.zig`
    - `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig`

Compact anchor map:

- Alacritty `window_context.rs:47-70, 168-257`: one per-window owner keeps terminal, display, notifier, mouse, config, and PTY startup together. Large owner is acceptable when it is the true runtime seam.
- Ghostty `Surface.zig:1-12, 62-176`: one surface owns runtime surface, renderer, IO, mouse, keyboard, config, and focus. Large owner is acceptable when it is the actual surface contract.
- Alacritty `display/content.rs:24-39, 153-185, 187-207`: renderable-content owner stays direct; it does not hide ownership behind generic helper buckets.
- Alacritty `glyph_cache.rs:46-99, 191-245`: text/font support keeps one direct cache owner with explicit state and arguments, not owner-probing generics.
- Ghostty `font/shaper/run.zig:10-39, 41-91, 149-259`: run shaping stays in one owner, but temporary logic stays domain-specific and direct.
- Ghostty `font/sprite/draw/special.zig:1-7, 13-72, 135-235`: special glyph drawing can stay in one file, but helpers are exact draw verbs, not option buckets.
- Ghostty `terminal/Parser.zig:49-80, 205-310`: parser stays one control spine; state transitions, exit, transition, and entry order remain centralized.
- TigerBeetle `TIGER_STYLE.md:90-100, 109-126, 161-176, 271-360`: reject ambient genericity, assert invariants at boundaries, keep one control spine, and fix nouns rather than narrating with helper buckets.
- Current Howl text-session seam `render_session.zig:89-99, 142-166, 257-345`: `TextSession` is the real text owner; `support.zig` currently hides that through `anytype` probes.
- Current Howl scratch proof roots:
  - `support_test.zig:50-101`
  - `surface_test.zig:37-84, 155-201, 853-931`
  - `emitter_test.zig:104-222, 267-1301`
  - `cluster.zig:805-1113`
  - `parser.zig:672-779`

Current-code facts:

- `howl-linux-host/src/terminal/surface.zig` is the actual host-surface owner: it owns PTY progress, render turn admission, submit/present sequencing, title, input focus, and VT/render startup in one file (`surface.zig:52-110, 355-377, 415-446, 521-670`).
- `howl-render/src/text/ft_hb/support.zig` owns FT/HB state, caches, retained shape input buffers, and provider-side shaping/raster lookup, but it currently reaches that owner state through `anytype` probing (`support.zig:38-90, 100-120, 150-742`).
- `howl-render/src/text/shape/cluster.zig` is already one owner for text-cache/renderable/cluster assembly and retained cluster scratch used by the surface preparer (`cluster.zig:101-154`; `surface_preparer.zig:33-36, 96-116, 169-251`).
- `howl-render/src/surface/emitter.zig` is a bounded data-plane owner: fixed arrays, counts, publish fixups, and resource emission all live in one comptime-bounded type (`emitter.zig:67-87, 89-153, 352-679`).
- `howl-render/src/text/raster/special_legacy_computing.zig` is one special-raster owner containing direct codepoint-to-raster logic, but some helpers use option bags instead of exact draw nouns (`special_legacy_computing.zig:169, 528-529`).
- `howl-vt/src/parser.zig` keeps one central parser control spine: `next`, `nextActive`, `buildPhases`, `exitPhase`, `entryPhase`, `doAction`, and CSI/DCS assembly remain centralized (`parser.zig:296-338, 382-657`).

Reference facts:

- Alacritty accepts large host/runtime owners when they are the real per-window seam (`window_context.rs:47-70, 168-257`).
- Ghostty accepts large surface owners when they directly own the runtime, renderer, IO, and focus surface (`Surface.zig:62-176`).
- Alacritty text/render owners stay direct and avoid ownership-probing abstractions (`display/content.rs:24-39, 153-185`; `glyph_cache.rs:46-99, 191-245`).
- Ghostty shaping and special drawing code keeps one owner file but uses exact domain verbs instead of generic assembly or option buckets (`font/shaper/run.zig:41-91, 149-259`; `font/sprite/draw/special.zig:13-72, 135-235`).
- Ghostty parser shape keeps a single ordered exit/transition/entry spine (`terminal/Parser.zig:205-310`).
- TigerBeetle style pressure rejects ambient genericity, support buckets without ownership truth, and multi-step narration when direct owner code is clearer (`TIGER_STYLE.md:90-100, 109-126, 161-176, 271-360`).

Owner roles and proposed shape:

- `surface.zig`: keep as one host surface owner. Proposed shape is direct owner code with helper buckets removed or inlined; no owner split.
- `support.zig`: keep as one FT/HB support owner. Proposed shape is explicit `FtHbSupport` plus explicit config inputs at the render-session seam; no `anytype` ownership probes.
- `cluster.zig`: keep as one cluster/text-cache assembly owner. Proposed shape is retained scratch plus direct assembly; remove scaffolding assembly structs.
- `emitter.zig`: keep as one bounded surface-emission owner. Proposed shape is explicit no-op unless identical fill-pass narration can be simplified without reducing directness.
- `special_legacy_computing.zig`: keep as one special-raster owner. Proposed shape is direct draw verbs with option buckets removed.
- `parser.zig`: keep as one parser owner. Proposed shape is the same control spine with only minor generic/transitional cleanup.

Sprint scratchpad:

- Highest-confidence source-backed cleanup: `support.zig` owner-probing generics.
- Next-best cleanup with strong proof roots: `surface.zig` internal `Ops`/`anytype` narration and `cluster.zig` assembly buckets.
- Highest proof risk: `special_legacy_computing.zig` because no current test root was found.
- Highest control-spine risk: `parser.zig`; keep last.
- Highest chance of stop/no-op after fresh proof: `emitter.zig`; current source already looks close to settled owner shape.

Per-target judgments:

## 1. `howl-linux-host/src/terminal/surface.zig`

- Exact file and line references:
  - Owner state and public runtime seam: `surface.zig:52-110, 170-413`.
  - Progress/render spine: `surface.zig:355-377, 521-670`.
  - Local protocol/support buckets: `surface.zig:37-50, 111-119, 454-479, 508-625, 689-733, 818-890`.
  - Ownership-probing generics: `surface.zig:359, 578, 824, 840, 855-888`.
- Exact reference comparison:
  - Matches Alacritty per-window runtime ownership pressure in `window_context.rs:47-70, 168-257`.
  - Matches Ghostty surface ownership pressure in `Surface.zig:1-12, 62-176`.
  - Diverges from both references by using test-seam `anytype`/`Ops` indirection inside the owner instead of keeping concrete owner code direct.
- Verdict: keep-large.
- Exact ugly/fake concepts to remove without splitting the owner:
  - Delete the ownership-probing test/runtime helpers `driveProgressWith`, `submitPreparedLockedWith`, `completePresentLockedWith`, and `applyPendingClipboardWrite` in their current `anytype` form.
  - Delete or inline `ContextDriveOps` and `ContextSubmitBackend`; they narrate obvious ownership instead of expressing direct surface behavior.
  - Inline `InitialRequest` + `initial` into `init` unless a smaller exact owner truth appears during implementation.
  - Inline `TermInit` and `SubmitPreparedResult` if they survive only as local assembly/result buckets after the generic seams are removed.
- Transitional or over-explanatory names:
  - `InitialRequest`: transitional local request bucket; reads like staging, not ownership.
  - `DriveAdmission`: acceptable but slightly protocol-sounding; keep only if the admission fact remains a real public noun.
  - `SubmitPreparedResult`: local result bucket; over-explanatory if only one caller remains after cleanup.
  - `ContextDriveOps` and `ContextSubmitBackend`: over-explanatory narration of current owner behavior.
- Exact changes that make the file read like one owner faster without splitting it:
  - Pull `init`, runtime start, progress drive, and submit/present paths closer to direct concrete owner calls.
  - Remove fake backend/protocol indirection where the real owner is already `Surface`.
  - Leave public surface methods grouped as lifecycle, input, render/progress, and VT/render startup so the file reads top-down as one surface runtime.
- Required assertions:
  - Preserve and sharpen render/present invariants around `preparedUpload`, `presentPending`, and stale-handle rejection at `surface.zig:595-611`.
  - Assert clipboard/present helpers operate on the real owner path, not a generic fake path.
  - Add positive assertions for the unlock/relock submit path if helper shape changes.
- Required tests:
  - Keep existing `surface_test.zig` coverage for clipboard policy and drive continuation: `37-84`, `155-201`.
  - Keep submit/present seam coverage already exercising the generic helpers today: `853-931` and the resize/retry cases below that range.
  - Add no new behavior tests unless helper deletion changes proof gaps; prefer rewiring current tests to the direct owner seam.
- Non-goals:
  - No surface split.
  - No event-loop redesign.
  - No ABI change.
  - No render policy change.
- Stop conditions:
  - Stop if direct helper removal forces a fake testing abstraction that is no clearer than the current `Ops` buckets.
  - Stop if the render/present mutex spine becomes less centralized.

## 2. `howl-render/src/text/ft_hb/support.zig`

- Exact file and line references:
  - State owner: `support.zig:38-90`.
  - Ownership-probing generic seam: `support.zig:100-120`.
  - Provider entrypoints and shaping path: `support.zig:150-380`.
  - More owner-probing helpers and fallback path: `support.zig:382-595, 625-742`.
  - Current real owner seam: `render_session.zig:89-99, 142-166, 257-345`.
  - Existing proof: `support_test.zig:50-101`.
- Exact reference comparison:
  - Alacritty `glyph_cache.rs:46-99, 191-245` keeps one direct owner with explicit state and arguments.
  - Ghostty `font/shaper/run.zig:41-91, 149-259` keeps the shaper path in one owner but never probes ownership through ambient generics.
  - Current Howl support file diverges through `textState`, `configView`, `lockFt`, `unlockFt`, and many `anytype` leaves.
- Verdict: keep-large.
- Exact ugly/fake concepts to remove without splitting the owner:
  - Delete `textState`, `configView`, `lockFt`, and `unlockFt` as ownership-probing generic helpers.
  - Delete `anytype` from internal leaves such as `shapeRunViaProviderOrFallback`, `shapeRunViaProvider`, `shapePlainAsciiRun`, `providerGlyphId`, `providerGlyphAdvance`, `ensurePrimaryFont`, `ensureFont`, `resetLoadedFace`, `resizeLoadedFaces`, `ensureFallbackFace`, `deriveCellMetrics`, `acquireShapingFaceLocked`, `ensureFaceForId`, `providerGlyphVisualWidth`, `glyphAdvanceFromFace`, `setFacePixelHeight`, and `useDeterministicTestTextFallback`.
  - Keep `FtHbSupport` as the state owner; move context extraction to the render-session thunk edge so support code receives explicit `*FtHbSupport` plus exact config.
  - Keep `ClusterWindow` and `ShapeRunInput`; they are local domain nouns, not generic buckets.
- Transitional or over-explanatory names:
  - `textState` and `configView`: transitional ownership-probing names, not domain nouns.
  - `lockFt` and `unlockFt`: acceptable only as direct owner methods; as generic free helpers they over-explain control flow.
  - `configuredCellMetrics`: slightly transitional alias for `deriveCellMetrics`; candidate for deletion if redundant.
- Exact changes that make the file read like one owner faster without splitting it:
  - Start each shaping/provider path from explicit state/config inputs rather than generic context recovery.
  - Keep caching, fallback, and shape-input assembly near the state owner so the file reads as one FT/HB support pipeline.
  - Delete alias/narration helpers that say how to find the owner instead of doing owner work.
- Required assertions:
  - Preserve capacity assertions around `max_shape_input_codepoints` and `ShapeRunInputOverflow` at `support.zig:625-642`.
  - Assert the explicit config/state pair stays in sync at the call boundary after generic removal.
  - Preserve fallback/icon assertions in `glyphAcceptedLocked` at `support.zig:512-522`.
- Required tests:
  - Keep `support_test.zig:20-48` for fallback-face behavior.
  - Keep `support_test.zig:50-68` for explicit retained capacities.
  - Keep `support_test.zig:70-101` for bounded shape-run input reuse and overflow.
  - Add no split tests; proof should stay in the existing support test root.
- Non-goals:
  - No new helper file.
  - No font fallback policy change.
  - No cache sizing policy change.
  - No HarfBuzz/Freetype behavior change.
- Stop conditions:
  - Stop if the only way to remove `anytype` is to invent a new vague `Context`/`Options` bucket.
  - Stop if implementation tries to move real text-session ownership out of `render_session.zig`.

## 3. `howl-render/src/text/shape/cluster.zig`

- Exact file and line references:
  - Output owners: `cluster.zig:31-99`.
  - Retained scratch owner: `cluster.zig:101-154`.
  - Support buckets: `cluster.zig:156-227`.
  - Scratch-based build paths: `cluster.zig:248-385, 471-600`.
  - Helper assembly tail: `cluster.zig:749-780`.
  - Existing proof: `cluster.zig:805-1113`.
- Exact reference comparison:
  - Alacritty `display/content.rs:24-39, 153-185, 187-207` keeps renderable assembly direct and close to the owner.
  - Ghostty `font/shaper/run.zig:72-91, 149-259` keeps transient shaping logic domain-specific and avoids generic assembly structs.
  - TigerBeetle `TIGER_STYLE.md:90-93, 158-176, 271-360` rejects support buckets that narrate obvious assembly.
  - Current Howl file is owner-true as one cluster/text-cache seam, but `InputRenderableAssembly` and `CellLineTextCacheAssembly` are scaffolding.
- Verdict: keep-large.
- Exact ugly/fake concepts to remove without splitting the owner:
  - Delete `InputRenderableAssembly`.
  - Delete `CellLineTextCacheAssembly`.
  - Keep `RetainedScratch`; it is a real retained owner seam already consumed by `surface_preparer.zig:33-36, 96-116, 169-251` and proved by bounds tests.
  - Keep output owners `OwnedLineTextCache`, `OwnedRenderableCells`, `OwnedClusters`, `SparseCells`, and `ComplexSelection`; they are returned ownership nouns, not fake scaffolding.
  - Rework `buildLineTextCacheFromCells`, `buildRenderableCellsFromCells`, and `buildRenderableCellsFromInputs` to write directly through scratch/local slices instead of assembly wrappers.
- Transitional or over-explanatory names:
  - `InputRenderableAssembly`: transitional assembly bucket.
  - `CellLineTextCacheAssembly`: transitional assembly bucket.
  - `RenderableText` and `RetainedScratch`: no rename pressure found; both are owner-true nouns in current use.
- Exact changes that make the file read like one owner faster without splitting it:
  - Put direct scratch-writing logic in the build functions so readers see one text-cache/renderable/cluster assembly pipeline.
  - Keep retained scratch as the explicit bounded memory seam and remove side narration from assembly wrappers.
  - Preserve the current proof-heavy flow and prune only helper structs that restate obvious append/adopt steps.
- Required assertions:
  - Preserve `ClusterScratchOverflow` bounds checks at `cluster.zig:150-154`.
  - Preserve span invariants at `cluster.zig:504-505, 556-557`.
  - Add assertions that direct assembly still fills exact counts before adopting/duping output slices.
- Required tests:
  - Keep the full existing proof root at `cluster.zig:805-1113`.
  - Especially keep sparse-cell, damage, and scratch-overflow tests: `920-1023`, `1087-1113`.
- Non-goals:
  - No split of cluster owner into extra files.
  - No change to text interning semantics.
  - No lane classification change.
- Stop conditions:
  - Stop if a proposed split only moves the same assembly narration into another helper file.
  - Stop if `RetainedScratch` is targeted just because it is large; it is currently owner-true.

## 4. `howl-render/src/surface/emitter.zig`

- Exact file and line references:
  - Bounded owner and error surface: `emitter.zig:17-87`.
  - Emission owner and pass spine: `emitter.zig:89-153`.
  - Repeated fill-pass wrappers: `emitter.zig:245-287`.
  - Sprite/upload/create/publish spine: `emitter.zig:352-679`.
  - Small support/testing seam: `emitter.zig:713-784`.
  - Existing proof root: `emitter_test.zig:104-222, 267-1301` and `handle_test.zig:282-336`.
- Exact reference comparison:
  - Alacritty `display/content.rs:24-39, 153-185` keeps render preparation/output direct instead of introducing generic result managers.
  - Alacritty `glyph_cache.rs:17-25, 46-52, 191-245` keeps the renderer data path explicit: load, cache, return, no ownership-probing layer.
  - TigerBeetle `TIGER_STYLE.md:96-100, 109-126, 249-264` pressures bounded arrays, explicit counters, and direct hot/data-plane helpers.
  - Current `emitter.zig` matches that source pressure closely: `Limits` and `Emitter(comptime limits)` encode exact bounds (`emitter.zig:67-90`), `appendPreparedPass` keeps one emission spine (`143-152`), sprite uploads stay explicit (`352-530`), and `publishSurface` performs the final pointer fixup in one owner (`615-679`).
  - Compared to the references, there is no under-owned split pressure and no ambient genericity debt beyond the acceptable bounded comptime owner shape.
- Verdict: keep-large.
- Exact ugly/fake concepts to remove without splitting the owner:
  - At most collapse the four identical fill-pass wrappers `appendPreparedClears`, `appendPreparedBackgrounds`, `appendPreparedDecorations`, and `appendPreparedCursors` into one exact owner-true helper if the result is clearer.
  - At most remove the tiny `testing` pass-through wrappers at `emitter.zig:776-783` if tests can call clearer direct seams.
  - Keep `Emitter(comptime limits)`; here the generic encodes bounded storage shape and is already heavily proved by tests.
- Transitional or over-explanatory names:
  - None found that are strong enough to justify a rename. `appendPrepared*`, `publishSurface`, `resetPrepared`, and `ByteRange` all read directly against the owner behavior.
  - `RenderSurfaceEmissionFailure` is long but precise at the ABI seam, so no rename is justified.
- Exact changes that make the file read like one owner faster without splitting it:
  - Either leave it unchanged as an explicit no-op judgment, or collapse only the four identical fill-pass wrappers if that reduces top-level repetition without hiding control flow.
  - Keep `appendPreparedPass`, sprite admission/upload, and `publishSurface` as the visible top-down spine.
  - Do not invent extra helper layers; current directness is already close to the references.
- Required assertions:
  - Preserve publish-time pointer/count assertions at `emitter.zig:615-679`.
  - Preserve upload byte accounting assertions at `emitter.zig:386-400, 500-501, 518`.
  - If fill-pass wrappers are collapsed, preserve merge invariants in `tryMergePreparedFillCommand`.
- Required tests:
  - Keep existing `surface/emitter_test.zig` proof root.
  - Keep `surface/handle_test.zig` overflow callers that depend on `Limits{}` defaults.
- Non-goals:
  - No removal of bounded compile-time limits.
  - No surface ABI consequence change.
  - No resource lifetime policy change.
- Stop conditions:
  - Stop if the only proposed change is metric-driven shrinking.
  - Stop if a replacement abstraction is less direct than the current explicit arrays and counters.

## 5. `howl-render/src/text/raster/special_legacy_computing.zig`

- Exact file and line references:
  - Generated entrypoints and early helpers: `special_legacy_computing.zig:7-167`.
  - Option buckets: `special_legacy_computing.zig:169, 528-529`.
  - Bucket-driven draw logic: `special_legacy_computing.zig:171-337, 392-549`.
  - Geometry helpers and lookup tables: `special_legacy_computing.zig:570-766`.
- Exact reference comparison:
  - Ghostty `font/sprite/draw/special.zig:1-7, 13-72, 135-235` keeps special drawing in one file with direct draw verbs.
  - Current Howl file is owner-true as one special-raster owner.
  - Divergence is mainly TigerBeetle-law pressure: `SpriteShade` and `BranchNode` are generic option buckets rather than exact draw nouns.
- Verdict: keep-large.
- Exact ugly/fake concepts to remove without splitting the owner:
  - Delete `SpriteShade` and make `drawCheckerShade` exact in its arguments or split into exact owner-true draw verbs.
  - Delete `BranchNode` and prefer exact branch draw helpers instead of a boolean option bag.
  - Keep the large switch tables; they are direct protocol-to-raster mapping, not fake narration.
- Transitional or over-explanatory names:
  - `SpriteShade`: generic option bucket, not a sharp noun.
  - `BranchNode`: generic boolean bag, not a sharp draw noun.
  - `BranchEdge`, `AlphaCorner`, `SpriteEdge`: no rename pressure found; they are direct geometry nouns.
- Exact changes that make the file read like one owner faster without splitting it:
  - Replace option buckets with exact draw verbs and exact argument lists.
  - Keep the codepoint dispatch tables, geometry helpers, and raster math in one file so the reader sees one special-raster owner.
  - Add local assertions at degenerate-size boundaries so helper math reads as bounded owner code instead of optimistic raster math.
- Required assertions:
  - Add assertions for non-zero width/height where helper math assumes `width - 1` or `height - 1`.
  - Add assertions around branch/octant/sextant selector ranges if implementation touches those paths.
- Required tests:
  - No current test root was found for this file.
  - Slice must add targeted raster proof for the bucket-removal path only: at minimum one checker shade case, one branch node case, and one degenerate-size bound case.
- Non-goals:
  - No generated table rewrite.
  - No Unicode coverage expansion.
  - No visual redesign of legacy glyph shapes.
- Stop conditions:
  - Stop if bucket removal requires adding a wider generic options struct elsewhere.
  - Stop if proof can only be visual/manual and no bounded test can be added.

## 6. `howl-vt/src/parser.zig`

- Exact file and line references:
  - Action surface and parser state: `parser.zig:17-227`.
  - Central control spine: `parser.zig:295-338, 382-657`.
  - Small generic helper: `parser.zig:548-555`.
  - Existing parser proof: `parser.zig:672-779`.
- Exact reference comparison:
  - Ghostty `Parser.zig:49-80, 205-310` also keeps one parser owner and one ordered control spine.
  - Current Howl parser already follows the same core shape: exit, transition, entry stay centralized.
  - The remaining ugliness is minor: `bufferedPut(anytype)` and the transitional alias `CsiActionData` -> `CsiAction`.
- Verdict: keep-large.
- Exact ugly/fake concepts to remove without splitting the owner:
  - Delete `bufferedPut(self, control: anytype, byte: u8)` and inline exact DCS/APC/PM put handling.
  - Delete `CsiActionData` and publish `CsiAction` directly unless that makes the action definition less readable.
  - Keep `ParamKind`, `BufferedControlKind`, and the large `OscAction` union; they are protocol nouns, not fake scaffolding.
- Transitional or over-explanatory names:
  - `CsiActionData`: transitional alias name; reads like staging for the public noun.
  - `bufferedPut`: generic helper name; acceptable only if exact control-specific inline code is worse.
  - `ParamKind` and `BufferedControlKind`: no rename pressure found; they are exact parser protocol discriminants.
- Exact changes that make the file read like one owner faster without splitting it:
  - Keep the control spine centralized and delete only the tiny generic helper and transitional alias.
  - Make DCS/APC/PM data forwarding explicit at the exact branch where each control is active.
  - Leave `next`, `nextActive`, phase builders, and CSI/DCS assembly as the visible parser story.
- Required assertions:
  - Preserve active-control exclusivity assertions at `parser.zig:297, 429-469, 564-580`.
  - Preserve CSI/DCS boundary assertions at `parser.zig:626-645` and `477-487`.
  - Add no new phase helpers that split the control spine.
- Required tests:
  - Keep existing tests at `parser.zig:672-779`.
  - If `bufferedPut` is removed, keep explicit proof for DCS/APC/PM byte forwarding order.
- Non-goals:
  - No parser split.
  - No string-control policy change.
  - No protocol coverage expansion.
- Stop conditions:
  - Stop if any change threatens the centralized exit/transition/entry spine.
  - Stop if parser cleanup broadens into OSC/DCS protocol redesign.

Exact ranked sprint plan:

1. `howl-render/src/text/ft_hb/support.zig`
   Reason: clearest reference-backed ownership-probing generic debt, contained seam, existing focused tests.
2. `howl-linux-host/src/terminal/surface.zig`
   Reason: true large owner with obvious internal `anytype`/Ops narration and strong current tests.
3. `howl-render/src/text/shape/cluster.zig`
   Reason: owner-true file with removable assembly buckets and already excellent proof.
4. `howl-render/src/text/raster/special_legacy_computing.zig`
   Reason: owner-true file with clear TigerBeetle bucket debt, but it needs new proof.
5. `howl-render/src/surface/emitter.zig`
   Reason: mostly settled already; only pursue small narration cleanup if still source-backed after the first four slices.
6. `howl-vt/src/parser.zig`
   Reason: smallest visible ugliness and highest control-spine risk; leave last.

Full execution package:

## Slice 1 support direct-owner cleanup

- Slice name: `Slice 1 support direct-owner cleanup`
- Allowed files:
  - `howl-render/src/text/ft_hb/support.zig`
  - `howl-render/src/render_session.zig`
  - `howl-render/src/text/ft_hb/support_test.zig`
- Required shape:
  - Keep `FtHbSupport` as the sole state owner in `support.zig`.
  - Move context extraction to the render-session boundary.
  - Delete ownership-probing helpers `textState`, `configView`, `lockFt`, and `unlockFt`.
  - Change support internals to take explicit state/config inputs instead of `anytype`.
  - Do not add a new vague `Context`, `State`, `Options`, or `Info` bucket to replace the removed generics.
  - Keep external behavior and fallback order unchanged.
- Tests:
  - `howl-render/src/text/ft_hb/support_test.zig`
  - Required test names:
    - `provider loads fallback face for symbol glyph with primary present`
    - `ft hb state configures explicit retained cache and input capacities`
    - `shape run input assembly reuses retained bounded buffers`
- Non-goals:
  - No `glyph_raster.zig` redesign.
  - No cache policy change.
  - No font-session API redesign beyond what direct support ownership requires.
- Stop conditions:
  - Stop if generic removal requires inventing a replacement bucket with weaker ownership truth.
  - Stop if the change spreads into non-target render files outside the allowed list.
  - Stop if fallback behavior changes.
- Accountable session ids:
  - Orchestrator: `orch-2026-06-14-six-target-pragmatic-shape-01`
  - Researcher: `research-2026-06-14-six-target-pragmatic-shape-01`
  - Reviewer: `review-2026-06-14-six-target-pragmatic-shape-01`
- Receipt fields required on acceptance:
  - planning seed receipt: `117b860` `Seed six-target pragmatic-shape planning`
  - execution slice seed receipt: pending orchestrator seed
  - reviewer verdict receipt: pending
  - commit-hash receipt status: pending at planning time

## Slice 2 surface direct-owner cleanup

- Slice name: `Slice 2 surface direct-owner cleanup`
- Allowed files:
  - `howl-linux-host/src/terminal/surface.zig`
  - `howl-linux-host/src/terminal/surface_test.zig`
- Required shape:
  - Keep `Surface` as the one host-surface owner.
  - Remove internal `anytype`/`Ops` narration where the real owner is already `Surface` or `HowlTerm`.
  - Prefer direct owner code over `ContextDriveOps`, `ContextSubmitBackend`, and local generic present/clipboard helpers.
  - Inline or delete local request/result buckets that survive only as scaffolding after helper removal.
  - Preserve the centralized render/progress and submit/present spine.
- Tests:
  - `howl-linux-host/src/terminal/surface_test.zig`
  - Required test names:
    - `pending VT clipboard write follows OSC 52 policy`
    - `drive progress keeps per-terminal continuation admission until a later non-keep turn`
    - `inactive tab continuation re-enters from per-terminal continuation admission`
    - `present pending blocks submit path until host present ack`
    - `submit path runs once no host present is in flight`
    - `submit backend upload observes terminal mutex unlocked`
    - `render submit runs under terminal mutex after backend upload`
    - `host upload failure returns failed submit without render submit`
    - `prepared handle mutation after upload does not submit`
    - `resize success path submits full surface and acks matching present token`
    - `resize upload failure zeros host dimensions and retry submits same full frame`
    - `resize while present pending waits for matching ack before resized submit`
    - `complete present acks matching host-owned token once and clears`
    - `mismatched complete present does not ack or clear`
- Non-goals:
  - No surface split.
  - No event-loop redesign.
  - No input policy change.
  - No VT/render ABI change.
- Stop conditions:
  - Stop if direct helper removal forces a weaker test seam than the current proof.
  - Stop if mutex or submit/present control flow becomes less centralized.
  - Stop if the change spreads outside the allowed files.
- Accountable session ids:
  - Orchestrator: `orch-2026-06-14-six-target-pragmatic-shape-01`
  - Researcher: `research-2026-06-14-six-target-pragmatic-shape-01`
  - Reviewer: `review-2026-06-14-six-target-pragmatic-shape-01`
- Receipt fields required on acceptance:
  - planning seed receipt: `117b860` `Seed six-target pragmatic-shape planning`
  - execution slice seed receipt: pending orchestrator seed
  - reviewer verdict receipt: pending
  - commit-hash receipt status: pending at planning time

## Slice 3 cluster assembly cleanup

- Slice name: `Slice 3 cluster assembly cleanup`
- Allowed files:
  - `howl-render/src/text/shape/cluster.zig`
- Required shape:
  - Keep `cluster.zig` as one cluster/text-cache assembly owner.
  - Delete `InputRenderableAssembly` and `CellLineTextCacheAssembly`.
  - Keep `RetainedScratch` as the explicit bounded retained owner.
  - Rewrite direct build paths through scratch/local slices without moving ownership into a new helper file.
- Tests:
  - `howl-render/src/text/shape/cluster.zig`
  - Required test names:
    - `cell inputs build text cache renderable cells and clusters`
    - `cell inputs retain combining sequences in text cache`
    - `cell inputs preserve style and presentation into renderables and clusters`
    - `partial damage filters clean clusters before shaping`
    - `sparse cells keep only damaged base cells`
    - `sparse cells intern repeated codepoints`
    - `sparse cells keep empty background witnesses for scene ownership`
    - `rich cell text interning deduplicates codepoint sequences`
    - `rich cell text renderables resolve exact interned text ids`
    - `retained scratch bounds sparse cell assembly`
    - `retained scratch bounds rich input codepoint assembly`
- Non-goals:
  - No split into new files.
  - No lane classification change.
  - No text interning behavior change.
- Stop conditions:
  - Stop if a replacement helper just moves the same narration sideways.
  - Stop if `RetainedScratch` is targeted without new reference proof.
  - Stop if proof requires weakening current inline tests.
- Accountable session ids:
  - Orchestrator: `orch-2026-06-14-six-target-pragmatic-shape-01`
  - Researcher: `research-2026-06-14-six-target-pragmatic-shape-01`
  - Reviewer: `review-2026-06-14-six-target-pragmatic-shape-01`
- Receipt fields required on acceptance:
  - planning seed receipt: `117b860` `Seed six-target pragmatic-shape planning`
  - execution slice seed receipt: pending orchestrator seed
  - reviewer verdict receipt: pending
  - commit-hash receipt status: pending at planning time

## Slice 4 special legacy raster bucket cleanup

- Slice name: `Slice 4 special legacy raster bucket cleanup`
- Allowed files:
  - `howl-render/src/text/raster/special_legacy_computing.zig`
  - `howl-render/src/text/raster/special_test.zig`
- Required shape:
  - Keep `special_legacy_computing.zig` as one special-raster owner.
  - Remove `SpriteShade` and `BranchNode` option buckets.
  - Replace them with exact draw verbs or exact argument lists.
  - Add explicit degenerate-size assertions where width/height math assumes positive sizes.
- Tests:
  - `howl-render/src/text/raster/special_test.zig`
  - Required preserved test names:
    - `generated shade preserves fallback intensity levels`
    - `generated branch nodes preserve filled and unfilled variants`
  - Required added test names:
    - `generated legacy computing raster guards degenerate size bounds`
- Non-goals:
  - No Unicode coverage expansion.
  - No generated table rewrite.
  - No visual redesign beyond bucket removal.
- Stop conditions:
  - Stop if cleanup cannot be proved with bounded tests.
  - Stop if the replacement requires a new generic options bucket elsewhere.
  - Stop if the required test root cannot stay owner-true and single-purpose.
- Accountable session ids:
  - Orchestrator: `orch-2026-06-14-six-target-pragmatic-shape-01`
  - Researcher: `research-2026-06-14-six-target-pragmatic-shape-01`
  - Reviewer: `review-2026-06-14-six-target-pragmatic-shape-01`
- Receipt fields required on acceptance:
  - planning seed receipt: `117b860` `Seed six-target pragmatic-shape planning`
  - execution slice seed receipt: pending orchestrator seed
  - reviewer verdict receipt: pending
  - commit-hash receipt status: pending at planning time

## Slice 5 emitter pragmatic no-op or micro-cleanup

- Slice name: `Slice 5 emitter pragmatic no-op or micro-cleanup`
- Allowed files:
  - `howl-render/src/surface/emitter.zig`
  - `howl-render/src/surface/emitter_test.zig`
  - `howl-render/src/surface/handle_test.zig`
- Required shape:
  - Re-verify during execution that `emitter.zig` is still owner-true and direct.
  - If no clearer reference-backed cleanup survives, record an explicit no-op acceptance for this slice.
  - If a cleanup is still justified, limit it to collapsing the four identical fill-pass wrappers or removing tiny testing pass-through wrappers.
  - Keep `Emitter(comptime limits)` and all explicit bounded arrays/counters.
- Tests:
  - `howl-render/src/surface/emitter_test.zig`
  - `howl-render/src/surface/handle_test.zig`
  - Verification-only no-op path exact test names:
    - `render surface surface emitter coalesces adjacent prepared fill commands`
    - `render surface surface emitter does not coalesce distinct prepared fills`
    - `render surface surface emitter rejects command bound overflow`
    - `render surface surface emitter rejects upload bound overflow`
    - `render surface surface emitter rejects retire bound overflow`
    - `render surface surface emitter rejects upload byte total overflow`
    - `render surface surface emitter emits transient sprite beyond persistent budget`
    - `render surface surface emitter reports exact transient retire bound`
    - `prepared handle reports missing surface when render_surface emission overflows`
  - If a micro-cleanup is still justified, preserve exactly the same test list above with no widening.
- Non-goals:
  - No removal of compile-time bounds.
  - No resource lifetime policy change.
  - No ABI consequence change.
- Stop conditions:
  - Stop and convert to explicit no-op if cleanup is metric-only.
  - Stop if a replacement abstraction is less direct than current explicit arrays/counters.
  - Stop if tests would need widening just to justify a cosmetic rewrite.
- Accountable session ids:
  - Orchestrator: `orch-2026-06-14-six-target-pragmatic-shape-01`
  - Researcher: `research-2026-06-14-six-target-pragmatic-shape-01`
  - Reviewer: `review-2026-06-14-six-target-pragmatic-shape-01`
- Receipt fields required on acceptance:
  - planning seed receipt: `117b860` `Seed six-target pragmatic-shape planning`
  - execution slice seed receipt: pending orchestrator seed
  - reviewer verdict receipt: pending
  - commit-hash receipt status: pending at planning time

## Slice 6 parser minor directness cleanup

- Slice name: `Slice 6 parser minor directness cleanup`
- Allowed files:
  - `howl-vt/src/parser.zig`
- Required shape:
  - Keep parser control flow centralized in `next`, `nextActive`, `buildPhases`, `exitPhase`, `entryPhase`, and `doAction`.
  - Remove `bufferedPut(anytype)` if exact inline control handling is clearer.
  - Remove transitional `CsiActionData` if publishing `CsiAction` directly remains readable.
  - Do not split parser ownership or string-control protocol handling into extra files.
- Tests:
  - `howl-vt/src/parser.zig`
  - Required test names:
    - `parser control spine orders populated phase slots in one next call`
    - `parser keeps active string controls exclusive`
    - `parser assembles CSI params and separators`
    - `parser DCS hook stays on the hook boundary`
- Non-goals:
  - No parser split.
  - No OSC/DCS/APC/PM policy change.
  - No protocol expansion.
- Stop conditions:
  - Stop if any change threatens the centralized control spine.
  - Stop if cleanup broadens into protocol redesign.
  - Stop if generic removal does not make the file clearer on direct reading.
- Accountable session ids:
  - Orchestrator: `orch-2026-06-14-six-target-pragmatic-shape-01`
  - Researcher: `research-2026-06-14-six-target-pragmatic-shape-01`
  - Reviewer: `review-2026-06-14-six-target-pragmatic-shape-01`
- Receipt fields required on acceptance:
  - planning seed receipt: `117b860` `Seed six-target pragmatic-shape planning`
  - execution slice seed receipt: pending orchestrator seed
  - reviewer verdict receipt: pending
  - commit-hash receipt status: pending at planning time

Risks:

- `surface.zig` and `parser.zig` have obvious cleanup pressure, but both are control-spine owners. Cleanup must not buy neatness with extra indirection.
- `special_legacy_computing.zig` has clear bucket debt and an existing raster proof root, but it still needs one added degenerate-size test before broad cleanup.
- `emitter.zig` may be ugly only by metric. It is the most likely target to yield a low-change or stop verdict during execution.

Proof gaps:

- `special_legacy_computing.zig` already has an owner-true raster proof root in `howl-render/src/text/raster/special_test.zig`, but the current root still lacks the exact degenerate-size case this slice requires.
- I found no compelling reference-backed split for `surface.zig`, `emitter.zig`, or `parser.zig`; all three should stay large unless execution reveals a smaller true owner that the references already use.
- `support.zig` and `surface.zig` both have cleanup pressure that currently spans test seams; execution must prove the direct replacement is actually simpler, not just less generic.

Readiness judgment:

- Ready for execution.
- The sprint is fully mapped into owner-true judgments.
- The first slice is precise, reference-backed, low-risk relative to the set, and already has proof roots.
