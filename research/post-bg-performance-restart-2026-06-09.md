# Post-Alpha Direct Divergence Next Shape

Date: 2026-06-09.
Role: researcher.
Status: active.
Primary researcher session id: `research-2026-06-09-post-alpha-direct-divergence-01`.
Sprint: `/home/home/personal/projects/howl/sprints/2026-06-09-post-bg-performance-restart.md`.
Loop: `/home/home/personal/projects/howl/loops/background-fill-after-playback-next-shape.txt`.

## Sources Read In Order

1. `/home/home/personal/projects/howl/loop/flow.md`
2. `/home/home/personal/projects/howl/loop/researcher.md`
3. `/home/home/personal/projects/howl/sprints/current.txt`
4. `/home/home/personal/projects/howl/loops/background-fill-after-playback-next-shape.txt`
5. `/home/home/personal/projects/howl/loops/done/direct-upload-playback-proof-after-alpha-hit-rejection.txt`
6. `/home/home/personal/projects/howl/loops/done/post-alpha-direct-divergence-next-shape.txt`
6. `/home/home/personal/projects/howl/reference-index.md`
7. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
8. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
9. Historical loop navigation cache only:
   - `/home/home/personal/projects/howl/loops/done/emitter-sprite-after-bg-next-shape.txt`
10. Current receipts:
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-131321-ascii/summary.json`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-134805-ascii/summary.json`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-term.stderr.log`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-direct-ascii.metrics.ndjson`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-132725-owner-create-after-bg-proof-1/howl-term.stderr.log`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-term.stderr.log`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-direct-ascii.metrics.ndjson`
11. Current Howl source:
   - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/sprite_resource_store.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
12. Alacritty references:
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs`
   - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`

## Hygiene

- Active sprint: `/home/home/personal/projects/howl/sprints/2026-06-09-post-bg-performance-restart.md`
- Active loop: `/home/home/personal/projects/howl/loops/background-fill-after-playback-next-shape.txt`
- Active research: `/home/home/personal/projects/howl/research/post-bg-performance-restart-2026-06-09.md`
- Hygiene issues: none
- Research execution is authorized.
- The proof-only host playback slice has executed and is under reviewer gate.
- No optimization beyond this proof slice is authorized yet.

## Current-Code Facts

- The current source is back on the baseline emitter path. It still stages sprite bytes before the alpha-atlas lookup, then asks the atlas/store for placement, then appends atlas upload on miss:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:508-558`
- `PreparedHandle.create(...)` still emits the render-surface payload up front, inside `emitPreparedFresh(...)`, before host submit:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:71-93`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig:168-179`
- The host direct path measures three distinct surfaces per render turn:
  - prepare time from the terminal/context seam:
    - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig:656-705`
  - upload/playback counts and times forwarded into process accounting:
    - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig:204-233`
    - `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig:52-66`
    - `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig:223-251`
  - submit timing counted separately:
    - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig:230-233`
- Host upload/playback already separates fill, sprite, and glyph command timing:
  - upload stats owner:
    - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig:274-289`
  - command playback split:
    - fill commands: `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig:567-577`
    - sprite commands: `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig:578-590`
    - glyph-run commands: `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig:592-602`
