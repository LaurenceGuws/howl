# Render Prepared FFI Status Research Cache - 2026-06-02

Research cache. Research only. No product code edits.

## Sources Read

- TigerBeetle style and architecture.
- `AGENTS.md`, `loop.txt`, `reference-index.md`.
- Existing `research/*.md` via grep only as navigation.
- `howl-render/src/session/text.zig`.
- `howl-render/src/prepared/owner.zig`.
- `howl-render/src/source/text_input.zig`.
- `howl-render/src/text/scene.zig`.
- `howl-render/src/ffi/prepared_surface.zig`.
- `howl-render/src/ffi/render_surface.zig`.
- `howl-render/include/howl_render.h`.
- Relevant render tests through `howl-render/src/test.zig`.

## Current Facts

- `PreparedInfo` is stable prepared metadata only.
- ABI info no longer carries render-surface retrieval status.
- `prepared/owner.zig` still imports C ABI and stores C status directly.
- `ffi/prepared_surface.zig` is already the retrieval ABI seam and returns `HowlRenderPreparedSurfaceRenderSurfaceStatus`.
- `TextSessionOwner` still owns session, geometry, source slot, prepare/submitted owners, font paths, prepared handles, cached publish/submit handles, sprite resource store, and debug failure count.
- `source/text_input.zig` is a true VT-source-to-text-input translator with direct tests.
- `text/scene.zig` is a true scene builder/scratch owner, not the next pressure point.

## Worker-Ready Slice

Move render-surface retrieval status mapping out of `prepared/owner.zig` and into `ffi/prepared_surface.zig`.

Allowed files:

- `howl-render/src/prepared/owner.zig`
- `howl-render/src/ffi/prepared_surface.zig`
- `howl-render/src/test/ffi.zig`
- Owner-local tests in `howl-render/src/prepared/owner.zig` only as needed

Required shape:

- Remove `const c = @import("../ffi.zig").c;` from `prepared/owner.zig`.
- Replace `Owner.render_surface_status: c.HowlRenderPreparedSurfaceRenderSurfaceStatus` with owner-local failure truth representing only prepared render-surface emission consequence.
- Keep `Owner.renderSurface()` returning `?*const render_surface_emitter.Surface`.
- Add or keep a narrow owner method exposing owner-local failure truth, not C ABI status.
- Move C status mapping to `ffi/prepared_surface.zig`, because FFI translates contracts only.
- Preserve behavior of `howl_render_prepared_surface_render_surface`.

## Tests And Gates

- Existing FFI status stability test in `howl-render/src/test/ffi.zig`.
- Existing FFI retrieval failure test in `howl-render/src/test/ffi.zig`.
- Existing prepared owner emission error mapping/overflow tests must assert owner-local failure truth, not C constants.
- Full render test entrypoint remains `howl-render/src/test.zig`.

## Non-Goals

- Do not split `TextSessionOwner` yet.
- Do not move `SpriteResourceStore` yet.
- Do not change `howl_render.h`.
- Do not change source text translation or scene building.

## Missing Facts Before Bigger Split

- Whether session-wide `SpriteResourceStore` should remain session-scoped because prepared surfaces reuse resource IDs across handles, or move behind a prepared render-surface resource owner.
- Whether font path lifetime should become a separate owner.
- Whether cached publish/submit prepared handles should become a session-local prepared-handle owner.
