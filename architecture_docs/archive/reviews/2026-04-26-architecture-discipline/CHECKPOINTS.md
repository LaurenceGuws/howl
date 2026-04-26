# Discipline Sprint Checkpoints

## Objective

Lock conventions and milestone clarity so module layering and ownership cannot be misread in future agent workflows.

## Execution Checkpoints

1. Authority documents created and linked
- `ENGINEERING_CONVENTIONS.md` created under `architecture_docs/`
- `CHECKIN_PROTOCOL.md` created under `architecture_docs/`
- `architecture_docs/README.md` updated with both links

2. Milestone target synchronization
- Every child `app_architecture/authorities/MILESTONE.md` has a non-stale `Current Target`
- Parent summary row added in `architecture_docs/authority/MILESTONES.md` for active target per repo

3. Guardrail automation
- Parent guard entry created under `utils/hygene/architecture_guard.sh` (no remote CI pipeline)
- Guard checks naming/header/comment/policy surfaces listed in `architecture_docs/authority/ENGINEERING_CONVENTIONS.md`
- Guard wired into local handover report gates via `architecture_docs/authority/CHECKIN_PROTOCOL.md`

4. Legacy normalization (minimum viable)
- VT-core: rename an initial tranche of milestone-tagged tests to behavior-first names
- Add migration note in repo docs to continue until complete

5. Evidence and closeout
- Publish evidence doc for this sprint in `architecture_docs/archive/reviews/...`
- Add new checkin entry with links to evidence and follow-up queue
- Include the `utils/hygene` validation block in every engineering handover.

## Stop Conditions

1. If a required rule causes false positives at high volume, freeze that rule and document a scoped exception list.
2. If milestone synchronization reveals contradictory parent/child phases, stop and publish a phase-resolution decision before continuing.
