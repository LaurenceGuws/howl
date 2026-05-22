# Howl Rules

Owner: workspace root.

Purpose: workspace boundary, source order, and change loop.

## Product

- The ABIs are the product.
- Howl is aiming at a C ABI embeddable terminal.

## Boundary

- Hosts depend on `howl-pty`, `howl-vt`, `howl-render`, and `howl-hosts/vendor/*` only.
- No reverse deps.
- No new umbrella runtime layer.
- Internal terminal modules are not host integration targets in Zig-module shape.
- If a host or embedding path needs something new, add or sharpen the C ABI contract.
- Do not bypass that boundary with Zig-shaped convenience imports.

## Ownership

- `howl-pty` owns PTY variants, child I/O, resize delivery, control signals, and transport state.
- `howl-vt` owns parser state, terminal state, selection, input encoding, host-facing protocol consequences, and VT-surface truth.
- `howl-render` owns render contracts, geometry policy, retained-frame state, prepare/submit scheduling, render-surface contracts, and text shaping.
- Hosts own platform UX, event loops, wake policy, presentation cadence, runtime orchestration, and backend resource realization.

## Owner Rules

- Public roots curate exports only.
- Namespace wrappers aggregate owners only.
- Owner files own state and mutation.
- FFI translates contracts only.
- Move behavior toward the smallest true owner.

## Runtime Rules

- The program runs at its own pace.
- Event loops do bounded work per turn.
- Main-thread control flow stays centralized.
- Leaf helpers do not own policy.
- Background threads wake the owner thread. They do not take over its work.

## Design Source Order

When deciding whether a shape is acceptable, use this order:

1. Ghostty does it.
2. Alacritty does it.
3. TigerBeetle mandates it.
4. If Howl's embeddable render boundary still has no direct match, invent the smallest possible shape and bias it toward a simple Alacritty-like host implementation.

Anything outside these rules is presumed stale debt until proved otherwise.

- VT-core shape follows Ghostty first.
- Host runtime shape follows Alacritty first.
- Bounds, assertions, simplicity, and proof follow TigerBeetle as a hard gate.
- Render-specific novelty is allowed only where the embeddable renderer truly has no direct source model.

## Default Loop

1. Read the boundary.
2. Identify the true owner.
3. Simplify the control spine first.
4. Move leaf behavior toward the true owner.
5. Add or tighten assertions around the invariant.
6. Remove any Zig-module-shaped bypass that fights the C ABI boundary.
7. Prove the changed path.
8. Update docs in the same checkpoint when boundaries, proofs, or public contracts move.
9. Review the actual diff against owner, proof, and style gates.

## Start Conditions

Before editing, answer these questions:

- Which repo owns this state?
- Which file owns this control flow?
- Which thread owns this work?
- Is this path honoring the C ABI boundary, or sneaking around it through Zig module structure?
- What proof closes the change?

If any answer is unclear, stop and mark `work-not-clear`.

## Stop Rules

Stop and escalate when:

- ownership is unclear
- two owners both mutate the same state
- the shortest correct change requires a new layer
- the path only works by bypassing the intended C ABI boundary through Zig imports
- proof and behavior disagree

In these cases, write down the open edge instead of guessing.

## References

Use `reference-index.md`.
