Post-styled direct-normal scan plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-post-styled-direct-normal-scan-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-post-styled-direct-normal-scan-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The accepted styled ASCII direct-normal slice landed in `howl-render` commit `98bb85a` and root commit `ad7195f`.
- Howl improved to `60.26 fps`, but Alacritty remains `981.84 fps` on the same 10-second ASCII-rain telemetry.
- The post-styled bottleneck proof still ranks `direct_normal` first: `direct_normal_avg_us=925`, `direct_normal_scan_avg_us=811`, while `owner_create_avg_us=318`.
- The next research task is to source-pin the remaining direct-normal scan debt and produce one reviewer-acceptable worker slice.

Required current evidence:

- `howl-render-debug prepare_handle count=640 prepare_surface_avg_us=927 prepare_surface_max_us=19037 input_avg_us=0 session_preparer_avg_us=0 session_prepare_cells_avg_us=0 direct_normal_avg_us=925 direct_normal_scan_avg_us=811 direct_normal_backgrounds_avg_us=29 direct_normal_clears_avg_us=0 direct_normal_decorations_avg_us=47 direct_normal_cursor_avg_us=0 direct_normal_raster_avg_us=35 owner_create_avg_us=318 owner_create_max_us=1202`
- `howl-render-debug prepared_handle_create count=640 alloc_avg_us=0 alloc_max_us=1 register_avg_us=0 register_max_us=1 emit_avg_us=317 emit_max_us=1200`
- `howl-render-debug emit_prepared count=640 ... sprites_avg_us=302 ... atlas_resource_avg_us=133 ... publish_avg_us=1 ...`

Initial owner focus:

- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- adjacent direct-normal tests only if source proves they own the next slice

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain what remains expensive in direct-normal scan after styled ASCII publication fast-candidate.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or temporary instrumentation unless current source proves it is required.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Pending researcher pass.
