# Howl Rules

Owner: workspace root.

Purpose: workspace boundary and source order.

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

## Workflow

Read `loop.txt`.

## References

Use `reference-index.md`.
