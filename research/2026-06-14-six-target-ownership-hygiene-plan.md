# Six-Target Ownership Hygiene Plan

Status:

- Active research artifact for planning.
- Orchestrator session id: `orch-2026-06-14-six-target-ownership-01`.
- Researcher session id: `research-2026-06-14-six-target-ownership-01`.
- Reviewer session id: `review-2026-06-14-six-target-ownership-01`.
- Reviewer accepted planning.
- No implementation is authorized from this file until the orchestrator seeds execution slices.
- Acceptance receipt: pending orchestrator commit.

Planning receipt:

- Planning seed receipt: `bbf5ca7` `Seed six-target ownership planning`.
- Commit-hash receipt status: documentation-only planning; no dedicated planning-acceptance commit yet.

## Sources Read In Order

1. `loop/flow.md`
2. `loop/orcestrator.md`
3. `loop/researcher.md`
4. `loop/reviewer.md`
5. `loop/coder.md`
6. `loop/researcher.md` reread
7. `sprints/current.txt`
8. `loops/six-target-ownership-hygiene-live-loop.txt`
9. `research/2026-06-14-six-target-ownership-hygiene-plan.md`
10. `reference-index.md`
11. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
12. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
13. `howl-render/src/text/shape/cluster.zig`
14. `howl-render/src/text/ft_hb/support.zig`
15. `howl-linux-host/src/terminal/surface.zig`
16. `howl-render/src/surface/emitter.zig`
17. `howl-render/src/surface/realizer.zig`
18. `howl-vt/src/parser.zig`
19. `howl-vt/src/parser/string_control.zig`
20. `howl-vt/src/parser/utf8.zig`
21. `howl-vt/src/parser/parse_table.zig`
22. `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig`
23. `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig`
24. `utils/dev_references/terminals/ghostty/src/Surface.zig`
25. `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
26. `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
27. `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
28. `howl-render/src/text/ft_hb/support_test.zig`
29. `howl-render/src/surface/emitter_test.zig`
30. `howl-render/src/surface/realizer_test.zig`
31. `howl-linux-host/src/terminal/surface_test.zig`
32. `howl-render/src/test_unit.zig`
33. `howl-render/build.zig`
34. `howl-linux-host/build.zig`
35. `howl-vt/build.zig`
36. `build.zig`

## Compact Anchor Map

Stable reference anchors:

- Ghostty parser stays a large parser owner, with parser state, bounded parameter/intermediate storage, and `next` as the central transition spine: `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig:187-242`, `248-310`.
- Ghostty keeps shaping-run construction in a dedicated run owner, separate from font-cache/state owners: `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:10-40`, `41-47`, `84-91`, `148-176`, `210-303`.
- Ghostty surface is a large aggregate owner for terminal runtime, renderer, input, IO thread, config, and focus state: `utils/dev_references/terminals/ghostty/src/Surface.zig:1-11`, `62-177`.
- Alacritty `WindowContext` is a large per-window owner for display, terminal, notifier, event queue, PTY loop, and focus/runtime state: `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:47-70`, `168-257`.
- Alacritty renderable-content prep is a dedicated owner seam for converting terminal truth into renderable cells and cursor state: `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-38`, `40-88`, `153-184`, `187-207`.
- Alacritty glyph cache keeps font keys, metrics, rasterizer state, and glyph-cache behavior together, not mixed with window/session runtime: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:42-79`, `81-99`, `191-245`, `271-317`.
- TigerBeetle pressure points for this sprint are explicit bounds, assertion density, central control flow, and anti-bucket ownership: `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:96-140`, `161-176`, `273-381`; architecture pressure for bounded, explicit owners: `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:189-229`, `281-307`.

Current owner seams under study:

