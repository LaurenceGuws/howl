# Howl-Term Render Reset Sprint

Purpose: lock the render reset sprint in writing so the work does not drift. This sprint is about
removing `howl-term/src/render/`, moving render runtime ownership to the right layer, and raising
the renderer cleanup bar to TigerBeetle-level code hygiene before further feature churn.

Last updated: 2026-05-12

## Position

This sprint is a cleanup-first architecture sprint.

Longer-term product target:
- make `howl-term` a clean terminal product with host-driven runtime behavior and a renderer stack
  that is maintainable enough to compete seriously.

This sprint target:
- stop letting `howl-term` act as a renderer runtime owner.
- delete `howl-term/src/render/` completely.
- move render runtime ownership into `howl-render-core` while preserving repo layering.
- make the host event loop and redraw flow match Alacritty's architecture shape.
- raise the code hygiene bar so future renderer work starts from a clean base instead of a pile of
  stale compatibility code.

This sprint does not claim success by squeezing out one more ad hoc latency fix.
This sprint claims success only if the default ownership shape becomes the right shape and the old
shape is removed.

## Why This Sprint Exists

Current problems:
- `howl-term` owns terminal state and renderer runtime state at the same time.
- `howl-term/src/render/` mixes VT projection, damage tracking, queue policy, prepare/submit
  orchestration, and render-only visual mutation.
- the hot path is hard to reason about because ownership is split by convenience, not by design.
- `howl-render-core` already contains queue, pipeline, snapshot, and renderer building blocks, but
  `howl-term` still wraps them with another large owner layer.
- `howl-render-core` itself has giant files and stale seams that make review and cleanup expensive.

Measured hygiene pressure inside `howl-render-core`:
- `src/backend/gl/backend.zig`: 1865 lines.
- `src/text/rasterizer.zig`: 1758 lines.
- `src/text/engine.zig`: 1462 lines.
- `src/backend/gles/backend.zig`: 1086 lines.
- `src/backend/gl/internal/provider.zig`: 1004 lines.

This is not maintainable enough for the next round of renderer work.

## Locked Architecture Target

The proper solution for this repo is:
- `howl-term` owns terminal semantics only.
- `howl-render-core` owns renderer runtime behavior, retained-frame logic, prepare/submit work,
  surface state, and render metrics.
- hosts own event loops, redraw scheduling, pacing, and presentation.
- `howl-term` may construct one render owner and feed it terminal-visible state through a narrow
  contract, but `howl-term` must not own render queue mechanics or renderer runtime policy.

In plain English:
- `howl-term` should initialize the renderer path and point VT-visible state at it.
- `howl-term` should not contain a render subsystem.
- `howl-linux-host` should keep the Alacritty-shaped event loop: PTY side wakes UI, UI requests
  redraw, display side renders.

## Locked Non-Negotiables

- No fake progress.
- No compatibility layer that preserves the current `howl-term/src/render/` architecture under new
  names.
- No gradual alias forest to make old and new owners coexist for comfort.
- No deprecated wrapper stage kept around "for safety" once the new owner chain exists.
- No hidden render scheduling policy in `howl-term`.
- No host-owned renderer internals that violate repo layering.
- No broad cleanup milestone pass while giant files keep growing.
- No milestone pass if old code still exists in dead files, dormant branches, old tests, or stale
  comments.

## Reference Pressure Points

### Alacritty Pressure Points

Use Alacritty as the architecture-shape reference, not as a line-for-line cargo cult target.

Pressure points:
- the PTY event loop owns PTY I/O and wakes the UI when terminal state changed.
- the UI thread owns redraw requests and window events.
- the display layer owns geometry updates, renderer updates, damage handling, and drawing.
- the terminal crate does not own the renderer.
- redraw signaling is simple: wake, mark dirty, request redraw, draw.

