# Workflow

Owner: workspace root.

Purpose: the default change loop.

## Root Docs
- `AGENTS.md`: workspace rules and owner boundaries.
- `WORKFLOW.md`: change loop and closure rules.
- `design/design-rules.md`: documentation contract.
- `design/reference-index.md`: local reference map.
- `design/style-law.md`: strict style law.

## Boundary Reminder

Howl is aiming at a C ABI embeddable terminal.

That means internal terminal modules such as `howl-pty`, `howl-vt`, and `howl-render` are not
supposed to drift into host integration surfaces shaped around Zig module imports.

If a host or embedding path needs something new, add or sharpen the C ABI contract. Do not bypass
that boundary with a Zig-shaped convenience path.

## Default Loop
1. Read the boundary.
2. Identify the true owner.
3. Simplify the control spine first.
4. Move leaf behavior toward the true owner.
5. Add or tighten assertions around the invariant.
6. Remove any Zig-module-shaped bypass that fights the C ABI boundary.
7. Prove the changed path.
8. Review touched files against `design/style-law.md`.
9. Run `nu "./style.nu"` for style cleanup, architecture cleanup, and code-touching feature work.
10. Update docs in the same checkpoint.
11. Commit and push.

## Start Conditions

Before editing, answer these questions:

- Which repo owns this state?
- Which file owns this control flow?
- Which thread owns this work?
- Is this path honoring the C ABI boundary, or sneaking around it through Zig module structure?
- What proof closes the change?

If any answer is unclear, stop and mark `work-not-clear`.

## References

Use `design/reference-index.md`.

## Style Gate

Run `nu "./style.nu"` before closing style cleanup, architecture cleanup, and code-touching
feature work.

If the default gate is not clean:

- run `nu "./style.nu" --failures`
- run `nu "./style.nu" --touched-files`
- use `--by-file`, `--by-repo`, or `--deep` only when deeper inspection is needed

Do not close a checkpoint with touched-file style regressions unless they are justified or removed.

## Commit Rules

- keep each commit about one meaningful checkpoint
- use commit messages that describe the boundary or invariant being locked
- push after each meaningful checkpoint
- do not batch unrelated repo changes into one commit message theme
- do not close a checkpoint with touched-file style regressions against `design/style-law.md` or `nu "./style.nu"`

## Stop Rules

Stop and escalate when:

- ownership is unclear
- two owners both mutate the same state
- the shortest correct change requires a new layer
- the path only works by bypassing the intended C ABI boundary through Zig imports
- proof and behavior disagree

In these cases, write down the open edge instead of guessing.
