# TUI Graphics Live Failure Scratchpad

Owner: workspace root.

Purpose:

- Record the current live TUI graphics failure without mixing it with speculative fixes.
- Reset the workflow back to research -> narrow promotion -> test-first code.
- Capture only owner-true facts proved from the recent `yazi` and `terminal-doom` live repros.

## User-Visible Problem

- `utils/send_app_icon_kitty.py` works.
- Real TUI workloads using Kitty graphics do not work correctly.
- `terminal-doom` was observed as no-op.
- `yazi` image preview was observed as:
  - sometimes no image
  - sometimes a misplaced image
  - at least once visually pinned toward the left side instead of the preview pane placement seen in Kitty/Ghostty
  - at least once causing broken-looking intermediate UI behavior during investigation

## Confirmed Live Facts

### VT Query / Reply Path

- VT receives Kitty graphics support queries.
- VT can produce pending output replies for the child PTY.
- Host writes those VT pending output bytes back to the child PTY.
- Therefore the child capability-reply path is not the current primary blocker.

### `yazi` Live Protocol Shape

- `yazi` uses chunked `a=T` Kitty uploads.
- The live `yazi` path uses:
  - Unicode placeholder mode
  - no-move cursor policy
- VT creates a virtual placement for this path.
- Recent live logs showed shapes such as:
  - `unicode=true`
  - `no_move=true`
  - `placements=0`
  - `virtuals=1`

### Host Graphics Acquisition

- Host acquisition sees the VT graphics publication.
- Host acquisition copies:
  - `images=1`
  - `placements=0`
  - `virtuals=1`
  - non-zero payload bytes
- Therefore the current blocker is later than VT graphics publication and host acquisition.

### Render Placeholder Preparation

- Render placeholder extraction now sees large numbers of placeholder cells for `yazi`.
- During investigation, placeholder extraction progressed from effectively collapsing to one survivor to reconstructing many runs.
- Recent live logs showed examples such as:
  - `placeholder_cells=2200`
  - `runs=44`
- The first reconstructed run can already preserve the preview-pane-relative starting cell, for example:
  - `cell=(1,74)` or `cell=(1,93)`
- Therefore the preview-pane offset is surviving at least into render placeholder run reconstruction.
- Therefore the current blocker is later than basic placeholder cell detection.

### Render Placeholder Reconstruction Is Still Unstable Across Snapshots

- Some live snapshots reconstruct many runs with plausible row/column/image progression.
- Other nearby snapshots collapse back to partial placeholder visibility with many cells still unresolved.
- Examples observed live:
  - one snapshot family with `placeholder_cells=2200`, `runs=44`
  - later snapshot families with smaller `placeholder_cells` and fewer surviving early rows
- Therefore the remaining break is not simply “placeholder mode unsupported.” It is unstable live behavior under the current prepare/update flow.

### Current Best Proven Placement Fact

- The image is not being pinned to the left edge by VT publication alone.
- The first reconstructed placeholder run can begin in the expected preview-pane region.
- Therefore the current visible left-pinned / misplaced result must happen later than VT publication and later than basic placeholder-run start-cell reconstruction.

## Current Best Boundary Guess

- The remaining likely seam is in render/live presentation behavior after placeholder runs exist.
- Candidate seams now are:
  - graphics-only prepare / submit scheduling if placeholder-bearing updates are not consistently producing the expected prepared buffer state across live snapshots
  - placeholder draw rectangle resolution from reconstructed runs to final `src` / `dest` rectangles
  - interaction between partial updates and placeholder-row reconstruction when explicit row anchors are not present in every visible row slice

## What Is No Longer The Top Suspect

- raw Kitty support query rejection
- host writeback of VT pending output to the child PTY
- absence of VT virtual placement publication for the live `yazi` path
- total failure to detect placeholder cells

## Cleanup Requirement

- Temporary `graphics-repro` probes are currently present in:
  - `howl-vt/src/kitty/graphics.zig`
  - `howl-render/src/frame/graphics_prepare.zig`
  - `howl-render/src/frame/surface_buffer.zig`
  - `howl-render/src/frame/prepared_surface_owner.zig`
  - `howl-linux-host/src/terminal/runtime/progress.zig`
  - `howl-linux-host/src/terminal/vt/surface.zig`
- These probes must be removed once the next narrow test-backed slice is defined.

## Required Next Slice

- Before more live repro chasing, we need a full owner-by-owner Kitty graphics proof surface.
- The user requirement is not one narrow regression. The requirement is to prove the full pipeline for payload data and metadata contracts across every owner.
- The next acceptable code slice should do all of the following:
  - define a complete contract matrix from VT ingest to final present
  - prove both payload bytes and metadata fields at each owner boundary
  - include ordinary placements and Unicode placeholder virtual placements
  - include partial/live-like update behavior, not just clean full snapshots
  - remove temporary repro probes once the replacement proof surface exists
  - turn the missing proof surfaces green with the smallest owner-true fixes

