# Workflow

Owner: workspace root.

Purpose: the default change loop for Howl.

## Doc Set
- `AGENTS.md`: workspace rules and owner boundaries.
- `WORKFLOW.md`: change loop, proof expectations, and commit cadence.
- `design/design-rules.md`: documentation rules.

## Default Loop
1. Read the boundary.
2. Identify the true owner.
3. Simplify the control spine first.
4. Move leaf behavior toward the true owner.
5. Add or tighten assertions around the invariant.
6. Prove the changed path.
7. Update docs in the same checkpoint.
8. Commit and push.

## Start Conditions

Before editing, answer these questions:

- Which repo owns this state?
- Which file owns this control flow?
- Which thread owns this work?
- What proof closes the change?

If any answer is unclear, stop and mark `work-not-clear`.

## Control-Flow Rule

Howl prefers one obvious control spine per runtime.

- Main-thread loops stay in the host entry owner.
- Background threads do bounded work and wake the main owner when needed.
- Leaf helpers do not hide scheduling policy.
- A loop turn should be readable top to bottom without chasing unrelated files.

## Change Shapes

### Boundary Change

- update the owning design doc
- update the owning boundary reference if the owner moved
- keep the public surface boring

### Runtime Change

- simplify the owner loop first
- prove the hot path with logs, tests, or runtime proof
- trim logs back to the smallest useful proof set afterward

### Cross-Repo Change

- change the lowest true owner first
- then change the consuming repo
- keep commit boundaries truthful per repo

## Proof Rules

A change is not closed because the code looks right.

Close with the strongest proof the owner can provide:

- unit tests for local logic
- build/test proof for repo health
- bounded runtime proof for host loops and render/input paths
- multi-host proof for user-visible parity changes

If proof is missing, leave the work open explicitly.

## Documentation Rules

Docs are part of the checkpoint, not cleanup afterward.

Update docs when any of these move:

- public API shape
- owner boundary
- lifecycle
- proof requirement
- runtime flow

## Commit Rules

- keep each commit about one meaningful checkpoint
- use commit messages that describe the boundary or invariant being locked
- push after each meaningful checkpoint
- do not batch unrelated repo changes into one commit message theme

## Debugging Rules

When a runtime path is unclear:

1. make the owner loop explicit
2. add one-time proof logs at seam boundaries
3. verify the first successful path
4. verify steady-state behavior
5. remove logs that are no longer earning their keep

Do not leave noisy trace scaffolding in the steady state.

## Stop Rules

Stop and escalate when:

- ownership is unclear
- two owners both mutate the same state
- the shortest correct change requires a new layer
- proof and behavior disagree

In these cases, write down the open edge instead of guessing.