- `howl-render/src/text/ft_hb/support.zig` currently mixes FT/HB face lifecycle, face-lookup primitives, metrics cache policy, provider/cache entrypoints, and shaping-input assembly in one owner: `35-58`, `100-120`, `150-375`, `382-719`.
- `howl-render/src/text/shape/cluster.zig` currently mixes text-cache assembly, renderable-cell assembly, cluster extraction, complex selection, and provisional run planning in one owner, while `howl-render/src/text/shape/run.zig` already exists as the run owner seam: `31-243`, `264-401`, `444-616`, `760-792`; `howl-render/src/text/shape/run.zig:4-47`, `67-130`.
- `howl-linux-host/src/terminal/surface.zig` is already an aggregate surface/runtime owner that delegates layout/input/scroll/selection subowners instead of owning their internals: `52-119`, `193-345`, `415-733`.
- `howl-render/src/surface/emitter.zig` is a bounded ABI-surface emission owner with no second runtime seam hiding inside it: `67-87`, `89-153`, `467-679`.
- `howl-render/src/surface/realizer.zig` is a bounded ABI-surface validation and realization owner with retained-store truth checks: `37-85`, `87-335`, `543-659`.
- `howl-vt/src/parser.zig` already pushes subowners down into `parse_table`, `string_control`, and `utf8`, leaving one central parser control spine, but currently lacks parser-owner-local tests in the file itself: `1-4`, `231-243`, `296-338`, `382-657`; compare current direct VT proofs in `howl-vt/src/parser/utf8.zig:55-87`, `howl-vt/src/osc.zig:64-93`, `howl-vt/src/dcs.zig:48-60`, `howl-vt/src/howl_vt.zig:18-30`.

## Target Evaluations

### 1. `howl-render/src/text/shape/cluster.zig`

Current-code facts:

- The file starts with ownership wrappers and retained scratch for texts, renderables, clusters, and runs, not cluster-only behavior: `13-170`.
- It builds text caches from plain cells and rich inputs: `264-401`.
- It builds renderable cells from plain cells and rich inputs: `444-476`.
- It extracts clusters and complex selections: `487-616`.
- It also builds provisional runs from clusters: `760-792`.
- The tests at the bottom prove all of those responsibilities inside the same file: `862-1187`.

Reference comparison:

- Alacritty keeps renderable-content preparation in a dedicated content owner: `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-38`, `153-207`.
- Ghostty keeps run construction in a dedicated run owner: `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:41-47`, `84-91`, `210-303`.
- Howl already has `howl-render/src/text/shape/run.zig` as the run owner seam for run nouns, run windows, and shaped-run ownership: `howl-render/src/text/shape/run.zig:4-47`, `67-161`.
- Current `cluster.zig` crosses the existing Howl run seam, so the cut can land in a proven owner instead of inventing a new one.

Owner judgment:

- Cut.

Exact reason:

- This is not a split-because-big call. The file owns at least one proven extra seam: provisional run planning. Ghostty's run seam gives direct evidence that run construction does not belong inside a cluster owner.

Proposed child-owner path and symbol movement:

- Do not invent a new file. Land the cut in the existing run owner: `howl-render/src/text/shape/run.zig`.
- Move `cluster.zig:72-80`, `760-804` into `run.zig` as run-owner symbols:
  - rename `OwnedRuns` to `OwnedProvisionalRuns`
  - move `buildProvisionalRuns`
  - move `buildProvisionalRunsScratch`
  - move `resolvedRun`
- Add run-local scratch ownership in `run.zig` for provisional run planning, instead of keeping run scratch inside `cluster.RetainedScratch`:
  - remove `runs: []contract.ResolvedRun` from `cluster.RetainedScratch` at `cluster.zig:111-169`
  - add `RetainedProvisionalRunScratch` in `run.zig` with explicit run-only storage and bounds
  - change `buildProvisionalRunsScratch` to take `*RetainedProvisionalRunScratch`, so no cluster scratch dependency survives the cut
- Keep text-cache assembly, renderable assembly, cluster extraction, and complex selection in `cluster.zig` for now. A broader cut would need fresh reference proof.

Required assertions:

- Assert non-empty cluster input before reading `clusters[0]` in the non-empty path.
- Preserve scratch-capacity assertions before writing run output.
- Assert run boundaries advance monotonically and cover the full cluster slice exactly once.

Required tests:

- Preserve the existing run segmentation proof for style/presentation transitions: current coverage at `913-946`.
- Preserve the basic cluster-to-run count proof: current coverage at `867-892`.
- Preserve or add explicit run-scratch overflow proof equivalent to the current retained-scratch bounds posture if run-local scratch becomes owner-local in `run.zig`.
- Add an owner-local empty-input proof if the moved owner no longer reuses the existing empty-input branch transitively.
- Verification command: `zig build test:unit` in `howl-render`.

Stop conditions:

- Stop if the slice starts moving renderable/text-cache assembly too; that broader cut needs new reference proof.
- Stop if the cut cannot remove run scratch from `cluster.RetainedScratch` cleanly.
- Stop if the move requires files outside `cluster.zig`, `run.zig`, and existing render unit proof files.
- Stop if the only way to finish is inventing a new file or bucket owner instead of using `shape/run.zig`.

