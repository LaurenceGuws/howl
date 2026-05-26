# Graphics Owner Split Strict Scratchpad

Owner: workspace root.

Purpose:

- Lock the graphics owner-split work into explicit slices.
- Remove room for guessing when promoting future slices.
- Make worker seeding deterministic with exact file paths.

## Settled Verdict

- Kitty placeholder detection is text-coupled by spec and must remain so.
- VT remains the owner of Kitty graphics semantics, animation state, placements, virtual placements, and runtime obligations.
- The current ownership debt is that `howl-render/src/frame/surface_text.zig` owns too much render-graphics preparation state.
- The first split must preserve the VT snapshot contract and the current animation path.

## Do Not Re-Research

These are already decided and should not be reopened before promotion unless code disproves them:

- Do not move Kitty semantics out of `howl-vt/src/kitty/graphics.zig`.
- Do not redesign the VT snapshot contract in the first split.
- Do not remove placeholder suppression from `howl-render/src/frame/input.zig`.
- Do not move viewport math out of `howl-render/src/frame/graphics_viewport.zig`.
- Do not move final graphics composition out of `howl-render/src/frame/surface_buffer.zig`.
- Do not introduce an umbrella render layer.
- Do not mix animation/runtime changes into the first render-owner split.

## Canonical References

Read in this order when seeding workers for any slice below.

Repo rules:

- `/home/home/personal/projects/howl/AGENTS.md`
- `/home/home/personal/projects/howl/loop.txt`
- `/home/home/personal/projects/howl/reference-index.md`

Scratchpads and notes:

- `/home/home/personal/projects/howl/graphics-owner-split-scratchpad.md`
- `/home/home/personal/projects/howl/graphics-owner-split-strict-scratchpad.md`

Howl current path:

- `/home/home/personal/projects/howl/howl-vt/src/kitty/graphics.zig`
- `/home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/surface.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/queue.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/input.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/surface_text.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/graphics_viewport.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/surface_buffer.zig`

Kitty spec truth:

- `/home/home/personal/projects/howl/utils/official_docs/kitty/graphics-protocol.md`

Ghostty comparison:

- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/kitty/graphics_exec.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/kitty/graphics_storage.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/kitty/graphics_unicode.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/renderer/image.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/renderer.zig`

TigerBeetle discipline:

- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

## Exact Owner Map

Must stay VT-owned:

- image/frame/placement/virtual-placement state
- parent-anchor rules
- placeholder-parent anchoring against cells
- animation/runtime obligation state
- publication sequence and dirty generation

Must stay text-owned:

- text shaping/session/font/atlas state
- placeholder suppression from normal text shaping in `frame/input.zig`
- top-level `SurfaceText.prepareSurface()` control flow for the first split only

Must become render-graphics-owned:

- graphics decode
- graphics payload slicing/validation
- graphics raster cache
- graphics publication image keys
- raster binding/remap into prepared graphics
- placeholder run extraction for graphics composition

Must stay render-composition-owned:

- viewport clipping and placement classification
- below-bg / below-text / above-text composition
- final pixel blending

## Target Shape

First acceptable target shape:

```text
howl-render/src/frame/
├── input.zig                  # keep placeholder suppression here
├── queue.zig                  # keep publish seam unchanged for now
├── surface_text.zig           # keep top-level orchestration + text owner only
├── graphics_prepare.zig       # new render-graphics prep owner
├── graphics_viewport.zig      # keep viewport/layer prep here
└── surface_buffer.zig         # keep final composition here
```

Preferred new owner symbol:

- `GraphicsPreparer`

Minimum owner surface:

- `init`
- `deinit`
- `prepare(...) !surface.PreparedGraphics`
- `raster(...) ?GraphicsRasterView`

## Slice Plan

### Slice 1

Goal:

- Extract graphics decode/cache/sweep/bind state and functions out of `surface_text.zig` into `graphics_prepare.zig`.

Allowed files:

- `/home/home/personal/projects/howl/howl-render/src/frame/surface_text.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/graphics_prepare.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/queue.zig` only if required for type imports or exact handoff shape
- `/home/home/personal/projects/howl/howl-render/src/frame/surface_buffer.zig` only if required for moved type imports
- tests directly proving the moved owner shape

Functions/state that must move in Slice 1:

- `graphics_publication_image_keys`
- `decoded_graphics_rasters`
- `DecodedGraphicsKey`
- `GraphicsPublicationImageKey`
- `DecodedGraphicsRaster`
- `GraphicsRasterView`
- `SourceGraphicsPayload`
- `clearGraphicsCache`
- `resolvePreparedGraphicsRasters`
- `sourceGraphicsPayloads`
- `replaceGraphicsPublicationImageKeys`
- `ensureDecodedGraphicsRaster`
- `bindPreparedGraphicsRasters`
- `publicationRasterIndex`
- `publicationKey`
- `findDecodedGraphicsRasterIndex`
- `sweepDecodedGraphicsRasters`
- `publicationReferencesKey`
- `graphicsKey`
- `decodedGraphicsKeyEqual`
- `decodeGraphicsRaster`
- `decodePngGraphicsRaster`
- `decodeRawGraphicsRaster`
- `graphicsPixelCount`
- `graphicsBytesLen`
- `graphicsRaster`

Functions/state that must not move in Slice 1:

- `prepareSurface`
- `preparePlaceholderGraphics`
- `appendPreparedPlaceholderRun`
- `findPreparedVirtualPlacementIndex`
- `placeholderCellFromVtCell`
- `placeholderHighByte`
- `placeholderIndex`
- `placeholderDiacriticIndex`
- `placeholderColorId`
- anything under `howl-vt`
- anything under `howl-linux-host`

Why this slice first:

- It removes the largest ownership lie without changing spec-coupled placeholder logic.

Proof gates:

- `zig fmt build.zig src` in `howl-render`
- `zig build check` in `howl-render`
- `zig build test:unit` in `howl-render`
- tests proving prepared graphics output is unchanged for existing decode/cache cases

Required assertions/tests:

- payload-size assertions remain paired
- raster indices stay valid after bind
- cache reuse unchanged for stable payload
- cache replacement unchanged when payload changes

### Slice 2

Goal:

- Move placeholder run extraction for graphics composition out of `surface_text.zig` into `graphics_prepare.zig`, while keeping placeholder suppression in `input.zig`.

Allowed files:

- `/home/home/personal/projects/howl/howl-render/src/frame/surface_text.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/graphics_prepare.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/input.zig` only if imports/helpers need a minimal adjustment
- tests directly proving placeholder behavior is unchanged

Functions/state that should move in Slice 2:

- `PlaceholderCell`
- `PlaceholderRun`
- `preparePlaceholderGraphics`
- `appendPreparedPlaceholderRun`
- `findPreparedVirtualPlacementIndex`
- `placeholderCellFromVtCell`
- `placeholderHighByte`
- `placeholderIndex`
- `placeholderDiacriticIndex`
- `placeholderColorId`
- `kitty_placeholder_codepoint`
- `kitty_placeholder_diacritics`
- `invalid_graphics_raster_index` if still graphics-owned after Slice 1

Functions/state that must stay in Slice 2:

- placeholder suppression in `frame/input.zig`
- VT placeholder-parent semantics in `howl-vt/src/kitty/graphics.zig`
- `graphics_viewport.zig`
- `surface_buffer.zig`

Why this slice second:

- This is where spec-coupled text adjacency still exists, so it should move only after the decode/cache split is proven stable.

Proof gates:

- `zig fmt build.zig src` in `howl-render`
- `zig build check` in `howl-render`
- `zig build test:unit` in `howl-render`
- placeholder inheritance and placeholder-run tests stay unchanged in meaning

Required assertions/tests:

- each placeholder run references a valid virtual placement
- placeholder-derived image bounds stay valid
- mixed text+graphics prepared output remains equivalent before/after move

### Slice 3

Goal:

- Tighten naming and local ownership once the split is working, if needed.

Non-goals before Slice 3:

- no VT ABI changes
- no host snapshot changes
- no render umbrella layer
- no animation/runtime relocation

## Worker Seed Template

When promoting Slice 1, seed workers with exactly:

- `/home/home/personal/projects/howl/AGENTS.md`
- `/home/home/personal/projects/howl/loop.txt`
- `/home/home/personal/projects/howl/reference-index.md`
- `/home/home/personal/projects/howl/current.txt`
- `/home/home/personal/projects/howl/graphics-owner-split-strict-scratchpad.md`
- `/home/home/personal/projects/howl/howl-render/src/frame/surface_text.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/queue.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/surface_buffer.zig`
- `/home/home/personal/projects/howl/howl-render/src/frame/graphics_viewport.zig`
- `/home/home/personal/projects/howl/howl-vt/src/kitty/graphics.zig`
- `/home/home/personal/projects/howl/utils/official_docs/kitty/graphics-protocol.md`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/kitty/graphics_storage.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/renderer/image.zig`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`

Instruction summary for Slice 1 workers:

- extract decode/cache/sweep/bind only
- do not move placeholder extraction yet
- do not touch VT, host, or ABI contracts
- preserve prepared graphics behavior
- prove equivalence with existing tests

When promoting Slice 2, add:

- `/home/home/personal/projects/howl/howl-render/src/frame/input.zig`
- `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/terminal/kitty/graphics_unicode.zig`

Instruction summary for Slice 2 workers:

- move placeholder run extraction only
- keep placeholder suppression in text input
- preserve Kitty cell-coupled semantics

## Promotion Checklist

Do not promote a slice unless all are true:

- the slice goal fits exactly one section above
- the allowed files are explicit
- the non-goals are explicit
- the proof gates are explicit
- the worker seed list is explicit

## Stop Line

- If code reveals that moving decode/cache first is impossible without also moving placeholder extraction, stop and re-research before editing more.
