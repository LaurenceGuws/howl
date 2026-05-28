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
- `howl-vt` owns parser state, terminal state, selection, input encoding,
  host-facing protocol consequences, and VT-surface truth.
- `howl-render` owns render contracts, geometry policy, retained-frame state,
  prepare/submit scheduling, render-surface contracts, and text shaping.
- Hosts own platform UX, event loops, wake policy, presentation cadence,
  runtime orchestration, and backend resource realization.

## Owner Rules

- Public roots curate exports only.
- Namespace wrappers aggregate owners only.
- Owner files own state and mutation.
- FFI translates contracts only.
- Move behavior toward the smallest true owner.
- Broad reshaping is encouraged when the current code shape is itself style debt.
- Do not preserve bad structure for minimal-diff comfort.

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
4. If Howl's embeddable render boundary still has no direct match, invent the smallest
   possible shape and bias it toward a simple Alacritty-like host implementation.

Anything outside these rules is presumed stale debt until proved otherwise.

- VT-core shape follows Ghostty first.
- Host runtime shape follows Alacritty first.
- Bounds, assertions, simplicity, and proof follow TigerBeetle as a hard gate.
- Render-specific novelty is allowed only where the embeddable renderer truly has no
  direct source model.
- Howl-only ideas are heavily discouraged until reference-backed options are exhausted.
- If Howl must invent, make the invention the smallest possible shape and record why no
  reference shape fits.

## Workflow

Read `loop.txt`.

TigerBeetle is our bible. It is not inspiration. It is law.

TigerBeetle style must crawl through every line of Howl code. It does not crawl on bad
style. It rejects vague ownership, hidden bounds, weak assertions, fake simplicity, and
rushed guesses. Zero tolerance.

All three working roles must read the TigerBeetle bible before non-trivial work:

- Main agent before promoting a slice or directing workers.
- Worker agent before implementing a slice.
- Reviewer agent before accepting or rejecting a slice.

The TigerBeetle bible is:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

If the work gets ambiguous, broad, rushed, or difficult, stop. Read the bible again.
Break the problem into smaller source-backed slices. Slow progress is always better than
fake progress. Fake progress is failure.

Do not confuse small slices with tiny diffs. A slice may require broad code movement when
the existing shape is wrong. The gate is source-backed ownership and TigerBeetle style,
not preserving vibe-coded structure.

## References

Use `reference-index.md`.