Sprint ranking:

- 2.

### 2. `howl-render/src/text/ft_hb/support.zig`

Current-code facts:

- `FtHbSupport` owns allocator, FT/HB handles, mutexes, fallback handles, resolve counters, caches, shaping scratch buffers, cached cell metrics, and fallback font path storage in one struct: `35-58`.
- The file uses generic `anytype` owner adapters for `textState`, `configView`, `lockFt`, and `unlockFt`: `100-120`.
- Provider entrypoints own cache lookup and shaping dispatch: `150-375`.
- The same file also owns primary/fallback face loading, reset, resize, metrics derivation, face acquisition, glyph acceptance, face metrics math, and fallback slot mapping: `382-699`, `731-826`.
- The current direct tests cover fallback-face loading, retained input-capacity configuration, and shape-input overflow only: `howl-render/src/text/ft_hb/support_test.zig:20-101`.

Reference comparison:

- Alacritty glyph cache keeps font keys, metrics, rasterizer state, and glyph-cache behavior in one dedicated font/cache owner, not mixed with outer session/provider glue: `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:42-79`, `81-99`, `191-245`, `271-317`.
- Ghostty keeps run assembly in a separate run owner, reinforcing that FT/HB support should not also own every shaping-adjacent seam: `utils/dev_references/terminals/ghostty/src/font/shaper/run.zig:41-47`, `210-303`.
- Current `support.zig` mixes at least two proven owners: loaded-face lifecycle and face lookup on one side, and outer session/provider/cache orchestration on the other. Metrics cache policy is adjacent, but not necessary to move in Slice 1.

Owner judgment:

- Cut.

Exact reason:

- The cut is source-backed by mixed ownership, not line count. The file currently owns loaded-face lifecycle and face lookup while also owning provider/session cache flow and shaping-input assembly. The repair narrows the move so the child owner is truly a loaded-face owner rather than a broader font-policy owner.

Proposed child-owner path and symbol movement:

- New child owner path: `howl-render/src/text/ft_hb/loaded_faces.zig`.
- Move the true loaded-face state into `LoadedFaces`, not the metrics cache policy:
  - `ThreadMutex`
  - state fields now living in `FtHbSupport` at `support.zig:37-43`, `56-57`: `ft_lib`, `ft_face`, `hb_font`, `ft_mutex`, `fallback_faces`, `fallback_hb_fonts`, `fallback_font_paths`, `fallback_font_paths_len`
- Move only the face-lifecycle and face-lookup behavior from `support.zig:382-699`, `731-826`:
  - `ensurePrimaryFont`
  - `resetLoadedFace`
  - `resizeLoadedFaces`
  - `ensureFallbackFace`
  - `ShapingFace`
  - `acquireShapingFaceLocked`
  - `shapeGlyphId`
  - `ensureFreeTypeLibraryLocked`
  - `selectUnicodeCharmap`
  - `ensureFaceForId`
  - `glyphAcceptedLocked`
  - `setFacePixelHeight`
  - `resetFallbackFaces`
  - `fallbackSlot`
- Keep these outer-session behaviors in `support.zig` because they are cache/policy/math owners, not loaded-face lifecycle owners:
  - `ensureFont`
  - `deriveCellMetrics`
  - `configuredCellMetrics`
  - `deriveCellSize`
  - `computeBaselineFromFace`
  - `providerGlyphVisualWidth`
  - `glyphVisualWidthPxLocked`
  - `glyphAdvanceFromFace`
  - `cellMetricsFromFace`
  - `faceMetricsInput`
  - `asciiCellAdvance`
  - `useDeterministicTestTextFallback`
  - `defaultCellMetrics`
  - `defaultBoxThickness`
  - `baselineFromFaceMetrics`
  - `advancePx`
  - `cellMetricsFromFaceMetrics`
- Keep `FtHbSupport` as the outer session-support owner for resolve counters, caches, shaping-input scratch, and cached cell-metrics policy.

Required assertions:

- Assert fallback-path count stays `<= max_fallback_fonts` at the `LoadedFaces` owner boundary.
- Assert fallback-slot mapping never indexes past configured fallback paths.
- Preserve paired assertions around reset so HB fonts and FT faces are torn down together.
- Preserve or add an assertion that a loaded shaping face always returns a matching HB font lifetime for the chosen FT face.

