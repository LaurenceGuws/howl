# Style Law

Owner: workspace root.

Purpose: strict workspace style law for pass or fail review.

## Scope

- This law applies to production code, tests, scripts, and docs unless a rule says otherwise.
- Repo `design.md` files own boundary facts. This file owns strict style rules.

## Control Flow

- Use only simple, explicit control flow.
- Do not use recursion.
- Centralize control flow in one parent function when a path branches.
- Push `if`s up and `for`s down.
- Leaf helpers do not own policy.
- Background threads wake the owner thread. They do not take over its work.
- Event loops do bounded work per turn.

## Bounds

- Put a bound on everything.
- Queues, retries, scans, caches, and per-turn work need explicit limits.
- If a loop is intentionally non-terminating, state the owner and the bound on each turn.

## Functions

- Functions must fit on one screen when possible.
- The hard limit is 70 lines per function body.
- If a function exceeds 70 lines, split it by ownership, not by line count theater.
- Parent functions keep branch control and local state.
- Helpers compute or apply one owned step.

## Assertions

- Assertions are for invariants, not decoration.
- Assert arguments, return conditions, preconditions, postconditions, and state transitions where the owner can prove them.
- Pair assertions on important invariants when two seams exist.
- Split compound assertions when separate checks make failure more exact.
- Use positive assertions for the state you expect and negative assertions for the state you reject.

## Types And State

- Prefer explicitly sized integers for domain state.
- Do not use `usize` for domain state unless the value is truly architecture-sized.
- Declare variables at the smallest practical scope.
- Keep the number of live mutable variables small.

## Naming

- Use short, specific nouns and verbs.
- Do not add ambiguous public names such as `adapter`, `bridge`, `bootstrap`, `manager`,
  `helper`, `util`, or `pattern`.
- Do not add sentence-style symbol names.
- Name things by owner and behavior, not by convenience.

## Comments

- Comments explain why, not what.
- Write the rationale where a reviewer would otherwise have to infer policy.
- Remove comments that restate the code.
- Source comments should lock a local invariant, boundary constraint, non-obvious rationale, or
  reviewer trap.
- Source comments must not restate architecture, ownership slogans, or workspace worldview already
  owned by docs and code structure.
- Repetitive file-header narration is not allowed.

## Options And Defaults

- Pass library and API options explicitly at the call site when defaults matter to correctness,
  ownership, or proof.
- Do not hide important policy in implicit defaults.

## Boundaries

- Public roots curate exports only.
- Namespace wrappers aggregate owners only.
- Owner files own state and mutation.
- FFI files translate contracts only.
- Do not add wrappers that only forward without owning a boundary difference.

## Review Gates

- A change fails style review if it adds unbounded work, hidden policy, vague ownership, or longer
  functions where a cleaner owner split was available.
- A change fails style review if it adds `usize` domain state without justification.
- A change fails style review if comments explain what the code does but not why the owner chose it.
- A change fails style review if source comments narrate architecture or ownership instead of
  locking a local constraint.
- A change fails style review if a helper or wrapper hides the true control spine.
