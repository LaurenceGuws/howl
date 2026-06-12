Post-damage-first direct-normal scan plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-post-damage-first-direct-normal-scan-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-post-damage-first-direct-normal-scan-plan.md`
- Current failed-slice proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-090917-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Accepted product baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084336-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084355-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The damage-first publication fast-candidate slice passed correctness but failed timing and was not committed.
- The final failed timing proof reported `direct_normal_scan_avg_us=509`, worse than the accepted baseline `311`.
- The accepted product baseline remains root `7bd26ba` plus `howl-render` `e391d92`, with Howl `120.3 fps` vs Alacritty `1003.65 fps`.
- The next research task is to explain the remaining direct-normal scan cost without re-promoting the failed damage-first ordering idea.

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain what remains expensive in direct-normal scan after printable styled ASCII, zero-codepoint fast-candidate, and the failed damage-first attempt.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or temporary instrumentation unless current source proves it is required.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Pending researcher pass.