Required tests:

- Preserve existing proofs in `support_test.zig:20-101`.
- Add direct owner-local proofs for fallback-slot bounds and loaded-face reset/resize behavior only if those behaviors become newly hidden behind `LoadedFaces`.
- Keep metrics-cache invalidation proof in `support_test.zig`, because that cache policy remains in `support.zig` under this repaired plan.
- Verification command: `zig build test:unit` in `howl-render`.

Stop conditions:

- Stop if the cut requires new public render-session API or C ABI churn.
- Stop if the slice starts moving metrics cache policy, resolve-stage policy, or shaping-cache policy into `loaded_faces.zig`; that would break the repaired owner boundary.
- Stop if the new owner cannot stay limited to loaded-face lifecycle and face lookup.

Sprint ranking:

- 1.

### 3. `howl-linux-host/src/terminal/surface.zig`

Current-code facts:

- `Surface` owns terminal/runtime/display/session state in one aggregate: `52-119`.
- Public methods mostly delegate input, layout, scrollbar, title, cursor-blink, and runtime obligations to narrower owners: `193-345`.
- Runtime bootstrap and PTY/startup ownership live here: `415-446`, `714-812`.
- Render-turn driving and submit/present sequencing also stay here: `521-669`, `824-849`.
- Owner-local tests target clipboard policy, progress continuation, and other surface behavior through explicit test seams: `howl-linux-host/src/terminal/surface_test.zig:37-84`, `155-201`.

Reference comparison:

- Alacritty `WindowContext` is a large per-window owner for PTY, display, terminal, notifier, and runtime state: `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:47-70`, `168-257`.
- Ghostty `Surface` is also a large aggregate owner for renderer, IO threads, input, config, and focus/runtime state: `utils/dev_references/terminals/ghostty/src/Surface.zig:1-11`, `62-177`.
- Current Howl `Surface` already delegates real child seams instead of hoarding their internals.

Owner judgment:

- Keep large.

Exact reason:

- This is reference-shaped host/runtime aggregation, not false concentration. Cutting it just because it is large would fight both Alacritty and Ghostty.

Proposed child-owner path and symbol movement:

- None. Hard stop: do not cut this target in the sprint.

Required assertions:

- No ownership cut required. Preserve present/submit and continuation assertions if touched later.

Required tests:

- No new ownership tests required for this sprint.
- Existing proof surface already includes `howl-linux-host/src/terminal/surface_test.zig` under `zig build test:unit` in `howl-linux-host`.

Stop conditions:

- Stop immediately if a coder proposes splitting runtime/render/input control flow out of `Surface` without stronger reference proof.

Sprint ranking:

- 3, but hold as keep-large and do not schedule.

### 4. `howl-render/src/surface/emitter.zig`

Current-code facts:

- The file defines bounded emission limits and asserts those ABI bounds at comptime: `17-25`, `67-87`.
- `Emitter(limits)` owns the full bounded command/create/upload/glyph/retire staging arrays and counts: `89-110`.
- `emitPrepared*` and `appendPreparedPass` own the one-way transformation from prepared render surface to C ABI surface payload: `120-153`.
- The rest of the file is direct bounded emission work and final publication, not a second runtime seam: `211-679`.
- Tests are extensive and behavior-focused in `howl-render/src/surface/emitter_test.zig:104-122`, `266-309` and beyond.

Reference comparison:

- There is no stronger Alacritty/Ghostty one-to-one ABI-surface emitter shape to override this with.
- TigerBeetle pressure favors explicit bounded arrays, direct control flow, and publish-time assertions, which this file already shows: `17-25`, `154-209`, `615-679`.

Owner judgment:

- Keep large.

Exact reason:

- This is one owner: emitting a retained prepared surface into the ABI surface packet. The helper functions are all data-plane pieces of that same owner.

Proposed child-owner path and symbol movement:

- None. Hard stop: do not cut this target in the sprint.

Required assertions:

- No ownership change required. Preserve current publish-time bound assertions if the file is edited later.

Required tests:

- No new ownership tests required for this sprint.
- Existing render-unit coverage already exercises emitter behavior through `emitter_test.zig` and `surface/handle_test.zig`.

Stop conditions:

- Stop if a proposed cut introduces an abstraction layer between prepared-surface emission and the ABI surface packet.

Sprint ranking:

