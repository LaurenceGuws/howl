# Howl Agent Contract

Howl is a private native Zig terminal family with no downstream compatibility
obligation.

## Active projects

- `howl-vt` owns terminal parsing, state, input encoding, and host consequences.
- `howl-headless` owns one bounded native PTY host and semantic snapshot.

Each child repository owns its source contract and verification.

`howl-render` is retained unchanged for text salvage and remains outside the
active build until that work has a native owner.

## Source bar

- Delete stale ownership and ceremony before adding abstractions.
- Prefer direct domain types and explicit owner boundaries.
- Make ownership, cleanup, bounds, narrowing, invariants, and errors exact.
- Keep public surfaces curated and comments factual.
- Add proof for behavior and failure paths that the product owns.
- Preserve unrelated work in shared trees.

Use Foot for directness, TigerBeetle for defensiveness, Zig 0.16 for runtime
and build interfaces, and terminal references for protocol evidence.

## Parent boundary

The parent repository tracks active projects and runs their `check` steps. It
does not own product source, compatibility layers, workflow archives, or
cross-package runtime abstractions.
