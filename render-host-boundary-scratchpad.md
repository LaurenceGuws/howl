# Render/Host Boundary Scratchpad

Archived 2026-05-30.

Durable render/host boundary facts were consolidated into `project-memory.md`
under `2026-05-30 Render And VT ABI Canonical Memory`.

Historical role of this file:

- Fixed backend independence as the first render ABI priority.
- Recorded that hosts own event loops, wake policy, presentation cadence,
  backend resource realization, and backend publication.
- Rejected render-owned runtime loops, presentation queues, swapchains, and
  backend frame lifecycle hidden behind the ABI.

Use `project-memory.md` as the canonical source for new work.
