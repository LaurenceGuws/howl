# Renderer Foundation Sprint

Purpose: lock the renderer-foundation sprint in writing so the work does not drift. This sprint is about replacing the wrong default renderer architecture with a best-in-class foundation. It is not the sprint that beats Alacritty outright. It is the sprint that makes that war winnable.

Last updated: 2026-05-11

## Position

This sprint is a foundation sprint.

Annual war target:
- beat `alacritty` decisively on real hostile terminal workloads.

This sprint target:
- replace the common-path renderer methodology that is structurally slower and less deterministic than `alacritty`.
- raise the architecture standard to be stricter than the `tigerbeetle` reference on simplicity, limits, and explicitness in the renderer hot path.

This sprint does not claim success by reaching a final FPS number.
This sprint claims success only if the default renderer path becomes the right path.

## Locked Scope

In scope:
- `howl-render-core` default text render path.
- `howl-render-core` benchmark and proof surfaces needed to judge the new default path.
- minimal contract changes in `howl-term` only if needed to feed the renderer the right unit of work.
- Linux-host benchmark proof only at milestone gates.

Out of scope:
- final year-target victory over `alacritty` on every benchmark.
- renderer-thread architecture changes.
- Android parity work.
- speculative GPU innovation beyond what is needed to replace the wrong common path.
- compatibility layers that preserve the old universal run-shaping pipeline for normal text.

Layer rules:
- `howl-render-core` owns renderer-path replacement.
- `howl-term` may only change to support the renderer contract cleanly.
- `howl-linux-host` is proof surface and harness owner, not renderer-policy owner.
- do not pull host concerns down into render-core.
- do not push render-core policy up into hosts.

## Locked Non-Negotiables

- No fake progress.
- No fallback architecture kept alive just to reduce churn.
- No compatibility layer that preserves the old wrong common path.
- No "temporary" normal-text exceptions that become permanent.
- No per-frame heap allocation in the final normal-text lane.
- No default-path dependence on full-run text hashes.
- No milestone passes on synthetic-only wins if host proof says the default path is still wrong.

## Reference Pressure Points

### Alacritty Pressure Points

Use `alacritty` as the common-path methodology reference, not as a line-for-line cargo cult target.

Pressure points:
- common unit of work is renderable cells and cached glyphs, not row-wide shaped text runs.
- common path goes from cell iteration to glyph cache lookup to atlas-backed draw batching.
- ASCII and ordinary monospace text stay out of expensive shaping/group-sprite machinery.
- glyph identity is local and cacheable; normal-path cost should not track line entropy.

Reference files:
- `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`

### TigerBeetle Pressure Points

Use `tigerbeetle` as the simplicity and determinism bar for the renderer hot path.

Pressure points:
- explicit, bounded control flow.
- fixed limits and known capacities.
- assertions on invariants and lane predicates.
- no runtime allocation in the final hot path.
- simple data plane, separate from control-plane complexity.
- no accidental dependence on hidden state, hash luck, or allocator behavior.

