# Checkin 6 — Terminal Boundary Realignment (2026-04-27)

## Intent

Record the scope correction that the current `howl-term-surface` repo has
grown into the effective `howl-term` boundary, then realign parent and child
MVP docs around that model before more feature work proceeds.

## Linked Review

- Review: `docs/architect/mvp_scope_alignment/REVIEW.md`
- Checkpoints: `docs/architect/mvp_scope_alignment/CHECKPOINTS.md`

## Decision

1. Hosts are platform shells and app containers, not primary terminal policy
   owners.
2. The current `howl-term-surface` repo is the effective `howl-term` boundary:
   one embeddable terminal instance/widget that composes session, VT core,
   render-core, and a selected backend.
3. App-level multiplexing remains host-owned.
4. `howl-session` remains the shared runtime/process boundary.
5. `howl-render-core` remains the sole render-policy owner; backends stay thin.
6. Android remains a peer proof host, but it is not the blocker for the first
   Linux MVP.

## Key Outcomes

1. Parent authority now states the corrected terminal-boundary model.
2. MVP child repo authorities were realigned to the same ownership language.
3. Parent planning is split into two explicit sprints:
   - Sprint 1: MVP scope alignment and cleanup
   - Sprint 2: scoped MVP completion

## Hard Rule Reminder

Remote CI remains forbidden.
All enforcement and closeout gates must run through local `utils/hygene`
workflow and the validation rules in `docs/engineer/REPORT_CHECKLIST.md`.
