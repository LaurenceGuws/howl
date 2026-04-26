# Checkin 4 — Architecture Discipline Lock (2026-04-26)

## Intent

Record the post-correction architecture hygiene status and establish a formal discipline sprint to prevent future drift.

## Linked Review

- Review: `architecture_docs/reviews/2026-04-26-architecture-discipline/REVIEW.md`
- Sprint checkpoints: `architecture_docs/reviews/2026-04-26-architecture-discipline/CHECKPOINTS.md`

## Snapshot

1. Renderer-lane ownership correction is materially in place.
2. Key repos currently pass basic hygiene scans (headers, naming, forbidden compatibility patterns).
3. Remaining drift is mostly governance/process:
- stale or contradictory local milestone targets
- conventions not codified as parent authority
- insufficient automation for enforcement
- residual legacy ticket-tag naming in test suites

## Decision

Run a dedicated discipline sprint before broad feature expansion.
The sprint objective is to make conventions and phase intent unmistakable and enforceable.

Hard rule recorded: remote CI is forbidden for this workspace. Enforcement must run through
local handover report gates using `utils/hygene`.

Required validation shape: use the copy-paste block in `architecture_docs/CHECKIN_PROTOCOL.md`
and include the `utils/hygene/architecture_guard.sh` result in every engineering handover.

## Next Handover Basis

Use the linked checkpoints doc as the long-sprint execution list.
Feature work should remain secondary until P0/P1/P2 checkpoints are closed.
