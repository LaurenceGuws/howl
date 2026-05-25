# Build/Test Architecture Blocker Scratchpad

Owner: workspace root.

Purpose:

- Record the current repo-wide blocker before more bug work or feature work proceeds.
- Define the need for a full architecture plan for tests, build entrypoints, install behavior, and auditability.

## Blocker

- The repo appears to have a large, fragmented verification surface and inconsistent build/entrypoint contract.
- There is no clearly documented repo-wide strategy for:
  - test taxonomy
  - build-step taxonomy
  - install/default-step behavior
  - package ownership of verification surfaces
  - auditability of what each step proves

## Consequence

- Adding more tests, tools, fuzzers, harnesses, and run/build entrypoints without a governing plan increases confusion and review cost.
- Before more local fixes proceed, we need a documented plan to go from current state to best-in-class organization.

## Research Goal

- Produce a comprehensive, documented, repo-wide plan covering:
  - current inventory
  - classification
  - gaps
  - normalization targets
  - migration order
  - acceptance criteria

## Constraint

- This is research and planning only.
- No code edits should be proposed as already accepted without an explicit follow-up review loop.
