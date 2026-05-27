# Graphics Generated Placement Transition Scratchpad

Owner: workspace root.

Purpose: coordinated VT/render/host plan for replacing render-side Kitty placeholder interpretation with VT-owned generated placeholder placements.

Reviewer status: research accepted with amendment. The core invariant is accepted. The exact public ABI extension remains a design gate: add only fields needed by render/host/product behavior, not debug convenience.

## Core Invariant

Do not publish both generated placeholder placements and render-consumed placeholder runs.

If VT publishes generated placeholder cell images through the placement stream, the render-facing publication must have:

- `placement_count` includes normal placements plus generated placeholder placements.
- `placeholder_run_count == 0` for that same render publication.
- `graphics_placeholder_runs.len == 0` in the host-to-render publish slot.

This avoids double drawing.

## Source Truth

Kitty source:

- `utils/dev_references/terminals/kitty/kitty/screen.c`: `screen_render_line_graphics`
- `utils/dev_references/terminals/kitty/kitty/screen.c`: `screen_dirty_line_graphics`
- `utils/dev_references/terminals/kitty/kitty/graphics.c`: `grman_put_cell_image`
- `utils/dev_references/terminals/kitty/kitty/graphics.c`: `grman_remove_cell_images`
- `utils/dev_references/terminals/kitty/kitty/graphics.c`: `grman_update_layers`
- `utils/dev_references/terminals/kitty/kitty/graphics.h`: `ImageRef`, `GraphicsRenderData`

Howl current render hack:

- `howl-render/src/frame/surface_buffer.zig`: `drawPlaceholderRunByIndex`, `resolvePlaceholderDrawPlacement`, placeholder sort helpers
- `howl-render/src/frame/graphics_prepare.zig`: `preparePlaceholderGraphics`, `ensureVirtualPlacementImageRefs`
- `howl-render/src/frame/surface.zig`: `PreparedGraphicsVirtualPlacement`, `PreparedGraphicsPlaceholderRun`
- `howl-render/src/frame/queue.zig`: placeholder-run copy/validation

## Recommended ABI Shape

Minimum accepted shape for implementation workers:

- Generated placeholder cell images are normal `HowlVtGraphicsPlacement` entries.
- VT resolves their `source_x`, `source_y`, `source_width`, `source_height` as image pixel source rects.
- VT resolves their destination through existing placement fields: `anchor`, `anchor_col`, `dest_*_cell_px`, `dest_grid_*`, `effective_*`, `columns`, `rows`.
- Generated placements use `z_index == -1`.
- Generated placements must have a deterministic placement identity/order.

ABI extension rule:

- Do not add provenance fields solely for debugging.
- If render needs to distinguish generated placements from normal placements to enforce the mixed-stream invariant, add the smallest possible field, preferably a `flags` field at the tail of `HowlVtGraphicsPlacement` mirrored exactly in `howl-render/src/ffi_types.zig`.
- If a flag is added, define `HOWL_VT_GRAPHICS_PLACEMENT_GENERATED_PLACEHOLDER = 1` in the public C header and mirror it in render.
- Do not add `virtual_placement_index`, `placeholder_run_order`, `placeholder_image_row`, or `placeholder_image_col` unless a concrete product consumer or test needs them across the C ABI. VT tests can validate those internally before FFI.

Why not a new stream:

- A separate `HowlVtGraphicsCellPlacement` stream repeats the split-truth problem.
- Render should consume one placement stream.

Why not keep placeholder runs as render truth:

- That keeps Kitty placeholder protocol interpretation in render.
- It directly contradicts Kitty's terminal/screen-owned materialization model.

## Double-Draw Avoidance Rule

Render-facing publication must never contain both:

- generated-placeholder placement entries, and
- non-empty placeholder-run spans.

Recommended enforcement:

- VT sets `placeholder_run_count == 0` for normal render publication once generated placements are enabled.
- Host does not query or pass placeholder runs to render when generated placements are active.
- Render validation rejects mixed input if a generated-placement flag exists and `placeholder_runs.len != 0`.

If no placement flag is added:

- The invariant must be enforced entirely in VT/host publication shape.
- This is acceptable only if tests prove host publishes empty placeholder-run spans after generated placements are active.

## Atomic Commit Sequence

### 1. ABI Mirror Safety Commit

Owner: `howl-vt`, `howl-render`, `howl-linux-host`.

Purpose: make any required placement ABI extension across all repos with no behavior change.

Allowed changes:

- `howl-vt/include/howl_vt.h`
- `howl-vt/src/ffi.zig`
- `howl-render/src/ffi_types.zig`
- host C import consumers only if required by compile drift

Acceptance:

- All new fields zero for existing placements.
- No generated placements emitted yet.
- Existing placeholder-run render path unchanged.
- `zig build test` in `howl-vt`
- `zig build test` in `howl-render`
- `zig build test:unit` in `howl-linux-host`
- `git diff --check`

Reviewer red flags:

- VT-only ABI changes.
- Extra debug-only fields.
- Behavior changes mixed into ABI mirror commit.

