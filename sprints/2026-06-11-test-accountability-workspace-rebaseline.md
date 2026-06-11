# Sprint: Test Accountability Workspace Rebaseline

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-test-accountability-workspace-rebaseline-02`.
Original sprint session id: `orch-2026-06-10-test-accountability-01`.
Execution reviewer session id: `review-2026-06-11-test-accountability-workspace-rebaseline-02`.
Required coder session id: `coder-2026-06-11-test-accountability-workspace-rebaseline-02`.
Required commit-hash receipt: required before slice acceptance.

## Problem

- The previously blocked workspace rebaseline is unblocked after the publication proof correction.
- The next honest step is to rerun the full exposed validation surface and close deferred sprint 3 only if it is now clean.

## Required Tests

- `cd /home/home/personal/projects/howl/howl-pty && zig build test`
- `cd /home/home/personal/projects/howl/howl-vt && zig build test`
- `cd /home/home/personal/projects/howl/howl-vt && zig build simulate`
- `cd /home/home/personal/projects/howl/howl-vt && zig build benchmark:m7_baseline`
- `cd /home/home/personal/projects/howl/howl-render && zig build test`
- `cd /home/home/personal/projects/howl/howl-render && zig build benchmark:render`
- `cd /home/home/personal/projects/howl/howl-linux-host && zig build test`

## Stop Conditions

- Stop if any command fails or skips unexpectedly.
- Stop if any accepted earlier slice lacks required receipts or proof output.
