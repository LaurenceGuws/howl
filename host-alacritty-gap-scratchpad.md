# Host Alacritty Gap Scratchpad

Archived 2026-05-30.

Durable host Alacritty/Ghostty/TigerBeetle findings were consolidated into
`project-memory.md` under `2026-05-30 Host Canonical Memory`.

Historical role of this file:

- Recorded eight host gaps around wake/redraw/present policy, present cadence,
  run-loop phase ownership, input-to-redraw ownership, frame pacing, present
  completion, redraw event shape, and the simple text path.
- Most of these historical specs are now reflected in current host code and are
  not active worker slices.

Use `project-memory.md` as the canonical source for new work.
