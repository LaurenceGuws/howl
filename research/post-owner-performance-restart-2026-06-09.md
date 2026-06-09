# Post-Owner Performance Restart

Date: 2026-06-09.
Role: researcher.
Status: active.
Loop: `loops/post-owner-performance-research-restart.txt`.
Primary researcher session id: `research-2026-06-09-post-owner-performance-01`.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/post-owner-performance-research-restart.txt`
5. `/home/home/personal/projects/howl/reference-index.md`
6. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
8. Accepted post-owner receipts:
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-115340-ascii/summary.json`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-095340-ascii-direct-post-owner/howl-direct.accounting.log`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
9. Rejected probe findings from:
   - reviewer session `rev-2026-06-09-post-owner-performance-01`
   - coder session `coder-2026-06-09-emitter-alpha-reuse-fast-path-01`
   - researcher correction from the rejected probe
10. Current Howl source:
   - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
   - `/home/home/personal/projects/howl/howl-render/src/session/text.zig`

## Current Accepted Facts

- The ownership-correction queue is complete. `prepared/owner.zig` is gone and that cleanup was a real performance win.
- Accepted post-owner baseline:
  - clean benchmark: Howl `79.42 fps`, Alacritty `1039.12 fps`
  - direct host run: `109.56 fps`
  - stable hot order:
    1. `PreparedHandle.create` / render-surface emission
    2. `direct_normal` scan
    3. host fill playback tail
- `render_surface_emitter.zig` and `sprite_resource_store.zig` remain owner-true seams. The failed probe did not expose a new bucket owner.

## Rejected Probe Facts

- Rejected slice: `emitter-alpha-reuse-fast-path`
- Earliest broken stage: research/planning assumption, not coding mechanics
- Reason:
  - the probe removed staged upload work
  - but replaced it with per-query prepared-sprite byte hashing before atlas reuse could answer
  - so the intended fast path still paid a full byte walk on every alpha glyph
- Reviewer verdict on the rejected probe:
  - clean benchmark regressed hard
  - direct host timing regressed hard
  - the shape must be dropped, not repaired in place

## Exact File And Line References

- current alpha sprite branch in emitter:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:427`
- current atlas lookup entrypoint:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:161`
- current direct-normal scan owner path:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:124`
- current direct-normal append path:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:261`

## Current Question

- What is the next source-backed performance slice after the rejected alpha-reuse probe?
- The answer must either:
  1. produce a new cheap cache-hit shape inside the same owner seam without per-query byte walking, or
  2. prove the sprint should switch to `direct_normal` scan as the next slice instead.

## Explicit Restart Rule

- No coder work is authorized from this artifact.
- Restart sequence is:
  1. researcher correction for the next slice
  2. same reviewer re-gates the corrected plan
  3. only then a new coder slice is seeded

## Non-Negotiables For The Next Research Correction

- do not reuse the rejected hash-first premise
- do not reopen ownership correction unless current proof shows a new bucket seam
- do not wave through an emitter-side fix unless the cache-hit path is actually byte-walk-free
- compare any proposed new slice against the accepted post-owner baseline receipts, not against the rejected probe

## Reference Facts

- Alacritty separates content iteration from renderer execution. Content iteration yields only renderable cells and skips empty cells before renderer work:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:153-182`
- Alacritty text rendering then performs glyph-cache lookup on the renderable cell path and adds render items from that cell path:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:140-170`
- Alacritty glyph-cache reuse is cheap because cache hit returns before raster/load work:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs:200-207`
- TigerBeetle pressure for this restart is:
  - do not keep iterating on a disproved hot-path premise
  - keep control flow explicit
  - move to the next owner-true measured cut instead of shifting cost around within a false “fast path”

## Current-Code Facts

- Accepted post-owner timing puts `owner_create_avg_us` at about `938-951`, but that aggregate still includes several emitter subphases. The accepted emitter-local split is:
  - `sprites_avg_us ~= 265-273`
  - `stage_upload_avg_us ~= 87-90`
  - `atlas_resource_avg_us ~= 92-95`
  - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
- The current emitter alpha path still stages upload bytes before atlas lookup:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:431-454`
- The current atlas-reuse seam still requires byte-derived hashing from sprite content for alpha atlas lookup:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig:161-198`
- The rejected probe proved the obvious emitter-local “reuse before upload” idea was false on this shape because the reuse query still paid a full byte walk. The active research restart therefore cannot honestly authorize another emitter/resource-store cut without a new source-backed cheap-hit premise.
- The accepted direct-normal timing is still large on the clean post-owner baseline:
  - `direct_normal_avg_us ~= 731-737`
  - `direct_normal_scan_avg_us ~= 664-671`
  - `direct_normal_backgrounds_avg_us ~= 26-27`
  - `direct_normal_decorations_avg_us ~= 29-30`
  - `direct_normal_raster_avg_us ~= 5-8`
  - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
