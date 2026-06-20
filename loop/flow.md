# Workflow

## Current Mode

- Howl is currently in single-agent mode.
- The active workflow is direct user <-> single agent collaboration.
- Prior multi-agent choreography is discarded for now.
- The agent may move, rename, create, and delete files, folders, and symbols when the owner boundary requires it.
- Changes must be complete for the chosen slice, not cosmetic, partial, or compatibility-shaped.
- Every structural decision must be taken carefully, source-backed where references apply, and then implemented fully.
- The agent must keep the user informed at real decision points, especially before broad owner moves or boundary changes.

## Doctrine

- This is a private infant terminal, not a public CRUD app.
- There are no external consumers to preserve.
- Stability and compatibility instincts are harmful unless the user explicitly asks for them.
- No aliases, shims, fallback names, old paths, or compatibility glue for wrong structure.
- If a name lies, rename it everywhere.
- If a file is in the wrong owner, move it.
- If a folder boundary is fake, delete the boundary and rebuild the true one.
- If references show a better shape, chase it aggressively and try to beat the references at their own game.
- Existing Howl code is presumed guilty until the owner, reference pressure, assertions, and tests prove it right.
- Breaking code during a structural slice is acceptable; leaving a broken sprint shape is failure.
- Never patch over imperfections silently to make green. Fix the owner model.

## Working Rule

- Pick one owner boundary at a time.
- Define the boundary plainly before changing code.
- The slice may be broad when the true owner boundary is broad.
- Small safe cuts are rejected when they preserve false ownership.
- Prefer Alacritty for host, window, event, input, presentation, and renderer organization.
- Prefer Ghostty for VT and terminal-core shape.
- Prefer TigerBeetle for ownership truth, exact names, assertions, bounds, and tests.
- Existing Howl shape is not authority when it conflicts with references or owner truth.
- If the user gives an explicit direction, follow it unless it conflicts with a non-negotiable project boundary or a reference rule that requires escalation.

## Breakage Rule

- Compile/test breakage is allowed inside an active structural slice.
- Use breakage as evidence of the next false dependency, not as an excuse for glue.
- Fix failures in the slow correct way with the user when the owner model is uncertain.
- End-of-slice state must be explicit and inspectable.
- End-of-sprint state must be coherent, owner-true, and verified.
- Temporary buckets may exist during grinding, but they are not an accepted sprint-end shape.

## Present Boundary

- Below GL/EGL present, code produces actions only: draw, present, refresh, wake, title/focus/window operations.
- Below GL/EGL present must not consume input, VT, PTY, selection, terminal, or event meaning.
- `events` owns consumption of platform/input/VT/PTY facts and decides what action happens next.
- `window` and GL/EGL owners may be called by `events`, but they must receive already-shaped facts/frames/actions.

## Acceptance

- A slice is done only when the code, names, imports, tests, and owner paths all match the chosen boundary.
- Run the relevant checks before declaring completion.
- Grep for stale names and old paths after structural changes.
- Commit and push when the user asks or when the user-approved workflow for that slice requires it.
