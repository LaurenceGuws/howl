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

1. `post-bg-performance-rebaseline`
- accept the corrected-path owner order from fresh receipts
- authorize one more proof-only split on the top corrected-path subowner only after reviewer acceptance

2. `owner-create-after-bg-proof`
- split `owner_create` / emitter work further if the corrected receipts still prove it is the top true subowner
- stop and reshape ownership first if that split exposes another bucket seam
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
  - `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig` only if proof output changes
- non-goals:
  - no behavior change
  - no `direct_normal` or `direct_scene` edits
  - no source-mapping edits
  - no host GL or runtime work
- stop conditions:
  - hidden top cost falls outside the allowed files
  - emitter proof exposes another false owner or bucket seam

3. `direct-normal-after-bg`
- allowed only if the accepted corrected receipts after the owner-create proof still prove `direct_normal` is the next true owner
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
  - `/home/home/personal/projects/howl/howl-render/src/text/prepare_counters.zig` only if proof fields change
  - `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig` only if proof output changes
- non-goals:
  - no emitter, source, session, host, or ABI changes
- stop conditions:
  - corrected receipts show background fill or emitter work above `direct_normal`
  - the cut needs files outside the allowed set

4. `background-fill-after-bg`
- allowed only if the accepted corrected receipts prove restored background fill work dominates
- allowed files:
  - `/home/home/personal/projects/howl/howl-render/src/text/direct_scene.zig`
  - `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
  - `/home/home/personal/projects/howl/howl-render/src/benchmark_main.zig` only if proof output changes
- non-goals:
  - no source-mapping, session, host, or ABI changes
- stop conditions:
  - the real top cost is glyph/normal-path work instead of fill work
  - the seam exposes a new bucket owner

Completion gate:

- The live sprint, loop, and research files all reflect corrected-path receipts.
- The first optimization slice is authorized from honest owner order only.