## Full Pipeline Proof Plan

- Treat Kitty graphics proof as a pipeline with explicit owner contracts:
  - VT protocol ingest and validation
  - VT graphics state storage and mutation
  - VT export / C ABI publication contract
  - render queue retained copy and republish rules
  - render viewport/placement resolution
  - render payload decode/cache and image identity rules
  - render placeholder reconstruction and virtual placement pairing
  - final composition and draw ordering
  - host upload/present proof

- For each owner boundary, prove both:
  - data payload truth
  - metadata truth

- Metadata proof must include, as applicable:
  - `image_id`
  - `image_number`
  - `placement_id`
  - `format`
  - `width` / `height`
  - payload byte length
  - compression/decompression result
  - source rect
  - destination rect
  - anchor kind/value
  - anchor column
  - cell offsets
  - grid columns/rows
  - effective columns/rows
  - z/layer ordering
  - alternate-screen separation
  - publication sequence / dirty generation

## Existing Proof Surfaces

- `howl-vt/src/test/terminal_graphics.zig` already covers substantial VT protocol/state truth:
  - query reply behavior
  - direct/file/temp/shared-memory upload
  - raw zlib decode handling
  - rejection paths
  - ordinary placement storage
  - virtual placement storage for `U=1`
  - alt-screen separation

- `howl-render/src/frame/queue.zig` already covers retained publication copy and republish rules:
  - graphics publication change forces full prepare
  - retained copied metadata replacement
  - copied item metadata survives into prepare state
  - payload byte-size validation

- `howl-render/src/frame/graphics_viewport.zig` already covers placement visibility and geometry derivation:
  - scrollback resolution
  - clipping
  - off-screen rejection
  - source/destination rectangle adjustment
  - z-band classification and stable ordering

- `howl-render/src/frame/surface_text.zig` already covers prepare-time graphics contracts:
  - prepared graphics wiring
  - payload decode and cache behavior
  - PNG metadata validation
  - virtual placement pairing
  - placeholder inheritance and unresolved-start rejection

- `howl-render/src/frame/surface_buffer.zig` already covers composition truth:
  - graphics composition band insertion
  - prepared placeholder draw ordering
  - real app-icon publication survives composition

- `howl-linux-host/src/test/kitty_graphics_replay.zig` already covers host replay/present proof for the app-icon path:
  - non-empty VT graphics truth
  - expected placement geometry
  - non-empty upload
  - non-empty presented texture
  - framebuffer delta at final present
  - expected icon signature in the final region

## Missing Proof Surfaces To Add

- The current gap is not basic app-icon replay. The current gap is a TUI-style Unicode placeholder pipeline proof.
- Missing or likely-missing contract surfaces now appear to be:
  - VT proof for the exact `yazi`-like `a=T` + chunking + Unicode placeholder + `C=1` / no-move shape as one coherent contract, not as isolated facts
  - VT export proof that the published virtual placement and payload metadata exactly match the ingest contract for that shape
  - queue proof that virtual-placement-only changes and payload-bearing updates survive retained copy and republish under partial/live-like snapshots
  - render prepare proof for multi-row placeholder fields with pane-relative start columns and partial visible slices
  - render proof that reconstructed placeholder runs resolve to stable final source/destination rectangles across partial/live-like updates
  - composition proof that placeholder-backed graphics remain in the correct region when only a subset of rows is visible or freshly updated
  - host replay proof for a TUI-style placeholder workload, not just the direct app-icon control path

## Promotion Target

- The next promoted work item should be a full Kitty graphics contract matrix, grouped by owner, with one or more tests per boundary where coverage is currently missing.
- Success means we can point to explicit proofs for every owner and every contract that matter for:
  - payload bytes
  - metadata fields
  - geometry derivation
  - virtual placement reconstruction
  - final presented region truth

## Research Round: Involved Repos

- `howl-vt`: substantive owner
- `howl-render`: substantive owner
- `howl-linux-host`: substantive owner
- `howl-pty`: transport-only, not a substantive Kitty-graphics owner

## Cross-Owner Proof Matrix

### `howl-vt`

