# Render Surface Owner Rename Sprint

Owner: workspace root.

Status: scratchpad draft. No product code is authorized until a reviewer accepts
this scratchpad and exactly one slice is promoted to `current.txt`.

Accepted research cache:

- `research/cache-2026-06-01-render-real-owner-names.md`

Rejected/incomplete inventory cache:

- `research/cache-2026-06-01-render-protocol-symbol-deletion.md`

## Purpose

Replace the made-up `protocol_v0` / product-phase `V0` / render-side `frame`
layer with real owner vocabulary.

This is a broad no-alias product rename. The public C ABI, FFI translation,
render owners, docs, render tests, and host consumers must move together because
the fake layer crosses the ABI boundary.

## Project Law

- `protocol` is banned from Howl render symbols.
- Product-phase `V0` vocabulary is banned.
- Render-side `frame` vocabulary is banned.
- VT owns `vt-surface`.
- Render owns `render-surface`.
- `render-surface` is the object crossing into backend presentation.
- Host wake and backend presentation are different owners and different cadences.
- Host wake/scheduling may use `frame` where it means SDL/event-loop frame
  scheduling.
- Presentation/backend/GL paths must not use `frame` for render-surface,
  texture upload, backend realization, or present paths.
- No compatibility aliases, typedefs, wrapper exports, macro aliases, or old-name
  shims.
- The repository has no downstream; downstream compatibility is not a reason to
  preserve rejected vocabulary.
- Render tests have one entrypoint: `howl-render/src/test.zig`.
- Duplicate test roots such as `src/test_abi.zig`, `src/test_unit.zig`, or
  equivalent wrapper roots are banned.

## Reference Decisions

- Ghostty supports `renderer`, `surface`, `Atlas`, `Region`, `TextRun`,
  `RunIterator`, and `Sprite` as concrete owner nouns.
- Alacritty supports `Display`, `RenderableContent`, `RenderableCell`,
  `DamageTracker`, `Renderer`, `TextRenderer`, `Atlas`, `GlyphCache`,
  `WindowContext`, `RendererUpdate`, texture/upload/resource vocabulary, and
  separate scheduling/presentation boundaries.
- Alacritty `request_frame`, `FrameTimer`, `Topic::Frame`, and
  `EventType::Frame` are host wake/scheduling facts only. They do not authorize
  render ABI/source/presentation/backend `frame` names.

## Required Names

Public C ABI:

- `HOWL_RENDER_PROTOCOL_V0_VERSION` -> `HOWL_RENDER_SURFACE_VERSION`
- `HOWL_RENDER_V0_*_MAX` -> `HOWL_RENDER_SURFACE_*_MAX`
- `HOWL_RENDER_V0_DAMAGE_*` -> `HOWL_RENDER_SURFACE_DAMAGE_*`
- `HOWL_RENDER_V0_RESOURCE_*` -> `HOWL_RENDER_RESOURCE_*`
- `HOWL_RENDER_V0_UPLOAD_*` -> `HOWL_RENDER_UPLOAD_*`
- `HOWL_RENDER_V0_COMMAND_*` -> `HOWL_RENDER_SURFACE_COMMAND_*`
- `HowlRenderV0Token` -> `HowlRenderSurfaceToken`
- `frame_seq` -> `surface_seq`
- `HowlRenderV0Rect` -> `HowlRenderSurfaceRect`
- `HowlRenderV0DamageItem` -> `HowlRenderSurfaceDamageItem`
- `HowlRenderV0DamageSpan` -> `HowlRenderSurfaceDamageSpan`
- `HowlRenderV0ResourceId` -> `HowlRenderResourceId`
- `HowlRenderV0Upload` -> `HowlRenderResourceUpload`
- `HowlRenderV0UploadSpan` -> `HowlRenderResourceUploadSpan`
- `HowlRenderV0Create` -> `HowlRenderResourceCreate`
- `HowlRenderV0CreateSpan` -> `HowlRenderResourceCreateSpan`
- `HowlRenderV0GlyphRef` -> `HowlRenderGlyphRef`
- `HowlRenderV0GlyphRunSpan` -> `HowlRenderGlyphRunSpan`
- `HowlRenderV0Command` -> `HowlRenderSurfaceCommand`
- `HowlRenderV0CommandSpan` -> `HowlRenderSurfaceCommandSpan`
- `HowlRenderV0Retire` -> `HowlRenderResourceRetire`
- `HowlRenderV0RetireSpan` -> `HowlRenderResourceRetireSpan`
- `HowlRenderV0HostAck` -> `HowlRenderResourceAck`
- `HowlRenderV0HostAckSpan` -> `HowlRenderResourceAckSpan`
- `HowlRenderV0Frame` -> `HowlRenderSurface`
- `protocol_version` -> `surface_version`
- `howl_render_prepared_surface_protocol_v0` ->
  `howl_render_prepared_surface_render_surface`