- 5, but hold as keep-large and do not schedule.

### 5. `howl-render/src/surface/realizer.zig`

Current-code facts:

- `realizeWithStore` owns the surface gate: pixel-length validation, retained-store transition validation, clear/base-copy decision, command dispatch, and retained commit: `45-85`.
- Validation is explicit and organized by ABI surface subspan: damage, create, retire, upload, command: `87-335`.
- Drawing is explicit and stays inside the same ABI surface contract owner: `336-788`.
- Tests are broad and hostile, covering both successful realization and invalid ABI payload rejection: `howl-render/src/surface/realizer_test.zig:40-148`, `150-320`.

Reference comparison:

- There is no upstream render-surface ABI validator/realizer reference that proves a narrower split here.
- TigerBeetle pressure favors keeping the contract gate and execution consequences in one explicit owner when they prove the same ABI truth.

Owner judgment:

- Keep large.

Exact reason:

- Validation and realization are the two halves of one ABI realizer owner. Splitting them without stronger proof would duplicate truth about visibility, upload coverage, and resource lifetime.

Proposed child-owner path and symbol movement:

- None. Hard stop: do not cut this target in the sprint.

Required assertions:

- No ownership cut required. Preserve the create/upload/retire visibility assertions if edited later.

Required tests:

- No new ownership tests required for this sprint.
- Existing `realizer_test.zig` already gives the relevant proof surface.

Stop conditions:

- Stop if a proposed cut separates validation from draw execution but leaves duplicated resource-visibility truth behind.

Sprint ranking:

- 6, but hold as keep-large and do not schedule.

### 6. `howl-vt/src/parser.zig`

Current-code facts:

- The file already delegates stable child seams into `parse_table`, `string_control`, and `utf8`: `1-4`.
- `Parser` owns parser state, bounded CSI storage, and active string-control owners: `231-243`.
- `next`, `nextActive`, `feedActiveByte`, and phase builders keep the transition control spine centralized: `296-338`, `382-475`.
- Parameter parsing and CSI dispatch stay in the parser owner rather than leaking into side helpers: `599-657`.
- String-control buffering is already broken out into `parser/string_control.zig`, which proves the file has already taken the main obvious subowner cut.
- The package currently has direct child-owner tests for `utf8`, `osc`, and `dcs`, but no parser-owner-local proof for phase ordering, active-control exclusivity, or CSI/DCS boundary assembly in `parser.zig` itself: `howl-vt/src/parser/utf8.zig:55-87`, `howl-vt/src/osc.zig:64-93`, `howl-vt/src/dcs.zig:48-60`.

Reference comparison:

- Ghostty's parser is also a large owner with central parser state and transition control flow: `utils/dev_references/terminals/ghostty/src/terminal/Parser.zig:187-242`, `248-310`.
- Current Howl parser already mirrors that shape by pushing UTF-8 and string-control buffer ownership into child files while keeping the state machine spine local.
- No stronger reference argues for another structural cut here. The missing pressure is proof, not ownership shape.

Owner judgment:

- Keep large.

Exact reason:

- This target is large but reference-shaped and owner-true. The main subowner cuts already happened. The remaining deficiency is hygiene: parser-owner-local proof is missing, so the sprint should add that proof instead of forcing a structural cut.

Proposed child-owner path and symbol movement:

- None. Hard stop: do not cut this target in the sprint.

Required assertions:

- No ownership cut required. Preserve the active-control-count assertions and bounded CSI/intermediate assertions if edited later.

Required tests:

- Add parser-owner-local inline tests in `howl-vt/src/parser.zig` covering at minimum:
  - phase ordering across exit/transition/entry actions
  - active-control exclusivity (`activeControlCount() <= 1`)
  - CSI parameter and separator assembly
  - DCS hook payload boundary behavior
- Preserve the existing child-owner proofs in `parser/utf8.zig`, `osc.zig`, and `dcs.zig`.
- Verification command: `zig build test:unit` in `howl-vt`.

Stop conditions:

- Stop if a proposed cut tries to split the parser transition spine itself rather than a proven child seam.

Sprint ranking:

- 3, as a keep-large proof slice rather than a structural cut.

## Exact Ranked Sprint Plan

