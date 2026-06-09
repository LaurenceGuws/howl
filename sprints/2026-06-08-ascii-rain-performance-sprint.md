ASCII rain performance sprint

Date: 2026-06-08.
Status: deferred.
Original orchestrator session id: `orch-2026-06-08-ascii-rain-performance-01`.

Deferred reason:

- User priority changed on 2026-06-09 from performance iteration to a correctness regression in default background rendering.
- Performance work is paused until the background-color regression is fixed and verified.

Original goal:

- Keep iterating on measured bottlenecks until Howl is faster than Alacritty on the agreed ASCII rain benchmark.

Accepted completed queue before defer:

1. `baseline-and-owner-proof`
2. `renderer-owner-proof`
3. `alacritty-shape-research`
4. `owner-delete-plan`
5. `owner-map-landing`
6. `session-submit-choreography`
7. `prepared-surface-boundary-cleanup`
8. `delete-owner-zig`
9. `post-owner-performance-rebaseline`
10. `emitter-alpha-reuse-fast-path` — rejected and recorded
11. `post-owner-performance-research-restart` — completed

Paused state at defer:

- The next proposed performance path had moved into `direct_normal` planning.
- Rejected probes were preserved in deferred loop/research artifacts to avoid repeating the same dead ends under context compaction.

Primary receipts preserved by the deferred sprint:

- `/home/home/personal/projects/howl/artifacts/stress/20260608-232747-ascii/summary.json`
- `/home/home/personal/projects/howl/artifacts/stress/20260609-095340-ascii-direct-post-owner/howl-direct.accounting.log`
- `/home/home/personal/projects/howl/artifacts/stress/20260609-095743-ascii-direct-post-owner-timing/howl-term.stderr.log`
- deferred research:
  - `research/defered/post-owner-performance-restart-2026-06-09.md`
- deferred loops:
  - `loops/defered/direct-normal-scan-reduction.txt`
  - `loops/defered/direct-normal-plain-ascii-shortcut.txt`