- VT must prove these invariants:
  1. accepted Kitty upload media/compression normalize into retained `(image_id, image_number, format, width, height, payload bytes)` truth
  2. re-upload of the same non-zero `image_id` replaces prior image data and drops dependent retained graphics state
  3. ordinary placements retain correct source rect, cell offsets, z, anchor row/col, requested grid size, and effective grid size
  4. ordinary placements move the cursor correctly unless `C=1`; relative placements never move it
  5. relative placement ancestry rejects self-parent, cycles, missing parent image, missing parent placement, and excessive parent depth
  6. `U=1` stores a virtual placement only and cannot itself be relative
  7. virtual-parent children publish only after placeholder anchor resolution succeeds
  8. placeholder anchor resolution chooses the correct published row/column from matching placeholder cells
  9. graphics state stays screen-local across alt-screen/reset transitions
  10. C ABI publication counts, payload queries, and `publication_seq` staleness rules are exact

- Current VT proof gaps:
  - no direct proof for all parent-error paths
  - no direct proof that `U=1` with parent reference is rejected
  - weak proof for multi-cell placeholder-anchor resolution
  - weak proof for exact chunked `a=T` + Unicode placeholder + `C=1` contract as one coherent publication test
  - missing delete-selector proofs for virtual placements

### `howl-render`

- Render must prove these invariants:
  1. queue metadata counts match copied image/placement/virtual-placement slices
  2. payload byte length equals the sum of per-image `payload_len`
  3. retained queue copy is deep and later source mutation cannot corrupt retained graphics truth
  4. any graphics publication change forces full prepare
  5. partial prepares are accepted only with a valid retained base and matching epochs/sequences
  6. payload slicing across multiple images is exact, with no underflow/overflow/trailing bytes
  7. decode/cache identity is stable for same payload and replaced for changed payload
  8. viewport clipping and ordinary placement geometry produce valid positive source/destination rects inside bounds
  9. z-band classification and stable placement ordering follow Kitty rules
  10. placeholder cell decoding from codepoint/colors/diacritics is exact
  11. placeholder inheritance/backfill only happens where Kitty rules allow it
  12. placeholder run reconstruction preserves image row/col truth and pane-relative cell origin
  13. virtual placement grid dimensions are sufficient for reconstructed runs
  14. placeholder final draw-rect resolution maps runs to correct source/destination rectangles with positive extents and correct aspect-fit behavior
  15. composition merges placeholder-backed draws and ordinary placements in stable Kitty order
  16. partial retained composition preserves previously rendered graphics truth across later non-graphics updates

- Current render proof gaps:
  - no direct metadata-count validation proof in queue
  - no direct multi-image payload partition proof
  - weak placeholder decode/high-byte/backfill proofs
  - weak wide multi-row pane-offset placeholder reconstruction proofs for `yazi`-like workloads
  - major gap: no direct proof for final placeholder draw-rect resolution math
  - weak proof for merge order between placeholder runs and ordinary z=-1 graphics
  - weak proof for partial retained placeholder-backed updates

### `howl-linux-host`

- Host must prove these invariants:
  1. VT acquisition copies visible cells and graphics arrays from one coherent snapshot/publication pair
  2. stale graphics publication causes retry instead of mixed truth
  3. copied payload bytes exactly match VT-published image payload order and length
  4. pending VT output is written back to PTY exactly once and only cleared after successful publish
  5. runtime pacing stays bounded and graphics-only work can still reach present
  6. upload uses valid dimensions and non-empty prepared graphics truth when graphics are present
  7. `finishPresent()` retires and acks exactly the presented snapshot
  8. final term texture and framebuffer proof show non-clear graphics in the expected region
  9. Unicode-placeholder workloads remain visible through upload/present even when `placement_count == 0` and `virtual_placement_count != 0`
  10. later movement/scroll of placeholder-backed graphics updates the final presented region correctly

- Current host proof gaps:
  - no direct test for pending-output writeback clear semantics
  - weak proof for upload invariants around buffer dimensions/base sequence tracking
  - weak proof that graphics-only updates reliably drive present
  - no end-to-end replay proof for Unicode-placeholder/virtual-placement workloads
  - no replay proof for later movement/scroll of placeholder-backed graphics

### `howl-pty`

- `howl-pty` is transport-only for this feature.
- It should only prove:
  1. byte-exact raw transport
  2. bounded pump/read/write behavior
  3. stable lifecycle/error classification
  4. resize/control/wake transport seams
- Kitty parsing, state, placeholder semantics, and presentation must stay out of `howl-pty`.

## Best Current Research Conclusion

- The strongest remaining owner gap is in `howl-render`, specifically final placeholder draw-rectangle resolution and retained partial/live-like placeholder composition.
- The strongest host gap is lack of an end-to-end Unicode-placeholder replay proof.
- The strongest VT gap is lack of one coherent proof for the exact `yazi`-like chunked `a=T` + Unicode placeholder + `C=1` publication contract.