Reference files:
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/event.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`

### TigerBeetle Pressure Points

Use TigerBeetle as the quality bar for safety, simplicity, assertions, and design discipline.

Pressure points:
- design first, churn later.
- explicit owner boundaries.
- bounded loops and bounded queues.
- explicit types, with `usize` kept local to indexing and allocation mechanics instead of leaking
  into contracts casually.
- assertion-heavy code with paired checks on boundaries.
- tests that cover positive and negative space.
- comments that explain why and how, never just what.
- zero tolerance for technical debt kept around for comfort.

Reference files:
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/internals/docs.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/coding/system-architecture.md`

## Locked Repo Rules For This Sprint

- Layering stays hard: hosts -> `howl-term`; `howl-term` -> session/render/vt variants.
- Module ownership stays hard: session owns PTY variants, render-core owns render backend variants,
  hosts own platform UX/runtime only.
- If ownership becomes unclear, stop and mark `work-not-clear`.
- Simplicity beats local convenience.
- Deletion beats compatibility.
- Breaking compile intentionally is acceptable when it removes the wrong owner chain early and the
  new chain is rebuilt immediately after.

## Sprint Done Definition

This sprint is done only when all of the following are true:

- `howl-term/src/render/` is gone.
- `HowlTerm` no longer owns renderer runtime fields or render queue policy.
- `howl-render-core` owns render runtime behavior behind a narrow terminal-facing contract.
- the host loop follows the Alacritty-style wake and redraw shape without hidden library pacing.
- the public `howl-term` surface no longer exposes the old render architecture as a semantic model.
- no compatibility wrappers, aliases, or stale tests keep the old owner chain alive.
- the worst renderer files are shrinking, not growing.
- new owner files, tests, and docs meet the TigerBeetle bar for assertions, intent comments, and
  bounded control flow.

If any one of these is false, the sprint is not done.

## Milestone 1: Freeze The New Owner Chain And The Deletion Map

Milestone goal:
- decide the final owner chain before touching implementation so the deletion work is direct.

### Checkpoint 1.1: Lock The Terminal Versus Renderer Boundary

Goal:
- write one explicit owner table for terminal semantics, renderer runtime behavior, and host
  runtime behavior.

Scope:
- classify every `HowlTerm` field as terminal-owned, render-owned, or host-owned.
- classify every file under `howl-term/src/render/` as delete, move, or split.

TigerBeetle gates:
- `usize` gate: public contracts use explicitly sized integers unless the value is truly an index,
  allocation size, or slice length.
- assert gate: every proposed boundary names the invariants that both sides must assert.
- test gate: each boundary names the positive and negative cases that future tests must cover.
- intent-comment gate: the owner table explains why each field belongs where it belongs.
- simplicity gate: one owner per mutable responsibility.
- old-code purge gate: no field is allowed to stay in `HowlTerm` "temporarily" if the final owner
  is already known to be elsewhere.

Done when:
- the sprint can point to one authoritative owner table.
- there is no unresolved argument about whether render queueing, prepare/submit, or retained-base
  validation belongs in `howl-term`.

### Checkpoint 1.2: Lock The Deletion-First Migration Order

Goal:
- define the migration so the old architecture is severed early instead of preserved until the end.

Scope:
- identify the first compile-breaking deletion step.
- identify the minimum new contract needed to rebuild after the break.

TigerBeetle gates:
- `usize` gate: migration steps name exact bounded surfaces, not vague future state.
- assert gate: every break point states what must fail hard if callers still depend on old code.
- test gate: characterization tests are identified before deletion starts.
- intent-comment gate: the order explains why deletion comes before refinement.
- simplicity gate: no dual-path migration where old and new paths both live for long.
- old-code purge gate: checkpoint text explicitly bans shadow wrappers and old-name aliases.

Done when:
- the plan names the exact point where `howl-term/src/render/` references start getting deleted.
- the plan names the exact rebuild order after that break.

### Milestone 1 Gate

Pass only if:
- the final owner chain is explicit.
- the deletion-first order is explicit.
- the sprint can start by removing code instead of protecting it.

Milestone 1 lock artifacts:
- `design/howl-term-render-owner-table.md`
- `design/howl-term-render-handover-model.md`