Reference files:
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/concepts/performance.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/concepts/safety.md`

## Sprint Done Definition

This sprint is done only when all of the following are true:

- The default normal-text renderer path is cell and glyph based.
- Normal monospace text no longer pays the run-shaping, regrouping, and sprite-scene pipeline.
- The complex-text path is explicit, narrow, and reserved for text that truly needs it.
- The normal-text path is bounded, assertion-heavy, and allocation-free after initialization.
- Benchmark and host proof clearly show that normal-path cost no longer scales with random line text churn the way it does today.
- Review can point to one clear owner chain for the hot path without hand-waving.

If any one of these is false, the sprint is not done.

## Milestone 1: Freeze The Right Architecture Contract

Milestone goal:
- lock the unit of work, lane split, and proof surfaces before deep implementation churn.

Scope done:
- the renderer has one explicit default path definition for normal text and one explicit exceptional path definition for complex text.
- benchmark surfaces can prove whether ordinary text still leaks into the wrong path.

### Checkpoint 1.1: Canonical Normal-Text Definition

Goal against `alacritty`:
- define the common path in `alacritty` terms: renderable cells, glyph identity, atlas-backed drawing.

TigerBeetle hygiene gate:
- the normal-text predicate is explicit and positive.
- the complex-text predicate is explicit and positive.
- lane choice is assertion-checked.
- no ambiguous "smart" auto-routing.

Done when:
- the code and design can name exactly what qualifies for the normal lane.
- the code and design can name exactly what forces the complex lane.

### Checkpoint 1.2: Canonical Proof Surface

Goal against `alacritty`:
- benchmark the same kind of common-path work that `alacritty` optimizes: ordinary visible cells and repeated glyph reuse.

TigerBeetle hygiene gate:
- deterministic workloads.
- fixed workload shapes with named capacities.
- scorecard includes cost by lane, not just one FPS number.

Done when:
- `howl-render-core` benchmark runs can prove whether a frame stayed fully in the normal lane.
- Linux-host gate runs remain sequential and artifact-backed.

### Checkpoint 1.3: Hot-Path Memory Contract

Goal against `alacritty`:
- move toward a glyph-cache hot path whose steady-state work does not depend on per-frame allocation.

TigerBeetle hygiene gate:
- final normal lane allocates all steady-state storage up front.
- capacities are explicit.
- overflow behavior is explicit and hard-failing in debug, never silently unbounded.

Done when:
- the milestone design states exactly which normal-lane buffers are preallocated, who owns them, and what their bounds are.

### Milestone 1 Gate

Pass only if:
- the sprint has one locked architecture target.
- the team can prove what the normal lane is, what the complex lane is, and how to measure leakage between them.
- there is no remaining ambiguity about whether normal text should ever enter run-shaping by default.

Fail if:
- benchmark work is still framed around the old universal pipeline.
- the lane split is still described in vague terms like "fast path" without an exact predicate.
- the design still allows a compatibility layer to keep normal text inside the old architecture.

## Milestone 2: Replace The Default Hot Path

Milestone goal:
- make normal monospace text use a direct cell-to-glyph path modeled after `alacritty`'s common-path methodology.

Scope done:
- normal text no longer enters run-shaping, regrouping, or sprite-scene preparation.

### Checkpoint 2.1: Stop Building Long Normal-Text Runs

Goal against `alacritty`:
- ordinary text should be processed as cells and glyphs, not as long same-face row runs.

TigerBeetle hygiene gate:
- remove the old default-path branch entirely for normal text.
- no hidden backdoor where normal text still forms run-hash identity.

Done when:
- a normal-text frame cannot produce default-path `ShapeRunKey` work.

### Checkpoint 2.2: Direct Glyph Identity And Cache Path

Goal against `alacritty`:
- normal text resolves to glyph-local identity and atlas lookup, not full-run textual identity.

TigerBeetle hygiene gate:
- glyph-key construction is explicit.
- cache ownership is explicit.
- cache miss behavior is deterministic and bounded.

Done when:
- normal text uses glyph-local cache keys.
- full-run hash churn is irrelevant to ordinary ASCII and monospace text cost.

### Checkpoint 2.3: Direct Draw Submission For Normal Text

Goal against `alacritty`:
- ordinary text goes from cell iteration to glyph batch submission without the sprite-group scene detour.

TigerBeetle hygiene gate:
- one obvious hot path.
- no side pipeline to translate normal glyphs into synthetic sprite groups.
- no duplicate representations that must be kept in sync for the same normal glyph.

Done when:
- normal text no longer needs regrouping or `sprite_key` generation to draw.

### Checkpoint 2.4: Steady-State No-Allocation Proof

Goal against `alacritty`:
- common repeated text work should stay in a stable cache-and-batch regime.

TigerBeetle hygiene gate:
- debug proof or instrumentation can show zero steady-state allocations in the normal lane.
- any remaining allocation is explicitly cold-path only.

Done when:
- the normal lane is allocation-free after initialization in steady-state benchmark runs.

### Milestone 2 Gate

Pass only if:
- normal text no longer flows through shaping, grouping, and sprite-scene generation.
- the code reviewer can trace the common path on one screen of code without crossing multiple translation layers.
- benchmark proof shows that random ASCII line entropy no longer destroys the common-path cache story.

Fail if:
- the new path still secretly falls back to the old default path for ordinary text.
- the old path remains in place as a convenience compatibility layer.
- the only win is synthetic and the host proof still shows the default path behaving like the old architecture.

## Milestone 3: Isolate Complex Text And Remove The Wrong Default World

Milestone goal:
- keep the sophisticated pipeline only where it is genuinely required and make that boundary explicit and reviewable.

Scope done:
- complex shaping exists as an exceptional lane.
- the old universal pipeline is gone as the mental model for renderer work.

### Checkpoint 3.1: Explicit Complex-Text Classifier

Goal against `alacritty`:
- match the spirit of a cheap common path by making expensive behavior conditional on real need.

TigerBeetle hygiene gate:
- the classifier is explicit, bounded, and assertion-checked.
- no inferred magic from downstream misses.

Done when:
- the code can state why each complex cell became complex before it enters that lane.

### Checkpoint 3.2: Complex Lane Narrowing

Goal against `alacritty`:
- expensive machinery must be the exception, not the default cost center.

TigerBeetle hygiene gate:
- complex-lane state is isolated.
- buffers and temporary storage are bounded.
- cost is measurable separately from the normal lane.

Done when:
- benchmark output shows lane split counts and costs clearly.

### Checkpoint 3.3: Remove Dead Architecture Paths

Goal against `alacritty`:
- do not carry structural baggage that `alacritty` avoids on its common path.

TigerBeetle hygiene gate:
- remove stale fallback code.
- remove duplicate default-path concepts.
- remove comments and docs that still describe the old world as normal.

Done when:
- the renderer no longer describes itself as a universal run-shaping pipeline with a "fast path" bolted on.

### Milestone 3 Gate

Pass only if:
- the renderer now has a simple normal lane and a narrow explicit complex lane.
- the old universal model is no longer the controlling architecture.
- code, docs, and benchmarks all describe the same default path.

Fail if:
- the old universal path is still treated as the real implementation with a special-case bypass.
- complexity remains smeared across both lanes.
- review still requires mental reconstruction of hidden control flow to explain the hot path.

## Review Rule For The Whole Sprint

The review standard is intentionally severe.

The reviewer must reject any milestone that:
- keeps the old wrong architecture alive for comfort.
- hides complexity under new names instead of deleting it.
- accepts a compromise because the best move causes churn.
- passes on benchmark folklore instead of proof.
- weakens determinism, limits, or explicitness to get a local speed bump.

The reviewer may approve the next milestone only when the current one passes on all three axes:
- speed direction is correct against `alacritty` methodology.
- determinism is strengthened against `tigerbeetle` standards.
- simplicity is visibly improved, not just redistributed.

## Exit Artifacts

By sprint end, the repository must contain:
- benchmark artifacts proving lane behavior and steady-state normal-path behavior.
- updated long-lived design docs for any new public renderer contract.
- improvements records for kept wins.
- reverted-experiment records for any discarded branches.

This sprint doc should be deleted only after its locked rules are promoted into long-lived design and performance docs.
