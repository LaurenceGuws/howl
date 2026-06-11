Owner create post-cache-first plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-owner-create-post-cache-first-01`.
Reviewer session id: `review-2026-06-12-owner-create-post-cache-first-01`.
Planning commit-hash receipt: pending until archival.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-owner-create-post-cache-first-plan.md`
- Current evidence receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-005326-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-005338-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Execution authorized:
  - no implementation is authorized from this research pass

Problem statement

- The cache-first owner-create slice landed and improved Howl again, but the 10-second rerun still trails Alacritty badly.
- The current timing proof still puts `owner_create` on top after the accepted slice, so the next step is another source-backed plan inside the current true seam unless proof now shows a different owner.
- The next plan must explain which remaining owner-create subwork is real, which already-landed work is spent, and what the sharpest next slice is without drifting into host-side work or stale direct-normal assumptions.

Sources read in order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/orcestrator.md`
3. `/home/home/personal/projects/howl/loop/researcher.md`
4. `/home/home/personal/projects/howl/loop/reviewer.md`
5. `/home/home/personal/projects/howl/loop/coder.md`
6. `/home/home/personal/projects/howl/sprints/current.txt`
7. `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
8. `/home/home/personal/projects/howl/research/2026-06-12-owner-create-post-cache-first-plan.md`
9. `/home/home/personal/projects/howl/reference-index.md`
10. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
12. `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
13. `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
14. `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
15. `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
16. `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
17. `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`
18. `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
19. `/home/home/personal/projects/howl/howl-render/src/prepared/submit.zig`
20. `/home/home/personal/projects/howl/howl-render/src/prepared/submit_result.zig`
21. `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-005326-ascii/summary.json`
22. `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-005338-ascii/summary.json`
23. `/tmp/opencode/howl-render-debug-control.log`
24. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
25. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs`
26. `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
27. Navigation only: `/home/home/personal/projects/howl/research/done/2026-06-12-direct-normal-scan-bottleneck-plan.md`

Exact files and line references

- Active authority and current loop state:
  - `sprints/current.txt:12-30` points at this research file and says the active step is post-cache-first `owner_create` planning.
  - `sprints/2026-06-11-ascii-rain-honest-performance-sprint.md:49-62` requires each loop to stay inside the currently proved owner seam and to stop if a correctness issue or vague bucket appears.
  - `loops/ascii-rain-live-loop.txt:263-341` records the accepted cache-first slice, its exact verification commands, and the accepted before/after `owner_create` receipts.
  - `loops/ascii-rain-live-loop.txt:450-455` says the accepted slice improved Howl to `35.67 fps` vs Alacritty `1008.17 fps` and that `owner_create` remains the top bucket.
- Fresh performance receipts:
  - `utils/tools/rain-bench/artifacts/stress/20260612-005326-ascii/summary.json:45-84` records the 3-second Howl rerun at `34.1 fps` with final metrics.
  - `utils/tools/rain-bench/artifacts/stress/20260612-005338-ascii/summary.json:45-121` records the 10-second rerun at Howl `35.67 fps` and Alacritty `1008.17 fps` with final metrics for both terminals.
  - `/tmp/opencode/howl-render-debug-control.log:1-15` records the fresh timing lines: `prepared_handle_create emit_avg_us=1093`, `owner_create_avg_us=1094`, `sprites_avg_us=345`, `sprite_lookup_avg_us=56`, `stage_upload_avg_us=0`, `atlas_resource_avg_us=155`, `publish_avg_us=2`.
