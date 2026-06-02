# Render Emitter Resource Store Research Cache - 2026-06-02

Research cache. Research only. No product code edits.

## Sources Read

- TigerBeetle style and architecture.
- `AGENTS.md`, `loop.txt`, `reference-index.md`.
- Existing `research/*.md` via grep only as navigation.
- `howl-render/src/prepared/render_surface_emitter.zig`.
- `howl-render/src/render/render_surface_realizer.zig`.
- `howl-render/src/prepared/owner.zig`.
- `howl-render/src/session/text.zig`.
- `howl-render/src/test.zig` and relevant tests.
- Alacritty `renderer/text/glyph_cache.rs`, `renderer/text/atlas.rs`, `renderer/text/mod.rs`, `renderer/mod.rs`.
- Ghostty `renderer.zig`, `font/Atlas.zig`.

## Ownership Map

- `render_surface_emitter.zig` owns render-surface C span assembly and publication.
- `Emitter` stores damage/create/upload/command/glyph/retire arrays and `surface_storage`; `emitPrepared` assembles pass order and publishes only after success; `publishSurface` fixes glyph/upload pointers and C spans.
- `render_surface_emitter.zig` also owns sprite resource cache and atlas packing today, which is the ownership knot.
- `SpriteResourceStore` stores persistent resource entries, byte cache, atlas resource, atlas entries, and atlas cursor state; `resourceFor`, `atlasRegionFor`, `ensureAtlasResource`, `reserveAtlasRect`, and `nextResource` mutate resource/atlas identity.
- `TextSessionOwner` owns the long-lived prepared sprite resource store through `render_surface_sprite_resources: render_surface_emitter.SpriteResourceStore = .init()`.
- This is source-backed as session lifetime ownership for resources spanning prepared surfaces, but the store type should not live under the emitter owner.
- `prepared/owner.zig` owns prepared handle lifetime and cached render-surface payload, not resource-store identity.
- `render_surface_realizer.zig` owns software render-surface validation/realization and an oracle retained `ResourceStore`. It is not the prepared atlas/resource owner.
- Alacritty `GlyphCache` owns rasterizer/cache and delegates upload to `LoadGlyph`; `Atlas` owns atlas dimensions, row state, texture id, insert/upload, clear, and deletion; `LoaderApi` bridges renderer-owned atlas state into glyph cache loading.
- Ghostty has explicit atlas state with data/regions/format/modified counters and reservation/write/grow/clear.

## Worker-Ready Slice

Extract the prepared sprite resource store and alpha atlas packing out of `render_surface_emitter.zig`.

Allowed files:

- Add `howl-render/src/prepared/sprite_resource_store.zig`.
- Edit `howl-render/src/prepared/render_surface_emitter.zig`.
- Edit `howl-render/src/session/text.zig`.
- Move owner-local sprite resource store tests into the new owner file if needed. No new test root.

Required shape:

- New owner path: `howl-render/src/prepared/sprite_resource_store.zig`.
- New owner symbol: `pub const SpriteResourceStore`.
- Move these ownership facts from emitter into the new owner: `persistent_sprite_resources_max`, `alpha_atlas_entries_max`, `persistent_sprite_resource_bytes_max`, `glyph_atlas_width_px`, `glyph_atlas_height_px`, `PreparedSprite`, `SpriteResourceStore`, `SpriteResourceStore.Result`, `SpriteResourceStore.AtlasResult`, `resourceFor`, `atlasRegionFor`, `ensureAtlasResource`, `reserveAtlasRect`, `nextResource`, `hashSpriteBytes`, and upload format helpers needed by that owner.
- Keep `Emitter` as the surface span assembler. It may call `resources.atlasRegionFor(...)` and `resources.resourceFor(...)`.
- `Emitter` must continue to own command/create/upload/glyph/retire span storage and `publishSurface`.
- Update `TextSessionOwner.render_surface_sprite_resources` to use `sprite_resource_store.SpriteResourceStore`, not `render_surface_emitter.SpriteResourceStore`.

## Tests And Gates

- From `howl-render`: `zig build test -- "render surface surface emitter"`.
- From `howl-render`: `zig build test -- "render-surface surface realizer"`.
- From `howl-render`: `zig build test -- "render surface prepared owner"`.
- If filters are unreliable: `zig build test --summary all`.
- Grep: `render_surface_emitter.zig` must not define `pub const SpriteResourceStore`.
- Grep: `render_surface_emitter.zig` must not contain `atlas_next_x`, `atlas_next_y`, or `atlas_entries`.
- Grep: `session/text.zig` must not refer to `render_surface_emitter.SpriteResourceStore`.
- Grep: `render_surface_realizer.zig` may still define `pub const ResourceStore`.
- Grep: no new `manager`, `engine`, `controller`, `types.zig`, or umbrella runtime names.

## Non-Goals

- No C ABI/header change.
- No render-surface layout/status change.
- No host GL/backend movement.
- No `render_surface_realizer.ResourceStore` movement.
- No `TextSessionOwner` lifecycle split beyond changing the store type import.
- No generic manager/controller/resource engine.
- No changes to resource id semantics, atlas size, command ordering, upload byte ownership, or failure statuses.

## Stop Conditions

- Stop if moving the store requires changing `HowlRenderSurface` ABI or public C statuses.
- Stop if the worker needs to choose a new resource id/generation policy.
- Stop if extraction would require moving `render_surface_realizer.ResourceStore`.
- Stop if tests need a new test root rather than owner-local tests reached through `src/test.zig`.

## Not Worker-Ready Yet

- Broader `TextSessionOwner` decomposition.
- Realizer/resource validator reshaping.
