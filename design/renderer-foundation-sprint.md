# Renderer Rewrite Sprint

Purpose: lock the renderer rewrite sprint so we can rewrite `howl-render` deliberately instead of
smearing style cleanup across the whole repo.

Last updated: 2026-05-13

## Position

This sprint is a rewrite sprint, not a polish sprint.

The target is not "make the current renderer nicer." The target is:

- rewrite `howl-render` into owner-true, bounded, reviewable code
- make the public control spine boring
- make each hot path small enough to prove
- remove style drift instead of preserving it

This sprint is done by checkpoints, not by line count.

## Scope

In scope:

- `howl-render` only
- public owner spine
- render runtime and retained publication state
- text engine, lane split, and raster path
- GL and GLES backend owner paths
- benchmark and proof surfaces needed to close each checkpoint

Out of scope:

- VT owner changes except contract adjustments required by render
- PTY owner changes
- host event-loop redesign
- Android parity work
- speculative new renderer layers

Layer rules:

- `howl-render` owns render policy and render runtime state
- `howl-vt` owns terminal meaning and render input facts
- hosts own wake, loop cadence, and presentation
- no new umbrella runtime layer

## Work Split

We use the architect/review/engineer split again.

### Architect

Architect owns:

- the checkpoint boundary
- the owner map
- the exact invariant being locked
- the done proof for the checkpoint
- the delete list for wrong structure that should not survive

Architect output per checkpoint:

- checkpoint note
- owner file list
- invariants
- proof command list
- explicit non-goals

### Engineer

Engineer owns:

- code changes inside the active checkpoint boundary
- carrying the checkpoint to build/test proof
- updating docs in the same checkpoint

Engineer must not:

- open the next checkpoint early
- preserve bad structure for comfort
- add convenience wrappers to dodge ownership

### Review

Review owns:

- owner-truth check
- control-spine check
- bound check
- proof check
- style drift rejection

Review passes only when the code is simpler, not just different.

## Global Gates

Every checkpoint must pass all gates.

### Clarity Gate

Before edits:

- which file owns the state?
- which file owns the mutation?
- which file owns the control flow?
- what proof closes the change?

If any answer is unclear, stop and mark `work-not-clear`.

### Owner Gate

- public roots curate exports only
- namespace wrappers aggregate only
- owner files own state and mutation
- FFI translates only
- hosts do not absorb render policy

### Code-Shape Gate

- shorten giant functions when a true owner seam exists
- prefer direct control flow over hidden pipelines
- keep capacities and bounds explicit
- keep assertions on invariants that matter
- do not keep both old and new paths alive without a hard reason

### Proof Gate

Each checkpoint closes only with proof from the owning repo:

- `zig build test --summary all` in `howl-render`
- any checkpoint-specific benchmark or runtime proof named below

### Stop Gate

Stop the checkpoint if:

- two files both own the same mutation
- the shortest change needs a fake bridge layer
- proof and behavior disagree
- a rewrite step would silently change public contract without a doc update

## Rewrite Order

We rewrite from the outside in and from the control spine toward the heavy leaves.

Order:

1. public owner spine
2. render runtime and retained publication path
3. text lane contract and text engine
4. raster and atlas path
5. GL backend
6. GLES backend
7. benchmark and proof cleanup

This order is mandatory unless a checkpoint explicitly proves a better dependency order.

## Milestone 1: Lock The Public Spine

Milestone goal:

- make the exported render surface boring, explicit, and easy to review

Files centered here:

- `howl-render/src/howl_render.zig`
- `howl-render/src/render_namespace.zig`
- `howl-render/src/render.zig`
- `howl-render/src/ffi.zig`
- `howl-render/src/renderer.zig`

### Checkpoint 1.1: Root And Namespace Cleanup

Done when:

- root exports are curated only
- namespace wrapper only aggregates owners
- no root or namespace file owns policy
- exported names are short and specific

### Checkpoint 1.2: Public Render Owner Contract

Done when:

- `Render` is the only obvious render owner surface
- the render surface matches the real owner files
- design docs name the same contract the code exports

### Checkpoint 1 Gate

Pass only if:

- a reviewer can explain the render public surface from one screen of code
- root and namespace files contain no hidden policy

## Milestone 2: Rewrite Runtime Ownership

Milestone goal:

- make retained publication, prepare, submit, and metrics ownership explicit and bounded

Files centered here:

- `howl-render/src/render.zig`
- `howl-render/src/frame_queue.zig`
- `howl-render/src/frame_pipeline.zig`
- `howl-render/src/frame_snapshot.zig`
- `howl-render/src/frame_metrics.zig`

### Checkpoint 2.1: Publication State

