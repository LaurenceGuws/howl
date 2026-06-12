Styled ASCII direct-normal scan plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-styled-ascii-direct-normal-scan-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-styled-ascii-direct-normal-scan-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-015956-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-020015-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Accepted baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014446-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-014500-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The strict default-style ASCII fast-candidate slice hit its accepted stop condition and was not committed.
- The proof showed live ASCII-rain does not fit the default-style subset because `/home/home/personal/projects/howl/utils/tools/rain-bench/ascii_rain_stress.zig` emits random SGR foreground/background/style changes in ASCII mode.
- The failed timing reruns did not beat the accepted baseline: `direct_normal_scan_avg_us=891` and `887` versus baseline `883`.
- The current top bottleneck remains direct-normal scan debt on styled/color ASCII publication cells.

Initial owner focus:

- `/home/home/personal/projects/howl/howl-render/src/text/direct_normal.zig`
- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`
- `/home/home/personal/projects/howl/howl-vt` publication cell/style facts only if needed to prove safe subset boundaries
- direct-normal and publication tests only if source proves they own the next slice

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain exactly which styled/color ASCII publication cell subset the live workload uses and whether it can be safely fast-candidated without weakening fallback semantics.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not broaden to Unicode, combining, wide, links, underline complexity, host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache-first, fresh rollback, payload initialization, or temporary instrumentation unless current source proves it is required.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Pending researcher pass.
