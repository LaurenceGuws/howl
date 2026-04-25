# Howl Host/Backend Split

## Purpose

Define high-level ownership boundaries for the Howl family so backend and host
work do not drift into each other.

## Repo Ownership

- `howl-vt-core`
  - portable terminal backend
  - parser, semantics, screen/state, replay tests, backend API
- `howl-hosts`
  - host applications and platform runtime
  - GUI lifecycle, Android/JNI/export surfaces, rendering integration, packaging
- `howl-shared`
  - reusable libraries and tools
- `howl-editor`
  - future editor engine

## Boundary Rule

If a change can be host/runtime/platform-owned, it belongs outside
`howl-vt-core`. If a change defines portable terminal behavior, it belongs in
`howl-vt-core`.

## Integration Rule

Hosts consume `howl-vt-core` through explicit public API contracts. They do not
reach into backend internals.