Fail if:
- the plan still talks about migrating carefully by preserving the wrong owner chain.
- `howl-term` is still allowed to keep renderer runtime policy for convenience.

## Milestone 2: Kill All References To The Current `howl-term/src/render/` World

Milestone goal:
- remove the old semantic center of gravity early so the rest of the sprint rebuilds on the right
  owner chain.

### Checkpoint 2.1: Delete Public And Internal References To `src/render/*`

Goal:
- remove imports, type aliases, and method delegation that make `howl-term/src/render/` part of the
  live architecture.

Scope:
- cut references from `howl-term/src/terminal.zig`.
- cut references from `runtime/lifecycle.zig`, `runtime/contract.zig`, `ffi.zig`, and tests.
- force compile errors to reveal every remaining dependency.

TigerBeetle gates:
- `usize` gate: replacement contracts use explicit integer widths at the new seam.
- assert gate: deleted call sites are replaced only with seams whose preconditions are assertable.
- test gate: every deleted public seam has a replacement test owner before code lands.
- intent-comment gate: replacement owners explain why the old path was wrong.
- simplicity gate: do not build a temporary wrapper module that forwards back to the old files.
- old-code purge gate: no compatibility aliases, no `deprecated_` names, no dual delegation.

Done when:
- there are no live imports of `howl-term/src/render/*` outside the directory itself.
- the compile break exposes only the new rebuild work, not uncertainty about ownership.

### Checkpoint 2.2: Delete The Directory

Goal:
- physically remove `howl-term/src/render/` instead of slowly hollowing it out.

Scope:
- delete:
  - `howl-term/src/render/render.zig`
  - `howl-term/src/render/frame.zig`
  - `howl-term/src/render/geometry.zig`
  - `howl-term/src/render/viewport.zig`
  - `howl-term/src/render/sync.zig`
  - `howl-term/src/render/token.zig`
  - `howl-term/src/render/resize.zig`

TigerBeetle gates:
- `usize` gate: replacement files do not reintroduce sloppy contract widths while moving code.
- assert gate: deletion must be paired with new owner assertions, not with silent loss of checks.
- test gate: removed tests are either deleted with the old behavior or rewritten for the new owner.
- intent-comment gate: replacement owners explain why the deleted files were the wrong boundary.
- simplicity gate: one delete pass, not a long half-dead limbo.
- old-code purge gate: deleted files must not survive as commented-out text, archive folders, or
  dormant build entries.

Done when:
- the directory is gone.
- the build graph and docs no longer refer to it.

### Milestone 2 Gate

Pass only if:
- `howl-term/src/render/` is deleted early in the sprint.
- no wrapper layer keeps the old architecture alive.

Fail if:
- old render files still exist.
- the sprint is rebuilding around the old names or old owner chain.

## Milestone 3: Establish The New Terminal-To-Renderer Contract

Milestone goal:
- replace the deleted subsystem with one narrow contract between terminal semantics and render
  runtime ownership.

### Checkpoint 3.1: Define The Terminal Visual-State Source

Goal:
- make terminal-visible state readable by the render runtime without making `howl-term` own render
  runtime policy.

Scope:
- define the terminal-facing visual source contract.
- keep VT, scrollback, selection, hyperlink, and focus semantics in `howl-term`.
- remove render-only mutation of renderer-owned snapshots.

TigerBeetle gates:
- `usize` gate: the source contract uses explicit widths for epochs, rows, cols, and counters.
- assert gate: assert source invariants before exposing state to render-core.
- test gate: tests cover clean, dirty, scrolled, selected, focused, and stale-epoch cases.
- intent-comment gate: comments explain why state is terminal semantics rather than render policy.
- simplicity gate: one read model, not multiple overlapping snapshots.
- old-code purge gate: `snapshot` versus `render_snapshot` duplication must not survive in spirit
  under new names.

