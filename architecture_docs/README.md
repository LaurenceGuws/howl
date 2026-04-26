# Howl Architecture Docs

Cross-repo architecture authority for Howl.

Repo-local implementation details stay in each repo's `app_architecture/`.
This directory owns only family-level structure, dependency direction, and milestone sequencing.

## Layout

- `authority/` — active, normative architecture authority docs
- `archive/` — dated checkins/reviews and legacy references

Parent workflow docs live outside this directory:

- `../docs/architect/` — workflow, reviews, and milestone progress
- `../docs/engineer/` — active queues and report checklists

## Single Source Of Truth

| Concern | Authority File |
| --- | --- |
| Module ownership, API boundary, consumes/produces | `authority/MODULE_MAP.md` |
| Allowed and forbidden dependency direction | `authority/DEPENDENCY_RULES.md` |
| Runtime integration sequence across modules | `authority/INTEGRATION_FLOW.md` |
| Family milestone ladder and per-module milestones | `authority/MILESTONES.md` |
| Required MVP repo structure and coupling rules | `authority/MVP_STRUCTURE.md` |
| Naming, docs, tests, handover discipline rules | `authority/ENGINEERING_CONVENTIONS.md` |
| Required handover/checkin validation schema | `authority/CHECKIN_PROTOCOL.md` |

## Active Authority Docs

- `authority/MODULE_MAP.md`
- `authority/DEPENDENCY_RULES.md`
- `authority/INTEGRATION_FLOW.md`
- `authority/MILESTONES.md`
- `authority/MVP_STRUCTURE.md`
- `authority/ENGINEERING_CONVENTIONS.md`
- `authority/CHECKIN_PROTOCOL.md`

## Archive

- `archive/checkins/` — historical checkin logs
- `archive/legacy/` — retained legacy notes not used as active authority

## Hard Rule

Remote CI remains forbidden.
All architecture and hygiene gates run locally through `utils/hygene` and must be reported per `authority/CHECKIN_PROTOCOL.md`.
