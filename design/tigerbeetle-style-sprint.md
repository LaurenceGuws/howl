# TigerBeetle Style Sprint

Owner: workspace root.

Purpose: explicit sprint scope, checkpoint order, review gates, and closure bar for the current
workspace-wide style enforcement push.

## Current Focus

The render architecture inversion sprint is closed.

The scoped render hotspot cleanup sprint is closed.

Current focus is the remaining biggest render style cancer:

- abstract text orchestration that still does not name a concrete owned product
- residual control-flow and sized-state debt concentrated in the text parent owner
- rejecting any rename or cleanup theater that leaves the real owner shape vague

Active cleanup target:

- source comments should be reduced to local constraints, local invariants, and non-obvious
  rationale only
- repetitive file-header narration should be removed repo by repo
- architecture, owner model, and workspace worldview should stay in docs, not be recopied across
  source files

Closed scoped sprint result:

- the largest render hotspot files were reduced in the planned owner order
- backend roots and provider leaves were tightened without reopening the architecture inversion
- this did not prove renderer-wide TigerBeetle compliance

This includes a non-negotiable boundary cleanup:

- internal terminal modules were never supposed to become host integration surfaces shaped around
  Zig module imports
- the end goal is a C ABI embeddable terminal
- any Zig-module-shaped bypass around that boundary is sprint debt and should be removed or designed
  out
- all Zig-shaped host facades in `howl-pty` are deletion targets, not preservation targets
- all Zig-shaped module roots in `howl-pty` are deletion targets, not preservation targets

Reference results already achieved:

- `howl-pty` now sets the boundary bar for internal terminal modules
- shipped surface is `include/howl_pty.h` plus `howl_pty_*` only
- ABI export root is explicit
- Zig-shaped host facades and wrapper roots were deleted
- Linux host consumes the sharpened PTY ABI
- `howl-vt` now meets the same boundary bar
- shipped surface is `include/howl_vt.h` plus `howl_vt_*` only
- ABI export root is explicit
- wrapper roots and Zig-shaped host import posture were deleted
- getter-heavy ABI convenience posture is gone
- Linux host builds and runs on the cleaned VT ABI path

Boundary target status:

- `howl-render` has now completed the same ABI cleanup pattern: wrapper roots deleted, ABI export
  split from repo-local wiring, Zig-shaped host import posture removed, integer-handle posture
  sharpened, and runtime-convenience ABI shape cleaned
- `howl-render` render/backend ownership inversion is now closed in code, tests, and docs
- no newer module boundary target is recorded in this sprint doc yet

Closed architecture result:

- GL and GLES layers are leaf wrappers over external C libraries and GPU objects only
- `Renderer` and `Render.Text` own render policy, text analysis, retained-frame orchestration, and
  staged prepare/submit sequencing
- backend roots no longer consume shared render logic as partial renderers

Render inversion retrospective:

- good: the workspace removed a real architectural lie instead of carrying it as debt
- good: the render proof split now matches the owner split
- bad: the broader render style debt is still concentrated in the text spine
- bad: the sprint closed ownership first, not the full simplicity bar
- lesson: close contract truth first
- lesson: keep checkpoints narrow and clean-tree-only
- lesson: treat test ownership as part of architecture ownership, not follow-up cleanup

What improved already:

- shorter functions forced more local reasoning
- stronger assertions started proving real invariants instead of decorating code

What to keep pushing now:

- cut control flow until tempo and branch policy stay in one obvious owner file
- redesign module roots around explicit state-machine contracts
- redesign public roots around explicit C ABI-facing contracts where the host or embedder depends on
  them
- keep owner splits honest so leaf layers stay leaf layers and control spines stay with their true
  owners
- remove root surfaces that hide internal threads, wake policy, or orchestration
- keep hosts capable of owning runtime policy instead of burying that ownership below the host

Root test:

- the root names the owned state machine, its inputs, and its bounded transitions
- the host can drive it step by step without guessing about hidden progress
- one owner is responsible for each state transition
- the integration surface is not quietly relying on Zig module structure where the real product
  boundary is C ABI