- `protocol_v0_emit_status` -> `render_surface_emit_status`

Render source and FFI:

- `src/ffi/protocol_v0.zig` -> `src/ffi/render_surface.zig`
- `src/prepared/v0_frame_emitter.zig` ->
  `src/prepared/render_surface_emitter.zig`
- `src/render/v0_frame_realizer.zig` ->
  `src/render/render_surface_realizer.zig`
- `src/test/unit/render_api_v0_oracle.zig` ->
  `src/test/unit/render_surface_oracle.zig`
- `V0Payload` -> `RenderSurfacePayload`
- `v0_payload` -> `render_surface_payload`
- `protocolV0Frame()` -> `renderSurface()`
- `protocolV0FrameForTest()` -> `renderSurfaceForTest()`
- `protocolV0FrameStorageEmptyForTest()` ->
  `renderSurfaceStorageEmptyForTest()`
- `protocolV0EmitStatus()` -> `renderSurfaceEmitStatus()`
- `protocol_v0_emit` / `protocol_emit` -> `render_surface_emitter`
- `protocol_realize` -> `render_surface_realizer`
- `protocol_v0_sprite_resources` -> `render_surface_sprite_resources`

Host consumers:

- `PreparedProtocolV0ResourcePlan` -> `PreparedRenderResourcePlan`
- `ProtocolV0ResourceStore` -> `RenderResourceStore`
- `ProtocolV0BackendOperation` -> `TextureResourceOperation`
- `ProtocolV0Textures` -> `RenderResourceTextures`
- `realizeFrame(frame)` -> `realizeSurface(surface)`
- `protocol_v0_frame` -> `render_surface`
- `protocol_v0_probe` -> `render_surface_probe`
- `protocol_v0_resource_plan` -> `render_surface_resource_plan`
- `protocolV0SpriteFrame` -> `renderSurfaceSprite`
- `protocolV0GlyphFrame` -> `renderSurfaceGlyphs`
- `protocolV0FillOnly` -> `renderSurfaceFillOnly`
- render-object shape counters `v0_*_frame_count` ->
  `render_surface_*_count`
- Existing `present_*`, `PresentInFlight`, and actual presentation outcome counts
  remain presentation vocabulary.
- Host wake/scheduling `frame` vocabulary may remain only where it refers to
  SDL/event-loop frame scheduling, not render-surface or backend presentation.

## Worker Slice 1: Broad No-Alias Rename

This sprint intentionally has one broad implementation slice. Splitting the ABI,
FFI, render owners, docs, and host consumers would preserve banned public names
or require aliases. Both are forbidden.

Allowed files:

