# TigerBeetle Rules We Can Extract

Source set:

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

## Machine-Countable Signals

- Count `assert(...)` sites.
- Count `usize` sites.
- Count function definitions.
- Count functions longer than `70` lines.
- Count top-level Zig `test` blocks.
- Count test-path code separately from production code.

## Safety Rules

- Use simple, explicit control flow.
- Do not use recursion.
- Put a limit on everything.
- Event loops must have an asserted bounded-work shape.
- Prefer explicitly-sized integers over `usize` for domain state.
- Assertions are required, not decorative.
- Assertions should check arguments, invariants, and postconditions.
- Pair assertions across multiple code paths when possible.
- Prefer `assert(a); assert(b);` over compound assertion clauses.
- Use positive-space and negative-space assertions.
- All errors must be handled.

## Structure Rules

- Declare variables at the smallest possible scope.
- Keep functions within `70` lines when possible.
- Push `if`s up and `for`s down.
- Centralize control flow in one owner function.
- Centralize state mutation in the owner function.
- Leaf helpers should avoid owning policy.
- Callbacks go last in parameter lists.

## Runtime Rules

- The program should run at its own pace instead of reacting directly to external events.
- Bound work per turn.
- Keep steady-state control flow explicit.
- Prefer batching.
- Avoid runtime allocation after initialization when the design allows explicit bounds.

## Build And Dependency Rules

- Keep dependencies explicit.
- Prefer zero or minimal dependencies.
- One build authority is better than split build ownership.

## Comment And Naming Rules

- Comments must explain why, not what.
- Naming should be consistent and intentional.
- Code should encode the mental model directly.

## Architecture Rules

- Design from first principles, then validate with experiments.
- Compute explicit worst-case bounds up front.
- Keep ownership clear.
- Move non-hot-path work off the hot path.
- Simpler programming models improve testing and reliability.
