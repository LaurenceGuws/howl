# Render VT ABI Decoupling Scratchpad

Archived 2026-05-30.

Durable render/VT ABI facts, reference findings, accepted decisions, proof gaps,
and follow-up slices were consolidated into `project-memory.md` under
`2026-05-30 Render And VT ABI Canonical Memory`.

Historical role of this file:

- Identified the ownership violation where `howl-render/include/howl_render.h`
  depended on VT-owned cell/color/selection/cursor types.
- Recorded Ghostty, Alacritty, and Kitty findings that terminal truth should be
  adapted into render-owned source/draw data rather than exported as renderer ABI
  truth.
- Proposed the render source ABI decoupling slice and host follow-up for
  owner-scoped translate-C modules.

Use `project-memory.md` as the canonical source for new work.
