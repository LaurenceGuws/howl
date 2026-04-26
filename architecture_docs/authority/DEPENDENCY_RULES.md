# Howl Dependency Rules

This document defines allowed dependency direction across modules.
The goal is loose coupling and replaceable implementations.

## Allowed Dependency Direction

Canonical direction:

`host app -> howl-term -> session -> vt_core`

`howl-term -> render-core -> render-backend`

`host app -> selected render-backend` (through howl-term wiring and host-owned context/present setup)

## Rules

1. `howl-vt-core` depends on no higher-level Howl module.
2. `howl-session` may consume `howl-vt-core` public API only.
3. `howl-term-surface` is the current repo name for the primary `howl-term` boundary and may consume `howl-session`, `howl-vt-core`, and render-facing APIs.
4. Render backends (`gl`, `gles`, `metal`, `vulkan`, `software`) depend on `howl-render-core` only.
5. `howl-render-core` must not depend on platform host frameworks.
6. Host apps (for example `howl-sdl-host` and `howl-android-host`) consume one or more `howl-term-surface` instances plus a chosen renderer backend path; they do not reach into lower-level internals.
7. `howl-sdl-host` and `howl-android-host` must remain equivalent callers of `howl-term-surface` operations (`start`, `stop`, `feedBytes`, `feedKey`, `tick`, `resize`, `control`, `frameData`) even if their platform event loops differ.
8. Utility repos consume public files, releases, local artifacts, and documented command surfaces; they do not become runtime dependencies of product modules.

## Forbidden Dependency Direction

1. `vt_core -> session/surface/render/host`
2. `session -> host renderer/framework types`
3. `render-core -> host frameworks (SDL, Cocoa, Android UI, etc.)`
4. `render-backend -> host-specific app orchestration logic`
5. `child module -> sibling internals` (only public APIs allowed)
6. `product runtime module -> utility repo`

## Public API Boundary Rule

- Cross-repo usage must go through exported public APIs.
- Internal folders/files are never cross-repo import targets.
- Hosts manage multiple terminal instances where needed; they do not orchestrate
  lower-layer policy by importing sibling internals.

## Change Review Rule

Any change that introduces a new cross-module dependency must update this file and `MODULE_MAP.md` in the same PR/commit series.