Done when:

- retained publication state has one obvious owner
- source acceptance and damage classification are readable top to bottom
- no unrelated render policy is mixed into publication storage

### Checkpoint 2.2: Prepare And Submit Flow

Done when:

- prepare and submit rules are explicit and bounded
- stale/idle/needs-prepare states are easy to prove
- no helper hides queue policy

### Checkpoint 2.3: Runtime Metrics Ownership

Done when:

- metrics mutation lives in the smallest true owner
- metric counters reflect real runtime phases only
- debug and proof counters are clearly separated from policy

### Checkpoint 2 Gate

Pass only if:

- the runtime path is readable without chasing unrelated files
- render runtime state has one clear mutation owner

## Milestone 3: Rewrite The Text Control Spine

Milestone goal:

- make lane choice, text preparation, and shaping ownership explicit before deep backend work

Files centered here:

- `howl-render/src/text_contract.zig`
- `howl-render/src/text_pipeline.zig`
- `howl-render/src/text/engine.zig`
- `howl-render/src/text/text_lane.zig`
- `howl-render/src/text/cluster.zig`
- `howl-render/src/text/scene.zig`

### Checkpoint 3.1: Lane Predicate And Contract

Done when:

- lane choice is explicit and positive
- the contract matches the implementation
- normal and complex paths have named reasons

### Checkpoint 3.2: Engine Control Flow

Done when:

- engine control flow is top-down and bounded
- stage ownership is explicit
- no leaf helper quietly owns routing policy

### Checkpoint 3.3: Scene And Cluster Ownership

Done when:

- grouping/scene logic follows the lane contract cleanly
- text intermediate shapes are reduced to the smallest set that still earns their keep

### Checkpoint 3 Gate

Pass only if:

- a reviewer can trace one normal lane and one complex lane without guessing
- the engine no longer feels like a bag of side pipelines

## Milestone 4: Rewrite Raster And Atlas Owners

Milestone goal:

- make raster, sprite, atlas, and provider ownership small and local

Files centered here:

- `howl-render/src/text/rasterizer.zig`
- `howl-render/src/text/provider.zig`
- `howl-render/src/text/ft_hb_provider.zig`
- `howl-render/src/text/atlas.zig`
- `howl-render/src/text/atlas_cache.zig`
- `howl-render/src/text/sprite_key.zig`

### Checkpoint 4.1: Raster Control Spine

Done when:

- raster decisions are explicit
- special glyph and fallback ownership are separate and readable
- bounds and capacities are stated where they matter

### Checkpoint 4.2: Atlas And Residency State

Done when:

- atlas state has one mutation owner
- residency/update paths are bounded
- cache semantics are explicit, not emergent

### Checkpoint 4 Gate

Pass only if:

- atlas and raster paths can be explained without hand-waving about cache magic

## Milestone 5: Rewrite Backend Owners

Milestone goal:

- make GL and GLES backends mirror the same render contract with boring control flow

Files centered here:

- `howl-render/src/backend/gl/**`
- `howl-render/src/backend/gles/**`

### Checkpoint 5.1: GL Backend

Done when:

- GL backend control flow is explicit
- provider, atlas, and draw submission responsibilities are local
- no backend file redefines render policy already owned elsewhere

### Checkpoint 5.2: GLES Backend

Done when:

- GLES follows the same owner story as GL
- GLES divergence is only where the API truly differs

### Checkpoint 5 Gate

Pass only if:

- both backends read like consumers of one render contract, not forks of render policy

## Milestone 6: Proof And Cleanup Closeout

Milestone goal:

- prove the rewritten renderer and delete sprint scaffolding that no longer earns its keep

Files centered here:

- `howl-render/src/test/**`
- `howl-render/build.zig`
- relevant proof docs

### Checkpoint 6.1: Benchmark Surface

Done when:

- benchmark entrypoints match the rewritten owner model
- proof output tells us which path is hot and why

### Checkpoint 6.2: Doc And Proof Cleanup

Done when:

- stale sprint language is removed
- owner tables and repo design docs describe the final structure

### Milestone 6 Gate

Pass only if:

- code, docs, and proof all describe the same renderer

## Checkpoint Output Template

Every checkpoint should leave behind this exact record shape in the working notes or commit summary:

- owner files touched
- invariant locked
- proof run
- remaining gap

## Current Active Checkpoint

Current checkpoint after the accepted public-spine, runtime-ownership, and text-lane contract cuts:

- Milestone 3, Checkpoint 3.2
- Text Engine Control Flow

Reason:

- the public spine and runtime spine are already locked
- the next risk is hidden routing and stage ownership inside the text engine
- backend rewrites should wait until the text control spine is boring