- `direct_normal` still owns the full visible-cell walk, renderable classification, and sprite-draw append before the emitter ever runs:
  - source scan and classification: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:178-210`
  - append path: `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig:261-306`

## Reference Facts

- Alacritty’s content owner iterates only renderable cells and does not turn that owner into renderer playback policy:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-38`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:153-183`
- Alacritty keeps rect/background playback in its own renderer owner:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:54-67`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:158-177`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:181-226`
- Alacritty keeps text batching and glyph drawing in a separate text owner:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-69`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:97-132`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:134-172`

## Findings

1. The clean benchmark improved, but it is only a coarse macro receipt.
   - Honest clean baseline:
     - Howl `33.16 fps`
     - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-131321-ascii/summary.json:45-80`
   - Rejected probe clean rerun:
     - Howl `38.62 fps`
     - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-134805-ascii/summary.json:45-80`
   - That proves only that the whole app moved faster on that uninstrumented harness. It does not prove which owner got better.

2. The valid direct host receipt disproves that the removed atlas-hit tax was the next shippable owner.
   - Honest direct baseline:
     - `47.88 fps`
     - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-direct-ascii.metrics.ndjson:1-5`
   - Rejected-probe direct rerun:
     - `36.94 fps`
     - receipt: `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-direct-ascii.metrics.ndjson:1-4`
   - The probe did remove the measured emitter subcost it targeted:
     - baseline `stage_upload_avg_us ~= 88-95`, `atlas_resource_avg_us ~= 93-102`
       - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-term.stderr.log:34-42`
       - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-term.stderr.log:82-87`
     - rejected probe `stage_upload_avg_us = 0`, `atlas_resource_avg_us ~= 69-76`
       - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-term.stderr.log:34-42`
       - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-term.stderr.log:91-99`

3. The most likely reason for the divergence is that the probe removed one emitter tax, but the direct host path remained bottlenecked by unchanged or slightly worse frame-level owners.
   - Honest direct baseline late steady-state:
     - `direct_normal_avg_us ~= 722-725`
     - `owner_create_avg_us ~= 957-965`
     - `render_upload_fill_avg_us ~= 327-366`
     - `render_upload_glyph_avg_us ~= 99-109`
     - `present_submit_avg_us ~= 71-78`
     - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-term.stderr.log:70-78`
     - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-term.stderr.log:91-99`
   - Rejected probe late steady-state:
     - `direct_normal_avg_us ~= 776-782`
     - `owner_create_avg_us ~= 1034-1061`
     - `render_upload_fill_avg_us ~= 326-381`
     - `render_upload_glyph_avg_us ~= 90-113`
     - `present_submit_avg_us ~= 85-103`
     - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-term.stderr.log:70-78`
     - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-term.stderr.log:91-99`
   - The direct receipt also shows less terminal progress on the main owner thread:
     - honest baseline `terminal_drive_performed ~= 1323-1428`
       - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-term.stderr.log:65-78`
     - rejected probe `terminal_drive_performed ~= 929-1199`
       - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-term.stderr.log:65-99`
   - So the honest read is:
     - the clean benchmark saw a coarse win from cheaper atlas-hit handling
     - but on the valid direct host path, that win was too small to change the real owner order
     - and the main thread still spent enough time in `render_prepare` plus fill/glyph playback plus submit that end-to-end PTY/frame throughput fell anyway

4. The next true seam is not another blind emitter optimization.
   - The direct receipt does not show a new dominant emitter subowner after `stage_upload` was removed.
   - What it does show is a still-heavy playback side:
     - fills are materially larger than glyph playback
     - fill plus glyph playback together remain a large competing owner under the same direct receipt
   - Under Alacritty pressure, rect/background playback and text playback are separate renderer owners, so the next honest move is to prove the playback split directly instead of forcing another mixed emitter slice.

5. No newly exposed bucket/false owner is proved strongly enough to pause performance for structural surgery first.
   - `render_surface_emitter.zig` and `sprite_resource_store.zig` are still suspiciously broad.
   - But the valid direct receipt does not prove `sprite_lookup` or `atlas_resource` as the dominant remaining owner:
     - `sprite_lookup_avg_us ~= 59-65`
     - `atlas_resource_avg_us ~= 69-76`
     - `/home/home/personal/projects/howl/artifacts/stress/20260609-emitter-alpha-atlas-hit-direct-2/howl-term.stderr.log:70-78`
   - So this is still performance-proof work, not mandatory ownership-correction work, provided the next slice stays proof-only.

## Proposed Shape

### Owner Roles

- `howl-render/src/text/direct_normal.zig` still owns candidate walk and sprite-draw production.
- `howl-render/src/prepared/render_surface_emitter.zig` owns prepared-surface emission.
- `howl-linux-host/src/display/renderer/render_surface.zig` owns host playback of fill/sprite/glyph commands.
- `howl-linux-host/src/terminal/context.zig` owns the prepare/upload/submit handoff timing seam.

### Next Honest Slice

