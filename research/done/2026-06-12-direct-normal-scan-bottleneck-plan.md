Direct normal scan bottleneck plan

Historical authority at the time: active researcher plan for the `direct_normal_scan` bottleneck after the first current-tree proof cycle.
Why superseded or done: the `direct-normal-single-pass-publication` slice landed, was remeasured, and the top bucket moved to `owner_create`.
Must not be used for: current active planning after the `20260612-002709-ascii` rerun.

Date: 2026-06-12.
Status: archived reviewer-accepted planning package.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-direct-normal-scan-plan-01`.
Reviewer session id: `review-2026-06-12-direct-normal-scan-plan-01`.
Planning commit-hash receipt: pending until archival.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-direct-normal-scan-bottleneck-plan.md`
- Current evidence receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-000332-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-000755-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Execution authorized:
  - no implementation is authorized from this research pass

Problem statement

- The current control run proves Howl is still far slower than Alacritty on the decoupled ASCII-rain harness.
- The current bottleneck proof shows the strongest logged cost is `direct_normal_scan` inside the text prepare path.
- The next step is to turn that evidence into a reviewer-accepted worker slice that attacks the true owner seam in pristine shape without drifting into host-side distractions or vague bucket work.

Sources read in order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/orcestrator.md`
3. `/home/home/personal/projects/howl/loop/researcher.md`
4. `/home/home/personal/projects/howl/loop/reviewer.md`
5. `/home/home/personal/projects/howl/loop/coder.md`
6. `/home/home/personal/projects/howl/sprints/current.txt`
7. `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
8. `/home/home/personal/projects/howl/research/2026-06-12-direct-normal-scan-bottleneck-plan.md`
9. `/home/home/personal/projects/howl/reference-index.md`
10. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
11. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
12. `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
13. `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-000332-ascii/summary.json`
14. `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-000755-ascii/summary.json`
15. `/tmp/opencode/howl-render-debug-control.log`
16. `/home/home/personal/projects/howl/utils/tools/rain-bench/README.md`
17. `/home/home/personal/projects/howl/utils/tools/rain-bench/benchmark_terminals.py`
18. `/home/home/personal/projects/howl/utils/tools/rain-bench/build.zig`
19. `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
20. `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
21. `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
22. `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`
23. `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
24. `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
25. `/home/home/personal/projects/howl/howl-render/build.zig`
26. `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig`
27. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
28. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
29. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
30. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
31. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`

Exact files and line references

- Active loop and sprint authority:
  - `sprints/current.txt:12-30` seeds this exact research file and says the active step is researcher/reviewer planning for the `direct_normal_scan` evidence.
  - `sprints/2026-06-11-ascii-rain-honest-performance-sprint.md:49-62` says no optimization is accepted before current-tree proof and that the bottleneck owner must be cleaned in pristine shape.
  - `loops/ascii-rain-live-loop.txt:167-199` requires the plan to center `howl-render/src/session/text.zig` and the `direct_normal_scan` proof seam and forbids host or wrapper redesign without current proof.
- Benchmark receipts:
  - `utils/tools/rain-bench/artifacts/stress/20260612-000332-ascii/summary.json:45-121` records Howl `11.35 fps` and Alacritty `970.58 fps` on the current control run.
  - `utils/tools/rain-bench/artifacts/stress/20260612-000755-ascii/summary.json:45-84` records the Howl-only proof run at `11.84 fps`.
  - `/tmp/opencode/howl-render-debug-control.log:1-15` shows `direct_normal_scan_avg_us=1785-1832`, above `owner_create_avg_us=1154-1315` and far above sprite work.
- Harness and wrapper ownership:
  - `utils/tools/rain-bench/README.md:20-33` makes `zig build --release=fast stress:rain:build` the tool-owned build step.
  - `utils/tools/rain-bench/README.md:53-65` makes `benchmark_terminals.py` the cross-terminal wrapper and keeps it outside the host product surface.
  - `utils/tools/rain-bench/build.zig:19-28` builds the stress binaries locally under the tool owner.
  - `utils/tools/rain-bench/benchmark_terminals.py:467-469` builds the host and stress binary when `--build` is used.
  - `utils/tools/rain-bench/benchmark_terminals.py:527-565` launches Howl and Alacritty as external terminals.
  - `utils/tools/rain-bench/benchmark_terminals.py:698-744` writes `summary.json` and treats missing final metrics as failure.
- Current hot owner seam:
  - `howl-render/src/session/text.zig:46-114` owns the timing receipt that prints `direct_normal_scan_avg_us`.
  - `howl-render/src/session/text.zig:220-270` routes publication input into `TextFramePreparer.preparePublicationWithSessionOptions` first, then falls back to borrowed cell input only if publication-direct preparation does not return a direct frame.
  - `howl-render/src/text/frame_preparer.zig:155-177` makes publication preparation try `prepareDirectNormal(.publication, .require_all_normal, ...)` before any shared shaped path.
  - `howl-render/src/text/frame_preparer.zig:414-450` makes `prepareDirectNormal` the owner that fills `direct_normal_scan_us`.
  - `howl-render/src/text/direct_normal.zig:110-139` makes `direct_normal.prepare` the hot direct path.
  - `howl-render/src/text/direct_normal.zig:165-195` shows `.require_all_normal` does a full preflight scan and then a second full append pass.
  - `howl-render/src/text/direct_normal.zig:204-225` rebuilds each candidate through `sourceItem` and `cluster.includeDamage` on every scan pass.
  - `howl-render/src/text/direct_normal.zig:243-291` appends renderables and sprite work only after classification succeeds.
  - `howl-render/src/text/direct_normal.zig:305-327` does raster work after the scan; the log proves this is much smaller than scan cost.
  - `howl-render/src/text/shape/cluster.zig:549-555` maps each publication cell into a fresh `RenderableText` during scan.
  - `howl-render/src/text/shape/cluster.zig:637-674` owns the damage filter and row skip logic, but `direct_normal` currently only uses per-cell `includeSpan`, not row skipping.
- Neighbor seams that are not the next target:
  - `howl-render/src/prepared/handle.zig:72-96` shows handle creation timing covers allocation, registration, and emitter work after prepare.
  - `howl-render/src/prepared/render_surface_emitter.zig:288-325` and `328-360` show emitter timing buckets after preparation.
- Existing proof roots in owner tests:
  - `howl-render/src/text/frame_preparer.zig:920-967` proves publication clears/background truth.
  - `howl-render/src/text/frame_preparer.zig:1088-1145` proves publication complex cells already route through the full shared pipeline.
  - `howl-render/src/text/shape/cluster.zig:1038-1096` proves damage filtering and sparse extraction semantics.
- Current owner-local benchmark proof gap:
  - `howl-render/build.zig:113-139` exposes `benchmark:render` as an owner-local render benchmark surface.
  - `howl-render/src/benchmark_main.zig:476-518` defines publication workloads, including `publication_ascii_full_large`.
  - `howl-render/src/benchmark_main.zig:862-889` does not call `preparePublicationWithSessionOptions`; it pre-maps publication to borrowed cell input and measures `prepareCellsWithSessionOptions` instead.
  - `howl-render/src/benchmark_main.zig:1259-1283` runs that benchmark for all workloads.
- Reference anchors:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-38,153-184` makes renderable content a single iterator over terminal cells, not a separate preflight plus render pass.
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs:845-879` feeds those cells directly into the renderer during draw.
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs:177-191` keeps the renderer entrypoint narrow: draw provided cells.
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:57-69,134-172` draws each renderable cell in one streaming pass.
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:117-123,311-317` preloads ASCII glyphs and keeps cache work explicit.
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:90-113,161-176,249-264` requires simple control flow, assertions, and extracting hot loops into direct stand-alone functions.
  - `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md:96-101,329-368` says experiments confirm a design, hot work must respect CPU-friendly straight-line code, and batching/streaming matter.

Current-code facts

- The accepted live proof is not a vague "text is slow" claim. The active timing seam in `session/text.zig` logs `direct_normal_scan_avg_us` separately from backgrounds, decorations, cursor, raster, prepared handle creation, and emitter work (`session/text.zig:46-114`).
- The Howl-only proof log keeps `direct_normal_scan_avg_us` around `1785-1832`, while `owner_create_avg_us` is `1154-1315` and sprite/emitter work is much lower (`/tmp/opencode/howl-render-debug-control.log:1-15`).
- The hot path for the live host run is publication input, not generic cell-input benchmarking: `TextSession.prepareSurface` calls `preparePublicationWithSessionOptions` first (`session/text.zig:220-252`).
- Publication preparation tries direct-normal first (`frame_preparer.zig:155-167`). That means the bottleneck lives before the fallback shaping owners.
- `prepareDirectNormal` measures the entire `direct_normal.prepare` call as `direct_normal_us`, then records its `scan_us` sub-bucket as `direct_normal_scan_us` (`frame_preparer.zig:414-450`).
- In `.require_all_normal` mode, `direct_normal.appendVisible` performs a first full scan to prove every visible candidate is normal (`direct_normal.zig:174-183`) and then a second full scan to actually append renderables (`direct_normal.zig:185-193`).
- Each scan pass rebuilds a `RenderableText` through `sourceItem` and `sourceRenderableTextFromPublication`, which remaps the publication cell and re-infers span (`direct_normal.zig:204-225`, `cluster.zig:549-555`).
- On the all-normal ASCII-rain workload, that duplicate scan/control work is exercised across the whole visible 320x120 surface on every frame.
- The current fallback path has separate additional publication scans in `countPublicationComplexCells` (`frame_preparer.zig:465-473`) and `buildSparsePublicationCellsWithDamageScratch` (`cluster.zig:328-375`), but that is not the active hot proof because the accepted ASCII bottleneck run stays in the direct-normal path.
- The neighbor timing seams in `prepared/handle.zig` and `render_surface_emitter.zig` are useful receipts, but the proof log keeps them below the scan bucket, so they are not the truthful next optimization owner.
- The owner-local render benchmark exists, but its publication workloads bypass `preparePublicationWithSessionOptions` and therefore bypass the exact `direct_normal.Source.publication` scan seam (`benchmark_main.zig:862-889`). It cannot currently close this worker slice honestly.

Reference facts

- Alacritty's display stack builds `RenderableContent` as an iterator and drains it directly into the renderer (`display/content.rs:24-38,153-184`; `display/mod.rs:845-879`). That is strong pressure against a repeated proof pass over the same cell stream when the fast path can stream once.
- Alacritty's renderer text path consumes cells as it draws them (`renderer/text/mod.rs:57-69,134-172`), with glyph caching separated into its own owner (`renderer/text/glyph_cache.rs:46-79,117-123`). The scan owner and the cache owner stay distinct.
- TigerBeetle style explicitly prefers extracting hot loops into direct functions with primitive arguments and keeping control flow simple and centralized (`TIGER_STYLE.md:90-113,161-176,249-264`).
- TigerBeetle architecture treats experiments as proof of a mental model rather than the design itself (`ARCHITECTURE.md:96-101`). The live timing proof is enough to rank owners, but the code change still has to be the cleanest owner-true design.
- TigerBeetle's CPU and batching pressure argues for straight-line work over duplicate scans through the same hot data (`ARCHITECTURE.md:329-368`).

Compact anchor map

- Stable reference anchors:
  - Alacritty single-pass content stream: `display/content.rs:153-184`, `display/mod.rs:845-879`, `renderer/text/mod.rs:57-69,134-172`.
  - TigerBeetle hot-loop and directness law: `TIGER_STYLE.md:90-113,161-176,249-264`.
  - TigerBeetle experiment-vs-design law: `ARCHITECTURE.md:96-101`.
- Current Howl owner seams:
  - Host receipt seam: `utils/tools/rain-bench/benchmark_terminals.py:467-469,698-744`.
  - Host-side bottleneck timing receipt seam: `howl-render/src/session/text.zig:46-114`.
  - True hot owner seam: `howl-render/src/text/frame_preparer.zig:155-177,414-450` and `howl-render/src/text/direct_normal.zig:110-139,165-225`.
  - Shared publication mapping and damage semantics: `howl-render/src/text/shape/cluster.zig:549-578,637-674`.
  - Neighbor seams to leave alone unless proof flips: `howl-render/src/prepared/handle.zig:72-96`, `howl-render/src/prepared/render_surface_emitter.zig:288-325`.
  - Owner-local benchmark proof gap: `howl-render/src/benchmark_main.zig:862-889`.

Exact proof receipts being relied on

- Control run receipt:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-000332-ascii/summary.json`
  - Howl `11.35 fps`, Alacritty `970.58 fps`.
