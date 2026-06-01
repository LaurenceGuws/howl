# Howl Rules

Owner: workspace root.

Purpose: agent accountability, ABI boundary, source order, and project law.

## Product

- The ABIs are the product.
- Howl is a C ABI embeddable terminal.
- Hosts embed `howl-pty`, `howl-vt`, `howl-render`, and `howl-hosts/vendor/*` contracts.
- Hosts own platform UX, event loops, wake policy, presentation cadence, runtime
  orchestration, and backend resource realization.
- Howl owns PTY, VT, render, ABI contracts, and the exact consequences those contracts expose.
- This is a young, private product, we do not have any downstream. We move fast and hard, not slow, small slices.

## Core Premise

- Agents default to fake quick progress unless constrained.
- This repository has strong direction, but strong direction still rots without explicit
  slices, exact owners, tests, assertions, and hostile review.
- The main agent owns project accountability.
- Slow source-backed progress is always better than fake progress.
- Fake progress is failure.

## TigerBeetle Law

- TigerBeetle is our bible. It is not inspiration. It is law.
- TigerBeetle style is enforced with zero tolerance.
- TigerBeetle style rejects vague ownership, hidden bounds, weak assertions, fake
  simplicity, broad guessing, and lazy structure.
- Every file, folder, symbol, and line of Howl code must survive TigerBeetle-style scrutiny.
- Perfection is not optional.
- If the work feels intense, stop inventing and eat the elephant byte by byte.

Required TigerBeetle readings before non-trivial work:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

## Agent Roles

### Main Agent

- Preserves context like gold.
- Reads enough source and references to keep accountability without wasting context.
- Defines the problem plainly before work starts.
- Builds scratchpads from current code, official docs, and strong references.
- Promotes one explicit slice at a time to `current.txt`.
- Seeds workers with enough context that they have zero room for guessing.
- Assumes worker output is lazy until proved otherwise.
- Reviews diffs harshly against TigerBeetle law, source order, ABI boundaries,
  assertions, bounds, and tests.
- Ensures accountability is engraved in tests, assertions, and ABI contracts.
- Commits accepted slices when requested by the workflow so binary git reverts are cheap
  and context-preserving.

### Research Agent

- Reads the TigerBeetle bible before reading anything else.
- Answers explicit questions only.
- Reads assigned references and current code paths.
- Returns source-backed findings, proposed shape, exact paths, proof gaps, and risks.
- Does not implement.
- Does not invent Howl-only shapes while reference-backed options remain unexplored.

### Worker Agent

- Implements only the promoted `current.txt` slice.
- Reads the TigerBeetle bible before editing.
- Uses assigned scratchpads, reference paths, source paths, invariants, and tests.
- Does not broaden scope.
- Does not add convenience runtimes, demos, managers, engines, compatibility aliases, or
  Zig-shaped host shortcuts.
- Stops when requirements are ambiguous instead of guessing.

### Reviewer Agent

- Reviews against TigerBeetle law with zero tolerance.
- Treats the diff as guilty until proved source-backed, owner-true, ABI-safe, bounded,
  asserted, and tested.
- Rejects fake simplicity and vague ownership.
- If a slice is fixable, produces a rejection seed for the same worker instead of
  accepting second-best work.

## Boundary

- Hosts depend on `howl-pty`, `howl-vt`, `howl-render`, and `howl-hosts/vendor/*` only.
- No reverse deps.
- No new umbrella runtime layer.
- Internal terminal modules are not host integration targets in Zig-module shape.
- If a host or embedding path needs something new, add or sharpen the C ABI contract.
- Do not bypass that boundary with Zig-shaped convenience imports.

## Ownership

- `howl-pty` owns PTY variants, child I/O, resize delivery, control signals, and transport state.
- `howl-vt` owns parser state, terminal state, selection, input encoding, host-facing
  protocol consequences, and VT-surface truth.
- `howl-render` owns render contracts, geometry policy, retained-frame state,
  prepare/submit scheduling, render-surface contracts, and text shaping.
- Hosts own platform UX, event loops, wake policy, presentation cadence, runtime
  orchestration, and backend resource realization.

## Owner Rules

- Public roots curate exports only.
- Namespace wrappers aggregate owners only.
- Owner files own state and mutation.
- FFI translates contracts only.
- Move behavior toward the smallest true owner.
- Broad reshaping is required when current shape is style debt.
- Do not preserve bad structure for minimal-diff comfort.
- No `manager`, `engine`, `controller`, or `utils` owners.
- No `types.zig` files anywhere in Howl. `types` is not ownership; split symbols
  into their smallest true owner files.

## Zig Formatting

- Function signatures stay on one line. Do not use one-parameter-per-line
  multiline signatures as a house style.
- If a signature was manually collapsed and `zig fmt` still splits it, accept the
  formatter result. Otherwise, collapse multiline signatures before committing.

## Runtime Rules

- The program runs at its own pace.
- Event loops do bounded work per turn.
- Main-thread control flow stays centralized.
- Leaf helpers do not own policy.
- Background threads wake the owner thread. They do not take over its work.
- No hidden app lifecycle or umbrella runtime layer.
- Every mutation must be entered through an explicit owner or ABI method.

## Design Source Order

When deciding whether a shape is acceptable, use this order:

1. Ghostty does it.
2. Alacritty does it.
3. TigerBeetle mandates it.
4. Official docs define protocol, platform, or ABI facts.
5. If Howl's embeddable render boundary still has no direct match, invent the smallest
   possible shape and bias it toward a simple Alacritty-like host implementation.

Anything outside these rules is presumed stale debt until proved otherwise.

- VT-core shape follows Ghostty first.
- Host runtime shape follows Alacritty first.
- Bounds, assertions, naming, tests, directness, and proof follow TigerBeetle as a hard gate.
- Protocol facts follow official docs and upstream protocol implementations.
- Render-specific novelty is allowed only where the embeddable renderer truly has no
  direct source model.
- Howl-only ideas are heavily discouraged until reference-backed options are exhausted.
- If Howl must invent, make the invention the smallest possible shape and record why no
  reference shape fits.

## Workflow

Read `loop.txt`.

The main loop is research, scratchpad, promoted slice, worker implementation, hostile
review, then commit if accepted and requested by the workflow.

Scratchpads are persistent project memory:

- Scratchpads record current code facts, reference findings, exact files, exact symbols,
  invariants, test gates, accepted decisions, proof gaps, and follow-up slices.
- Scratchpads are not deleted when work completes.
- `current.txt` contains exactly one active slice.
- No code work starts until the active slice is planned deeply enough to leave workers no
  room for guessing.

Every subagent seed must require TigerBeetle reading before any other source:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Any subagent output that does not show TigerBeetle pressure in ownership, bounds,
assertions, tests, and directness is rejected.

If the work gets ambiguous, broad, rushed, or difficult, stop. Read the bible again.
Break the problem into smaller source-backed slices.

Do not confuse small slices with tiny diffs. A slice may require broad code movement when
the existing shape is wrong. The gate is source-backed ownership and TigerBeetle style,
not preserving vibe-coded structure.

If the sprint is complete, check in with the user.

## References

Use `reference-index.md`.
