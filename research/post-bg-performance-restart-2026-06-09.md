# Post-BG Performance Restart

Date: 2026-06-09.
Role: researcher.
Status: active.
Primary researcher session id: `research-2026-06-09-post-bg-performance-01`.
Sprint: `sprints/2026-06-09-post-bg-performance-restart.md`.
Loop: `loops/post-bg-performance-rebaseline.txt`.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/publication-default-background-truth.txt`
5. `/home/home/personal/projects/howl/research/background-default-correctness-2026-06-09.md`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. Current Howl source:
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
10. Honest corrected-path receipts:
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-131321-ascii/summary.json`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-term.stderr.log`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-direct-ascii.metrics.ndjson`
11. Alacritty references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`

## Current-Code Facts

- Source mapping now preserves default background truth in both source seams:
  - `/home/home/personal/projects/howl/howl-render/src/source/publication_cell_map.zig`
  - `/home/home/personal/projects/howl/howl-render/src/source/text_input.zig`
- Background emission still skips only truly transparent cells:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:82`
- `direct_normal` still owns the normal-path candidate walk and append path:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:110`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:178`
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:261`
- `render_surface_emitter` still publishes fills and sprites with row-local fill merging:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:316`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:385`

## Honest Receipt Facts

- Corrected clean benchmark:
  - Howl `33.16 fps`
  - Alacritty `1004.67 fps`
  - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-131321-ascii/summary.json`
- Corrected direct host run:
  - `47.88 fps`
  - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-direct-ascii.metrics.ndjson`
- Corrected direct host owner order:
  - `render_prepare_avg_us ~= 1674-1788`
  - `render_upload_avg_us ~= 495-579`
  - `present_submit_avg_us ~= 71-95`
  - `direct_normal_avg_us ~= 722-867`
  - `direct_normal_scan_avg_us ~= 658-718`
  - `owner_create_avg_us ~= 957-1084`
  - `render_upload_fill_avg_us ~= 311-372`
  - `render_upload_glyph_avg_us ~= 88-123`
  - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-term.stderr.log`
- PTY-side work is still not the limiter:
  - `howl-main` remains saturated while `howl-term-host` stays near idle in the direct receipt above

## Reference Facts

- Alacritty computes background truth at content prep, not by erasing it upstream:
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- Alacritty keeps rect/background work and text/glyph work in separate owners:
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs`
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`

## Findings

- The old post-owner performance plan is invalid for execution because it was based on broken background semantics.
- On the corrected path, the hot order is still render-side, not PTY-side.
- The top true owner is still `render_prepare`.
- On the corrected direct-host receipt, `owner_create` / emitter work is currently larger than `direct_normal`:
  - `owner_create_avg_us ~= 957-1084`
  - `direct_normal_avg_us ~= 722-867`
  - `direct_normal_scan_avg_us ~= 658-718`
- Restored background truth also raised fill playback materially, so any optimization slice must preserve the option that fill work becomes the next owner after a `direct_normal` cut.
- No new bucket owner is currently proved from the corrected receipts alone, but `render_surface_emitter.zig` remains large enough that the next proof slice must stop immediately if it exposes another false owner.

## Proposed Shape

- Authorize one proof-only restart slice first.
- Do not optimize yet.
- Accept the corrected-path owner order into the live loop.
- Then authorize one more proof-only split on `owner_create` / emitter work, because that is the top corrected-path subowner on current receipts.
- Only after that may the loop authorize the first real optimization seam.

## Explicit Ordered Slice Plan

1. `post-bg-performance-rebaseline`
   - no behavior change
   - active work is receipt capture and owner-order acceptance only
2. `owner-create-after-bg-proof`
   - purpose:
     - prove whether the corrected-path `owner_create` tax is primarily sprite path, fill publication, atlas-resource work, or another hidden subowner
   - allowed files:
     - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
     - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
     - `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig` only if proof output changes
   - required shape:
     - proof-only or env-gated timing split inside the smallest true owner files
     - no behavior change
     - no `direct_normal`, `direct_scene`, source-mapping, host, or ABI edits
   - required tests:
     - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
     - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
     - corrected direct host timing rerun
   - non-goals:
     - no optimization yet
     - no ownership rename unless the proof itself exposes a false owner
   - stop conditions:
     - hidden top cost falls outside the allowed files
     - proof exposes another false owner or bucket seam
3. `direct-normal-after-bg`
   - allowed only if accepted corrected receipts after the owner-create proof show `direct_normal` as the next true owner
   - allowed files:
     - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
     - `/home/home/personal/projects/howl/howl-render/src/text/prepare_counters.zig` only if proof fields change
     - `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig` only if proof output changes
   - required shape:
     - reduce candidate walk / append work inside the direct-normal owner only
     - no emitter, source, session, host, or ABI work
   - required tests:
     - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
     - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
     - corrected direct host timing rerun
     - corrected clean benchmark rerun
   - non-goals:
     - no background-fill optimization
     - no source-mapping changes
   - stop conditions:
     - corrected receipts show background fill or emitter work above `direct_normal`
     - the cut needs files outside the allowed set
4. `background-fill-after-bg`
   - fallback if restored background work overtakes `direct_normal`
   - allowed files:
     - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
     - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
     - `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig` only if proof output changes
   - required shape:
     - reduce background fill production/publication while preserving corrected background truth
     - keep rect/fill ownership local to the true owners
   - required tests:
     - `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
     - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
     - corrected direct host timing rerun
     - corrected clean benchmark rerun
   - non-goals:
     - no source-mapping, session, host, or ABI changes
   - stop conditions:
     - the real top cost is glyph/normal-path work instead of fill work
     - the seam exposes a new bucket owner

## Required Tests

- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit`
- `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
- `cd /home/home/personal/projects/howl/howl-linux-host && python3 ../utils/tools/benchmark_terminals.py --build --duration 10 --mode ascii --terminals howl alacritty`
- direct host timing receipt on the same corrected path

## Risks

- Optimizing from the old `79.42 fps` plan would be optimizing lies.
- If `owner_create` hides another bucket seam, performance must pause for ownership correction before optimization.
- If restored background work dominates after an owner-create or `direct_normal` attempt, the loop must stop and retarget instead of forcing a stale premise through.
- `render_surface_emitter.zig` remains large enough that a future corrected receipt could still expose it as another bucket seam.

## Proof Gaps

- Reviewer acceptance of the new performance restart loop is still pending.

## Readiness Judgment

Ready to seed one proof-only performance restart slice: `post-bg-performance-rebaseline`.

Not ready to authorize an optimization slice yet.