- Howl-only bottleneck proof receipt:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-000755-ascii/summary.json`
  - Howl `11.84 fps`.
- Timing proof log:
  - `/tmp/opencode/howl-render-debug-control.log`
  - Strongest repeated lines:
    - `direct_normal_scan_avg_us=1832 owner_create_avg_us=1315 sprites_avg_us=569`
    - `direct_normal_scan_avg_us=1791 owner_create_avg_us=1177 sprites_avg_us=474`

Owner roles and proposed shape

- `howl-render/src/session/text.zig` owns host-facing session orchestration and timing receipts. It is not the right place to fix duplicate scan work.
- `howl-render/src/text/frame_preparer.zig` owns path selection between direct-normal and shared complex shaping. It should keep choosing the owner path, but it should not absorb the scan loop itself.
- `howl-render/src/text/direct_normal.zig` is the true owner seam for the next slice. It owns the scan, the normal-lane decision, and the direct append path.
- `howl-render/src/text/shape/cluster.zig` is a support owner only for shared publication mapping and damage semantics. It should only be touched if the direct-normal owner needs a sharper helper that preserves current classification and damage truth.
- Proposed shape for the next worker slice:
  - keep the public prepare/session ABI and prepared surface consequences unchanged;
  - keep the optimization inside `direct_normal`'s normal-only scan owner;
  - collapse the current preflight-plus-second-pass pattern into one owner-true scan path that either:
    - emits a complete direct-normal product for all-normal visible publication data, or
    - rejects cleanly on the first complex candidate with scratch and counters restored so the shared complex path can take over honestly;
  - do not broaden into handle/emitter/host work;
  - do not require benchmark-wrapper work.

Sprint scratchpad

- The truthful next worker slice is not "speed up render" in general.
- The truthful next worker slice is "clean and sharpen the direct-normal scan owner so the all-normal publication fast path stops paying a duplicated whole-surface scan every frame."
- This slice should not include prepared handle creation, render-surface emission, GL backend work, PTY/VT work, or wrapper changes.
- The current owner-local render benchmark is a proof gap, not a reason to redirect the slice. It can stay untouched if acceptance uses unit tests plus the live timing harness. If the team wants owner-local benchmark proof for this seam later, that is a separate proof slice because `benchmark_main.zig` currently bypasses the exact publication owner path.

Explicit ordered worker slice plan

1. Slice: `direct-normal-single-pass-publication`
   - Purpose:
     - remove duplicated whole-surface direct-normal scan work from the proven publication fast path without changing render consequences.
   - Receipt fields:
     - coder session id
     - exact files changed
     - exact tests run
      - exact benchmark commands run
      - exact updated receipt paths
      - quoted before/after timing lines for `direct_normal_scan_avg_us`
      - commit-hash handoff status for orchestrator closure

Exact allowed files

- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/shape/cluster.zig`

