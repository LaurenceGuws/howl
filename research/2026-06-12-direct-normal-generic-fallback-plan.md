Direct-normal generic fallback plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-direct-normal-generic-fallback-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-direct-normal-generic-fallback-plan.md`
- Ranking-only proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-025154-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-025340-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Accepted product baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The proof-only child-cost slice removed all temporary instrumentation before handoff and is ranking-only because per-cell timers inflated product timing.
- The largest ranked child cost was `scan_generic_candidate_avg_us=767`, owned by `direct_normal.sourceCandidate` generic fallback/classification.
- The accepted product baseline remains root `ad7195f` plus `howl-render` `98bb85a`, with Howl `60.26 fps` vs Alacritty `981.84 fps` and accepted `direct_normal_scan_avg_us=811`.
- The next research task is to decide whether `scan_generic_candidate` can be reduced by a reviewer-safe worker slice, or whether the timer perturbation is too large and another proof method is needed first.

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Treat the child-cost proof as ranking evidence only, not additive absolute timing truth.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations, or explicitly require another proof slice if the ranking is too perturbed.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or unbounded instrumentation unless current source proves it is required.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Pending researcher pass.
