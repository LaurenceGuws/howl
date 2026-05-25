# Issue 6 Scratchpad

Owner: workspace root.

Source:

- `feature-gap-scratchpad.md` item 6

Issue:

- Kitty graphics queue is complete for the chosen Howl boundary decisions.

## Outcome

- VT owns graphics protocol truth and publication consequences.
- Host copies published C ABI truth only.
- Render owns decode/cache, prepare, and draw from published truth.

## Landed

- truthful VT placement lifecycle and geometry
- host paired surface/graphics acquisition with publication retry
- render retained graphics publication state
- render prepare visibility, clipping, source adjustment, z-band ordering
- draw-band insertion in compose
- raw decode/cache for `f=24` / `f=32`
- PNG decode for `f=100`
- destination extent truth
- relative placement truth
- placeholder cell truth export
- virtual placement prototype export
- placeholder pairing and visible draw path
- virtual placeholder parents for relative placements
- non-direct media: `t=f` / `t=t` / `t=s`
- raw compression: `o=z` for `f=24` / `f=32`
- raw frame retention and current-frame publication
- PNG current-frame publication through VT-private coalescing

## Chosen Boundary

- PNG current-frame coalescing is handled privately in `howl-vt`.
- Above VT, publication still looks like ordinary image truth.
- Host/render stay unchanged.

## Remaining Open Edge

- Full autonomous animation playback over time is not part of this completed queue.
- If we want Kitty-like autonomous animation behavior later, that is a separate runtime/policy feature.

## Not A Blocker

- `f=100,o=z` on local media remains rejected where protocol meaning is ambiguous.
- That is not blocking the completed chosen queue.

## Status

- This scratchpad is complete for its current purpose.