Promote a proof-only contract, not a coding optimization slice.

- Slice name: `direct-upload-playback-proof-after-alpha-hit-rejection`
- Purpose:
  - explain whether the direct-host regression lives primarily in fill playback, glyph playback, or frame-submit/pacing under the same corrected path
  - prove whether the next optimization seam should move to host playback or back to `direct_normal`
  - avoid repeating another emitter-side guess after the rejected atlas-hit probe already removed its targeted tax

### Exact Loop Contract To Promote

- Allowed files:
  - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
- Required shape:
  - add one narrower proof split inside host playback only
  - keep fill playback, glyph playback, and submit/present as distinct measured subowners
  - split fill playback into dispatch/walk time and draw execution time
  - split glyph playback into dispatch/walk time and draw execution time
  - split sprite playback into dispatch/walk time and draw execution time
  - do not change renderer policy, emitter policy, sprite keys, atlas reuse logic, or `direct_normal`
  - produce a fresh valid direct host receipt that can answer:
    - is fill playback still the next owner?
    - is glyph playback the next owner?
    - or did the regression actually come from submit/pacing overhead?
- Exact non-goals:
  - no emitter changes
  - no `howl-render/src/prepared/render_surface_emitter.zig`
  - no `howl-render/src/prepared/sprite_resource_store.zig`
  - no `howl-render/src/text/direct_normal.zig`
  - no ABI changes
  - no host UX/event-loop redesign
- Exact stop conditions:
  - stop if the proof requires behavior change instead of measurement split
  - stop if the proof exposes a real false owner in host playback that needs review before more performance work
  - stop if the direct receipt still cannot separate fill/glyph/submit enough to name a single next owner

## Required Tests

- `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`
- `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
- fresh valid direct host rerun on the corrected path with timing enabled
- fresh clean benchmark rerun only after the proof slice, to confirm that the proof code itself did not change behavior

## Risks

- Another emitter-side optimization slice would still be guesswork against the current receipts.
- If playback proof shows `render_surface.zig` mixing too many owner responsibilities, performance work must pause for ownership correction before optimization resumes.
- Fill playback may dominate because restored background truth materially increased rect work; forcing a glyph-centric story would repeat the same mistake in a new owner.

## Proof Gaps

- The next optimization seam inside host fill playback is not yet planned/reviewed.
- The clean benchmark harness remains too noisy to act as the behavior-stability proof for accounting-only slices.
- The current source is already back on the baseline emitter path, so the rejected probe survives only as receipt evidence, not as live code to inspect.

## Execution Update

- Coder session id: `019eac48-c12a-7483-9d1f-a832326bc6bc`
- Allowed-file diff only:
  - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
- Verification passed:
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`
  - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
- Invalid direct receipt dropped:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-121533-direct-upload-playback-proof-1/`
  - wrong CLI shape (`--mode ascii` instead of `--ascii`)
- Valid direct proof receipt:
  - stderr: `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-term.stderr.log`
  - metrics: `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-direct-ascii.metrics.ndjson`
  - direct result: `47.96 fps` vs honest direct baseline `47.88 fps`
- Fresh clean benchmark receipts on the same proof-only code:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-141537-ascii/summary.json`
    - Howl `51.18 fps`
    - Alacritty `981.58 fps`
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-141951-ascii/summary.json`
    - Howl `43.50 fps`
    - Alacritty `1006.50 fps`
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-142016-ascii/summary.json`
    - Howl `45.69 fps`
    - Alacritty `1001.49 fps`

### Accepted proof judgment

- The proof slice successfully isolates the next owner on the honest direct path.
- `fill` remains the next owner.
- Within `fill`, draw execution dominates dispatch/walk overhead.
- `glyph` playback is materially smaller than fill playback.
- `sprite` playback is irrelevant on this workload.
- `present_submit` remains below fill playback and does not outrank it.

### Receipt-backed direct numbers