This focus does not replace the existing style gates. It sharpens them toward control-spine
simplicity and owner-true contracts.

## Active Render Sprint

Theme: kill abstract text orchestration.

Purpose:

- remove the remaining owner shape that still reads like mechanism branding instead of a concrete
  owned product
- force the text parent owner to justify every surviving phase, state transition, and retained
  intermediate
- refuse rename theater until the owner either names a real product or shrinks into one

Current render reality:

- `howl-render` no longer has long-function hotspot debt in production render code
- backend roots and provider leaves are cleaner than they were at sprint start
- the biggest remaining render style cancer is now conceptual, not just mechanical:
  - `src/text/engine.zig` still concentrates the parent text control spine
  - the owner name is not earned
  - the retained intermediate state is broader than a concrete owned product justifies

Current measured render leaders by `usize` and production size:

1. `howl-render/src/text/engine.zig`: `prod=1116`, `usizes=84`
2. `howl-render/src/text/rasterizer.zig`: `prod=1180`, `usizes=64`
3. `howl-render/src/backend/gl/backend.zig`: `prod=1342`, `usizes=50`
4. `howl-render/src/text/cluster.zig`: `prod=488`, `usizes=42`
5. `howl-render/src/text/scene.zig`: `prod=524`, `usizes=35`
6. `howl-render/src/backend/gl/internal/provider.zig`: `prod=726`, `usizes=29`
7. `howl-render/src/backend/gles/internal/provider.zig`: `prod=723`, `usizes=29`

The next render checkpoint does not open by metric alone.

It opens only if the owner can answer all of these questions exactly:

- what concrete product does this file own?
- what exact inputs does it consume?
- what exact outputs does it produce?
- which state transitions does it own and which belong to leaf phases?
- which retained intermediate forms are indispensable and why?

If those answers are weak, the owner does not get renamed. It gets reduced.

## Problem

Howl has a real style gate, but the repo still carries baseline debt that violates the workspace
law in durable ways:

- domain state still uses `usize` in many owner files
- some owners still have functions beyond the 70-line hard limit
- invariant proof is uneven across repos, especially in `howl-vt`
- cleanup work can drift into fake progress unless each checkpoint closes on measured debt and proof

The problem is not only formatting or naming drift. The real problem is owner ambiguity, hidden
policy, weak invariant proof, and oversized control paths that make review less exact.

## Render Result

The render hotspot sprint started as a bounded blocker-removal pass, not as a claim that the full
renderer would become TigerBeetle-compliant in one move.

What is now true:

- the renderer/backend ownership inversion is closed
- the chosen render text and atlas hotspot owners are cleaner, smaller, and more exact
- the render proof split now matches the owner split
- the render style gate is clean for the landed checkpoints

What is not yet true:

- `howl-render` is not yet renderer-wide TigerBeetle-compliant
- broad `usize` debt still exists across production render code
- some render owners still need stronger invariant proof and more exact control flow
- the current top render problem is not another backend hotspot; it is the abstract parent text
  owner that still does not name a concrete product

Current measured render status:

- `howl-render`: `prod=12425`, `usizes=640`, `long_funcs=2`, `asserts=83`

Largest remaining render production owners by current style report:

- `howl-render/src/backend/gl/backend.zig`: `prod=1342`, `usizes=50`
- `howl-render/src/text/rasterizer.zig`: `prod=1180`, `usizes=64`
- `howl-render/src/text/engine.zig`: `prod=1116`, `usizes=84`
- `howl-render/src/backend/gl/internal/provider.zig`: `prod=726`, `usizes=29`
- `howl-render/src/backend/gles/internal/provider.zig`: `prod=723`, `usizes=29`
- `howl-render/src/backend/gles/backend.zig`: `prod=717`, `usizes=23`

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

## Render Gate

Clarified bar:

- performance tuning is not the goal of this pass
- outcome quality is not the goal of this pass
- clean control flow is the goal
- intentional, cohesive code is the goal
- do only what is needed, do it well and simply, and do it only in the true owner
- “You shall not pass!” applies to abstract owner names, convenience flow, and rename theater too