- In current source, `direct_normal` still owns the expensive candidate walk and append path:
  - prepare/scan entry: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:110-139`
  - candidate walk: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:178-210`
  - append/glyph lookup/atlas reserve/draw append: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:261-305`
- The direct-normal path is not another bucket seam in current source:
  - it owns one domain job: deciding normal-path renderable cells and building the normal-path draw/raster requests
  - it does not own session policy, FFI translation, host realization, or a generic compatibility bucket

## Owner Roles And Proposed Shape

- Decision: the next authorized performance slice must switch to `direct_normal`, not remain in `render_surface_emitter.zig` / `sprite_resource_store.zig`.
- Slice name: `direct-normal-scan-reduction`
- Why this is not optimizing a false owner:
  - `render_surface_emitter.zig` and `sprite_resource_store.zig` remain owner-true, but the rejected probe disproved the currently available cheap-hit premise in that seam
  - current source still makes atlas reuse depend on byte-derived hashing, so another emitter/resource-store slice would be planning on inference, not proof
  - `direct_normal.zig` still carries a large accepted cost on a clean owner seam with explicit scan, classification, glyph lookup, atlas reserve, and sprite append ownership
- Required shape:
  1. stay entirely inside the direct-normal owner seam
  2. reduce repeated per-cell work in `appendVisible`, `sourceCandidate`, and `appendRenderable`
  3. target the normal-path scan/append cost first, not backgrounds, host upload, or emitter publication
  4. keep emitter/resource-store, session, FFI, and host GL untouched
  5. if proof counters are needed, expose them only through existing benchmark/proof owners, not through new runtime plumbing

## Sprint Scratchpad

- Accepted baseline to beat:
  - clean benchmark:
    - `/home/home/personal/projects/howl/artifacts/stress/20260609-115340-ascii/summary.json`
    - Howl `79.42 fps`
    - Alacritty `1039.12 fps`
  - direct host accounting:
    - `/home/home/personal/projects/howl/artifacts/stress/20260609-095340-ascii-direct-post-owner/howl-direct.accounting.log`
    - direct host run `109.56 fps`
  - detailed timing:
    - `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
- Disproved premise to avoid:
  - “remove upload staging from alpha reuse path” is not a valid next cut unless cache hit is truly byte-walk-free
- Measured next owner-true cut:
  - `direct_normal` candidate walk and append path

## Explicit Ordered Slice Plan

1. `direct-normal-scan-reduction`
   - allowed files:
     - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
     - `/home/home/personal/projects/howl/howl-render/src/text/prepare_counters.zig` only if needed for proof fields
     - `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig` only if needed for proof output
   - required shape:
     - reduce repeated candidate-walk / append work inside the direct-normal seam
     - do not change emitter/resource-store ownership or behavior in this slice
     - do not change session ownership, FFI, or host GL
   - required receipts:
     - updated `benchmark:render` proof if counters/output change
     - fresh direct host timing receipt on the ASCII-rain harness
     - fresh clean Howl vs Alacritty benchmark receipt
2. Re-evaluate hot order from the new receipts
   - only after accepted direct-normal receipts may planning revisit emitter/resource-store or host upload again

## Required Assertions

- Assert positive and negative space for any new direct-normal fast path:
  - normal-only policy still rejects non-normal lanes under `require_all_normal`
  - empty/continuation/publication-empty cells still do not enter renderable output
  - visible-span filtering still agrees with `direct_scene.includeSpan`
- If a helper bypasses repeated work for plain ASCII cells, assert the exact eligibility conditions at entry.

## Required Tests

- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
- If proof counters or benchmark output change:
  - `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render -- --runs 20`
- Verification receipts required for acceptance:
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
  - rerun direct host timing on ASCII rain and compare against:
    - `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
  - rerun clean Howl vs Alacritty benchmark and compare against:
    - `/home/home/personal/projects/howl/artifacts/stress/20260609-115340-ascii/summary.json`

## Risks

- `direct_normal` is on the common renderable-cell path, so an overly broad change can perturb mixed or non-ASCII workloads.
- Because `prepare_surface_avg_us` and `direct_normal_avg_us` are nearly the same magnitude on the accepted baseline, a bad direct-normal cut will show up immediately in the real host receipt.

## Proof Gaps

- Current accepted receipts do not split `direct_normal_scan_avg_us` into finer subowners such as source extraction vs lane classification vs glyph lookup.
- That gap does not block the slice, because the owner seam is still narrow and the rejected emitter premise removes the stronger alternative.

## Readiness Judgment

Ready to leave research restart once the reviewer re-gates this corrected plan.

- the next valid coder slice is `direct-normal-scan-reduction`
- no new bucket owner is currently proved
- emitter/resource-store should not be retried until a new byte-walk-free cache-hit premise is source-backed
