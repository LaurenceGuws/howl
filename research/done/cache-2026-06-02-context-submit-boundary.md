# Context Submit Boundary Research Cache - 2026-06-02

Research cache. Research only. No product code edits.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `reference-index.md`
- Existing `research/*.md` via grep only as navigation.
- Current Howl files: `howl-linux-host/src/terminal/context.zig`, `howl-linux-host/src/display/renderer/render_surface.zig`, `howl-linux-host/src/display/renderer/render_surface_contract.zig`, `howl-linux-host/src/terminal/render/retained.zig`, `howl-linux-host/build.zig`.
- Alacritty display/renderer references under `utils/dev_references/terminals/alacritty/alacritty/src/display` and `utils/dev_references/terminals/alacritty/alacritty/src/renderer`.

## Current Facts

- `Context` owns the host render turn and submit transaction: `renderTurn`, `driveRenderLocked`, and `submitPreparedLockedWith` centralize present blocking, submit pending, prepare/submit, terminal lock release during backend upload, relock, prepared-handle stability, and submit result handling.
- `ContextSubmitBackend` still owns too much display-renderer policy: resource realization calls, host surface ensure, render-surface shape dispatch, patch/full upload policy, unsupported-shape panic, retrieval-status mapping, and submit execution construction.
- `display/renderer/render_surface.zig` owns `RenderResourceTextures`, GL texture state, GL realization, rollback, host surface texture, upload/draw functions, and shape classifiers.
- `display/renderer/render_surface_contract.zig` now owns host-side C ABI render-surface validation with `RenderSurfaceContractStatus`, `RenderSurfaceContract`, and `validate`.
- `terminal/render/retained.zig` now carries `PreparedUpload.render_surface_contract` and no longer owns the old validation/status/resource-store mirrors.
- Context submit transaction tests already prove lock/unlock/relock, upload-failure no-submit, and handle mutation no-submit behavior.

## Reference Facts

- Alacritty `Display` owns window/surface/context/renderer/glyph cache and draw-turn sequencing.
- Alacritty `Display.draw` collects renderable state, drops terminal lock early, makes the GL context current, then calls renderer methods.
- Alacritty renderer owns concrete draw calls and batching behind renderer API methods.
- TigerBeetle pressure rejects hidden broad status/validation spread and favors owner-true boundaries with direct call paths and assertions.

## Worker-Ready Slice

Move render-surface upload classification and patch/full upload policy out of `ContextSubmitBackend` and into `display/renderer/render_surface.zig`.

Allowed files:

- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/display/renderer/render_surface.zig`

Do not edit:

- `howl-linux-host/src/display/renderer/render_surface_contract.zig`
- `howl-linux-host/src/terminal/render/retained.zig`
- build files or test roots
- public C ABI headers

## Owner Boundary

Remain in `terminal/context.zig`:

- Host turn sequencing: `renderTurn`, `driveRenderLocked`, `renderAction`.
- Submit transaction and lock policy: `submitPreparedLockedWith`.
- Prepared-handle stability checks and submit failure mapping.
- Retrieval-status panic mapping for `prepared_upload.render_surface == null`.
- `ContextSubmitBackend.execution`.
- Context-owned host surface field assignment after successful submit.

Move/stay in `display/renderer/render_surface.zig`:

- Shape dispatch currently in `ContextSubmitBackend.uploadRenderSurfaceCommands`.
- Patch/full upload policy currently in `ContextSubmitBackend.renderSurfaceUploadPolicy`.
- `RenderSurfaceUploadPolicyError`.
- `crashOnRenderSurfaceUploadPolicyError`.
- `panicUnsupportedTrustedRenderSurfaceShape`.
- New public display-renderer entrypoint: `pub fn uploadRenderSurface(textures: *RenderResourceTextures, host_surface: *render_c.HowlRenderHostSurface, surface: *const render_c.HowlRenderSurface) bool`.

`uploadRenderSurface` should compute matching-host-surface policy from `host_surface` and `surface.render_px`, call `textures.realizeSurface(surface)`, call `ensureSurface(host_surface, surface.render_px.width, surface.render_px.height)`, dispatch to existing upload functions, and zero `host_surface.width/height` on failure to preserve current context behavior.

Context after the slice:

- `ContextSubmitBackend.upload` handles null render surface retrieval status.
- Non-null render surface delegates to `term_texture.uploadRenderSurface(&self.render_surface_textures, &self.term_texture, surface)`.
- Delete context-local upload dispatch/policy helpers.

## Required Tests

- Move `render surface upload policy rejects patches without matching host surface` from `context.zig` to `render_surface.zig`, retargeting to the display renderer policy.
- Keep context retrieval-status tests in `context.zig`.
- Keep submit transaction, resize submit, and failure tests in `context.zig`.
- Add or preserve display renderer tests proving full surfaces do not require a matching host surface and patch surfaces do require one.
- Do not add test roots.

## Grep Gates

- `ContextSubmitBackend.uploadRenderSurfaceCommands` has zero matches.
- `ContextSubmitBackend.renderSurfaceUploadPolicy` has zero matches.
- `TrustedPatchRequiresMatchingHostSurface` exists only in `display/renderer/render_surface.zig`.
- `renderSurfaceUploadPolicy` exists only in `display/renderer/render_surface.zig`.
- `panicUnsupportedTrustedRenderSurfaceShape` exists only in `display/renderer/render_surface.zig`.
- `ContextSubmitBackend.shouldRealizeRenderSurface` has zero matches if removed.

## Non-Goals

- No ABI changes.
- No build/test root changes.
- No `render_surface_contract.zig` changes.
- No retained-render redesign.
- No moving context turn/submit transaction out of `context.zig`.
- No changing lock/unlock behavior around backend upload.
- No changing GL texture ownership or `RenderResourceTextures` lifecycle.
- No new manager/controller/options/types bucket.

## Stop Conditions

- Public ABI change appears.
- Build/test root change is needed.
- Context submit transaction tests fail because lock timing changed.
- Worker needs to choose new owner names beyond `uploadRenderSurface` and moved existing names.
- Move requires changing `render_surface_contract.zig` semantics.

## Verification

From `howl-linux-host`:

- `zig build test:unit --summary all`
- `zig build check`

After reviewer acceptance or before commit, run full host gates from promoted `current.txt`.

## Readiness Judgment

Worker-ready after reviewer acceptance. The slice has exact files, exact symbols, owner boundary, tests, grep gates, non-goals, and stop conditions.
