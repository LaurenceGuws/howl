# Sprint: Test Accountability Workspace Rebaseline

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-test-accountability-workspace-rebaseline-01`.
Original sprint session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session id: `research-2026-06-10-test-accountability-01`.
Execution reviewer session id: `review-2026-06-11-test-accountability-workspace-rebaseline-01`.
Required coder session id: `coder-2026-06-11-test-accountability-workspace-rebaseline-01`.
Required commit-hash receipt: required before slice acceptance.

## User Direction

- Resume deferred sprint 3 now.
- Continue autonomously unless reviewer returns `user needed`.

## Resumed Sprint Context

- Source deferred sprint:
  - `sprints/defered/2026-06-10-test-accountability-sprint.md`
- Source deferred research:
  - `research/defered/2026-06-10-test-accountability-research.md`
- Historical deferred loop:
  - `loops/defered/workspace-validation-rebaseline.txt`

## Problem

- The deferred test-accountability sprint was left open because `howl-render` aggregate `zig build test` still failed on text-stack ABI proofs.
- Those text and VT ownership repairs are now landed and accepted.
- The next honest step is the final verification-only rebaseline across the exposed repo validation surface.

## Exact Slice

Slice name: `workspace-validation-rebaseline`.

## Allowed Files

- `/home/home/personal/projects/howl/sprints/2026-06-11-test-accountability-workspace-rebaseline.md`
- `/home/home/personal/projects/howl/loops/workspace-validation-rebaseline.txt`
- `/home/home/personal/projects/howl/sprints/current.txt`

## Required Shape

- Verification-only slice.
- Rerun every exposed command from the deferred sprint surface.
- Record a clean baseline only if those commands actually pass without unjustified skips.
- If any command fails, record the exact blocker and stop.

## Required Tests

- `cd /home/home/personal/projects/howl/howl-pty && zig build test`
- `cd /home/home/personal/projects/howl/howl-vt && zig build test`
- `cd /home/home/personal/projects/howl/howl-vt && zig build simulate`
- `cd /home/home/personal/projects/howl/howl-vt && zig build benchmark:m7_baseline`
- `cd /home/home/personal/projects/howl/howl-render && zig build test`
- `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render`
- `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`

## Non-Goals

- No new code changes beyond receipt updates unless an earlier accepted slice is proved wrong.
- No benchmark interpretation beyond whether the exposed commands run cleanly.

## Stop Conditions

- Stop if any command above fails or skips unexpectedly.
- Stop if any accepted earlier slice lacks required receipts or proof output.

## Completion Gate

- No unjustified skipped tests in the exposed validation surface.
- `howl-render` aggregate `zig build test` passes.
- `howl-vt` simulate passes.
- The repo validation baseline is rerun from current code and recorded honestly.
