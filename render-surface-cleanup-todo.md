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
- `TextSurface` is not accepted as a replacement control-object noun if it only renames the current bucket.
- Do not choose a replacement control-object noun until enough state has moved to true owners that the remaining object has a narrow job.

## Completed Research Findings

- Alacritty does not support a broad render/text `session` owner. Its closest pressure is `Display`, but Howl hosts own display/window/presentation, so copying `Display` would violate Howl's host/render split.
- Alacritty cursor pressure is local to display/render input and rect primitive emission: `RenderableContent`, `RenderableCursor`, `display/cursor.rs`, and `DisplayUpdate.cursor_dirty`.
- Kitty cursor trail pressure supports keeping trail math explicit and render-side, not hiding it in the broad control bucket.
- Source publication and prepare scheduling are pending-update flow, not a generic owner. Alacritty's `DisplayUpdate` is a small pending record consumed by `Display.handle_update`, not a replacement for `TextSessionOwner`.
- Current prepared/submitted code already has partial true owners: `surface/handle.zig` owns prepared handle state and payload lifetime, while `submitted_surface.zig` owns submitted retained-base validation.
- Prepared/submitted research found a real missing owner for the single pending prepared candidate slot and C handle identity. That state should not move into `SubmittedSurface`, because submitted retained-base identity and pending prepared work are different lifecycle stages.
- Reference-backed candidate owner: `PendingPreparedSurface`, analogous to Alacritty's explicit pending update records, but scoped to Howl's prepared-before-submitted surface state.

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
  - Cursor fields currently embedded in the bucket: host cadence colors/opacities/shape/thickness/decay, trail rect output, trail trigger state, and `text_cursor_trail.CursorTrail`.
  - Source/prepare fields currently embedded in the bucket: `latest_source`, `latest_source_dirty_epoch`, `prepare_request`, and damage classification/request recomputation methods.
- C adapter handle lookup: `howl-render/src/c/text_session_handle.zig`
- C text-session adapter: `howl-render/src/c/text_session.zig`
- C prepare/submit/work/geometry adapters under `howl-render/src/c/`.
- Prepared handle lifecycle: `howl-render/src/surface/handle.zig`
- Submitted retained-base state: `howl-render/src/submitted_surface.zig`
- Text shaping/prep roots: `howl-render/src/text/session.zig`, `howl-render/src/text/surface_preparer.zig`.
- Prepared/submitted state still embedded in `TextSessionOwner`: `rdr_sfc_handle`, `prepared_candidate`, `prepared_handles`, candidate registration/clear/invalidation, active submit decision, and submit-pending work-state truth.

## Research Tasks Before Editing

Status:

- Cursor render ownership research: complete enough for a first extraction proposal.
- Source/prepare scheduling research: complete enough to reject a broad `DisplayUpdate`/`TextSurface` rename.
- Prepared/submitted ownership research: complete enough for a first extraction proposal using a narrow pending prepared owner.

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

## Candidate Implementation Slices

### Cursor Presentation

- Do not start a broad rename here.
- Extract cursor cadence/trail presentation state out of `TextSessionOwner` into an owner-true render-side cursor presentation object, reusing `text/cursor_trail.zig` for trail math rather than inventing a scheduler/manager/control layer.
- The slice should reduce `TextSessionOwner` fields and methods materially: host cadence storage, trail trigger state, source mutation for cursor presentation, and animation pending truth should move together or not at all.
- Keep file/folder moves out of this slice unless the user approves an exact move list first.

### Pending Prepared Surface

- Extract the pending prepared candidate slot from `TextSessionOwner` into a narrow `PendingPreparedSurface` owner.
- Move together or not at all: `rdr_sfc_handle`, `prepared_candidate`, `prepared_handles`, candidate registration/clear/invalidation, candidate submit decision checks, and submit-pending truth.
- Keep `SubmittedSurface` focused on submitted retained-base identity and validation. Do not put pending prepared candidate state there.
- Keep `PreparedHandle` focused on one handle's lifetime/payload. Do not make an individual handle own the session's pending slot.
- Keep source publication, cursor cadence, font/text preparation, and geometry out of this slice.
- `PendingPreparedSurface` must receive latest prepare-token freshness as input and return a decision. It must not own or mutate `prepare_request`.
- `TextSessionOwner` remains responsible for applying returned full-prepare decisions to `prepare_request`.
- `PreparedHandle.release`, `PreparedHandle.consume`, and detach logic must route candidate/list mutation through `PendingPreparedSurface`, not through wrapper methods that keep the extracted fields semantically owned by `TextSessionOwner`.
- The pending owner must assert candidate identity, opaque handle identity, live state, and one-shot `submit_ready` transition order.
- Required new tests: empty slot is idle, accept makes submit pending true, stale/invalid retained base clears candidate and asks for full prepare, wrong/non-live handle fails, submit-ready transition happens once, submit consume clears without double release, destroy destroys registered handles.

Stop this slice if implementation requires C ABI changes, moves files/folders without approval, moves source publication/geometry/cursor/text/font/submitted retained-base state into the pending owner, leaves `PreparedHandle` mutating extracted fields through `TextSessionOwner`, or only proves old session-level outcomes without owner-local tests.

### Verification For Any Slice

- Every slice must run at least:
  - `timeout 300s zig build test:unit` in `howl-render`
  - host build/tests if ABI or host calls change.

## Recent Commits Relevant To This Cleanup

- root `62d1bab Track runtime log and owner wording cleanup`
- `howl-linux-host` `feb51f6 Rename host pending event admission`
- `howl-render` `4030297 Make cursor cadence mutation void`
- `howl-pty` `8cbc6a6 Remove PTY start error log`

## Open Questions

- After cursor/source/prepared state is reduced, what narrow job remains for the C ABI control object?
- Does the ABI need a new handle noun at all, or should it wait until the internal bucket is decomposed enough to name honestly?
- What is the smallest decomposition slice that reduces bucket shape rather than just renaming it?
- Which file moves are worth doing in the same slice as ABI renaming, and which should wait?