Not allowed:

- `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig`
- `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/utils/tools/rain-bench/*`
- host, PTY, VT, GL, or ABI files

Exact required shape

- Keep the fast-path owner in `direct_normal.zig`.
- Keep `frame_preparer.preparePublicationWithSessionOptions` as the selector that first tries direct-normal and then falls back to the shared complex path.
- Replace the duplicated `.require_all_normal` proof-and-rescan control flow with one direct-normal owner path that does bounded rollback on complex rejection instead of a second whole-source pass.
- Preserve current damage semantics, continuation handling, cell-span inference, and direct-normal render output ordering.
- Preserve the current shared complex-path assertion pressure in `frame_preparer.zig`; do not silently weaken `expected_complex_cells` truth just to make the fast path easier.
- Do not add bucket structs, managers, controllers, or host convenience layers.

Exact tests

- Required unit test command:
  - `zig build test:unit` in `/home/home/personal/projects/howl/howl-render`
- Required existing proof roots to keep green:
  - `text preparation publication clears use empty default background truth` (`frame_preparer.zig:920-967`)
  - `text preparation prepares publication cells through shared full pipeline frame` (`frame_preparer.zig:1088-1145`)
  - `partial damage filters clean clusters before shaping` (`cluster.zig:1038-1067`)
  - `sparse cells keep only damaged base cells` (`cluster.zig:1069-1096`)
