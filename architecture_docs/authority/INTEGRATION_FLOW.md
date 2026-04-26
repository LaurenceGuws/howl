# Howl Integration Flow

This document defines runtime integration flow at the family level.
It is intentionally host-framework agnostic.

## High-Level Runtime Loop

1. Host receives platform events (window/input/timer/process signals).
2. Host forwards relevant events to one or more `howl-term-surface` instances.
3. Each terminal boundary routes lifecycle and transport actions to `howl-session`.
4. Session drives terminal processing via `howl-vt-core` behavior.
5. The terminal boundary obtains a render-ready frame model from composed state.
6. The terminal boundary invokes `howl-render-core` to prepare backend-agnostic render work.
7. The selected renderer backend executes GPU/CPU draw using host-owned context/device setup.
8. Host presents frame.

## Data and Control Split

- Control/lifecycle path:
  - host -> `howl-term` -> session -> vt_core
- Render path:
  - vt_core/session state -> `howl-term` frame model -> render-core -> render-backend -> host present

## Multi-Widget Model

- One `howl-term`/session instance per terminal widget/tab/pane.
- Host/app manager orchestrates multiple terminal instances.
- Shared renderer resources are allowed via renderer-core/backend policies, not by merging session state machines.

## Error Boundary Expectations

- Transport and lifecycle errors are handled at session/surface boundaries.
- Renderer failures are isolated to renderer path and reported to host without mutating terminal semantics.
- Host platform errors stay host-owned and must not leak platform types into core/session contracts.
- App-level multiplexing, tab state, and workspace policy stay host-owned even when many terminal instances share renderer resources.

## Latency and Quality Objectives (Family Level)

- Stable input-to-frame latency under mixed feed/apply/render load.
- Deterministic state transitions across reset/resize/control boundaries.
- Replaceable renderer backend without changing terminal/session semantics.
