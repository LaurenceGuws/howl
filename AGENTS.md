# Howl Rules

Owner: workspace root.

Purpose: agent accountability, ABI boundary, source order, and project law.

## Product

- The ABIs are the product.
- Howl is a C ABI embeddable terminal.
- C ABI only is non-negotiable. Host integration does not get Zig-shaped convenience APIs.
- Hosts embed `howl-pty`, `howl-vt`, `howl-render`, and `howl-hosts/vendor/*` contracts.
- Hosts own platform UX, event loops, wake policy, presentation cadence, runtime
  orchestration, and backend resource realization.
- Howl owns PTY, VT, render, ABI contracts, and the exact consequences those contracts expose.
- GL is only the first host backend. It is not the renderer architecture.
- Hosts consume render surfaces host-side. Window chrome does not own render-surface consumption,
  backend resource realization, GL texture ownership, presentation pacing, or render policy.
- This is a young, private product, we do not have any downstream. We move fast and hard, not slow, small slices.

## Reference Pressure

- The user owns product direction and all non-negotiables.
- Alacritty carries the main pressure for host runtime, event loop, display, window,
  input, presentation, and most renderer organization.
- TigerBeetle carries the main pressure for Zig discipline: exact names, owner truth,
  assertions, bounds, source order, directness, and tests.
- Ghostty is selective pressure for embedding seams and VT shape.
- Kitty is selective pressure for UX and protocol maturity.
- Official docs define protocol, platform, ABI, and OS facts.
- Howl-only architecture is presumed wrong until the references and user boundary prove
  that no source-backed shape exists.

For host/display/window/render organization, ask these questions before accepting any
concept, folder, file, symbol, or data shape:

1. Does Alacritty have this concept?
2. Does Alacritty have this folder boundary?
3. Does Alacritty have this file boundary?
4. Does Alacritty have this symbol or data-shape pattern?

If Alacritty directly fights the user's C ABI or embeddable render boundary, stop for
orchestrator/user review. Otherwise Alacritty wins host-shape disputes.

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
- Never hands new implementation work to a worker on an unpushed accepted tree. Workers,
  reviewers, and the main agent must be able to diff the worker's exact changes cleanly.
- If reviewer accepts most work with one or two minor issues, fixes those issues directly,
  verifies, commits, and pushes instead of muddying the tree with another worker handoff.

### Research Agent

- Reads the TigerBeetle bible before reading anything else.
- Answers explicit questions only.
- Reads assigned references and current code paths.
- Returns source-backed findings, proposed shape, exact paths, proof gaps, and risks.
- Does not implement.
- Does not invent Howl-only shapes while reference-backed options remain unexplored.

### Worker Agent

- Implements only the promoted `current.txt` slice.
- Reads the role preload before editing. Do not re-read large preloads on follow-up tasks
  in the same worker session unless instructed; use accepted caches and prior task context.
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
- No bucket structs. Do not add structs merely to group parameters, facts, options,
  diagnostics, context, or state unless a reference has the same data-shape pressure or
  the C ABI/product boundary forces it.
- Structs must be small, intentional data shapes with a true domain noun, owner,
  lifecycle, invariants, and tests. Generic buckets named `Context`, `State`, `Options`,
  `Config`, `Info`, `Data`, `Result`, or `Diagnostics` are rejected unless source-backed
  and owner-true.

## Tests

- Tests are organized by curated package roots per test class.
- No duplicate roots proving the same owner/class combination and no opportunistic side-entry test files.
- Owner-local tests are allowed inline in owner files or in sibling owner-true test files only when reached through exactly one curated root for that class.
- Benchmarks, simulations, stress surfaces, fuzzers, and similar non-proof surfaces must stay explicit and must not hide inside unit or ABI roots.
- Test wiring is ownership. Moving tests, adding test roots, filtering tests, or weakening
  gates requires explicit source-backed proof.

## Zig Formatting

- Function signatures stay on one line. Do not use one-parameter-per-line
  multiline signatures as a house style.