Checkpoint entry gate for render:

- identify one true owner file
- state the concrete product that file owns
- state the exact inputs and outputs
- state the exact state transitions it owns
- state which retained intermediate forms are indispensable
- if the owner cannot answer those questions concretely, reduce it before renaming it

Checkpoint fail conditions for render:

- abstract subsystem names such as `engine`, `analyzer`, `pipeline`, or similar survive without a
  concrete owned product underneath them
- branch policy is split across helpers instead of staying in one parent owner
- retained intermediate state survives only for convenience or observability vanity
- a rename lands before the owner shape becomes more exact
- a checkpoint claims progress because a file reads cleaner while the real owner boundary stays vague

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
- hidden progress engines or internal-thread convenience roots
- Zig-module-shaped host integration paths that bypass the intended C ABI boundary
- Android host style parity beyond work needed to keep docs and tooling honest

## Historical Baseline

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

## Historical Milestone Map

This milestone map records the opening style-hotspot plan for the sprint.

Active execution should follow `Current Focus` and the current checkpoint packet, not treat the
historical milestone list below as a live queue.

## Milestones

### Milestone 0

Theme: source-comment truth cleanup.

Goal:

- remove comment narration that explains architecture, ownership slogans, or workspace worldview in
  source files
- keep only comments that lock a local boundary, local invariant, local rationale, or reviewer trap
- preserve small exact source comments where they prevent real boundary regression

Checkpoints:

1. `howl-render`
2. `howl-hosts/howl-linux-host`
3. `howl-vt`
4. `howl-pty`

Milestone closes when:

- source files no longer carry repetitive `Responsibility` / `Ownership` / `Reason` narration
- surviving source comments earn their keep as local proof or local boundary constraints
- no repo needs architecture comments in source files to explain code that should already be made
  clear by owner structure and docs

### Milestone 1

Theme: `howl-render` backend ownership inversion.

Goal:

- make GL and GLES backend layers leaf wrappers over external C libraries and GPU state only
- move render pipeline orchestration back into `Renderer` and `Render.Text`
- remove backend-owned shared render policy surfaces

Checkpoints:

1. `howl-render/architecture-sprint.md`
2. `howl-render/design.md`
3. `howl-render/src/renderer.zig`
4. `howl-render/src/backend/gl/backend.zig`
5. `howl-render/src/backend/gles/backend.zig`
6. `howl-render/src/backend/gl/internal/provider.zig`
7. `howl-render/src/backend/gles/internal/provider.zig`

Milestone closes when:

- backend roots are leaf wrappers only
- renderer consumes a smaller backend contract instead of the reverse
- the backend inventory and disposition table are committed explicitly
- touched render files are clean against the touched-file style gate
- GL and GLES still close on the owned host proof path
- GL and GLES close on equivalent renderer-owned sequencing rather than matching backend internals

### Milestone 2

Theme: `howl-render` text spine cleanup after inversion.

Goal:

- reduce the largest remaining concentration of `usize` debt
- remove oversized control paths in the render text stack
- keep the text engine spine owner-true after the backend inversion lands

Checkpoints:

1. `howl-render/src/text/engine.zig`
2. `howl-render/src/text/rasterizer.zig`
3. `howl-render/src/text/cluster.zig`
4. `howl-render/src/text/scene.zig`
5. `howl-render/src/backend/gl/internal/atlas.zig`
6. `howl-render/src/backend/gles/internal/atlas.zig`

Milestone closes when:

- touched files have real invariant assertions where the owner can prove them
- touched files do not use assertion count as a style proxy
- touched files reduce measured `usize` and long-function debt

### Milestone 3

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

### Milestone 4

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

### Milestone 5

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
- keeps a module root that hides policy, timing, or progress that should be explicit in the contract
- spreads one control decision across multiple layers when one owner file can hold it directly
- keeps or adds a Zig-module-shaped integration bypass where the owner boundary is supposed to be C
  ABI
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