- From `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-term.stderr.log` late steady-state:
  - `render_upload_fill_avg_us ~= 387-488`
  - `render_upload_fill_dispatch_avg_us ~= 47-60`
  - `render_upload_fill_draw_avg_us ~= 340-428`
  - `render_upload_glyph_avg_us ~= 94-138`
  - `render_upload_sprite_avg_us = 0`
  - `present_submit_avg_us ~= 79-96`

### Clean-benchmark gate judgment

- The proof-only host slice does not change renderer policy or command behavior; it only adds narrower accounting splits on the host playback path.
- Repeated clean benchmark reruns remain materially above the old `33.16 fps` honest baseline, but they also vary widely (`43.50`, `45.69`, `51.18`) while the valid direct host path stays effectively flat (`47.88 -> 47.96 fps`).
- So the clean benchmark harness is too noisy to serve as the acceptance proof for “no material behavior change” on this accounting-only slice.
- For this slice, the authoritative acceptance proof is:
  - bounded allowed-file diff with no behavior-path edits
  - stable direct host receipt
  - explicit next-owner judgment from the direct timing split

## Readiness Judgment

Accepted the proof-only host-playback split.

Ready to seed follow-on research/review for the next exact fill-owner contract.

The rejected `emitter-alpha-atlas-hit-without-byte-walk` probe remains valid historical evidence only. The accepted proof result from `direct-upload-playback-proof-after-alpha-hit-rejection` is that host fill playback, specifically fill draw execution, is the next true owner on the honest direct path. The next active work is planning, not coding, for `background-fill-after-playback-proof`.

## Next Fill Contract

### Follow-on sources read

13. Accepted proof receipts:
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-term.stderr.log`
   - `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-direct-ascii.metrics.ndjson`
14. Current fill-path source:
   - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
   - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
   - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface_test.zig`

### Current-code facts

- The accepted direct proof names host fill playback, not renderer-side fill production, as the next owner:
  - `render_upload_fill_avg_us ~= 387-488`
  - `render_upload_fill_draw_avg_us ~= 340-428`
  - `render_upload_fill_dispatch_avg_us ~= 47-60`
  - `render_upload_glyph_avg_us ~= 94-138`
  - `render_upload_sprite_avg_us = 0`
  - `present_submit_avg_us ~= 79-96`
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-term.stderr.log:19-31`
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-term.stderr.log:35-47`
- The direct proof stayed behavior-flat on the authoritative host path:
  - `47.96 fps`
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-direct-ascii.metrics.ndjson:1-5`
- Renderer-side fill production already has two owner-true merge stages before host playback:
  - `direct_scene.appendBackgrounds(...)` merges contiguous same-color row spans into `TextBackgroundDraw` records:
    - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:82-124`
  - `render_surface_emitter.appendPreparedFillCommand(...)` merges adjacent prepared fill commands of the same kind and color:
    - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:445-506`
- The host playback owner still pays the actual fill draw cost in one leaf:
  - fill commands are dispatched in `uploadRenderSurfaceCommands(...)`:
    - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig:503-625`
  - fill draw execution lands in `drawFillCommand(...)` and `drawQuad(...)`:
    - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig:896-1003`
- The same file also contains the fill-only shortcut path:
  - `uploadFillCommands(...)`:
    - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig:481-501`

### Reference facts

- Alacritty keeps renderable-cell discovery outside the renderer owner:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:24-38`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:153-183`
- Alacritty keeps rect/background playback in a dedicated renderer owner with its own rect data shape and batch:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:19-33`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:247-255`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:257-280`
- Alacritty keeps text batching separate from rect/background drawing:
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-69`
  - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:97-132`
- TigerBeetle pressure still rejects broad bucket owners and says to move behavior toward the smallest true owner:
  - `/home/home/personal/projects/howl/AGENTS.md:103-118`
  - `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md:80-118`

### Answers

1. The next honest optimization seam is host-side fill playback.
   - The accepted receipt proves fill draw execution, not dispatch, dominates the remaining fill cost:
     - `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-term.stderr.log:19-31`
     - `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-term.stderr.log:35-47`
   - Current renderer-side fill production already merges at `direct_scene` and again at `render_surface_emitter`, so there is no receipt-backed proof that command production outranks host draw execution:
     - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:82-124`
     - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig:445-506`
   - Under Alacritty pressure, this also matches the right owner boundary: rect/background playback belongs in the renderer owner, separate from text production:
     - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/rects.rs:247-280`
     - `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:49-69`