- The hard line limit is 190 characters. A signature longer than 190 characters
  must be split by owner-true structure, not preserved as a long line.
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

1. The user's product direction and non-negotiable C ABI boundary require it.
2. Alacritty does it for host/runtime/display/window/input/presentation/render organization.
3. Ghostty does it for VT shape or embedding seams.
4. Kitty does it for UX or protocol maturity.
5. TigerBeetle mandates it for Zig discipline, ownership proof, bounds, assertions, tests,
   directness, or source order.
6. Official docs define protocol, platform, ABI, or OS facts.
7. If Howl's embeddable render boundary still has no direct match, invent the smallest
   possible shape, record why no reference fits, and bias it toward Alacritty outside the
   C ABI boundary.

Anything outside these rules is presumed stale debt until proved otherwise.

- VT-core shape follows Ghostty first.
- Host runtime, display, window, input, presentation, and most renderer organization follow
  Alacritty first.
- Bounds, assertions, naming, tests, directness, source order, and proof follow TigerBeetle
  as a hard gate.
- Protocol facts follow official docs and upstream protocol implementations.
- Kitty and Ghostty are selective pressures, not broad host architecture owners.
- Render-specific novelty is allowed only where the user-owned embeddable renderer boundary
  truly has no direct source model.
- Howl-only ideas are rejected until reference-backed options are exhausted.
- If Howl must invent, make the invention the smallest possible shape and record why no
  reference shape fits.

## Workflow

Read `loop.txt`.

The work loop is adaptive, not ritual. The main agent chooses the role sequence that fits
the work, while preserving research, scratchpad, worker contract, hostile review, and
handoff accountability where they matter.

For a planned sprint lane with multiple candidate slices, the default posture is a parallel
worker-loop pipeline when the work allows it.

Default broad-sprint sequence:

1. Parallel research across the lane to produce the candidate slice list and source-backed classifications.
2. Pre-implementation review of each ready candidate slice for correctness and scope.
   - If pre-implementation review rejects a slice, the correction must be backed by a researcher session id before worker seeding resumes.
3. Parallel worker implementation across independent accepted slices when they do not share files, ownership moves, or verification risk.
4. Post-implementation reviewer pass on each actual diff.
5. Orchestrator decides slice-by-slice when work is pristine enough to accept, verify, commit, and push.

Use sequential implementation only when the work is coupled, slow, high-risk, or would create dirty-tree ambiguity between slices.

Scratchpads are persistent project memory:

- Scratchpads record current code facts, reference findings, exact files, exact symbols,
  invariants, test gates, accepted decisions, proof gaps, and follow-up slices.
- Scratchpads are not deleted when work completes.
- `current.txt` is the global loop index.
- Each active independent loop gets its own current-contract file under `loops/`.
- A loop file contains exactly one active slice for that loop.
- Every accepted slice needs a receipt.
- Every receipt must record the orchestrator session id, reviewer session id, and coder/worker session id.
- No code work starts until the active slice is planned deeply enough to leave workers no
  room for guessing.

Every fresh non-trivial subagent session must receive a role preload requiring TigerBeetle
reading before any other source:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

Any subagent output that does not show TigerBeetle pressure in ownership, bounds,
assertions, tests, and directness is rejected.

For follow-up tasks in the same subagent session, reference the prior role preload and
accepted caches instead of re-sending large context unless quality or clarity requires it.

Any summarize, compact, or handoff must order the next agent to read its role preload,
role work, active scratchpad, `current.txt`, the relevant active `loops/*.txt` file,
relevant research caches, reviewer findings, dirty-state notes, and verification results
before continuing.

If the work gets ambiguous, broad, rushed, or difficult, stop. Read the bible again.
Break the problem into smaller source-backed slices.

Do not confuse small slices with tiny diffs. A slice may require broad code movement when
the existing shape is wrong. The gate is source-backed ownership and TigerBeetle style,
not preserving vibe-coded structure.

If the sprint is complete, check in with the user.

## References

Use `reference-index.md`.