- Current owner seam and hot control flow:
  - `howl-render/src/session/text.zig:46-114` owns the current timing receipt and still reports `owner_create_avg_us` at the host-facing seam.
  - `howl-render/src/session/text.zig:529-535` measures `PreparedHandle.create` as the whole `owner_create` bucket.
  - `howl-render/src/session/text.zig:548-555` shows `render_surface_sprite_resources` is session-owned retained state and is reset only when text state is invalidated.
  - `howl-render/src/prepared/handle.zig:72-95` shows `PreparedHandle.create` does three things: allocate the handle, register it, then immediately emit a fresh render-surface payload.
  - `howl-render/src/prepared/handle.zig:184-195` shows the hot call is `payload.emitPreparedFresh(&self.session_owner.render_surface_sprite_resources, ...)`.
  - `howl-render/src/prepared/render_surface_emitter.zig:288-325` keeps `emitPrepared` transactional by copying both emitter state and the sprite-resource store before mutating them, then writing back only on success.
  - `howl-render/src/prepared/render_surface_emitter.zig:328-360` shows `emitPreparedFresh` still copies `resources.*` into `next_resources`, but records `copy_in_ns` and `copy_out_ns` as zero and therefore hides that cost from the timing receipt.
  - `howl-render/src/prepared/render_surface_emitter.zig:508-639` shows the post-cache-first sprite path already admits atlas/color reuse before staging upload bytes; reused paths now roll back staged bytes and skip uploads.
  - `howl-render/src/prepared/render_surface_emitter.zig:789-843` shows publish fixup is tiny and not the remaining bottleneck.
  - `howl-render/src/prepared/sprite_resource_store.zig:37-50` shows `SpriteResourceStore` is a large retained owner with fixed arrays for entries, bytes, atlas entries, and mutable admission metadata.
  - `howl-render/src/prepared/sprite_resource_store.zig:162-226` and `268-306` show the new cache-first admission helpers mutate only logical admission state and return `.reused`, `.persistent`, `.transient`, or atlas create/upload consequences.
- Existing proof roots and current test gap:
  - `howl-render/src/prepared/render_surface_emitter_test.zig:865-911` proves reuse across surfaces through `emitPrepared`.
  - `howl-render/src/prepared/render_surface_emitter_test.zig:913-961` proves the accepted cache-first slice for the reusable emitter path: second emission skips uploads for reused atlas and persistent color sprites.
  - `howl-render/src/prepared/render_surface_emitter_test.zig:1053-1168` proves `emitPrepared` preserves accepted resource/surface state on failure.
  - `howl-render/src/prepared/owner_test.zig:126-153` proves the fresh `PreparedHandle.create` path emits a realizable surface.
  - `howl-render/src/prepared/owner_test.zig:195-250` proves fresh create surfaces failure mapping, but does not yet prove fresh-path cache reuse or fresh-path resource-state rollback.
- Reference anchors:
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:46-79` keeps glyph-cache ownership separate from draw-path ownership.
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:117-123,200-245` shows cached glyph reuse is a direct lookup, not a copy of the whole cache owner.
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:14-31,72-140` shows atlas insertion uses explicit row metadata and in-place mutation, not whole-atlas duplication per insert.
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs:198-240` shows only the atlas placement metadata advances on successful insertion.
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-113,158-176,241-264` requires explicit bounds, assertions, and hot-loop directness instead of hidden broad copies.
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:96-101,179-185,221-229` says measurements confirm the model, but the model should still prefer direct hot-state mutation with explicit bounds over expensive structural copying.

Current-code facts

- The accepted cache-first slice already spent the obvious upload-byte waste. The fresh log now shows `stage_upload_avg_us=0`, so repeating that work is dishonest (`/tmp/opencode/howl-render-debug-control.log:1-15`; `render_surface_emitter.zig:535-567,589-615`).
- The `owner_create` bucket is still exactly `PreparedHandle.create`, and the `prepared_handle_create` timing line shows the remaining cost is almost entirely the fresh render-surface emission step, not allocation or registration (`session/text.zig:529-535`; `handle.zig:72-95`; `/tmp/opencode/howl-render-debug-control.log:2,5,8,11,14-15`).
- The emitter timing sub-buckets no longer add up to the total fresh emission cost. At the accepted 640-count line, `fills_avg_us=19`, `sprites_avg_us=345`, and `publish_avg_us=2`, but `prepared_handle_create emit_avg_us=1093` (`/tmp/opencode/howl-render-debug-control.log:13-15`). The missing cost is not vague runtime noise; current source shows `emitPreparedFresh` still performs `var next_resources = resources.*` before any sprite work while logging copy cost as zero (`render_surface_emitter.zig:328-360`).
- That by-value copy is large enough to matter. `SpriteResourceStore` owns fixed arrays for retained resource entries, a 64 KiB byte store, atlas entries, and mutable atlas/resource admission metadata (`sprite_resource_store.zig:37-50`). Copying the whole owner on every `PreparedHandle.create` is now a better match for the remaining hot bucket than the already-improved sprite staging path.
- The currently accepted correctness contract still matters. The reusable emitter path intentionally stages mutations into copied `next` and `next_resources` values so a failed emission leaves the previously accepted surface and resource state untouched (`render_surface_emitter.zig:288-325`; `render_surface_emitter_test.zig:1053-1168`).
- The fresh `PreparedHandle.create` path does not need to preserve a previous payload surface, because it creates a brand-new payload and maps failure to `render_surface_emission_failure` (`handle.zig:184-195`; `owner_test.zig:195-250`). It does still need to preserve the session-owned retained sprite-resource store on failure (`session/text.zig:548-555`).
- That makes the truthful next debt narrower than “optimize emitter.” The specific remaining debt is “stop whole-store cloning in `emitPreparedFresh` while keeping explicit rollback of retained sprite-resource admission state.”

