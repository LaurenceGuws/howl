# Sprint: Text Publication Full Path

Date: 2026-06-11.

Owner: orchestrator.

Status: accepted and committed in `howl-render` `603c0f1`.

Orchestrator session id: `orch-2026-06-11-text-publication-full-path-01`.
Planning orchestrator session id: `orch-2026-06-10-test-accountability-01`.
Planning researcher session ids:
- `research-2026-06-10-text-sprint-01`
- `research-2026-06-10-text-sprint-01-c1`
Execution reviewer session id: `review-2026-06-11-text-publication-full-path-01`.
Planning reviewer session id: `review-2026-06-10-text-sprint-01`.
Required coder session id: `coder-2026-06-11-text-publication-full-path-01`.
Required commit-hash receipt: fulfilled by `howl-render` commit `603c0f1`.

## Accepted Result

- Publication now enters the same normal-then-complex pipeline as raw VT cells and rich inputs.
- `preparePublicationWithSessionOptions` no longer returns `null` for mixed or complex publication text.
- Publication fallback is asserted to continue through the shared shaped-scene owner instead of slipping back into a publication-only lane.

## Verification

- `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input borrowed publication mapping reuses caller storage"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:abi -- "source text input borrowed publication mapping applies selection styling across scrollback rows"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation prepares mixed publication cells through non-null publication frame"`
- `cd /home/home/personal/projects/howl/howl-render && zig build test:unit -- "text preparation prepares complex publication cells through non-null publication frame"`
