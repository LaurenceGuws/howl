# Render capability reset scratchpad

Current slice: `classify_terminal_visual_values`

This tracked file contains only current-slice working state. Promote accepted
facts and commits into `sprint_render_capability_reset.yml`, then reset it for
the next slice or delete it when no slice remains active.

## Required outcome

Classify every symbol in `howl-render/src/howl_frame.zig` before changing its
implementation. Separate backend-neutral terminal visual knowledge from
rejected runtime policy, executable evidence, and removable tests.

## Settled facts

- VT owns terminal semantic state and dirty facts.
- Render owns backend-neutral terminal visual knowledge and plain rendering
  values without runtime policy.
- The executable owns publication storage and runtime coordination.
- Control has no rendering relation.
- Every module allocation uses an explicit caller-provided allocator.
- File location and current consumers do not establish ownership.

## Required classification

For every public and private type, function, constant, test family, allocation,
lock, and import in `howl_frame.zig`, record:

- exact symbol and source range;
- current purpose and consumers;
- allocation, ownership, lifetime, and cleanup;
- one disposition: retain in render, executable evidence, delete, or discussion;
- concrete reason grounded in settled ownership;
- behavior/proof worth preserving independently of the current API.

## Explicit rejected families

- Publication slots and two-slot policy.
- Mutexes and runtime synchronization.
- Borrow/release and renderer acknowledgement.
- Runtime generations, saturation, and retirement policy.
- Resize reservation or storage policy belonging to the executable.
- Tests whose only subject is a rejected runtime API.

## Discussion gate

Do not decide the VT/render transformation API during classification. Return
concrete evidence needed to decide:

- transformation owner;
- input and output types;
- dependency direction;
- allocation and lifetime contract;
- whether a public transformation API is earned.

## Validation

- [ ] Every symbol and test family is accounted for exactly once.
- [ ] No classification follows current file placement by default.
- [ ] Visual behavior is separated from publication/runtime policy.
- [ ] Allocation and borrowed lifetimes are explicit.
- [ ] No source implementation changes are made.
- [ ] Findings are concise enough to promote into the sprint discussion gate.

## Immediate next action

Produce the complete read-only symbol inventory and recommended dispositions,
then return it for pedantic review and the supervised VT/render boundary decision.