2. The next coding slice should be allowed to touch exactly:
   - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig`
   - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface_test.zig`
   - No other source file is justified by the accepted proof.
   - The next owner is inside host fill playback, and the existing unit-test root for that owner already exists:
     - owner file: `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig:481-625`
     - test root: `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface_test.zig:55-236`

3. The next loop should promote this exact coding contract:
   - Slice name:
     - `background-fill-host-playback-owner`
   - Required shape:
     - optimize host fill playback only inside `render_surface.zig`
     - keep rect/background playback as a renderer-owned path, separate from glyph playback
     - keep render-surface command semantics, command ordering, fill colors, and patch/full-surface behavior unchanged
     - keep renderer-side fill production unchanged; no `direct_scene` or emitter changes in this slice
     - if a helper is introduced, it must remain owner-local to `render_surface.zig` and serve fill playback only
     - preserve the existing upload/playback accounting fields so the same direct receipts remain comparable
   - Required tests:
     - `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`
     - `cd /home/home/personal/projects/howl/howl-linux-host && zig build install -Doptimize=ReleaseFast`
     - one fresh direct-host timing rerun with `HOWL_RENDER_DEBUG_TIMING` enabled against the ASCII-rain workload
     - acceptance requires the fresh direct receipt to improve `render_upload_fill_draw_avg_us` relative to `/home/home/personal/projects/howl/artifacts/stress/20260609-121557-direct-upload-playback-proof-2/howl-term.stderr.log`
   - Non-goals:
     - no `howl-render/*`
     - no `howl-linux-host/src/terminal/context.zig`
     - no `howl-linux-host/src/app/process_accounting.zig`
     - no `howl-linux-host/src/app/processor.zig`
     - no ABI changes
     - no event-loop, wake-policy, or present-policy redesign
     - no glyph or sprite playback changes
   - Stop conditions:
     - stop if the honest change requires renderer-side command production edits
     - stop if the honest change requires touching files outside the two-file set above
     - stop if reducing fill draw cost requires changing command ordering or fill semantics
     - stop if implementation reveals `render_surface.zig` must first be split into a new owner file to avoid a false owner

4. Current code does expose a bucket-shaped struct, but not one that should pause this performance slice first.
   - `direct_scene.MergedBuffers` is a generic grouping of clear/cursor/background/sprite/decoration/missing slices:
     - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig:25-32`
   - But the accepted direct-normal-only path that produced the fill proof bypasses that bucket by borrowing the direct scene directly:
     - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:358-367`
   - `MergedBuffers` is only used in the merge path when direct output is combined with an existing text scene:
     - `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig:324-355`
   - So it is real style debt, but it is not the proved next owner on the accepted fill path and does not justify pausing the host fill playback slice first.

### Sprint scratchpad

- Next owner:
  - host fill playback
- Smallest accountable owner:
  - `howl-linux-host/src/display/renderer/render_surface.zig`
- Proof basis:
  - accepted direct receipt `20260609-121557-direct-upload-playback-proof-2`
- Why not renderer-side fill production:
  - current source already merges fill spans before host playback, and no receipt proves that path outranks host fill draw
- Why not ownership correction first:
  - no current receipt proves a false owner ahead of host fill playback on the accepted path

### Risks

- `render_surface.zig` currently owns shape classification, fill-only upload, mixed command playback, and GL draw leaves in one file:
  - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig:439-625`
- That breadth is tolerable for one more tightly scoped owner-local optimization, but if the change wants to escape that file or change command semantics, stop and re-cut the owner boundary first.

### Readiness judgment

Ready to promote one host-only coding slice for fill playback.

The next honest contract is not renderer-side fill command production and not a forced ownership-correction pause. It is a two-file host slice centered on `howl-linux-host/src/display/renderer/render_surface.zig`, with direct-host receipt comparison against `20260609-121557-direct-upload-playback-proof-2` as the acceptance proof.