Done when:
- the new seam can describe terminal-visible state without referencing the old render files.
- render-only hover overlay mutation no longer lives in terminal-owned render storage.

### Checkpoint 3.2: Define The Render Runtime Contract

Goal:
- make `howl-render-core` own prepare/submit/runtime state through one explicit owner surface.

Scope:
- define the render runtime owner API for geometry sync, publication, prepare, submit, metrics, and
  surface queries.
- keep host scheduling outside this contract.

TigerBeetle gates:
- `usize` gate: all public counters and statuses use deliberate widths; `usize` stays local.
- assert gate: assert queue invariants, retained-base invariants, and geometry invariants on both
  ingress and egress.
- test gate: tests cover valid submit, stale base, stale target, geometry change, and idle paths.
- intent-comment gate: every method comment says why the boundary exists and what the caller owns.
- simplicity gate: no convenience overloads that restore the old broad semantic surface.
- old-code purge gate: do not mirror the old `renderFrame` API just to keep old caller habits alive.

Done when:
- one narrow render runtime owner exists in `howl-render-core`.
- `howl-term` can depend on it without becoming it.

### Milestone 3 Gate

Pass only if:
- one terminal source contract exists.
- one render runtime contract exists.
- the boundary is smaller and stricter than the deleted one.

Fail if:
- state duplication remains.
- `howl-term` still owns render queue semantics through a different filename.

## Milestone 4: Move Render Runtime Ownership Into `howl-render-core`

Milestone goal:
- make the new contract real by moving runtime behavior out of `howl-term` and into the renderer
  stack.

### Checkpoint 4.1: Move Queue, Prepare, And Submit Ownership

Goal:
- move retained-frame scheduling, prepare, submit, and surface bookkeeping into render-core runtime
  owners.

Scope:
- rehome `render_queue`, prepared-frame slots, and surface metrics ownership.
- rehome render wake bookkeeping that exists only because of render work.

TigerBeetle gates:
- `usize` gate: queue capacities and sequence counters are explicit and bounded.
- assert gate: queue transitions are asserted at every state edge.
- test gate: tests cover coalescing, stale submit rejection, forced full prepare, and present state.
- intent-comment gate: comments explain why the queue belongs with render runtime ownership.
- simplicity gate: no duplicated queue policy in both term and render-core.
- old-code purge gate: remove old queue fields from `HowlTerm` as soon as the new owner exists.

Done when:
- `HowlTerm` no longer stores render queue state.
- render-core owns retained-frame lifecycle completely.

### Checkpoint 4.2: Move Geometry And Surface Ownership

Goal:
- make geometry derivation and surface state render-owned rather than terminal-owned.

Scope:
- move frame layout derivation and surface handle evolution to render-core runtime ownership.
- keep terminal resize semantics limited to VT/session state.

TigerBeetle gates:
- `usize` gate: geometry values use explicit widths and checked conversions.
- assert gate: assert surface and grid invariants before resize side effects happen.
- test gate: cover invalid dimensions, first-frame geometry, same-size no-op, and geometry epoch
  changes.
- intent-comment gate: comments distinguish terminal resize semantics from renderer surface policy.
- simplicity gate: one owner derives layout.
- old-code purge gate: no new geometry helper inside `howl-term` may reconstruct render policy.

Done when:
- `HowlTerm` no longer derives render layout itself.
- terminal resize code only updates terminal semantics and forwards explicit geometry input.

### Checkpoint 4.3: Move Render Metrics Ownership

Goal:
- keep render metrics with the owner that produces them.

Scope:
- move prepare/render metrics storage and reporting to render-core runtime ownership.

TigerBeetle gates:
- `usize` gate: metric counters and timings use explicit widths.
- assert gate: metrics are reset and taken under asserted lifecycle rules.
- test gate: cover metric reset, take, and stale read behavior.
- intent-comment gate: comments explain which metrics are terminal metrics versus render metrics.
- simplicity gate: no metric mirror copies unless they are immutable snapshots crossing a boundary.
- old-code purge gate: remove term-owned render metric storage when moved.

