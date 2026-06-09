ASCII rain performance restart after background truth fix

Date: 2026-06-09.
Status: active.
Orchestrator session id: `orch-2026-06-09-background-default-01`.

Problem statement:

- Default background correctness is restored on the real host path.
- All pre-fix performance planning that depended on transparent default backgrounds is navigation only.
- The broad goal is unchanged: beat Alacritty on the agreed ASCII-rain benchmark.
- The next authorized work is proof-only restart on corrected behavior, not optimization.

Restart rule:

- No optimization slice is accepted until the corrected path has fresh benchmark and direct-host receipts.
- If the honest restart exposes a new bucket or false owner, pure performance pauses and ownership correction resumes first.

Honest baseline receipts:

- Clean benchmark:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-131321-ascii/summary.json`
  - Howl `33.16 fps`
  - Alacritty `1004.67 fps`
- Direct host timing:
  - `/home/home/personal/projects/howl/artifacts/stress/20260609-1338-bg-honest-direct/howl-term.stderr.log`
  - direct host run `47.88 fps`

Sequential slice queue:

1. Historical completed slices, navigation only:
- `post-bg-performance-rebaseline`
- `owner-create-after-bg-proof`
- `emitter-alpha-atlas-hit-without-byte-walk`

2. `direct-upload-playback-proof-after-alpha-hit-rejection`
- completed and accepted proof slice
- purpose:
  - separate host playback and submit costs enough to name the next true owner from honest direct receipts
- allowed files:
  - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/process_accounting.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/app/processor.zig`
- required shape:
  - proof only
  - no behavior change
  - split fill playback dispatch/walk from fill draw execution
  - split glyph-run playback dispatch/walk from glyph draw execution
  - split sprite playback dispatch/walk from sprite draw execution
  - keep submit/present timing separate
- non-goals:
  - no `howl-render/*`
  - no emitter or sprite-store changes
  - no `direct_normal` changes
  - no ABI changes
  - no host UX/event-loop redesign
- stop conditions:
  - isolating the subowners requires behavior change
  - proof exposes a false owner that needs structural review first
  - direct receipts still cannot name one next owner

3. Historical rejected optimization evidence:
- completed and rejected as historical evidence only
- proved:
  - clean benchmark improved
  - valid direct host path regressed
  - removed emitter tax was real but not the next shippable owner
- no further emitter optimization is authorized from this result alone

4. `background-fill-after-playback-proof`
- completed and accepted host-fill optimization slice
- allowed files:
  - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface.zig`
  - `/home/home/personal/projects/howl/howl-linux-host/src/display/renderer/render_surface_test.zig`
- non-goals:
  - no `howl-render/*`
  - no host runtime/accounting file changes
  - no ABI changes
- stop conditions:
  - the seam exposes a new bucket owner
  - the honest change requires renderer-side fill production edits
  - the honest change requires files outside the two-file host fill set

5. `post-host-fill-rebaseline`
- next active measurement step
- rerun honest clean benchmark and update current owner order from the accepted host-fill state before more optimization coding

6. `direct-normal-after-playback-proof`
- allowed only if later accepted rebaseline/proof disproves fill as the next true owner and restores `direct_normal` to the top spot
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/prepare_counters.zig` only if proof fields change
  - `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig` only if proof output changes
- non-goals:
  - no emitter, source, session, host, or ABI changes
- stop conditions:
  - accepted playback proof ranks host playback or submit above `direct_normal`
  - the cut needs files outside the allowed set

Completion gate:

- The live sprint, loop, and research files all reflect corrected-path receipts.
- The first optimization slice is authorized from honest owner order only.
