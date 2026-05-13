# Backend Parity Sprint

Owner: workspace root.

Purpose: define Sprint 2 as an architect-owned GL/GLES backend parity push with explicit gates,
checkpoint order, and closure bar.

## Problem

Howl has two render backends for one reason: to prove one rendering contract across more than one
graphics API.

Today, GL and GLES still show structural drift:

- backend-local policy appears in places that should be shared or hoisted to a smaller seam
- one backend can end up more mature, more defensive, or more complete than the other
- a future backend such as Metal or Vulkan would risk learning two architectures instead of one
- parity talk can degrade into drift preservation if the contract is not stated aggressively

The problem is not that two APIs differ. The problem is any difference that is not forced by the
graphics API.

## North Star

GL and GLES are not peers to compare politely.

They are two implementations of one backend contract.

Any unexplained structural mismatch is a defect until proven otherwise.

Sprint 2 closes only when adding another backend is mostly mechanical because the contract is clear,
the staged spine is shared, and the remaining differences are truly API-forced.

## Rules

- Do not use abstract seam names.
- Use concrete code nouns only.
- Do not preserve asymmetry just because it already exists.
- Do not let one backend prove lifecycle, shaping, upload, submit, or cleanup more strongly than the
  other.
- Do not let platform policy leak through multiple backend layers if a smaller seam can own it.
- Do not let docs close a checkpoint that code and proof do not support.

## In Scope

- `howl-render/src/backend/gl/`
- `howl-render/src/backend/gles/`
- `howl-render/design.md` only when the backend contract needs sharper wording
- render-local parity docs only when they describe the actual contract and actual mismatch ledger

## Out Of Scope

- host architecture planning
- VT or PTY work
- broad render text architecture outside the backend parity surface unless a touched backend seam
  truly forces it
- adding a new backend in this sprint

## Contract Questions

Every checkpoint must answer before editing:

- what is the one backend contract being enforced here
- which GL file and GLES file pair across this checkpoint
- which differences are forced by the graphics API
- which differences are only drift
- what proof closes the changed path

If those answers are unclear, close the checkpoint with `work-not-clear`.

## Milestones

### Milestone 1

Theme: backend spine canonization.

Goal:

- force GL and GLES onto the same staged backend architecture
- move special casing up to the smallest true seam where possible

Checkpoints:

1. `internal/c_api.zig` and `internal/provider.zig` seam parity
2. `backend.zig` lifecycle parity
3. backend root public-surface parity

Milestone closes when:

- provider and C seams are structurally aligned
- shaping and font special casing live at the smallest true seam
- backend root lifecycle phases read in the same order on both sides

### Milestone 2

Theme: font, raster, and atlas parity.

Goal:

- make GL and GLES equally strong in text, fallback, raster, and atlas behavior

Checkpoints:

1. primary and fallback font lifecycle parity
2. glyph lookup and shaping parity
3. raster special-case parity
4. atlas upload and residency parity

Milestone closes when:

- one backend is not carrying more font or raster policy than the other without API cause
- fallback and atlas paths are equally defensive

### Milestone 3

Theme: submit, proof, and future-backend closure.

Goal:

- finish parity at prepare, submit, and proof surfaces
- lock a future-backend checklist that Metal or Vulkan could follow mechanically

Checkpoints:

1. prepare or submit or one-shot render parity
2. metrics and error-surface parity
3. future-backend checklist and parity ledger closure

Milestone closes when:

- GL and GLES have the same maturity, completeness, and defensiveness
- a future backend would implement one checklist, not infer two architectures

## Review Gates

A checkpoint fails review if it does any of the following:

- explains away an unexplained GL/GLES mismatch instead of classifying it as drift
- introduces abstract seam naming instead of using concrete code nouns
- preserves backend-local special casing that can move up to a smaller seam
- leaves one backend with weaker lifecycle proof or weaker defensive checks
- mixes unrelated backend areas into one checkpoint
- closes without saying which side is ahead where they still differ

## Proof Gates

Do not accept a checkpoint unless all of the following are true:

- `nu "./style.nu" --touched-files` is clean or the touched-file output is explicitly justified
- `nu "./style.nu" --failures` is clean
- `zig build test:render` passed in `howl-render`
- if the changed backend path reaches the owning host seam, `zig build install` passed in
  `howl-hosts/howl-linux-host`
- `git diff --check` passed for all touched files

## Handoff Model

The architect sets the contract, the checkpoint scope, and the rejection criteria.

The engineer executes within those bounds.

The engineer does not set sprint direction, milestone gates, or contract wording.

Normal checkpoint size:

- one coherent backend seam or lifecycle slice
- or a small same-owner batch when GL and GLES files must move together
- soft churn cap: roughly 1000 changed lines per checkpoint unless the architect explicitly expands
  scope

## Current Starting Point

Sprint 2 starts with one in-flight backend parity candidate in `howl-render`.

That candidate is not accepted by default.

It must be reviewed only as:

- Milestone 1
- Checkpoint 1
- `internal/c_api.zig` and `internal/provider.zig` seam parity

No further backend work should stack on top until that checkpoint is explicitly accepted or rejected.

## Success Condition

Sprint 2 closes only when all of the following are true:

- GL and GLES read like two implementations of one backend architecture
- all remaining differences are proven API-forced
- lifecycle, shaping, upload, submit, cleanup, and proof surfaces are equally mature on both sides
- a Metal or Vulkan backend would mostly be a mechanical implementation of the same contract