Done when:
- render metrics are not stored as render-runtime state inside `HowlTerm`.

### Milestone 4 Gate

Pass only if:
- render-core owns render runtime behavior.
- `HowlTerm` is no longer a shadow render runtime.

Fail if:
- moved code still depends on term-owned render internals.
- fields were copied instead of re-owned.

## Milestone 5: Rewire The Host Around The New Shape

Milestone goal:
- make the Linux host a clean embedder of the new contract using the Alacritty-style wake and draw
  flow.

### Checkpoint 5.1: Tighten The PTY Wake And Redraw Flow

Goal:
- keep PTY progress, terminal wake, redraw request, and draw submission in clear separate layers.

Scope:
- PTY thread waits and advances terminal state.
- terminal-visible state change wakes the host.
- host marks dirty and requests redraw.
- draw path consumes prepared render work and presents.

TigerBeetle gates:
- `usize` gate: budgets and counts are explicit and bounded.
- assert gate: assert that wake edges correspond to real work edges.
- test gate: host-facing tests cover idle wait, wake on output, wake on input-triggered output, and
  no-wake when nothing changed.
- intent-comment gate: comments explain why pacing stays in the host.
- simplicity gate: no hidden scheduler inside `howl-term`.
- old-code purge gate: remove old wake latches or callbacks that only existed for the deleted owner
  chain.

Done when:
- the host loop reads like an embedder of the right contract, not like a rescue harness around
  library-owned pacing.

### Checkpoint 5.2: Rebuild The FFI And Public Surface Around The New Contract

Goal:
- ensure the public `howl-term` surface describes the new architecture and not the deleted one.

Scope:
- rewrite Zig and C entry points around the new owner chain.
- delete API shapes whose semantics only made sense in the old render subsystem.

TigerBeetle gates:
- `usize` gate: ABI structs use explicit integer widths only.
- assert gate: handle validity, lifecycle ordering, and nullability are asserted at the boundary.
- test gate: Zig and C parity tests cover the same semantic operations and invalid-handle cases.
- intent-comment gate: public surface docs explain ownership and ordering rules.
- simplicity gate: one product surface, not a compatibility museum.
- old-code purge gate: do not keep old function names just to soften the cut if their semantics are
  wrong.

Done when:
- the public surface reads like the new architecture.
- deleted architecture terms no longer dominate the API.

### Milestone 5 Gate

Pass only if:
- the host loop shape matches the intended architecture.
- the public surface no longer teaches the old system.

Fail if:
- host code still compensates for hidden render behavior.
- ABI or Zig surface still mirrors deleted internals.

## Milestone 6: Raise The Renderer Hygiene Bar Before More Optimization Work

Milestone goal:
- cut giant files, harden invariants, and strip stale code so future renderer work starts from a
  clean base.

### Checkpoint 6.1: Split Giant Files Along Real Owner Boundaries

Goal:
- shrink the worst files using ownership cuts rather than aesthetic chopping.

Scope:
- split giant files in `howl-render-core` where one file owns multiple responsibilities today.
- especially target backend runtime, text analysis, rasterization, and provider files.

TigerBeetle gates:
- `usize` gate: file splits do not introduce casual size typing drift in new contracts.
- assert gate: moved leaf functions gain local assertions instead of relying on distant callers.
- test gate: moved units gain unit tests at their new owner seams.
- intent-comment gate: each new file starts with why/ownership comments.
- simplicity gate: split by responsibility, not by arbitrary line count alone.
- old-code purge gate: no graveyard files, no "old" suffix files, no duplicate helpers left behind.

Done when:
- the largest files are measurably smaller.
- each new file has one owner story.

### Checkpoint 6.2: Raise Assertion Density And Invariant Clarity

Goal:
- make correctness bugs fail fast instead of hiding in stale state transitions.

Scope:
- add paired assertions on queue, geometry, retained-base, and snapshot invariants.
- prefer positive-space assertions and split compound assertions.

