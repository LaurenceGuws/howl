Direct-normal publication scan post-zero-codepoint plan

Date: 2026-06-12.
Status: active researcher target.
Role owner: researcher.
Orchestrator session id: `orch-2026-06-11-ascii-rain-honest-performance-02`.
Researcher session id: `research-2026-06-12-direct-normal-publication-scan-post-zero-codepoint-01`.
Reviewer session id: pending.
Planning commit-hash receipt: pending.

Preload receipt:

- Role: researcher
- Active sprint:
  - `/home/home/personal/projects/howl/sprints/2026-06-11-ascii-rain-honest-performance-sprint.md`
- Active loop:
  - `/home/home/personal/projects/howl/loops/ascii-rain-live-loop.txt`
- Active research:
  - `/home/home/personal/projects/howl/research/2026-06-12-direct-normal-publication-scan-post-zero-codepoint-plan.md`
- Current proof receipts:
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084336-ascii/summary.json`
  - `/home/home/personal/projects/howl/utils/tools/rain-bench/artifacts/stress/20260612-084355-ascii/summary.json`
  - `/tmp/opencode/howl-render-debug-control.log`
- Execution authorized:
  - research and planning only; no implementation from this pass

Problem statement:

- The accepted zero-codepoint slice landed in `howl-render` commit `e391d92` and root commit `7bd26ba`.
- Howl improved to `120.3 fps`, but Alacritty remains `1003.65 fps` on the same 10-second ASCII-rain telemetry.
- The fresh bottleneck proof still ranks `direct_normal_scan` first at `311`, while `owner_create` is now `216`.
- The next research task is to source-pin the remaining direct-normal publication scan cost and produce one reviewer-acceptable worker slice.

Research requirements:

- Read the live workflow, active loop, current sprint index, this file, TigerBeetle readings, and source/reference anchors before writing a plan.
- Explain what remains expensive in the direct-normal publication scan after printable styled ASCII and zero-codepoint fast-candidate slices have landed.
- Produce one reviewer-acceptable worker slice with exact allowed files, shape, tests, non-goals, stop conditions, assertions, receipt paths, and timing proof expectations.
- Do not drift into host, GL, benchmark-wrapper, PTY, VT, ABI, owner-create, sprite cache, fresh rollback, payload initialization, or temporary instrumentation unless current source proves it is required.
- Stop and report if the truthful next step exposes a big correctness issue or vague bucket.

Readiness judgment:

- Pending researcher pass.
