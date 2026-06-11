Render surface payload initialization plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-render-surface-payload-init-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-render-surface-payload-init-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-013159-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Prior accepted baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011550-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-011602-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The proof-only residual slice removed temporary source instrumentation before handoff and produced a receipt at `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-013159-ascii/summary.json`.
- The proof line-owned the largest post-fresh `owner_create` child bucket to `payload.* = .{}` inside `PreparedHandle.emitRenderSurfacePayload`.
- Current proof lines:
  - `payload_init_avg_us=740`
  - `payload_emit_fresh_avg_us=358`
  - `payload_emit_total_avg_us=1099`
  - `payload_emit_residual_avg_us=0`
  - `fresh_total_avg_us=358`
  - `fresh_residual_avg_us=0`
  - `fresh_record_avg_us=0`
- The next research task is to produce one reviewer-acceptable optimization slice for eliminating or avoiding the hot payload full zero-initialization while preserving prepared handle lifecycle, publication pointer stability, render-surface bounds invariants, and host-facing ABI consequences.

Initial owner focus:

- `/home/home/personal/projects/howl/howl-render/src/prepared/handle.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/render_surface_emitter.zig`
- `/home/home/personal/projects/howl/howl-render/src/prepared/surface.zig`
- prepared owner tests only if source proves the lifecycle/pointer-stability contract needs proof there

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain exactly why `payload.* = .{}` is expensive in current source shape and what owner should avoid it.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, direct-normal, sprite cache-first, fresh rollback, or temporary instrumentation work.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Pending researcher pass.
