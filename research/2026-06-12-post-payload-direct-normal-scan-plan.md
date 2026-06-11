Post-payload direct-normal scan plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-post-payload-direct-normal-scan-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-post-payload-direct-normal-scan-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014446-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014500-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The accepted payload initialization slice landed in `howl-render` commit `01e8bec` and root commit `150b14d`.
- Howl improved to `55.54 fps`, but Alacritty remains `987.81 fps` on the same 10-second ASCII-rain telemetry.
- The post-payload bottleneck proof ranks `direct_normal` first: `direct_normal_avg_us=991`, `direct_normal_scan_avg_us=883`, while `owner_create_avg_us=361`.
- The next research task is to source-pin the current direct-normal scan debt and produce one reviewer-acceptable worker slice.

Required current evidence:

- `howl-render-debug prepare_handle count=640 prepare_surface_avg_us=993 prepare_surface_max_us=14434 input_avg_us=0 session_preparer_avg_us=0 session_prepare_cells_avg_us=0 direct_normal_avg_us=991 direct_normal_scan_avg_us=883 direct_normal_backgrounds_avg_us=30 direct_normal_clears_avg_us=0 direct_normal_decorations_avg_us=49 direct_normal_cursor_avg_us=0 direct_normal_raster_avg_us=27 owner_create_avg_us=361 owner_create_max_us=1474`
- `howl-render-debug prepared_handle_create count=640 alloc_avg_us=0 alloc_max_us=6 register_avg_us=0 register_max_us=2 emit_avg_us=360 emit_max_us=1472`
- `howl-render-debug emit_prepared count=640 ... sprites_avg_us=343 ... atlas_resource_avg_us=149 ... publish_avg_us=1 ...`

Initial owner focus:

- `/home/home/personal/projects/howl/howl-render/src/session/text.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- direct-normal tests and adjacent text publication tests only if source proves they own the next slice

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain why the current direct-normal scan remains expensive after the earlier single-pass publication slice.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache-first, fresh rollback, payload initialization, or temporary instrumentation work unless the current source proves that direct-normal cannot be fixed honestly without it.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Pending researcher pass.
