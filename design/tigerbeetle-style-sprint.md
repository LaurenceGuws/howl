# TigerBeetle Style Sprint

Owner: workspace root.

Purpose: explicit sprint scope, checkpoint order, review gates, and closure bar for the current
workspace-wide style enforcement push.

## Problem

Howl has a real style gate, but the repo still carries baseline debt that violates the workspace
law in durable ways:

- domain state still uses `usize` in many owner files
- some owners still have functions beyond the 70-line hard limit
- invariant proof is uneven across repos, especially in `howl-vt`
- cleanup work can drift into fake progress unless each checkpoint closes on measured debt and proof

The problem is not only formatting or naming drift. The real problem is owner ambiguity, hidden
policy, weak invariant proof, and oversized control paths that make review less exact.

## End State

This sprint closes when the active hotspot files have all of the following properties:

- touched files have no avoidable `usize` domain state
- touched files have no functions over the 70-line hard limit
- assertions in touched files prove real preconditions, postconditions, or state transitions only
- parent owners keep branch policy and local state
- leaf files own one true step only
- proof exists for user-visible behavior changes on the owning host or repo test surface
- each checkpoint lands as a narrow, truthful commit

This sprint does not require the whole workspace to be perfect in one turn. It does require each
landed checkpoint to remove real debt and never add fake progress.

## Scope

Primary scope is the measured style hotspots in Zig production code.

In scope:

- `howl-render`
- `howl-vt`
- `howl-hosts/howl-linux-host`
- `howl-pty`

Secondary scope:

- root style and review tooling when it improves enforcement clarity

Out of scope for this sprint unless a checkpoint names them:

- broad feature work
- architecture expansion
- wrapper layers for cleanup convenience
- Android host style parity beyond work needed to keep docs and tooling honest

## Baseline View

Current measured repo totals:

- `howl-render`: `prod=12304`, `usizes=770`, `long_funcs=14`, `asserts=72`
- `howl-vt`: `prod=8687`, `usizes=482`, `long_funcs=11`, `asserts=0`
- `howl-hosts/howl-linux-host`: `prod=5642`, `usizes=133`, `long_funcs=2`, `asserts=60`
- `howl-pty`: `prod=1524`, `usizes=70`, `long_funcs=0`, `asserts=3`

Highest-value hotspot files at sprint start:

- `howl-render/src/text/engine.zig`
- `howl-render/src/text/rasterizer.zig`
- `howl-render/src/backend/gl/internal/provider.zig`
- `howl-render/src/backend/gl/backend.zig`
- `howl-vt/src/grid/edit.zig`
- `howl-vt/src/grid/history.zig`
- `howl-vt/src/grid/resize.zig`
- `howl-vt/src/parser.zig`
- `howl-hosts/howl-linux-host/src/terminal/api.zig`

## Milestones

### Milestone 1

Theme: `howl-render` text spine cleanup.

Goal:

- reduce the largest concentration of `usize` debt
- remove oversized control paths in the render text stack
- keep the text engine spine owner-true

Checkpoints:

1. `howl-render/src/text/engine.zig`
2. `howl-render/src/text/rasterizer.zig`
3. `howl-render/src/backend/gl/internal/provider.zig`
4. `howl-render/src/backend/gl/backend.zig`
5. `howl-render/src/backend/gles/internal/provider.zig`
6. `howl-render/src/backend/gles/backend.zig`

Milestone closes when:

- the touched render files are clean against the touched-file style gate
- each touched hotspot shows real metric reduction
- text-engine control flow still matches `howl-render/design.md`

### Milestone 2

Theme: `howl-vt` invariant recovery and sized-state cleanup.

Goal:

- remove `usize` from grid and parser domain state where explicit widths are correct
- add real invariant proof in owner seams
- keep parser syntax, interpret meaning, grid mutation, and terminal consequences separated

Checkpoints:

