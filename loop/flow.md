# Workflow

## Sprint Planning

- Researcher and reviewer do the sprint planning work ahead of execution.
- Planning stops only when the full problem statement is fully and explicitly scoped into slices for the coder.
- No coding starts while scope, slice boundaries, ownership, tests, non-goals, or stop conditions are unsettled.
- Only the user may:
  - narrow scope
  - call for a smaller sprint
  - declare a v1 of the sprint
- Any agent language that drifts toward smaller sprint, narrower scope, v1, partial for now, or similar scope weakening drops the planning work from acceptance unless the user explicitly asked for it.

Planning order:

1. Orchestrator states the full problem plainly.
2. Researcher produces source-backed evidence, the sprint scratchpad, and the full slice plan.
3. Reviewer reviews the research package and rejects vague, under-scoped, or worker-inventing planning.
4. Researcher corrects the evidence, scratchpad, and slice plan until the reviewer accepts them.
5. Orchestrator seeds the accepted sprint plan for execution.

Planning completion gate:

- Planning is complete only when the sprint is fully and explicitly scoped into sequential worker slices.
- Every slice must have:
  - exact allowed files
  - exact required shape
  - exact tests
  - exact non-goals
  - exact stop conditions
  - accountable planning session ids
- Accepted planning artifacts must record:
  - orchestrator session id
  - researcher/worker session id
  - reviewer session id
  - commit-hash receipt status
- Research planning artifacts must be reference-first:
  - historical local artifacts are navigation only
  - stable reference anchors and current source re-proof carry the authority
  - the active research artifact must include a compact anchor map for the references and current owner seams that actually govern the next decision
- If the accepted planning package is documentation-only and no dedicated commit exists yet, the artifact must say so explicitly and the orchestrator must close that receipt when archiving the accepted package.

## Sprint Execution

- Coder executes slices sequentially for the full sprint after planning settled the full sprint.
- The same reviewer from the research/planning step reviews the execution slices.
- No execution-phase redesign, narrowing, or rescoping is allowed unless the user explicitly intervenes.

Execution order:

1. Orchestrator seeds the next accepted slice from the sprint queue with the receipt fields the coder and reviewer will require, including coder/worker session id and commit-hash demand.
2. Coder implements only that slice.
3. The same reviewer from planning reviews the actual diff and gates acceptance or rejection.
4. Orchestrator verifies the slice after the review verdict.
5. Orchestrator records receipts and the accountable final decision.
6. If the reviewer accepted and verification passed, the slice is accepted.
7. If the reviewer rejected or verification failed, the slice is rejected and restarted at the earliest broken stage.
8. If accepted, move to the next queued slice and repeat.

Execution acceptance gate:

- A slice is accepted only with:
  - commit hash
  - orchestrator session id
  - researcher session id when research or correction backed the slice
  - reviewer session id
  - coder/worker session id
  - required verification results

## Hard Stops

- Drop work from acceptance and restart from the earliest broken stage if:
  - any teammate concludes the user may need to understand the references better before work can continue
  - any teammate sees user direction that appears to invent truths against the references without an explicit receipted override
  - coder invents names, scope, tests, or ownership
  - reviewer changes from the accepted planning reviewer without explicit reassignment
  - receipts are missing
  - execution broadens or narrows the sprint without user direction
  - implementation reveals the sprint plan was not actually settled
  - work happened outside the loop

When this stop is triggered:

- block work
- surface the reference conflict plainly to the user
- do not continue until the user resolves it or records an explicit override receipt

## Rule

- Accountability is the workflow.
- Every accepted slice needs receipts.
- Accepted planning packages also need receipts. The orchestrator must either record the commit-hash receipt on acceptance or record the exact missing receipt as an open handoff that blocks archival completion.
- Work outside the loop is dropped and redone from the earliest missing accountable stage.
- Live accountability files are read first.
- Broad repo doc browsing before reading the live accountability surface is a workflow violation.
- If the user checks workspace guidance files at any point and they are stale, wrong, misplaced, or incomplete against the real work state, the work is dropped from acceptance.

## Active Artifact Rule

- `loops/`, `research/`, and `sprints/` are the live accountability surface.
- Only current active artifacts may live directly inside those folders.
- Historical artifacts must move into the domain-local archive folders:
  - `loops/done/`
  - `loops/defered/`
  - `research/done/`
  - `research/defered/`
  - `sprints/done/`
  - `sprints/defered/`
- If stale or historical artifacts are left in the active folders, accountability is weakened and work should stop until the active surface is cleaned.
- No stale files may linger in active folders.
- No invented files may be created outside the active scope.
- Active/done/defered placement is part of the work, not optional cleanup.

## Read Order

Before any non-trivial work, read in this order:

1. `loop/flow.md`
2. all role docs under `loop/`:
   - `loop/orcestrator.md`
   - `loop/researcher.md`
   - `loop/reviewer.md`
   - `loop/coder.md`
3. the role doc for the current task, reread with special attention
4. `sprints/current.txt`
5. active `loops/*.txt` files explicitly seeded for the task
6. active `research/` files explicitly seeded for the task

Only after that may the role read additional source, project docs, or external references required by the task.