Reference facts

- Alacritty keeps glyph-cache ownership and draw-path ownership separate; cached lookup returns a glyph entry directly instead of copying the entire cache owner into the draw path (`glyph_cache.rs:46-79,200-245`).
- Alacritty’s atlas owner advances only the row-placement metadata required for a successful insertion (`atlas.rs:14-31,72-140,198-240`). That is pressure toward a small, explicit retained-state checkpoint rather than a whole-owner copy when only logical admission metadata must be rolled back.
- TigerBeetle style rejects hidden hot-path bulk work when the real mutable owner state is smaller and explicit (`TIGER_STYLE.md:90-113,158-176,241-264`).
- TigerBeetle architecture says experiments prove the model but the code should still move directly through the true owner with explicit bounds (`ARCHITECTURE.md:96-101,179-185,221-229`). The current measurements plus current source point at retained sprite-resource admission state as the remaining hot owner debt inside `owner_create`.

Compact anchor map

- Stable reference anchors:
  - Alacritty glyph-cache lookup owner: `renderer/text/glyph_cache.rs:46-79,200-245`.
  - Alacritty atlas placement metadata owner: `renderer/text/atlas.rs:14-31,72-140,198-240`.
  - TigerBeetle hot-path directness and assertion law: `TIGER_STYLE.md:90-113,158-176,241-264`.
  - TigerBeetle explicit-state design pressure: `ARCHITECTURE.md:96-101,179-185,221-229`.
- Current Howl owner seams:
  - Host timing receipt seam: `howl-render/src/session/text.zig:46-114,529-535`.
  - Fresh owner-create control seam: `howl-render/src/prepared/handle.zig:72-95,184-195`.
  - Fresh emitter seam with hidden store copy: `howl-render/src/prepared/render_surface_emitter.zig:328-360`.
  - Post-cache-first sprite admission owner: `howl-render/src/prepared/render_surface_emitter.zig:508-639` plus `howl-render/src/prepared/sprite_resource_store.zig:162-226,268-306`.
  - Existing reusable-emitter proof roots only: `howl-render/src/prepared/render_surface_emitter_test.zig:865-1168`.
  - Missing fresh-path proof roots: `howl-render/src/prepared/owner_test.zig:126-250`.

Exact proof receipts being relied on

- 3-second Howl rerun:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-005326-ascii/summary.json`
  - final Howl FPS: `34.1`
- 10-second Howl vs Alacritty rerun:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-005338-ascii/summary.json`
  - final Howl FPS: `35.67`
  - final Alacritty FPS: `1008.17`
- Timing proof log:
  - `/tmp/opencode/howl-render-debug-control.log`
  - strongest accepted post-cache-first lines:
    - `howl-render-debug emit_prepared count=640 ... sprites_avg_us=345 sprite_lookup_avg_us=56 stage_upload_avg_us=0 atlas_resource_avg_us=155 ... publish_avg_us=2 ...`
    - `howl-render-debug prepared_handle_create count=640 ... emit_avg_us=1093 ...`
    - `howl-render-debug prepare_handle count=640 ... direct_normal_avg_us=949 ... owner_create_avg_us=1094 ...`

Owner roles and proposed shape