1. `howl-vt/src/grid/edit.zig`
2. `howl-vt/src/grid/history.zig`
3. `howl-vt/src/grid/resize.zig`
4. `howl-vt/src/parser.zig`
5. `howl-vt/src/input/keyboard.zig`
6. `howl-vt/src/terminal.zig`

Milestone closes when:

- touched files have real invariant assertions where the owner can prove them
- touched files do not use assertion count as a style proxy
- touched files reduce measured `usize` and long-function debt

### Milestone 3

Theme: Linux host owner-file cleanup.

Goal:

- tighten the biggest host owner files without smearing policy across leaves
- keep host orchestration in host owners and runtime consequences explicit

Checkpoints:

1. `howl-hosts/howl-linux-host/src/terminal/api.zig`
2. `howl-hosts/howl-linux-host/src/input/input.zig`
3. `howl-hosts/howl-linux-host/src/config/terminal.zig`
4. `howl-hosts/howl-linux-host/src/main.zig`

Milestone closes when:

- touched host owners stay the control spine
- leaves compute or apply one true step only
- touched files show net style improvement by the gate

### Milestone 4

Theme: PTY cleanup and residual owner debt.

Goal:

- finish smaller owner files after the highest-value hotspots are stable

Checkpoints:

1. `howl-pty/src/session.zig`
2. `howl-pty/src/pty/pty_unix.zig`
3. `howl-pty/src/pty/pty_android.zig`
4. residual touched-file follow-up from earlier milestones

Milestone closes when:

- remaining touched PTY files keep queue and transport policy in `Session`
- no cleanup step adds wrappers or policy leaks

## Checkpoint Rules

Each checkpoint must answer before editing:

- which repo owns this state
- which file owns this control flow
- which thread owns this work
- what proof closes this change
- which invariants this owner can locally prove, or the exact reason no such invariants exist

If any answer is unclear, close the report with `work-not-clear` and stop.

Each checkpoint must produce:

- one narrow diff
- before and after style metrics for the touched file
- proof command output
- explicit invariant accounting for the owner: proved invariants, paired seam assertions, or a direct
  explanation for why no local invariant was provable
- a commit recommendation of `ready` or `not ready`

## Review Gates

A checkpoint fails review if it does any of the following:

- adds assertions that do not prove a real invariant
- fails to name provable invariants where the owner can locally prove them
- splits a function by line count theater instead of ownership
- introduces a wrapper that only forwards
- leaves avoidable `usize` domain state in a touched file
- moves behavior away from the smallest true owner
- claims cleanup without measured debt reduction
- mixes unrelated files into one checkpoint

## Commit Gates

Do not commit a checkpoint unless all of the following are true:

- `nu "./style.nu" --touched-files` is clean for the touched files
- `nu "./style.nu" --failures` is clean
- the owning proof command passed
- the review report explains the owner change exactly
- the commit message describes the boundary or invariant being locked

Fake progress gets dropped. Cosmetic churn is not a checkpoint.

Checkpoint review does not stack indefinitely. Once a checkpoint is accepted, the architect closes it
with a commit before moving the engineer to the next checkpoint unless an explicit same-owner batch
was approved up front.

## Handoff Model

The engineer reports to the TigerBeetle Architect only.

Normal handoff size:

- one sizable checkpoint in a hotspot owner file, or
- a small batch of closely related checkpoints inside one milestone
- soft churn cap: keep each handoff at or under roughly 1000 changed lines unless the architect
  explicitly approves a larger checkpoint

Preferred review cadence:

- Milestone 1: one hotspot file per turn
- Milestone 2: one to two related grid or parser files per turn
- Milestone 3: one host owner file per turn
- Milestone 4: batch only when ownership remains obvious

Each report must include:

- owner view
- provable invariants, or the reason none exist
- before metrics
- changes made
- why the change is owner-true
- proof
- after metrics
- open edges
- commit recommendation

## Manager Use

Use this sprint doc to assign either:

- a full milestone, or
- a short run of named checkpoints from the current milestone

Do not hand over a new milestone while the previous active milestone still has unresolved hotspot
checkpoints unless the architect explicitly reorders the sprint.