TigerBeetle gates:
- `usize` gate: integer domain assumptions are asserted where conversions happen.
- assert gate: touched functions average at least two meaningful assertions unless trivially simple.
- test gate: invalid-state tests exist for each assertion family.
- intent-comment gate: surprising assertions document the invariant they protect.
- simplicity gate: assertions clarify control flow instead of masking confusion.
- old-code purge gate: no old unchecked path survives next to the new asserted one.

Done when:
- reviewers can see the core invariants in code, not just infer them.

### Checkpoint 6.3: Rewrite Tests To Match The New Owner Chain

Goal:
- stop testing the deleted architecture and start testing the actual one.

Scope:
- rewrite `howl-term` tests so they cover terminal semantics and public contract only.
- move render-runtime tests to render-core.
- delete tests whose only purpose was preserving old implementation details.

TigerBeetle gates:
- `usize` gate: test fixtures use explicit widths where contracts require them.
- assert gate: tests check invariants, not just outputs.
- test gate: positive, negative, stale, and boundary cases are all named.
- intent-comment gate: non-trivial tests explain goal and method.
- simplicity gate: each test has one reason to fail.
- old-code purge gate: no tests remain whose pass condition depends on deleted architecture.

Done when:
- test ownership matches production ownership.
- deleted architecture behavior is gone from the test vocabulary.

### Milestone 6 Gate

Pass only if:
- giant files are shrinking.
- assertions and tests now defend the new architecture.
- stale code is gone.

Fail if:
- the sprint finished the migration but left the hygiene debt in place.

## Milestone 7: Final Proof And Closure

Milestone goal:
- close the sprint with proof that matches the claims and the layer where those claims live.

### Checkpoint 7.1: Contract And Runtime Proof

Goal:
- prove the new owner chain in unit and integration surfaces before claiming host-visible success.

TigerBeetle gates:
- `usize` gate: proof fixtures cover contract widths and conversions explicitly.
- assert gate: assertion-backed failures are exercised, not just present.
- test gate: contract proof and runtime proof are named separately.
- intent-comment gate: proof artifacts explain what layer they cover.
- simplicity gate: no overloaded benchmark trying to prove everything at once.
- old-code purge gate: no proof artifact depends on deleted terminology or dead code.

Done when:
- the sprint has explicit contract proof and runtime proof artifacts for the new owner chain.

### Checkpoint 7.2: Host Proof And Parity Closure

Goal:
- prove the user-visible runtime on real hosts without overclaiming from lower layers.

TigerBeetle gates:
- `usize` gate: host metrics and ABI counters remain explicit-width.
- assert gate: host-visible lifecycle and wake assumptions are asserted where possible.
- test gate: SDL proof and Android proof are both required for user-visible runtime closure.
- intent-comment gate: logs and scorecards explain what they measure and what they do not measure.
- simplicity gate: no sprawling proof harness that hides basic regressions.
- old-code purge gate: no fallback host path kept alive just to satisfy old behavior.

Done when:
- SDL and Android proof both back the final user-visible claim.
- no milestone text relies on lower-layer proof to hide host regressions.

### Milestone 7 Gate

Pass only if:
- proof matches claim layer.
- the codebase is cleaner, smaller, and stricter than when the sprint started.

Fail if:
- host-visible closure is claimed from unit-only evidence.
- the new architecture exists but the cleanup bar was waived.

## First Deletions

The sprint should start by preparing then deleting these architectural anchors early:
- `howl-term/src/render/`
- `HowlTerm.renderer`
- `HowlTerm.render_queue`
- `HowlTerm.render_snapshot`
- terminal-owned prepare/submit/render metric storage that is really renderer runtime state

The sprint should not protect these with wrappers.
It should replace them with the new owner chain.

## Active Checkpoint Recommendation

Start with:
- Milestone 1, Checkpoint 1.1

Then immediately move to:
- Milestone 2, Checkpoint 2.1

Reason:
- the current architecture is already known to be wrong.
- spending time preserving it would be wasted motion.