- `howl-render/include/howl_render.h`
- `howl-render/src/ffi/protocol_v0.zig`
- `howl-render/src/ffi/render_surface.zig`
- `howl-render/src/libhowl_render.zig`
- `howl-render/src/ffi/prepared_surface.zig`
- `howl-render/src/prepared/owner.zig`
- `howl-render/src/session/text.zig`
- `howl-render/src/prepared/v0_frame_emitter.zig`
- `howl-render/src/prepared/render_surface_emitter.zig`
- `howl-render/src/render/v0_frame_realizer.zig`
- `howl-render/src/render/render_surface_realizer.zig`
- `howl-render/src/test/unit/root.zig`
- `howl-render/src/test/unit/render_api_v0_oracle.zig`
- `howl-render/src/test/unit/render_surface_oracle.zig`
- `howl-render/src/test/ffi.zig`
- `howl-render/src/test.zig`
- `howl-render/build.zig`
- `docs/render-api-v0.md`
- `docs/render-surface.md`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/window/term_texture.zig`

Required shape:

- Delete old fake names; do not leave re-export files, macro aliases, typedef
  aliases, wrapper functions, or compatibility names.
- Rename the public C ABI symbols and all render FFI/layout assertions together.
- Preserve ABI layout, sizes, alignments, offsets, constant values, and enum/kind
  numeric values unless a test proves an intentional equivalent rename.
- Rename docs from product-phase vocabulary to render-surface vocabulary.
- Route all render test build steps through single root `src/test.zig`.
- Do not restore `src/test_abi.zig` or `src/test_unit.zig`.
- Do not create equivalent duplicate test roots under other names.
- Preserve all ABI/layout/unit/oracle tests through the single entrypoint.
- Keep host wake/scheduling `frame` vocabulary only where it means SDL/event-loop
  frame scheduling.
- Remove `frame` from render-surface, presentation/backend, texture upload,
  resource realization, docs, and render tests.

Non-goals:

- No runtime behavior changes.
- No host wake policy changes.
- No backend presentation cadence changes.
- No compatibility layer.
- No unrelated VT/PTTY/input changes.
- No broad formatting-only churn.
- No changes to vendored/reference sources.

Stop conditions:

- Stop if any old public ABI symbol must be kept as an alias.
- Stop if any worker wants to restore duplicate test entrypoints.
- Stop if any render test build step needs a root source file other than
  `src/test.zig`.
- Stop if layout assertions are removed or weakened instead of renamed.
- Stop if a host behavior change is needed beyond symbol/name updates.
- Stop if backend presentation and host wake are collapsed into one owner or
  cadence.
- Stop if presentation/backend code uses `frame` for render-surface, texture
  upload, backend realization, or present paths.
- Stop if the final grep gates require editing historical `research/` files.

Required verification:

From `howl-render`:

- `zig build test`
- `zig build test:unit`
- `zig build test:abi`
- `zig build test:build`
- `zig build check`
- `git diff --check`

From `howl-linux-host`:

- `zig build test --summary all`
- `zig build -Doptimize=ReleaseFast`
- `git diff --check`

From workspace root:

- `zig build check`
- `zig build test`
- `git diff --check`

Required grep gates from workspace root:

- `rg -n "protocol_v0|ProtocolV0|PROTOCOL_V0" howl-render howl-linux-host docs build.zig build.zig.zon`
  prints nothing.
- `rg -n "protocol" howl-render/include howl-render/src howl-linux-host/src docs --glob '!docs/**/official*'`
  prints nothing.
- `rg -n "RenderV0|RENDER_V0|render-api-v0|Render API V0|\bV0\b" howl-render howl-linux-host docs build.zig build.zig.zon`
  prints nothing.
- `rg -n "HowlRenderV0|HOWL_RENDER_V0|HOWL_RENDER_PROTOCOL" howl-render/include howl-render/src howl-linux-host/src docs`
  prints nothing.
- `rg -n "\bframe\b|\bFrame\b|FRAME" howl-render/include howl-render/src docs howl-linux-host/src/terminal/render howl-linux-host/src/window/term_texture.zig`
  prints nothing.
- `rg -n "prepared_surface_protocol|protocolV0|protocol_v0_emit_status|v0_payload|V0Payload|v0_frame" howl-render howl-linux-host docs`
  prints nothing.
- `rg -n "test_abi|test_unit|src/test_abi\.zig|src/test_unit\.zig" howl-render`
  prints nothing.
- `rg -n "root_source_file = b\.path\(\"src/test\.zig\"\)" howl-render/build.zig`
  prints the single render test root usage.
- `rg -n "HowlRenderSurface|HOWL_RENDER_SURFACE|render_surface|RenderSurface|surface_seq|howl_render_prepared_surface_render_surface" howl-render howl-linux-host docs`
  prints expected new render-surface names.
- `rg -n "HowlRenderResource|HOWL_RENDER_RESOURCE|RenderResource|TextureResource|uploadTextureRect|retireTexture" howl-render howl-linux-host docs`
  prints expected resource/texture names.

Allowed grep exception:

- `frame` may remain only in host wake/scheduling paths that are not included in
  the render/presentation/backend frame-ban gate. If implementation touches a
  `frame` occurrence in `howl-linux-host/src/terminal/context.zig`, it must prove
  the occurrence is SDL/event-loop wake scheduling and not render-surface,
  presentation, backend realization, texture upload, or resources.

## Completion Criteria

- No fake `protocol_v0` / product-phase `V0` / render-side `frame` vocabulary in
  product render/host/docs paths.
- Public C ABI uses render-surface/resource/glyph vocabulary.
- FFI layout assertions prove the renamed C ABI shape.
- Host consumers build against renamed C ABI without compatibility aliases.
- Render tests use one entrypoint and no duplicate wrapper roots.
- Scratchpad is closed with accepted commit hashes and verification output.