- `howl-render/src/session/text.zig` remains the host-facing timing and orchestration owner. It should keep reporting the bucket, not absorb emitter/resource-store policy.
- `howl-render/src/prepared/handle.zig` remains the fresh owner-create control owner. It should keep creating the fresh payload and mapping emission failure into a diagnostic, but it is not the right place to own retained sprite-resource rollback logic.
- `howl-render/src/prepared/render_surface_emitter.zig` is the true next worker seam. It owns `emitPreparedFresh`, so it should stop whole-owner cloning there and instead run the fresh emission directly against the true retained resource owner.
- `howl-render/src/prepared/sprite_resource_store.zig` is the only correct owner for any checkpoint/restore API used to preserve retained sprite-resource admission state on failure.
- Proposed shape for the next slice:
  - keep `emitPrepared` unchanged for the reusable-emitter path and its accepted failure-preservation tests;
  - change only `emitPreparedFresh` to mutate the retained sprite-resource store in place behind an explicit owner-local rollback receipt;
  - the rollback state must cover only the logical admission prefix and metadata needed to restore the exact pre-emission store state on error, not the whole fixed arrays;
  - preserve the already-landed cache-first admission order and all render-surface ABI consequences;
  - prove the fresh `PreparedHandle.create` path now reuses cached atlas/color resources without uploads on the second create and preserves retained state on failure.

Sprint scratchpad

- The truthful next slice is not another generic sprite optimization.
- The truthful next slice is: remove the hidden full `SpriteResourceStore` copy from the fresh `owner_create` path while preserving retained-store rollback on failure.
- The current reusable-emitter tests are necessary but insufficient because the hot host path is `emitPreparedFresh`, not `emitPrepared`.
- No host, GL, benchmark-wrapper, PTY, VT, or spent direct-normal work belongs in this slice.
- The current proof does not show a correctness blocker. It shows a measurement blind spot plus a clear owner-local hot copy.

Explicit ordered worker slice plan

1. Slice: `owner-create-fresh-resource-rollback`
   - Purpose:
     - remove whole-store cloning from fresh render-surface emission while preserving exact retained sprite-resource state on error.
   - Receipt fields:
     - coder session id
     - exact files changed
     - exact tests run
     - exact updated receipt paths
     - quoted timing lines from `/tmp/opencode/howl-render-debug-control.log`
     - exact before/after `owner_create_avg_us`, `prepared_handle_create emit_avg_us`, `sprites_avg_us`, and `atlas_resource_avg_us`
     - commit-hash handoff status pending orchestrator closure

Exact allowed files

- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter_test.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/owner_test.zig`

Not allowed:

- `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/submit.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/submit_result.zig`
- `/home/home/personal/projects/howl/utils/tools/rain-bench/*`
- host, GL, PTY, VT, ABI, or direct-normal files

Exact required shape

- Keep `PreparedHandle.create` and the host-facing ABI consequences unchanged.
- Keep `emitPrepared` on its current copy-and-commit shape for the reusable-emitter path.
- In `emitPreparedFresh`, stop copying the whole `SpriteResourceStore` value before emission.
- Add the smallest owner-true rollback mechanism in `sprite_resource_store.zig` that can restore the exact pre-emission retained admission state after a fresh-path error.
- The rollback mechanism must restore the logical prefix and metadata that define accepted retained state, including resource counts, byte counts, atlas counts, `atlas_resource`, resource id progression, atlas placement cursors, and last-hit hints.
- Do not reintroduce upload staging before cache admission.
- Do not add broad manager/context/state buckets or a second runtime layer.

Exact tests

- Required unit test command:
  - `zig build test:unit` in `/home/home/personal/projects/howl/howl-render`
- Required existing proof roots to keep green:
  - `render surface surface emitter persists prepared sprite resource across surfaces` (`render_surface_emitter_test.zig:865-911`)
  - `render surface surface emitter reused alpha atlas sprite skips uploads on second emission` (`render_surface_emitter_test.zig:913-936`)
  - `render surface surface emitter reused persistent color sprite skips uploads on second emission` (`render_surface_emitter_test.zig:938-961`)
  - `render surface surface emitter failure preserves accepted persistent resource state` (`render_surface_emitter_test.zig:1053-1069`)
  - `render surface surface emitter rejects missing prepared sprite without mutating accepted surface` (`render_surface_emitter_test.zig:1144-1168`)
  - `render surface prepared owner surface equals kitty dim rgba oracle` (`owner_test.zig:126-153`)
  - `prepared handle reports missing surface when render_surface emission overflows` (`owner_test.zig:195-210`)
- Required new tests:
  - add one owner-local test in `owner_test.zig` proving a second `PreparedHandle.create` on the same alpha prepared sprite emits zero uploads on the fresh path;
  - add one owner-local test in `owner_test.zig` proving a second `PreparedHandle.create` on the same persistent color sprite emits zero uploads on the fresh path;
  - add one emitter-owner test in `render_surface_emitter_test.zig` proving `emitPreparedFresh` restores the retained sprite-resource store state exactly after a forced error, including `atlas_resource`, atlas counts, byte counts, id progression, and last-hit hints.
- Required live verification commands:
  - `zig build install -Doptimize=ReleaseFast` in `/home/home/personal/projects/howl/howl-linux-host`
  - `zig build --release=fast stress:rain:build` in `/home/home/personal/projects/howl/utils/tools/rain-bench`
  - `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log` in `/home/home/personal/projects/howl`
  - `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty` in `/home/home/personal/projects/howl`
- Acceptance proof expectation:
  - `prepared_handle_create emit_avg_us` in `/tmp/opencode/howl-render-debug-control.log` must drop below the current accepted baseline `1093`.
  - `owner_create_avg_us` in `/tmp/opencode/howl-render-debug-control.log` must drop below the current accepted baseline `1094`.
  - the 10-second Howl vs Alacritty rerun must still complete with final metrics receipts for both terminals.

Exact non-goals

- No host-side runtime or GL work.
- No benchmark-wrapper or benchmark-main work.
- No new direct-normal work.
- No ABI or surface-contract changes.
- No fresh instrumentation outside the existing timing seam.
- No redesign of atlas packing, glyph lookup semantics, or text shaping owners.

Exact stop conditions

- Stop if preserving retained sprite-resource state honestly requires widening beyond the four allowed files.
- Stop if the current proof rerun shows `owner_create` is no longer the top bucket before the slice is finished.
- Stop if the only way to remove the fresh-path store copy is to weaken accepted failure semantics for the reusable emitter path.
- Stop if current tests expose a retained resource identity bug rather than a pure hot-copy debt.
- Stop if the timing rerun cannot move both `prepared_handle_create emit_avg_us` and `owner_create_avg_us` below their current accepted baselines `1093` and `1094` without changing semantics.

Required assertions

- Assert that any fresh-path rollback restores every retained admission field needed to define the accepted store prefix, including `atlas_resource`.
- Assert that restored counts and byte ranges stay within the fixed store bounds.
- Assert that successful fresh-path reuse still returns non-zero resource ids and keeps zero-upload behavior on the second create.
- Keep the existing positive-space assertions that upload ranges, upload counts, and atlas/resource ids remain valid inside `render_surface_emitter.zig`.

Risks

- The main implementation risk is an incomplete rollback that restores counts but not id progression or atlas cursor state, causing subtle later reuse bugs.
- A second risk is accidentally changing `emitPrepared` along with `emitPreparedFresh`, which would broaden the slice and threaten accepted failure-preservation behavior.
- A third risk is overfitting to the current receipt and chasing tiny sprite sub-buckets instead of removing the larger hidden store-copy debt.

Proof gaps

- The current timing log does not isolate the fresh-path resource-store copy directly. The proof is an inference from the gap between `emit_avg_us` and the logged emitter sub-buckets plus the current-source `resources.*` copy in `emitPreparedFresh` (`render_surface_emitter.zig:328-360`; `/tmp/opencode/howl-render-debug-control.log:13-15`).
- Existing automated tests prove reusable-emitter reuse and failure preservation, but they do not yet prove the same properties on the fresh `PreparedHandle.create` path (`render_surface_emitter_test.zig:865-1168`; `owner_test.zig:126-250`).
- I did not find a direct Alacritty analogue for Howl’s prepared-surface payload owner, so the reference pressure here is selective: explicit atlas/cache owner mutation and no whole-owner copying in the hot draw path.

Readiness judgment

- Ready.
- The next reviewer-acceptable worker slice is narrow, owner-true, and still inside the live `owner_create` seam.
- The only meaningful proof gap is measurement granularity: the fresh-path store-copy cost is code-proved and receipt-supported, but not separately logged today. That is not a blocker for the slice because the change can be accepted on existing timings plus the new fresh-path correctness tests.
