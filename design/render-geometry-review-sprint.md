# Render Geometry Review Sprint

Owner: workspace root.

Purpose: checkpoint plan for making `howl-render` the sole owner of font-derived cell geometry and
closing the host/render ABI around that owner model.

## Sprint Goal

- remove host-owned `cell_px` from render configuration
- make render derive one authoritative cell geometry from font config and surface constraints
- make the host consume render-owned layout instead of defining text geometry policy
- make font mutation invalidate all render-owned derived font state
- prepare the resulting ABI and runtime path for architect review

## Owner Rule

`cell_px` is render-owned derived state.

The host may provide:

- surface size
- primary font selection
- font size or scale policy, if still part of the public contract

The host may not provide an independent competing cell box.

## Checkpoints

### Checkpoint 0

Decision lock.

Engineer must report:

- the chosen owner for cell geometry
- any remaining conflicting call sites

Architect accepts only if:

- the checkpoint states plainly that render owns `cell_px`
- no alternate owner model is left implied

### Checkpoint 1

Delete stale input shape.

Engineer must:

- remove host-owned `cell_px` from `SurfaceTextConfig`
- remove FFI and host plumbing that sets it
- list all remaining geometry inputs to render

Architect accepts only if:

- no host-facing config struct contains `cell_px`
- no host API still sets `cell_px`
- touched docs and headers match the implementation

### Checkpoint 2

Create one geometry spine.

Engineer must:

- define the render-owned derivation path from font config and surface constraints to `cell_px`
- make `deriveFrameLayout` the authoritative source for `cell_px` and grid
- make prepare consume the same derived geometry

Architect accepts only if:

- one exact function chain owns cell width, cell height, baseline, and grid
- prepare does not use a second geometry authority
- the engineer can name the one geometry truth for the runtime path

### Checkpoint 3

Move host to layout consumer.

Engineer must:

- have the host ask render for layout
- have the host resize VT, PTY, and presentation from render-owned layout output
- remove host-side precomputation of text geometry policy

Architect accepts only if:

- the host role is limited to orchestration and presentation
- runtime control flow stays centralized on the host thread
- no host path reintroduces a second text-geometry policy

### Checkpoint 4

Sharpen font invalidation.

Engineer must:

- define one reset path for font mutation
- invalidate loaded FT faces, HB fonts, font caches, and atlas residency through that path
- report which state is reset and why

Architect accepts only if:

- one render-owned invalidation path exists
- no cache survives font mutation by accident
- proof covers font changes and continued rendering

### Checkpoint 5

Classify remaining ABI leakage.

Engineer must:

- classify each remaining prepared-surface execution type as durable, temporary, or dead
- call out any unsafe slot-only residency assumptions
- identify the next cleanup cuts without pretending they already landed

Architect accepts only if:

- the public ABI inventory is explicit
- temporary leakage is named as temporary
- remaining risks are tied to real files and contracts

## Engineer Report Contract

Engineer reports include only:

- owner view
- changes made
- proof results
- open edges or blockers

Engineer reports do not include acceptance, commit authority, push authority, or next-gate
authority.

## Architect Review Questions

- Which repo owns this state?
- Which file owns this control flow?
- Can the host still invent text geometry?
- Is there exactly one geometry truth?
- Did the change sharpen the C ABI instead of bypassing it?
- What proof closes the checkpoint?

## Proof Gate

Run after each meaningful checkpoint:

- `zig build test:unit`
- `zig build test:render`
- `zig build test:runtime-proof`
- `zig build render-benchmark:build`
- `zig build install` in `howl-linux-host`
- `zig build run` in `howl-linux-host`

Runtime closure requires:

- first prepare succeeds
- first submit succeeds
- first present succeeds
- no visible text corruption on steady-state render
- font changes do not leave stale glyph state
- resize continues to use the same render-owned geometry truth

## Stop Rules

Stop and mark the checkpoint open if:

- host and render both still mutate geometry truth
- prepare and layout derive geometry from different paths
- font invalidation is partial or unclear
- the shortest path requires a new umbrella layer
- proof and visible behavior disagree

## Current Open Decisions

- whether `font_size_px` remains host-provided policy or moves fully into render-owned policy
- whether fallback font paths remain temporarily public or move directly to render-owned discovery
- whether `SurfaceQuery.cell_px` remains output truth or is replaced by a tighter layout packet
