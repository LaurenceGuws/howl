# Design Rules

## Purpose
This file defines the shared design language for product repos in `howl/`.

These docs are not classic OO teaching material.
They are owner-boundary docs for a low-level system.

## Core Model
- A repo exports boring public owners.
- Owners define the public API and lifecycle boundary.
- Internal units support owners and stay behind those boundaries.
- Diagrams should show responsibility, state, lifecycle, and call flow.
- Diagrams should not mirror every file mechanically.

## Terms
- Owner: the public surface callers are meant to depend on.
- Unit: an internal module or submodule with a narrow responsibility.
- Contract: a stable payload, enum, or method shape that other code relies on.
- Lifecycle: valid state transitions and call ordering.
- Flow: startup, input, render, shutdown, repair, or other important runtime path.

## Design Rules
- `root.zig` or root Java package owners should stay boring.
- Public owners may forward to sibling owner files.
- App entrypoints should depend on owners, not deep internal leaves.
- Public docs should explain why a boundary exists, not restate syntax.
- Visual docs should lock API intent and ownership rules, not implementation trivia.

## Required Sections
Each repo `design.md` should include:
- `Purpose`
- `Public Surface`
- `Ownership Rules`
- `Lifecycle`
- `Main Flows`
- `API Contracts`
- `Non-Goals`
- `Change Rules`

## Mermaid Rules
- Use `classDiagram` for owners and major contracts.
- Use `sequenceDiagram` for runtime flows.
- Use `stateDiagram-v2` for lifecycle.
- Use `flowchart TD` only when a sequence or state diagram is too awkward.
- Keep diagrams small enough to read without zooming into noise.

## What To Show
- Public owners and their exported contracts.
- Which owner owns lifecycle.
- Which owner owns mutable state.
- Which unit owns translation, rendering, I/O, config, or platform binding.
- Important call ordering and invariants.

## What To Avoid
- Inheritance-heavy UML unless the code actually uses it.
- Diagrams of private helpers with no design importance.
- File-by-file mirror diagrams.
- Future architecture speculation without labeling it as future.

## API Contract Rules
- Document required call ordering.
- Document ownership and cleanup rules.
- Document state transitions.
- Document whether a method mutates state, reports state, or forwards work.
- Document which surfaces are stable and which are internal.

## Change Rules
- New public APIs should be added to the repo `design.md` in the same change.
- Owner moves should update diagrams and ownership rules together.
- Internal refactors that do not change public design can keep diagrams unchanged.
- If a diagram becomes misleading, fix the doc immediately rather than letting it drift.
