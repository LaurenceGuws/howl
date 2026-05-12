# Howl-Term Render Reset Handover Model

Purpose: define how the architect slices this sprint into engineer-agent handovers, and define the
review gates that must be met before any handover is accepted, committed, or pushed.

Proof layer: contract

Last updated: 2026-05-12

## Roles

Architect responsibilities:
- define the owner chain
- define the milestone and checkpoint scope
- define the seed handover for the engineer agent
- review the returned work against TigerBeetle bars
- accept or reject the work
- commit and push only accepted work

Engineer-agent responsibilities:
- execute exactly the handed-over scope
- preserve layering and owner boundaries
- return a factual report with changed files, tests run, open risks, and any `work-not-clear`
  moments
- do not expand scope silently

User responsibilities:
- carry the handover to the engineer agent
- bring the engineer report back to the architect for review

## Architect Review Law

Nothing is accepted if it misses the TigerBeetle bar.

Specifically, the architect rejects work that:
- preserves the old architecture through wrappers or aliases
- leaves stale dead code or stale tests behind
- widens scope beyond the handover
- introduces unclear ownership
- uses comments as decoration instead of rationale
- leaves obvious invariant boundaries unasserted
- increases giant files without an owner-based split plan in the same scoped work

The architect does not rescue weak work by rewriting the acceptance standard after the fact.

## Universal Handover Shape

Each engineer handover must contain these sections:

### 1. Scope

- one milestone or at most two adjacent checkpoints
- exact in-scope files
- explicit out-of-scope files

### 2. Goal

- plain-English statement of what must be true when the handover is done

### 3. Required Deletes

- exact files, fields, helpers, comments, tests, or APIs that must be removed

### 4. Required Adds Or Moves

- exact owners or contracts that must be created or filled in

### 5. TigerBeetle Gates

- `usize` rules
- assert rules
- test rules
- intent-comment rules
- simplicity rules
- stale-code purge rules

### 6. Proof Required From Engineer

- compile proof
- unit-test proof
- integration-test proof if applicable
- exact statement of what was not proven

### 7. Rejection Triggers

- specific conditions that cause the architect to reject the handover on review

## Universal TigerBeetle Gates

These gates apply to every handover in this sprint.

### `usize` Gate

- public contracts use explicit integer widths unless the value is truly an index, slice length, or
  allocation size
- conversions between integer domains are local, explicit, and asserted where interesting

### Assert Gate

- touched functions assert preconditions
- touched state transitions assert invariants
- touched boundary conversions assert assumptions
- split compound assertions where clarity improves
- paired assertions are preferred at both ingress and egress of important boundaries

### Test Gate

- positive path covered
- negative path covered
- stale or invalid transition path covered where applicable
- geometry or retained-base edge covered where applicable
- deleted behavior no longer has tests preserving it by accident

### Intent-Comment Gate

- comments explain why or how
- comments are sparse and precise
- surprising invariants may be documented with assertions instead of prose where stronger
- no comments that merely narrate the code

### Simplicity Gate

- one obvious owner per mutable responsibility
- one obvious hot path per scoped change
- no dual-path compatibility story unless the architect explicitly asked for one
- no new abstraction unless it removes more complexity than it creates

### No-Traces-Of-Old-Code Gate

- no legacy wrappers
- no dormant files
- no commented-out old code
- no stale tests
- no stale docs
- no dead fields kept "until later"

## Default Engineer Report Format

The engineer report should be returned in this shape:

1. Scope completed
2. Files changed
3. Deletes performed
4. Assertions added or updated
5. Tests run and results
6. Open risks or unproven areas
7. Any `work-not-clear` decisions encountered

## Recommended Handover Size

Preferred size:
- one milestone if it is documentation-only
- one checkpoint or two tightly coupled checkpoints if it changes code

Do not hand over:
- Milestones 2 through 6 all at once
- unrelated cleanup plus behavior changes in the same handover
- architecture work and benchmark victory work in one bundle

## Initial Handover Bundles

### Handover A

Scope:
- Milestone 2, Checkpoint 2.1
- Milestone 2, Checkpoint 2.2

Goal:
- sever all references to `howl-term/src/render/*` and delete the directory early

Why this bundle is safe:
- architecture is already decided by the sprint doc and owner table
- this bundle is destructive on purpose and should not be diluted with later rebuild work

Required deletes:
- imports of `src/render/*`
- terminal delegations to deleted render owners
- dead tests tied to the deleted files
- the `src/render/` directory itself

Required report focus:
- exact compile breaks remaining after deletion
- exact old references removed
- whether any stale wrappers were tempting and refused

### Handover B

Scope:
- Milestone 3, Checkpoint 3.1
- Milestone 3, Checkpoint 3.2

Goal:
- establish the replacement terminal source seam and render runtime seam

Required report focus:
- final contract shapes
- deleted old contract shapes that were intentionally not preserved
- assertions on the new seam

### Handover C

Scope:
- Milestone 4, Checkpoint 4.1
- Milestone 4, Checkpoint 4.2
- optionally 4.3 if the engineer proves the scope stayed coherent

Goal:
- move render runtime ownership fully into `howl-render-core`

Required report focus:
- exact `HowlTerm` fields removed
- exact new render-core owners added
- queue and geometry invariants now enforced in the new owner

### Handover D

Scope:
- Milestone 5, Checkpoint 5.1
- Milestone 5, Checkpoint 5.2

Goal:
- make the Linux host and public surface teach the new architecture only

Required report focus:
- host wake and redraw flow
- deleted old ABI or Zig surface semantics
- proof that host code is no longer compensating for library-owned render policy

### Handover E

Scope:
- Milestone 6, Checkpoint 6.1
- Milestone 6, Checkpoint 6.2
- Milestone 6, Checkpoint 6.3

Goal:
- raise the hygiene bar after the owner move is real

Required report focus:
- file-size reductions
- assertion density improvements
- test ownership cleanup

## Architect Acceptance Checklist

Before committing and pushing, the architect checks:
- does the work match the handover scope exactly?
- did old code actually get deleted?
- did ownership get simpler?
- do assertions state the important invariants clearly?
- do tests cover negative space, not just the happy path?
- do comments explain why, not what?
- did giant files shrink or at least avoid growth when the handover claimed cleanup?
- did the engineer report admit what was not proven?

If any answer is no, reject the handover.
