# Howl Dependency Rules

This document defines allowed dependency direction across modules.
The goal is loose coupling and replaceable implementations.

## Allowed Dependency Direction

Canonical direction:

`host app -> surface -> session -> vt_core`

`surface -> render-core -> render-backend`

`host app -> selected render-backend` (through surface wiring)

## Rules

1. `howl-vt-core` depends on no higher-level Howl module.
2. `howl-session` may consume `howl-vt-core` public API only.
3. `howl-term-surface` may consume `howl-session`, `howl-vt-core`, and render-facing APIs.
4. Render backends (`gl`, `gles`, `metal`, `vulkan`, `software`) depend on `howl-render-core` only.
5. `howl-render-core` must not depend on platform host frameworks.
6. Host apps (for example `howl-sdl-host`) consume surface + chosen renderer backend; they do not reach into lower-level internals.
7. Utility repos consume public files, releases, local artifacts, and documented command surfaces; they do not become runtime dependencies of product modules.

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

## Change Review Rule

Any change that introduces a new cross-module dependency must update this file and `MODULE_MAP.md` in the same PR/commit series.
