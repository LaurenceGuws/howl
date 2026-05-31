# V0 Atlas Backed Prepared Sprites

Owner: workspace root.

Status: promoted to `current.txt`; implementation pending.

## Problem

User `vttest` run after `render: bound protocol v0 sprite resources` shows the transient
resource lifetime fix is not the architecture fix.

Observed log facts:

- `v0_emit_status=2`, which is `HOWL_RENDER_V0_EMIT_CREATE_BOUND_OVERFLOW`.
- `resource_plan_status=call_failed`, `no_sidecar_call_failed=10`, and `rgba_fallback=10`
  every interval during the failure.
- `create=3471`, `upload=3471`, `retire=3168`, `delete=3168`.
- `churn_same_frame=3168`, `created_not_surviving=3168`.
- `slots live=303`, `retired=3168`, `empty=625`.
- This proves lifetime is bounded now, but V0 emission is still creating one backend resource
  per prepared sprite/raster draw until the create bound is exceeded.

## Reference Findings

Ghostty:

- `utils/dev_references/terminals/ghostty/src/font/Atlas.zig` owns texture atlas data,
  region reservation, uniform pixel format, modified/resized counters, and packed atlas bytes.
- `utils/dev_references/terminals/ghostty/src/renderer/generic.zig` syncs shared grayscale
  and color font atlas textures only when their atlas `modified` counters advance.
- Ghostty draws text using shared atlas textures, not one texture per glyph draw.

Alacritty:

- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs` owns a
  1024x1024 texture atlas and inserts rasterized glyphs via `TexSubImage2D` into atlas
  regions.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
  caches `GlyphKey -> Glyph`, where `Glyph` stores texture id and UV region.
- Alacritty caches glyphs and draws from atlas texture regions, not one texture per draw.

Howl facts:

- `howl-render/src/text/raster/cache.zig:OwnedAtlasCache` is currently a sprite slot cache,
  not a packed texture atlas. It tracks `SpritePosition.slot`, `key`, `rendered`, and stored
  raster bytes, but not atlas x/y placement.
- `howl-render/src/text/direct_normal.zig` reserves cache slots by sprite key and emits
  `TextSpriteDraw.sprite.slot/key/rendered`.
- `howl-render/src/text/frame_preparer.zig` merges `TextSpriteDraw` and raster outputs into
  prepared surfaces.
- `howl-render/src/protocol_v0/emit.zig` currently turns prepared sprite draws into V0
  sprite resources, creating/uploading one resource per new raster identity and transiently
  creating/uploading/retiring resources past the persistent cap.
- V0 already has `HOWL_RENDER_V0_COMMAND_DRAW_GLYPH_RUN` and `HowlRenderV0GlyphRef` with
  `atlas_resource`, `atlas_rect`, destination coordinates, glyph id, and color.
- `howl-render/src/protocol_v0/realize.zig` already validates and realizes alpha glyph atlas
  resources with fixed 1024x1024 atlas dimensions.

## Decision

The product fix is atlas-backed V0 emission, not another Howl-only transient churn budget.

The next implementation should move prepared glyph/sprite raster payloads into shared atlas
resources and emit draw commands that reference atlas regions. If the current V0 glyph-run ABI can
represent alpha prepared sprite draws, use it. If it cannot, prove the gap before changing ABI.

## Promoted Slice

- `current.txt` - `V0 Atlas Backed Prepared Sprites`

## Required Shape

- Keep full RGBA fallback/oracle unchanged.
- Keep the transient sprite path only as a safety fallback until atlas-backed V0 is accepted.
- Add render-owned atlas placement truth where Howl currently only has slot truth.
- Emit shared atlas creates/uploads and glyph-run/draw refs instead of one sprite resource per draw.
- Preserve exact overflow diagnostics if atlas upload/command/glyph bounds are exceeded.
- Do not add a host-owned eviction policy or backend ack in this slice.

## Acceptance Gates

- Protocol proof tests show repeated prepared sprite/glyph draws share atlas resources instead of
  creating per-draw resources.
- Software oracle proves atlas-backed V0 equals full RGBA for prepared alpha sprite/glyph draws.
- Bounded `vttest` smoke should not enter steady-state `v0_emit_status=2` create-bound fallback
  caused by per-draw sprite resources.
- Existing root and subrepo gates pass.

## Implementation

- `howl-render/src/protocol_v0/emit.zig` now emits alpha prepared sprites through the existing
  V0 glyph-run/alpha-atlas command path.
- The renderer owns one persistent 1024x1024 alpha atlas resource for prepared alpha sprites.
- New alpha sprite rasters reserve simple row-packed atlas rectangles and upload only those
  rectangles.
- Reused alpha sprite rasters emit glyph refs to the existing atlas rectangle with no create/upload.
- Color prepared sprites remain on the existing sprite resource path.
- Existing transient sprite fallback remains available for color sprites only.
- No host ABI change was needed for this slice.

## Verification

- From `howl-render`: `zig build test:protocol-proof -- "protocol v0"`
- From `howl-render`: `zig build test:unit -- "protocol v0"`
- From `howl-render`: `zig build test`
- From `howl-render`: `git diff --check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`
- From `howl-linux-host`: `zig build test --summary all`
- From `howl-linux-host`: `zig build -Doptimize=ReleaseFast`
- From `howl-linux-host`: `git diff --check`

Smoke:

- From `howl-linux-host`: `timeout 22s zig build run -Doptimize=ReleaseFast -- --duration-ms 18000 --debug-process-accounting --debug-log-every-ms 5000 --command vttest`
- Result no longer reproduced create-bound sidecar failure:
  `v0_emit_status=0`, `no_sidecar_call_failed=0`, `create=1`, `retire=0`, `delete=0`,
  `churn_same_frame=0`, `gl gen=1`, `subimage=67`.
- Remaining fallback reason is host presentation coverage, not renderer sidecar emission:
  `v0_unsupported_shape` rose, `resource_plan_status` reported `unsupported_command` or
  `unsupported_resource`, and intervals still showed `rgba_fallback=10`.

## Follow-Up

- Promote a host slice for atlas-backed glyph partial/patch presentation.
- The host currently accepts full-clear glyph frames; `vttest` produces partial/no-full-clear atlas
  glyph frames that are now cheap and valid sidecars but not yet presentable by the host V0 path.
