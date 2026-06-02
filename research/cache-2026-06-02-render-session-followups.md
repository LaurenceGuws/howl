# Render Session Followups Research Cache - 2026-06-02

Research cache. Research only. No product code edits.

## Key Gating Fact

Follow-ups after sprite store extraction should be gated on moving that store first. At research time, `SpriteResourceStore` still lived in `render_surface_emitter.zig` and `TextSessionOwner` still stored `render_surface_emitter.SpriteResourceStore`.

## Owner Map

- `TextSessionOwner` is currently an over-bundled session orchestrator: owns `TextSession`, geometry, source slot, prepare requests, submitted state, prepared handle caches, font path storage, sprite resources, and debug failure count.
- `TextSession` owns text shaping/raster preparation state, cell input scratch, font provider context, and submit marking.
- `SourceSlot` is already a true owner for retained VT publication slot storage and reservation/commit lifecycle.
- Prepared handle lifetime is split awkwardly: `Owner` owns one prepared surface and payload lifecycle, while session caches all handles and publish/submit handles.
- FFI correctly maps prepared render-surface status at `ffi/prepared_surface.zig` after the prepared FFI status boundary slice.
- Font path ownership is currently in `TextSessionOwner`, while `TextSessionConfig` and `text_support.State` borrow path slices.
- Software realizer is a validation/oracle/reference consumer for the C render-surface contract. It owns retained validation `ResourceStore`, transition validation, and pixel realization.

## Reference Pressure

- Alacritty keeps long-lived glyph/font cache and renderer atlas ownership in display/renderer, not transient draw content.
- Alacritty prepares renderable content before drawing and owns font/renderer updates centrally in `Display`.
- Ghostty backs explicit atlas ownership with `Atlas` owning data/format/nodes/modified/resized and reserve/set/grow/clear tests.
- Ghostty renderer root separates generic renderer/backend/thread/state exports from terminal state.

## Likely Next Slices

1. Finish sprite store extraction first.
   - Move `SpriteResourceStore`, `PreparedSprite`, atlas constants/state, resource ID allocation, hash/upload-format helpers into `howl-render/src/prepared/sprite_resource_store.zig`.
   - Keep `Emitter` as surface span assembler only.
2. Extract prepared handle/session cache ownership.
   - Candidate owner: `howl-render/src/session/prepared_handles.zig` with `PreparedHandles`.
   - Move `prepared_publish_handle`, `prepared_submit_handle`, `prepared_handles`, `registerPreparedHandle`, `clearCachedPreparedHandle`, destruction loop, and handle publish/submit cache mutation out of `TextSessionOwner`.
   - Keep `prepared/owner.zig` owning one prepared payload and state machine.
   - Keep FFI translation in FFI owners.
3. Extract font path ownership.
   - Candidate owner: `howl-render/src/text/font/paths.zig` with a true path owner, not generic config.
   - Move primary/fallback owned path allocation/free/adoption/sync into that owner.
   - Preserve `TextSessionConfig.font_path` as borrowed session config input until text/font state is sharpened.
4. Leave `SourceSlot` mostly alone.
5. Keep software realizer as ABI contract oracle, not host backend.

## Missing Facts

- Whether resource acknowledgements are intended for a future host feedback ABI or dead contract surface.
- Whether `resource_epoch` should remain zero or become session/resource-store epoch.
- Whether prepared handle cache should destroy all live handles on session destroy without unregistering from a dedicated owner first.
- Whether font path invalidation should also resize loaded faces or always fully reset FreeType/HarfBuzz.

## Tests And Gates

- `zig build test -- "render surface surface emitter"`.
- `zig build test -- "render-surface surface realizer"`.
- `zig build test -- "render surface prepared owner"`.
- `zig build test -- "prepared handle"` or full `zig build test --summary all` if filters are unreliable.
- Grep gates: no `SpriteResourceStore` definition in `render_surface_emitter.zig`; no `render_surface_emitter.SpriteResourceStore` in `session/text.zig`; no new `manager`, `engine`, `controller`, `types.zig`, or umbrella runtime names.

## Risks

- Splitting `TextSessionOwner` before sprite store extraction will mix two ownership cuts and hide failures.
- Prepared handle extraction can accidentally move ABI translation into owner code.
- Font path extraction can create dangling borrowed slices if owner/config/text_state synchronization is not asserted.
- Realizer reshaping can accidentally turn software validation into renderer architecture; hosts still own backend resource realization.