1. Slice 1: cut loaded-face lifecycle and face-lookup ownership out of `howl-render/src/text/ft_hb/support.zig` into `howl-render/src/text/ft_hb/loaded_faces.zig`.
2. Slice 2: cut provisional-run planning out of `howl-render/src/text/shape/cluster.zig` into the existing run owner `howl-render/src/text/shape/run.zig`, with run-local scratch moved out of `cluster.RetainedScratch`.
3. Slice 3: keep `howl-vt/src/parser.zig` large, but add parser-owner-local proof inline in `parser.zig` so the keep-large judgment is directly proved.
4. Stop the sprint after Slice 3 unless new current-source plus reference proof re-promotes one of the remaining keep-large targets.

Do not schedule execution slices for:

- `howl-linux-host/src/terminal/surface.zig`
- `howl-render/src/surface/emitter.zig`
- `howl-render/src/surface/realizer.zig`

The unscheduled keep-large targets are explicitly judged owner-true for this sprint:

- `howl-linux-host/src/terminal/surface.zig`
- `howl-render/src/surface/emitter.zig`
- `howl-render/src/surface/realizer.zig`

## Execution Slice Queue

### Slice 1

- Slice 1: `ft_hb` loaded-face owner cut.

Allowed files:

- `howl-render/src/text/ft_hb/support.zig`
- `howl-render/src/text/ft_hb/loaded_faces.zig`
- `howl-render/src/text/ft_hb/support_test.zig`

Required shape:

- Add a true child owner in `loaded_faces.zig` for FT/HB primary/fallback face lifecycle and face lookup only.
- Move only the lifecycle and lookup symbols listed in the repaired Slice 1 target section above.
- Keep cached metrics policy, resolve-stage policy, provider cache policy, and shaping-input scratch in `support.zig` under `FtHbSupport`.
- Replace the mixed owner shape with delegation from `support.zig` to the new loaded-face owner.
- Preserve behavior for fallback loading, deterministic test fallback, and metrics derivation.
- No C ABI change, no package-root export change, no host-facing API churn.

Required tests:

- `zig build test:unit` in `howl-render`.

Non-goals:

- No shaping-cache redesign.
- No run-builder cut in the same slice.
- No benchmark work.
- No fallback-policy change.
- No new generic helper or bucket owner.
- No movement of cached metrics policy into `loaded_faces.zig`.

Stop conditions:

- Stop if the cut requires touching files outside the allowed set.
- Stop if the new owner cannot stay limited to face lifecycle and face lookup without pulling policy with it.
- Stop if preserving behavior would require public render-session or ABI churn.

Session ids:

- Orchestrator session id: `orch-2026-06-14-six-target-ownership-01`
- Researcher session id: `research-2026-06-14-six-target-ownership-01`
- Reviewer session id: `review-2026-06-14-six-target-ownership-01`
- Planning seed receipt: `bbf5ca7` `Seed six-target ownership planning`

Receipt fields required in the seeded execution contract:

- orchestrator session id
- researcher session id
- reviewer session id
- coder session id
- planning seed receipt `bbf5ca7`
- accepted planning receipt status
- commit-hash handoff required on slice acceptance
- required verification result: `zig build test:unit` in `howl-render`

### Slice 2

Slice name:

- Slice 2: cluster run-planning cut into existing `shape/run.zig` owner.

Allowed files:

- `howl-render/src/text/shape/cluster.zig`
- `howl-render/src/text/shape/run.zig`

Required shape:

- Do not create a new owner file.
- Move provisional run planning from `cluster.zig` into `run.zig`, because `run.zig` is already the run owner.
- Rename `OwnedRuns` to `OwnedProvisionalRuns` during the move so the run-owner vocabulary is explicit and does not collide with shaped-run owners already in `run.zig`.
- Move `buildProvisionalRuns`, `buildProvisionalRunsScratch`, and `resolvedRun` into `run.zig`.
- Add run-local scratch ownership in `run.zig` as `RetainedProvisionalRunScratch` and remove run scratch storage from `cluster.RetainedScratch`.
- Leave `cluster.zig` owning text-cache assembly, renderable assembly, cluster extraction, and complex selection only.
- No C ABI change, no package-root export change, no render-session policy change.

Required tests:

- `zig build test:unit` in `howl-render`.
- Preserve or relocate the current run proofs from `cluster.zig:867-892`, `913-946` into owner-true inline tests after the move.
- Preserve or add run-scratch overflow proof under the new run-local scratch owner.

Non-goals:

- No new `provisional_run.zig` file.
- No movement of text-cache assembly or renderable-cell assembly out of `cluster.zig`.
- No font-resolution work.
- No shape-run behavior change in `run.zig` beyond owning provisional run planning.
- No generic scratch bucket shared back across owners.

