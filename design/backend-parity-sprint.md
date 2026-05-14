# Backend Parity Sprint

Owner: workspace root.

Purpose: keep the old backend parity work as a focused subtrack, not a separate active sprint.

## Status

This doc is collapsed into `design/tigerbeetle-style-sprint.md`.

Use that sprint as the active control document.

Backend parity remains a render-specific checkpoint theme inside the broader sprint, not a parallel
planning track.

## Carry Forward

When a checkpoint touches `howl-render/src/backend/gl/` or `howl-render/src/backend/gles/`, keep
these backend-specific gates in addition to the main sprint rules:

- treat GL and GLES as two implementations of one backend contract
- classify every mismatch as API-forced or drift
- do not preserve backend-local policy when a smaller seam can own it
- do not leave one backend with weaker lifecycle proof or weaker defensive checks
- close with `zig build test:render` in `howl-render`
- if the changed path reaches the host seam, also close with `zig build install` in
  `howl-hosts/howl-linux-host`

## Current Backend Focus

If backend parity work resumes, start with:

1. `internal/c_api.zig` and `internal/provider.zig` seam parity
2. `backend.zig` lifecycle parity
3. backend root public-surface parity

Anything beyond that belongs back in the main sprint doc once it becomes active again.