- Required new tests:
  - add one new test in `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig` proving pure ASCII publication input takes the direct-normal publication path without entering resolve/shape counters;
  - add one new test in `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig` proving a complex publication cell causes clean direct-normal rejection before the shared path succeeds, while the shared path still resolves and shapes exactly once;
- Required live verification commands:
  - `zig build install -Doptimize=ReleaseFast` in `/home/home/personal/projects/howl/howl-linux-host`
  - `zig build --release=fast stress:rain:build` in `/home/home/personal/projects/howl/utils/tools/rain-bench`
  - `env HOWL_RENDER_DEBUG_TIMING=1 python3 utils/tools/rain-bench/benchmark_terminals.py --duration 3 --mode ascii --terminals howl 2> /tmp/opencode/howl-render-debug-control.log` in `/home/home/personal/projects/howl`
  - `python3 utils/tools/rain-bench/benchmark_terminals.py --duration 10 --mode ascii --terminals howl alacritty` in `/home/home/personal/projects/howl`
- Acceptance proof expectation:
  - `direct_normal_scan_avg_us` in `/tmp/opencode/howl-render-debug-control.log` must be `<= 1648`, which is at least a 10 percent improvement over the current worst accepted baseline `1832`, without a correctness regression in the required tests.
  - the 10-second Howl vs Alacritty rerun must complete with final metrics receipts for both terminals under the decoupled rain-bench harness.

