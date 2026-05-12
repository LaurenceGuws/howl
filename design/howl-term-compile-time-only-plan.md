# Howl-Term Compile-Time Only Plan

Purpose: replace the old `howl-term` runtime-era plan with the new rule: `howl-term` is a
compile-time composition and equality-enforcement package only.

Last updated: 2026-05-12

## Position

`howl-term` is no longer allowed to be a runtime owner.

`howl-term` now exists to do three things only:
- compose the owner-true lower modules into one product-shaped package at compile time
- enforce cross-host equality of shared ABI vocabulary at compile time
- provide one narrow umbrella surface that teaches the right owner chain

`howl-term` must not own:
- PTY or session runtime behavior
- VT runtime behavior
- render runtime behavior
- host event loops
- redraw policy
- platform wake policy
- runtime convenience wrappers that hide lower-module ownership

In plain English:
- `howl-session` owns PTY and child-process runtime
- `howl-vt-core` owns terminal protocol and terminal-state vocabulary
- `howl-render-core` owns snapshot storage, render runtime, renderer execution, and render-facing
  data model types
- hosts own wake, pacing, redraw, and presentation
- `howl-term` only ensures those pieces line up correctly at compile time

## Non-Negotiables

- no runtime state in `howl-term`
- no runtime threads in `howl-term`
- no hidden scheduler policy in `howl-term`
- no fake all-in-one `howl-term` render seam
- no compatibility museum for deleted `howl-term` runtime APIs
- no wrapper theater that forwards lower-module runtime behavior back through `howl-term`
- Android stays frozen until Linux is stable on the new boundary

## Target Owner Chain

Canonical chain:
- hosts -> `howl-term`
- `howl-term` -> `howl-session`, `howl-vt-core`, `howl-render-core`

Meaning of that chain now:
- hosts may still depend on `howl-term` as the umbrella package/root
- runtime semantics must come from the owner-true lower modules
- `howl-term` may re-export lower-module namespaces or C ABI catalogs only when that does not add
  new runtime semantics

## What `howl-term` Is Allowed To Do

- re-export owner-true lower-module surfaces
- install compile-time assertions that shared enums, statuses, widths, and struct layouts stay equal
  across hosts and owner modules
- install umbrella headers only if they add no new runtime semantics
- define build-time product composition rules
- fail compilation when host-facing equality rules drift

## What `howl-term` Is Not Allowed To Do

- own mutable runtime state that duplicates lower-module owners
- define a second C ABI for behavior already owned by `howl-session`, `howl-vt-core`, or
  `howl-render-core`
- translate lower-module runtime operations into a new broad convenience API
- compensate for host scheduling or renderer ownership mistakes

## Equality Enforcement Rule

`howl-term` is now the compile-time equality gate for host-facing product shape.

That means:
- shared constants exposed through multiple modules must match exactly
- shared C-facing integer widths must match exactly
- shared status values must match exactly
- any umbrella surface exported by `howl-term` must be a strict subset or exact pass-through of
  owner-true module semantics
- if equality cannot be asserted, the surface should not exist in `howl-term`

## New Milestones

### Milestone 1: Delete Runtime Ownership From `howl-term`

Goal:
- remove all remaining runtime behavior from `howl-term`

Done when:
- `howl-term` owns no runtime threads
- `howl-term` owns no runtime queue state
- `howl-term` owns no render runtime state
- `howl-term` owns no fake runtime convenience ABI

### Milestone 2: Mature Lower-Module C ABIs

Goal:
- make the smaller modules real C ABI products

Required outcome:
- `howl-session` exposes PTY/session vocabulary only
- `howl-vt-core` exposes VT/input vocabulary only
- `howl-render-core` exposes the render data model, render runtime, and renderer owner surfaces the
  hosts actually need

Done when:
- every runtime behavior used by hosts belongs to a lower-module C ABI
- `howl-term` does not need to invent runtime shims

### Milestone 3: Make `howl-term` A Pure Compile-Time Product Gate

Goal:
- reduce `howl-term` to build-time composition and equality checks

Required outcome:
- `howl-term` root and namespace wrappers stay behavior-free
- any remaining `howl-term` code exists only to compose and assert, not to run
- compile-time failures are the primary enforcement tool when module surfaces drift

### Milestone 4: Realign Hosts To The Owner-True Runtime Surfaces

Goal:
- make Linux and later Android consume the real owner chain

Required outcome:
- host wake/redraw flow stays host-owned
- render runtime calls come from `howl-render-core`
- PTY/session calls come from `howl-session`
- VT/input vocabulary comes from `howl-vt-core`
- `howl-term` remains compile-time-only

## TigerBeetle Rules For This Plan

- explicit control flow only
- bounded work only
- explicit-width public C types
- assert-dense boundaries
- no compatibility aliases kept for comfort
- comments explain why a boundary exists
- deletion beats wrappers

## Ghostty Pressure

Ghostty is the architecture-shape reminder:
- terminal state owner and renderer owner are different owners
- renderer wakeups are explicit
- mailbox and wake paths are explicit
- the terminal package must not quietly become the renderer runtime

## Done Definition

This plan is complete only when:
- `howl-term` runtime ownership is gone
- the smaller modules are the real runtime C ABI products
- `howl-term` acts only at compile time
- Linux is stable on the new owner chain
- Android remains frozen until that Linux proof exists
