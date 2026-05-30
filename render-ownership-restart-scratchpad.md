# Render Ownership Restart Scratchpad

Archived 2026-05-30.

Durable render ownership restart facts, accepted decisions, proof gaps, and
pending slices were consolidated into `project-memory.md` under
`2026-05-30 Render And VT ABI Canonical Memory`.

Historical role of this file:

- Rejected `surface/flow.zig` and generic `surface/types.zig` as fake-simple
  umbrella owners.
- Established the target split across `source/*`, `render/*`, `prepared/*`, and
  `session/*`.
- Recorded the accepted first implementation shape replacing `SurfaceTextOwner.flow`
  with explicit geometry, source slot, prepare request, submitted, source epoch,
  and cursor blink owners.

Use `project-memory.md` as the canonical source for new work.