Stop conditions:

- Stop if the slice cannot remove `ResolvedRun` scratch ownership from `cluster.RetainedScratch` cleanly.
- Stop if the move requires touching files outside the allowed set.
- Stop if the only viable outcome is inventing a new file instead of using `run.zig`.
- Stop if moved tests cannot remain reachable through the existing render unit root without adding a new test root.

Session ids:

- Orchestrator session id: `orch-2026-06-14-six-target-ownership-01`
- Researcher session id: `research-2026-06-14-six-target-ownership-01`
- Reviewer session id: `review-2026-06-14-six-target-ownership-01`
- Planning seed receipt: `bbf5ca7` `Seed six-target ownership planning`

Receipt fields required in the seeded execution contract:

- orchestrator session id
- researcher session id
- reviewer session id
- coder session id
- planning seed receipt `bbf5ca7`
- accepted planning receipt status
- commit-hash handoff required on slice acceptance
- required verification result: `zig build test:unit` in `howl-render`

### Slice 3

Slice name:

- Slice 3: parser keep-large proof hygiene.

Allowed files:

- `howl-vt/src/parser.zig`

Required shape:

- Keep `parser.zig` structurally large and owner-true.
- Add parser-owner-local inline tests in `parser.zig` proving the control spine directly.
- Do not cut new parser child files.
- Do not move UTF-8 or string-control logic back into `parser.zig`.
- Use inline tests only so the VT package keeps its current curated test root shape.

Required tests:

- `zig build test:unit` in `howl-vt`.
- Inline tests must prove at minimum:
  - exit/transition/entry phase ordering
  - active-control exclusivity
  - CSI parameter and separator assembly
  - DCS hook boundary behavior

Non-goals:

- No parser ownership cut.
- No parse-table redesign.
- No new test root.
- No protocol feature expansion.
- No benchmark or simulation work in this slice.

Stop conditions:

- Stop if direct parser-owner-local proof cannot be added within `parser.zig`.
- Stop if the slice requires touching files outside the allowed set.
- Stop if the work drifts from proof into parser architecture redesign.

Session ids:

- Orchestrator session id: `orch-2026-06-14-six-target-ownership-01`
- Researcher session id: `research-2026-06-14-six-target-ownership-01`
- Reviewer session id: `review-2026-06-14-six-target-ownership-01`
- Planning seed receipt: `bbf5ca7` `Seed six-target ownership planning`

Receipt fields required in the seeded execution contract:

- orchestrator session id
- researcher session id
- reviewer session id
- coder session id
- planning seed receipt `bbf5ca7`
- accepted planning receipt status
- commit-hash handoff required on slice acceptance
- required verification result: `zig build test:unit` in `howl-vt`

## Risks

- `loaded_faces.zig` is now narrowed to a true lifecycle owner, but reviewer pressure is still needed on whether face-lookup helpers and lifecycle belong together at that seam.
- `cluster.zig` still has more mixed ownership than Slice 2 removes. The plan is intentionally incremental to avoid invention.
- `parser.zig` now has a proof slice, but until Slice 3 lands the keep-large judgment is not fully closed by direct owner-local tests.

## Proof Gaps

- No direct upstream reference gives an exact ABI-surface emitter/realizer file split, so both keep-large judgments rely on ABI-owner reasoning plus TigerBeetle pressure rather than line-for-line upstream mimicry.
- `support.zig` tests currently do not directly prove loaded-face reset/resize behavior apart from the existing fallback-loading proof; Slice 1 should add proof only where lifecycle behavior becomes newly hidden.
- `cluster.zig` currently proves run behavior inline; Slice 2 must preserve those proofs when moving run ownership into `run.zig`.
- `parser.zig` still lacks direct owner-local proof today; Slice 3 is required to close that gap.

## Readiness Judgment

- Ready for reviewer pass.
- If accepted, exact execution work should be limited to three slices: Slice 1 `ft_hb` loaded-face lifecycle cut, Slice 2 cluster run-planning move into `shape/run.zig`, then Slice 3 parser keep-large proof hygiene.
- `howl-linux-host/src/terminal/surface.zig`, `howl-render/src/surface/emitter.zig`, and `howl-render/src/surface/realizer.zig` remain settled as keep-large for this sprint unless new reference-backed evidence appears.
