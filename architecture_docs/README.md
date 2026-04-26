# Howl Architecture Docs

Family-level architecture authority for cross-repo ownership, dependency direction, and integration flow.

Repo-local architecture details stay in each repo's `app_architecture/`.
This directory is for cross-module fit only.

## Documents

- `MODULE_MAP.md` — module ownership map (responsibility/API/consumes/produces)
- `DEPENDENCY_RULES.md` — allowed and forbidden dependency direction
- `INTEGRATION_FLOW.md` — runtime lifecycle/input/render flow across modules
- `MILESTONES.md` — MVP and long-term milestone map across modules
- `MVP_STRUCTURE.md` — required MVP structural layout and coupling per repo
- `ENGINEERING_CONVENTIONS.md` — parent authority for Zig docs, naming, tests, and commit isolation
- `CHECKIN_PROTOCOL.md` — required handover schema, validation fields, and residual-risk reporting
- `HOWL_HOST_BACKEND_SPLIT.md` — legacy split note (kept for continuity)

## Checkins

- `checkins/checkin4-architecture-discipline-2026-04-26.md` — latest architecture-discipline checkpoint
- `checkins/checkin5-full-howl-review-2026-04-26.md` — full workspace MVP structure review checkpoint

## Reviews

- `reviews/2026-04-26-architecture-discipline/REVIEW.md` — hygiene/drift audit and root-cause analysis
- `reviews/2026-04-26-architecture-discipline/CHECKPOINTS.md` — long-sprint execution checklist
- `reviews/2026-04-26-full-howl-review/REVIEW.md` — full workspace architecture audit
- `reviews/2026-04-26-full-howl-review/CHECKPOINTS.md` — corrective execution sequence for MVP structure lock
