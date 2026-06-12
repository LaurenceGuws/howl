Non-printable publication normal plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-non-printable-publication-normal-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-non-printable-publication-normal-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-082436-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Failed instrumentation probes retained as context only:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-082209-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-082228-ascii/summary.json`
- Accepted product baseline receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021917-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-021928-ascii/summary.json`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The count-only generic-fallback proof resolved the prior vague bucket enough for planning.
- At `count=640`, live generic fallback was dominated by `unsupported_non_printable=6966461`, with `publication_generic_entered=6966461` and `publication_generic_normal=6966461`.
- Every other unsupported reason and generic consequence count was `0` in the final proof line.
- The accepted product baseline remains Howl `60.26 fps`, Alacritty `981.84 fps`, and accepted `direct_normal_scan_avg_us=811` on root `ad7195f` plus `howl-render` `98bb85a`.
- The next research task is to explain which non-printable publication cell classes dominate the live fallback and whether they can be fast-pathed safely without violating publication semantics.

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Identify the exact non-printable publication cell classes present in the live workload and whether they are semantically empty, control-derived blanks, erase consequences, scroll consequences, or another owner-truth class.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or unbounded instrumentation unless current source proves it is required.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Pending researcher pass.