Exact non-goals

- No prepared handle or render-surface emitter optimization.
- No GL/backend resource redesign.
- No PTY, VT, or host event-loop work.
- No rain-bench wrapper redesign.
- No ABI contract changes.
- No broad text shaping redesign, atlas redesign, or glyph cache redesign.
- No benchmark-main correctness work unless it is explicitly promoted as a follow-up proof slice.

Exact stop conditions

- Stop if fixing the duplicate scan honestly requires changing session/prepared ABI consequences.
- Stop if the direct-normal owner cannot reject on complex cells without broadening into unrelated owners.
- Stop if current-source proof shows the live host path no longer enters `preparePublicationWithSessionOptions` first.
- Stop if the rerun shows `direct_normal_scan` is no longer the dominant bucket after the slice.
- Stop if the only way to prove the slice is to broaden into host-side or wrapper measurement work.

Required assertions

- Assert that any `.require_all_normal` rejection leaves direct-normal scratch in an empty state before control returns to the shared complex path.
- Assert that lane-report counters remain valid after direct-normal success and after direct-normal rejection.
- Keep positive-space assertions around inferred spans and damage inclusion behavior; do not weaken the existing `assertValid` and `expected_complex_cells` checks.
- If a helper is added for publication scanning, assert that its visible-cell count and complex-rejection behavior match the current renderable and damage rules.

Risks

- The highest implementation risk is subtle state leakage during one-pass rejection: scratch arrays, lane counters, or raster request state could survive a complex-cell bailout if rollback is incomplete.
- A second risk is accidentally optimizing the generic source union in a way that broadens the slice and makes the owner harder to audit.
- A third risk is over-trusting `benchmark_main.zig`; today it does not measure the exact hot publication seam.

Proof gaps

- `howl-render/src/benchmark_main.zig` publication workloads currently bypass `preparePublicationWithSessionOptions` and therefore cannot serve as acceptance proof for this slice (`benchmark_main.zig:862-889`).
- The live timing proof log is strong enough to rank owners, but it is aggregate logging, not a per-branch proof of how much of `direct_normal_scan` is specifically the preflight pass. The code shape still makes that duplication the strongest current design debt.
- I did not find a current Alacritty text path that does a separate whole-surface preflight to prove a fast path before it streams the same cells again. The reference pressure points away from preserving that pattern.

Readiness judgment

- Ready with one explicit proof gap.
- The next worker slice is reviewer-ready if acceptance uses unit tests plus the live ASCII-rain timing reruns.
- The current owner-local render benchmark must not be cited as proof for this slice unless it is first corrected to exercise `preparePublicationWithSessionOptions` directly.
