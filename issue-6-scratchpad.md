# Issue 6 Scratchpad

Owner: workspace root.

Source:

- `feature-gap-scratchpad.md` item 6

Issue:

- Kitty graphics truth exists in VT and is now exported above VT, but drawing is still blocked by missing VT owner truth for implicit-size destination extent.

## Comparison

### Kitty Has

- VT is the source of truth for graphics lifecycle.
- Main and alternate screens have separate graphics owners.
- Physical placements are retained terminal truth, not a render cache.
- Scrolling and clipping mutate retained placement truth.
- `a=T` is real transmit-and-display.
- Omitted `c` and/or `r` dimensions are resolved from source size, aspect ratio, cell size, and offsets.
- Visible ordering uses Kitty z-band semantics.

### Ghostty Has

- A strong VT-owned retained row/location model.
- A public C seam for graphics inspection.
- Integration helpers compute destination/grid/viewport facts from VT-owned truth.
- Useful integration shape reference, not a literal copy target.

### Howl Has Now

- `howl-vt` owns graphics truth.
- Main and alternate screens own separate graphics state.
- Reset, replacement, upward retention, below-screen anchors, and supported clipping are repaired for the supported subset.
- Public ABI exists for graphics meta, indexed image query, indexed placement query, payload copy, and cell pixel size.
- Host pairs surface/meta acquisition and retries on stale item publication.
- Render ingests copied graphics metadata and proves publication-scoped replacement.
- No drawing is implemented.

### Howl Does Not Yet Have

- Kitty-honest VT truth for implicit-size destination extent.
- A truthful drawing contract above VT.
- Virtual/placeholder placements.
- Relative placements.
- Non-`t=d` media.
- Compression.
- Animation/frame publication.

## Goal

- Kitty-level lifecycle honesty.
- Ghostty-level integration discipline.
- Alacritty-level bounded/simple control flow.
- TigerBeetle-level skepticism and proof.

VT remains the source of truth.
Render translates VT truth.
Hosts use copied C-ABI truth only.

## Supported Subset

- direct payload medium `t=d`
- physical cursor-anchored placements only
- actions `t`, `T`, `p`, `d`
- image ids and image numbers
- source crop truth
- cell-pixel offsets
- row-anchor truth including off-screen retained states

Out of scope:

- placeholders / `U=1`
- relative placements `P/Q/H/V`
- decoded/render-ready image publication
- non-`d` media
- compression
- animation control/composition
- render-derived geometry

## Accepted Coherence Rule

- `copy_surface()` publishes visible truth under `snapshot_seq`.
- `query_graphics_meta()` publishes graphics truth under `publication_seq`.
- Graphics item queries must use that exact `publication_seq`.
- If any item query rejects it, restart the whole acquisition attempt.
- Graphics publication is still conservative, not graphics-local.

## Accepted Above-VT State

- Host acquisition boundary is honest and proved.
- Copied item metadata ingestion is landed.
- Render replacement/invalidation from publication truth is landed.
- Draw order is not the immediate blocker anymore.

## Current Blocker

- Current VT truth is false for implicit-size placements.
- `effective_columns` / `effective_rows` are not Kitty-honest for `c=0,r=0`, `c>0,r=0`, and `c=0,r>0`.
- That means viewport inclusion and clipping cannot be decided honestly above VT.
- This is a VT owner-truth bug first, not a render gap first.

## Next Checkpoint

`VT Destination-Extent Truth`

### Exact Missing Truth

- truthful current grid extent for implicit-size placements
- truthful current destination pixel edges in anchor-cell pixel space
- truthful omitted-`c`/`r` resolution from source rect, cell size, offsets, and aspect ratio

### Contract Direction

- Keep requested `columns` / `rows`.
- Add or redefine current resolved destination truth explicitly.
- Likely fields:
  - `dest_left_cell_px`
  - `dest_top_cell_px`
  - `dest_right_cell_px`
  - `dest_bottom_cell_px`
  - `dest_grid_columns`
  - `dest_grid_rows`

### Must Remain Render-Owned

- decoded/render-ready image bytes
- texture/upload state
- backend transforms and final scissor rectangles
- batching and draw submission
- scene/cache policy

### Proof Target

1. Kitty-honest resolution for:
   - `c=0,r=0`
   - `c>0,r=0`
   - `c=0,r>0`
   - `c>0,r>0`
2. Non-zero offsets.
3. Cursor movement uses resolved grid extent.
4. Viewport inclusion derives from resolved truth without guesses.
5. Viewport clipping derives from resolved truth without guesses.
6. No render-owned geometry leaks into VT.

### Stop Condition

- Mark `work-not-clear` if exact current destination edges cannot be stated from VT-owned source crop, offsets, requested size, anchor truth, and VT cell size alone.
- Do not start drawing, scene, or cache work until this checkpoint is proved.
