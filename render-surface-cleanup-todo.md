# Render Surface Cleanup Todo

Purpose:

- Keep the render `owner` / `session` cleanup grounded across handoffs and context compaction.
- Record constraints, source pressure, current facts, and next slices before touching ABI or file names.
- Avoid fake cleanup by renaming buckets without removing the bucket shape.

## Non-Negotiables

- No compatibility aliases or migration shims.
- No stale `TextSession*` names if `session` is not source-backed for render/text ownership.
- No preserving ABI names for temporary compatibility. Howl is private and the ABI should be honest.
- No file or folder moves without explicit user approval for the concrete move list.
- Do not start implementation until the reference/current-code map proves the target names and slice order.

## Current Decision State

- `TextSessionOwner` is not defended by Alacritty.
- `session` is not source-backed as a render/text API noun in Alacritty, Kitty, or Ghostty from the initial scan.
- Howl already exports a prepared render command surface through `HowlRenderSurface` and `HowlRenderRdrSfcHandle`.
- A replacement for `TextSessionOwner` must not collide with the existing prepared/output render surface noun.
- Candidate control object noun to prove or reject: `TextSurface` / `HowlRenderTextSurfaceHandle`.

## Reference Anchors To Re-Read

Alacritty:

- `utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
  - `Display` owns window-facing render state, `Renderer`, GL surface, glyph cache, damage, pending display update, frame timer, and draw/present flow.
- `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
  - `RenderableContent`, `RenderableCell`, `RenderableCursor` shape the terminal content draw input.
- `utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
  - `Renderer` owns backend draw primitives, text renderer provider, rect renderer, and resize/draw calls.
- `utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs`
  - damage tracking is display-side state.
- `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
  - event/window context owns dirty/update handoff into `Display`.

Ghostty:

- `utils/dev_references/terminals/ghostty/src/Surface.zig`
- `utils/dev_references/terminals/ghostty/src/renderer.zig`
- `utils/dev_references/terminals/ghostty/src/termio/Termio.zig`
  - surface and renderer state/mailbox naming pressure; termio is renderer-agnostic and not a render session model.

Kitty:

- `utils/dev_references/terminals/kitty/kitty/cursor_trail.c`
- `utils/dev_references/terminals/kitty/kitty/child-monitor.c`
- Kitty `Session` hits are startup/app lifecycle pressure, not render text API pressure. Verify before relying on this.

## Current Howl Anchors

- ABI header: `howl-render/include/howl_render.h`
  - Current stale names: `HowlRenderTextSession`, `HowlRenderTextSessionHandle`, `howl_render_text_session_*`, `HowlRenderSessionWorkState`.
  - Existing output surface names: `HowlRenderSurface`, `HowlRenderSurfaceToken`, `HowlRenderSurfaceCommand`, `HowlRenderRdrSfcHandle`.
- Bucket candidate: `howl-render/src/render_session.zig`
  - Current stale type: `TextSessionOwner`.
  - Responsibilities currently include source publication, geometry, prepare request, prepared handles, submitted state, cursor cadence/trail, font config, text shaping session, and sprite resources.
- C adapter handle lookup: `howl-render/src/c/text_session_handle.zig`
- C text-session adapter: `howl-render/src/c/text_session.zig`
- C prepare/submit/work/geometry adapters under `howl-render/src/c/`.
- Prepared handle lifecycle: `howl-render/src/surface/handle.zig`
- Submitted retained-base state: `howl-render/src/submitted_surface.zig`
- Text shaping/prep roots: `howl-render/src/text/session.zig`, `howl-render/src/text/surface_preparer.zig`.

## Research Tasks Before Editing

1. Alacritty render split map.
   - Map `Display`, `Renderer`, `RenderableContent`, `GlyphCache`, `DamageTracker`, `DisplayUpdate`, and frame/present flow.
   - Return exact source lines and Howl responsibility equivalents.
   - Identify names Howl should not copy because its C ABI/surface split differs.

2. Ghostty surface/render map.
   - Verify how Ghostty uses `Surface`, `renderer.State`, renderer mailbox/wakeup, and termio boundaries.
   - Decide whether `TextSurface` is consistent with Howl's VT/render surface split.

3. Current `TextSessionOwner` inventory.
   - Inventory every field and method in `howl-render/src/render_session.zig`.
   - Classify each into true owner/stage:
     - source publication
     - geometry
     - text shaping/raster/cache
     - prepared surface handles
     - submitted surface
     - cursor visual state
     - sprite resources
     - C ABI translation/control object
   - Identify which pieces already have true owner files.

4. ABI rename plan.
   - Replace `HowlRenderTextSession*` with the chosen noun if source-backed.
   - No compatibility aliases.
   - Include host caller updates and tests.
   - Include `HowlRenderSessionWorkState` rename if `session` dies there too.

5. File/folder move proposal.
   - Produce an explicit list for user approval before moving files.
   - Candidate moves to evaluate, not yet approved:
     - `src/render_session.zig` -> a source-backed control object file name.
     - `src/c/text_session_handle.zig` -> matching handle lookup file name.
     - `src/c/text_session.zig` -> matching C adapter file name.

## Likely First Implementation Slice

- Do not start here until research is complete.
- Preferred first slice should remove the most misleading public/internal names without splitting behavior yet only if the target noun is proved.
- If `TextSessionOwner` is confirmed as a bucket, first slice may instead move one responsibility to an existing true owner before a broad rename.
- Every slice must run at least:
  - `timeout 300s zig build test:unit` in `howl-render`
  - host build/tests if ABI or host calls change.

## Recent Commits Relevant To This Cleanup

- root `62d1bab Track runtime log and owner wording cleanup`
- `howl-linux-host` `feb51f6 Rename host pending event admission`
- `howl-render` `4030297 Make cursor cadence mutation void`
- `howl-pty` `8cbc6a6 Remove PTY start error log`

## Open Questions

- Is the control object best named `TextSurface`, `TerminalSurface`, or another source-backed noun?
- Does the ABI need `HowlRenderTextSurfaceHandle`, or should it be named around `Display`/`RenderableContent` adapted to Howl vocabulary?
- What is the smallest decomposition slice that reduces bucket shape rather than just renaming it?
- Which file moves are worth doing in the same slice as ABI renaming, and which should wait?
