# Post-BG Performance Restart

Date: 2026-06-09.
Role: researcher.
Status: active.
Primary researcher session id: `research-2026-06-09-post-bg-performance-01`.
Sprint: `sprints/2026-06-09-post-bg-performance-restart.md`.
Loop: `loops/emitter-sprite-after-bg-next-shape.txt`.

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
- Accepted owner-create proof receipt:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-132725-owner-create-after-bg-proof-1/howl-term.stderr.log`
  - narrowed emitter split:
    - `sprites_avg_us ~= 407-421`
    - `sprite_lookup_avg_us ~= 63-65`
    - `stage_upload_avg_us ~= 93-96`
    - `atlas_resource_avg_us ~= 97-100`
    - `alpha_glyph_append_avg_us ~= 30-31`
    - `publish_avg_us ~= 2`
    - `publish_glyph_fixup_avg_us ~= 1-2`
  - conclusion:
    - `owner_create` remains inside the emitter seam
    - publish fixup is negligible
    - no new false owner or bucket seam is proved

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
- The accepted owner-create proof now narrows the top corrected-path tax further:
  - the remaining `owner_create` cost is primarily sprite/emitter work
  - publish fixup is not the next owner
  - any next emitter slice must account for the previously rejected byte-walk-first alpha reuse premise before coding starts
- The main proof gap for a cheap reuse key is now closed only for glyph-driven alpha sprites:
  - `contract.SpriteKey` for glyph groups is derived from face id, glyph ids, cell span, and cell metrics in `/home/home/personal/projects/howl/howl-render/src/text/raster/key.zig`
  - raster requests dedupe by that key in `/home/home/personal/projects/howl/howl-render/src/text/raster/rasterizer.zig`
  - cached raster lookup also keys by that same sprite key in `/home/home/personal/projects/howl/howl-render/src/session/text.zig` and `lookupPreparedSprite(...)`
  - so the honest cheap query identity for glyph-driven alpha-atlas reuse can be `sprite.key + clipped width/height + upload format`
  - this does not justify dropping width/height from the reuse key, because clipping changes the uploaded payload shape even when the source raster key stays the same
  - this proof does not yet cover every prepared sprite path or the direct color-resource path

## Proposed Shape

- Authorize one proof-only restart slice first.
- Do not optimize yet.
- Accept the corrected-path owner order into the live loop.
- Then authorize one more proof-only split on `owner_create` / emitter work, because that is the top corrected-path subowner on current receipts.
- Only after that may the loop authorize the first real optimization seam.
- After the accepted owner-create proof, coding pauses again until research/review cut the next exact emitter/sprite slice against the fresh proof and the earlier rejected alpha-reuse findings.

## Explicit Ordered Slice Plan

1. `post-bg-performance-rebaseline`
   - completed and accepted
2. `owner-create-after-bg-proof`
   - completed and accepted
3. `emitter-sprite-after-bg-next-shape`
   - planning/research only
   - purpose:
     - cut the next exact emitter/sprite coding contract from the accepted owner-create proof
     - avoid repeating the rejected byte-walk-first alpha-reuse premise
   - corrected coding direction:
     - use cheap identity `sprite.key + clipped width/height + format` for glyph-driven alpha-atlas hit queries only
     - keep byte-content proof only on miss insertion, never on hit queries
4. `direct-normal-after-bg`
   - fallback only if fresh planning proves emitter/sprite is no longer the next true coding target
5. `background-fill-after-bg`
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

- The next exact emitter/sprite coding contract is not yet written into the active loop.
- Reviewer acceptance of that next coding contract is still pending.

## Coder Trial Update

- The accepted coding contract `emitter-alpha-atlas-hit-without-byte-walk` was executed under coder session `coder-2026-06-09-emitter-alpha-atlas-hit-01`.
- The implementation stayed inside:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
- The owner-local unit suite passed, but the diff is not accepted because the valid direct host receipt regressed.

### Accepted coder-run receipts

- clean benchmark rerun:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-134805-ascii/summary.json`
  - Howl `38.62 fps`
  - Alacritty `994.84 fps`
- valid direct host rerun:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-term.stderr.log`
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-direct-ascii.metrics.ndjson`
  - Howl direct `36.94 fps`

### Dropped invalid coder receipts

- `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct/`
  - invalid relative stress-binary path
- `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-3/`
  - incomplete metrics, not an acceptance receipt

### Findings from the valid direct host receipt

- The accepted cheap-hit seam does remove the targeted staged-upload tax on the measured path:
  - `stage_upload_avg_us = 0`
  - `render_upload_bytes_avg = 0`
- Atlas query work also dropped relative to the pre-slice proof:
  - `atlas_resource_avg_us ~= 69-76`
  - pre-slice proof was `97-100`
- The remaining emitter split in the valid receipt is roughly:
  - `sprites_avg_us ~= 255-278`
  - `sprite_lookup_avg_us ~= 59-65`
  - `alpha_glyph_append_avg_us ~= 36-39`
- But the valid direct host outcome regressed against the accepted honest baseline:
  - accepted honest direct baseline: `47.88 fps`
  - coder-run valid direct receipt: `36.94 fps`
- The direct receipt also kept overall top owners high enough that the slice cannot be accepted on benchmark-only improvement:
  - `owner_create_avg_us ~= 1034-1061`
  - `direct_normal_avg_us ~= 776-782`
  - `render_upload_fill_avg_us ~= 326-381`
  - `render_upload_glyph_avg_us ~= 90-113`

### Updated judgment

- Reject the `emitter-alpha-atlas-hit-without-byte-walk` coding slice.
- The clean benchmark win is not enough because the valid direct host receipt hit the slice stop condition.
- The next work is research/review only:
  - explain why benchmark and direct host receipts diverged
  - re-order the next owner seam from the valid direct receipt
  - authorize a new coding contract only after that

## Readiness Judgment

Not ready to authorize coding from chat alone.

Ready to seed the next exact coding contract:

- slice name: `emitter-alpha-atlas-hit-without-byte-walk`
- owner seam:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