### 2. Render Mixed-Stream Guard Commit

Owner: `howl-render`.

Purpose: prevent double draw before VT starts publishing generated placements.

Allowed changes:

- `howl-render/src/frame/surface_text_ffi.zig`
- `howl-render/src/frame/queue.zig`
- tests in render only

Acceptance:

- Old VT publication with placeholder runs still works.
- If generated-placement flags exist, render rejects or ignores mixed generated placements plus placeholder runs according to the chosen ABI shape.
- No render-side Kitty placeholder parsing is added.

Reviewer red flags:

- Any new render parsing of `U+10EEEE`, diacritics, fg/underline colors, or virtual placement semantics.

### 3. VT Generated Placement Publication Commit

Owner: `howl-vt` plus host bridge if needed.

Purpose: materialize placeholders in VT and publish them as normal placements.

Allowed changes:

- `howl-vt/src/kitty/graphics.zig`
- `howl-vt/src/terminal.zig`
- `howl-vt/src/ffi.zig`
- `howl-vt/src/test/terminal_graphics.zig`
- `howl-linux-host/src/terminal/vt/surface.zig` only if needed to stop querying/passing placeholder runs for render publication

Acceptance:

- Placeholder cells produce generated z `-1` placements.
- Render-facing meta has `placeholder_run_count == 0` when generated placements are active.
- Host publish slot has empty placeholder-run span for generated path.
- Clearing/replacing placeholder cells removes stale generated placements.
- Updating virtual placement republishes generated placements.
- Existing placeholder run assembly tests remain, but may need to use a VT-only debug query or internal tests if render-facing meta now reports zero runs.

Reviewer red flags:

- Publishing generated placements and nonzero render-facing placeholder runs together.
- Generated placement source fields in cell units instead of image pixels.
- Generated placement destination fields that require render to know placeholder protocol.

### 4. Render Placeholder Path Deletion Commit

Owner: `howl-render`.

Purpose: remove render-owned Kitty placeholder interpretation.

Delete or simplify:

- `surface_buffer.zig`: `drawPlaceholderRunByIndex`, `resolvePlaceholderDrawPlacement`, `placeholderSourceRect`, `placeholderGrid`, placeholder sort helpers, placeholder draw/reject logs
- `graphics_prepare.zig`: `preparePlaceholderGraphics`, `ensureVirtualPlacementImageRefs` if no other caller remains
- `surface_text.zig`: call to `preparePlaceholderGraphics`
- `surface.zig`: placeholder prepared structs if no longer used
- `queue.zig`: placeholder-run validation/copy if no longer render-facing

Acceptance:

- Generated placeholder placements render via `prepareGraphics` and `drawGraphicsPlacement`.
- No references remain in render to Kitty placeholder protocol helpers.
- Mixed normal/placeholder-generated z-order test passes.

Reviewer red flags:

- Keeping a special placeholder drawer after generated placements exist.
- Removing normal raster decode/bind machinery.

### 5. Host Cleanup Commit

Owner: `howl-linux-host`.

Purpose: remove placeholder-run render-publication plumbing and update diagnostics.

Acceptance:

- Host no longer allocates/passes placeholder-run spans for render publication after generated placements are active.
- Graphics logs describe placement truth, not placeholder-run render truth.
- Host tests pass.

## Acceptance Tests For Whole Transition

VT:

- Placeholder cells create generated z `-1` placements.
- Generated placement source rect is in image pixels.
- Generated placement destination rect is in cell pixels through existing placement geometry fields.
- Clearing/replacing placeholder cells removes generated placements.
- Updating a virtual placement changes generated placement publication.
- Diacritics remain 0-based.

Render:

- Generated placement enters `prepareGraphics` as a normal placement.
- Generated placement classifies below text by `z_index == -1`.
- Generated placement draws through `drawGraphicsPlacement`.
- Mixed generated placement plus placeholder-run input is rejected or impossible.
- No render code parses placeholder cells, diacritics, fg image ids, or underline placement ids.

Host:

- VT acquisition publishes generated placements and empty placeholder-run spans.
- Render publish accepts generated placements.
- No Zig-shaped shortcut bypasses the C ABI.

Full verification:

- `zig build test` in `howl-vt`
- `zig build test:regression:build` in `howl-vt`
- `zig build test` in `howl-render`
- `zig build test:unit` in `howl-linux-host`
- `zig build test:integration:kitty-graphics-replay` in `howl-linux-host`
- `zig build -Doptimize=ReleaseFast` in `howl-linux-host`
- `git diff --check` at workspace root

## Rejected Alternatives

- VT-only generated placement implementation: rejected because ABI mirrors and render publication shape must change together.
- Generated placements plus nonzero placeholder-run publication: rejected because it can double draw.
- New render-facing cell-placement stream: rejected because it creates another placement-like render contract.
- Render-side smarter placeholder logic: rejected because render would still own Kitty protocol consequences.
- Debug-only placement ABI fields: rejected unless a real C-facing consumer needs them.
