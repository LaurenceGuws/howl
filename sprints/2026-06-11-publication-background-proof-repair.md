# Sprint: Publication Background Proof Repair

Date: 2026-06-11.

Owner: orchestrator.

Status: active execution slice.

Orchestrator session id: `orch-2026-06-11-publication-background-proof-repair-01`.
Execution reviewer session id: `review-2026-06-11-publication-background-proof-repair-01`.
Required coder session id: `coder-2026-06-11-publication-background-proof-repair-01`.
Required commit-hash receipt: required before slice acceptance.

## Problem

- The resumed test-accountability rebaseline is blocked by one wrong accepted proof in `frame_preparer.zig`.
- Publication default-background blanks correctly produce opaque background draws, not clear draws.
- The accepted post-sprint repair encoded the wrong expectation for the publication path and now fails aggregate `zig build test`.

## Exact Slice

Slice name: `publication-background-proof-repair`.

## Allowed Files

- `/home/home/personal/projects/howl/howl-render/src/text/frame_preparer.zig`

## Required Shape

- Correct the publication-side proof to match current owner truth.
- Keep the raw-cell partial-clear proof intact.
- Do not change render behavior in this slice unless the proof exposes a real behavior mismatch.

## Required Tests

- `zig build test:unit -- "text preparation partial damage clears use empty default background truth"`
- `zig build test:unit -- "text preparation publication clears use empty default background truth"`
- `zig build test`

Run from:

- `/home/home/personal/projects/howl/howl-render`

## Non-Goals

- No renderer behavior changes if proof-only correction is sufficient.
- No ABI changes.

## Stop Conditions

- Stop if the proof correction exposes a real publication rendering bug instead of a wrong test expectation.
- Stop if the fix needs files outside `frame_preparer.zig`.
