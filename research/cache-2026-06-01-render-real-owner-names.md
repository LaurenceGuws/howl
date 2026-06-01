# Render Real Owner Names Research Cache

Date: 2026-06-01.
Role: Research Agent only.
Scope: naming/ownership evidence for deleting made-up render `protocol_v0`, render `protocol`, render-side `frame`, and product-phase `V0` vocabulary from Howl render ABI/source/docs/host consumers.

## Sources Read In Order

1. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
2. `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
3. `/home/home/personal/projects/howl/AGENTS.md`
4. `/home/home/personal/projects/howl/loop.txt`
5. `/home/home/personal/projects/howl/reference-index.md`
6. `/home/home/personal/projects/howl/current.txt`
7. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/renderer.zig`
8. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/Atlas.zig`
9. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/shaper/run.zig`
10. `/home/home/personal/projects/howl/utils/dev_references/terminals/ghostty/src/font/sprite/draw/special.zig`
11. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/mod.rs`
12. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs`
13. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/display/damage.rs`
14. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/mod.rs`
15. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs`
16. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/atlas.rs`
17. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/glyph_cache.rs`
18. `/home/home/personal/projects/howl/utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs`
19. `/home/home/personal/projects/howl/howl-render/include/howl_render.h`
20. `/home/home/personal/projects/howl/howl-render/src/prepared/v0_frame_emitter.zig`
21. `/home/home/personal/projects/howl/howl-render/src/render/v0_frame_realizer.zig`
22. `/home/home/personal/projects/howl/howl-render/src/prepared/owner.zig`
23. `/home/home/personal/projects/howl/howl-render/src/ffi/protocol_v0.zig`
24. `/home/home/personal/projects/howl/howl-render/src/ffi/prepared_surface.zig`
25. `/home/home/personal/projects/howl/howl-render/src/libhowl_render.zig`
26. `/home/home/personal/projects/howl/docs/render-api-v0.md`
27. `/home/home/personal/projects/howl/howl-linux-host/src/terminal/render/retained.zig`
28. `/home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig`
29. `/home/home/personal/projects/howl/howl-linux-host/src/window/term_texture.zig`
30. `/home/home/personal/projects/howl/howl-render/build.zig`
31. `/home/home/personal/projects/howl/howl-render/src/test.zig`
32. `/home/home/personal/projects/howl/howl-render/src/test/unit/root.zig`
33. `/home/home/personal/projects/howl/howl-render/src/test/ffi.zig`

## Project Law Anchors

- TigerBeetle naming law says to get nouns and verbs exactly right because names capture domain mental models, and to avoid overloaded names (`TIGER_STYLE.md:271-347`). This directly rejects `protocol_v0` as a fake bucket hiding multiple owners.
- TigerBeetle requires explicit limits and bounded work (`TIGER_STYLE.md:96-100`) and assertions for preconditions/invariants (`TIGER_STYLE.md:104-140`). The rename must preserve the existing explicit public bounds and layout assertions while changing their vocabulary.
- TigerBeetle architecture emphasizes owner-held contexts for concurrency and bounded in-flight work (`ARCHITECTURE.md:480-487`). Host wake, presentation, backend realization, and render-surface ownership are separate boundaries.
- Howl law says the ABIs are the product and hosts embed `howl-render` contracts (`AGENTS.md:7-15`). ABI names are therefore product names, not cosmetic cleanup.
- Howl ownership law says `howl-render` owns render contracts, geometry policy, retained-frame state, prepare/submit scheduling, render-surface contracts, and text shaping; hosts own wake policy and presentation cadence (`AGENTS.md:95-103`). Under the user law, the render-facing object name for backend-independent render integration is `render-surface`.
- User law for this research: VT owns `vt-surface`; render owns `render-surface`; host wake is event-loop, scheduling, wakeup, work, dirty, and request policy; presentation is where a `render-surface` is realized and presented through GL or another backend; backend/GL presentation is not the same cadence as host wake.
- Howl source order is Ghostty first, Alacritty second, TigerBeetle third, then official docs, then smallest Howl invention (`AGENTS.md:128-149`, `loop.txt:11-19`, `reference-index.md:7-16`).
- Current state explicitly says no active implementation slice exists and fresh research is required for full banned `protocol` symbol deletion across render ABI, FFI, docs, tests, and host consumers (`current.txt:1-3`, `current.txt:23-33`).

## Reference Findings

### Ghostty Nouns

- Ghostty root noun is `Renderer`; it is responsible for turning internal screen state into output, usually for a screen (`ghostty/src/renderer.zig:1-3`).
- Ghostty says renderers assume backend setup has already happened: OpenGL has a context, Vulkan has a surface, etc. (`ghostty/src/renderer.zig:5-8`). This supports keeping backend realization outside Howl render ABI and naming Howl's backend-independent render object `render-surface`, not GL/texture/frame/protocol.
- Ghostty exposes `Backend`, `GenericRenderer`, `OpenGL`, `Metal`, `WebGL`, `Thread`, `State`, `Size`, `Coordinate`, `CellSize`, `ScreenSize`, `GridSize`, and `Padding` from the renderer root (`ghostty/src/renderer.zig:16-31`). It exposes no `protocol_v0` product-phase bucket noun for render output.
- Ghostty atlas noun is `Atlas`; it is a texture atlas, with `data`, `size`, `nodes`, `format`, `modified`, and `resized` fields (`ghostty/src/font/Atlas.zig:1-16`, `ghostty/src/font/Atlas.zig:27-52`). `Region` is the noun for a reserved rectangle inside the atlas (`ghostty/src/font/Atlas.zig:81-88`).
- Ghostty shaping noun is `TextRun`, and iteration noun is `RunIterator`; a text run is row-local and valid only for one shaper instance (`ghostty/src/font/shaper/run.zig:10-13`, `ghostty/src/font/shaper/run.zig:41-47`). This backs `glyph_run` as real render vocabulary, not `frame`.
- Ghostty special glyph/sprite noun is `Sprite`; special draw functions are named to exactly match enum fields in `Sprite` (`ghostty/src/font/sprite/draw/special.zig:1-7`). This supports `sprite`, `draw_sprite`, and `sprite_resource` vocabulary.

### Alacritty Nouns

- Alacritty display subsystem includes window management, font rasterization, and GPU drawing (`alacritty/src/display/mod.rs:1-2`). Its owner noun is `Display` (`alacritty/src/display/mod.rs:341-342`).
- Alacritty `Display` owns `Window`, `SizeInfo`, `FrameTimer`, `DamageTracker`, `Renderer`, GL `surface`, GL `context`, and `GlyphCache` (`alacritty/src/display/mod.rs:341-399`). This cleanly separates display/window/presentation from renderer/text/cache nouns.
- Alacritty creates a GL surface, makes a context current, creates `Renderer`, fills `GlyphCache`, resizes renderer, clears, and swaps buffers during display init (`alacritty/src/display/mod.rs:428-483`). The backend resource/presentation nouns live under display/window, not inside terminal content nouns.
- Alacritty pending renderer changes are `RendererUpdate`; they are cached and applied just before rendering to avoid platform issues (`alacritty/src/display/mod.rs:647-650`, `alacritty/src/display/mod.rs:739-768`, `alacritty/src/display/mod.rs:1543-1554`). This supports Howl render owning prepared `render-surface` consequences, while host decides when to apply backend operations.
- Alacritty display/presentation paths use `swap_buffers` and `pre_present_notify` (`alacritty/src/display/mod.rs:607-623`, `alacritty/src/display/mod.rs:1019-1047`). Alacritty scheduling paths use `request_frame`, `FrameTimer`, `Topic::Frame`, and `EventType::Frame` (`alacritty/src/display/mod.rs:1434-1458`, `alacritty/src/display/mod.rs:1556-1601`). These reference names support `frame` only for host wake/scheduling. They do not authorize `frame` for render-surface, backend realization, texture upload, or presentation.
- Alacritty content preparation noun is `RenderableContent`; it provides a terminal cursor and iterator over non-empty cells (`alacritty/src/display/content.rs:24-38`). Cell output noun is `RenderableCell` (`alacritty/src/display/content.rs:187-198`), and cursor output noun is `RenderableCursor` (`alacritty/src/display/content.rs:399-407`).
- Alacritty damage noun is `DamageTracker`; it stores `FrameDamage` because this is host display scheduling state (`alacritty/src/display/damage.rs:12-28`, `alacritty/src/display/damage.rs:138-147`). In Howl, `frame` belongs to host wake/scheduling, not to render-surface, backend realization, texture upload, or presentation.
- Alacritty renderer root noun is `Renderer`, with `TextRendererProvider`, `TextRenderer`, `RectRenderer`, `GlyphCache`, and `LoaderApi` (`alacritty/src/renderer/mod.rs:26-34`, `alacritty/src/renderer/mod.rs:82-93`, `alacritty/src/renderer/mod.rs:177-190`, `alacritty/src/renderer/mod.rs:232-255`).
- Alacritty text renderer nouns are `TextRenderer`, `TextRenderBatch`, `TextRenderApi`, `LoaderApi`, `RenderingPass`, and `RenderingGlyphFlags` (`alacritty/src/renderer/text/mod.rs:33-57`, `alacritty/src/renderer/text/mod.rs:97-132`, `alacritty/src/renderer/text/mod.rs:182-191`). These support `command`, `glyph_run`, `glyph_ref`, `upload`, `batch`, and `loader` vocabulary, not `protocol`.
- Alacritty atlas noun is `Atlas`; it manages a single texture atlas and has `AtlasInsertError`, `insert`, `load_glyph`, and `clear_atlas` (`alacritty/src/renderer/text/atlas.rs:11-16`, `alacritty/src/renderer/text/atlas.rs:63-70`, `alacritty/src/renderer/text/atlas.rs:118-140`, `alacritty/src/renderer/text/atlas.rs:247-295`).
- Alacritty glyph cache noun is `GlyphCache`; `LoadGlyph` copies rasterized glyphs into graphics memory, `Glyph` stores texture coordinates, and `GlyphCache` caches buffered glyphs and owns the rasterizer (`alacritty/src/renderer/text/glyph_cache.rs:17-26`, `alacritty/src/renderer/text/glyph_cache.rs:28-40`, `alacritty/src/renderer/text/glyph_cache.rs:42-79`).
- Alacritty host owner noun is `WindowContext`; it owns `Display`, `dirty`, event queue, terminal, notifier, mouse/touch, PTY file descriptors, and config (`alacritty/src/window_context.rs:47-70`). It bootstraps GL display/config/context and creates `Display` (`alacritty/src/window_context.rs:73-119`). It processes queued events and requests redraw only when dirty, has a frame, and is not occluded (`alacritty/src/window_context.rs:400-493`).

## Current Howl Findings

### Render ABI

- Public render header currently exposes `HOWL_RENDER_PROTOCOL_V0_VERSION` and many `HOWL_RENDER_V0_*` constants (`howl-render/include/howl_render.h:19-44`). This violates both banned `protocol` and product-phase `V0` vocabulary.
- Public ABI currently names `HowlRenderV0Token` with `frame_seq`, `HowlRenderV0Rect`, `HowlRenderV0DamageItem`, `HowlRenderV0ResourceId`, `HowlRenderV0Upload`, `HowlRenderV0Create`, `HowlRenderV0GlyphRef`, `HowlRenderV0Command`, `HowlRenderV0Retire`, `HowlRenderV0HostAck`, and `HowlRenderV0Frame` (`howl-render/include/howl_render.h:184-314`). `HowlRenderV0Frame` also carries `protocol_version` (`howl-render/include/howl_render.h:302-314`).
- Public prepared diagnostics expose `protocol_v0_emit_status` (`howl-render/include/howl_render.h:516-522`).
- Public FFI exposes `howl_render_prepared_surface_protocol_v0()` returning `const HowlRenderV0Frame **` (`howl-render/include/howl_render.h:644-647`). This name is a direct ABI violation under the user law.

### Render Source Owners Hidden By Fake Names

- `prepared/v0_frame_emitter.zig` is not a protocol owner. It emits bounded render-surface consequences from a prepared surface: damage, creates, uploads, commands, glyph refs, sprites, and retires. Current aliases make this explicit: `ResourceId`, `Rect`, `GlyphRef`, and `Frame` are all `HowlRenderV0*` ABI shapes (`prepared/v0_frame_emitter.zig:12-15`), and limits are damage/creates/uploads/commands/glyph_refs/retires/upload_bytes (`prepared/v0_frame_emitter.zig:47-66`).
- `prepared/v0_frame_emitter.zig` also owns sprite resource storage and atlas packing under `SpriteResourceStore`, `AtlasResult`, `AtlasEntry`, `resourceFor`, `atlasRegionFor`, and `ensureAtlasResource` (`prepared/v0_frame_emitter.zig:99-143`, `prepared/v0_frame_emitter.zig:175-255`, `prepared/v0_frame_emitter.zig:257-260`). This is real `render-surface` resource/atlas/upload ownership hidden by `V0` and `frame` names.
- `render/v0_frame_realizer.zig` is not a protocol owner. It is a software oracle/realizer for render-surface consequences. It validates spans, resource transitions, damage, creates, uploads, commands, and retires (`render/v0_frame_realizer.zig:17-55`, `render/v0_frame_realizer.zig:179-194`, `render/v0_frame_realizer.zig:196-263`). It rejects `frame.protocol_version` mismatch (`render/v0_frame_realizer.zig:256-258`).
- `prepared/owner.zig` hides a sidecar payload as `protocol_v0_emit` and `V0Payload`, stores `v0_payload`, `protocol_v0_emit_status`, and exposes `protocolV0Frame()` (`prepared/owner.zig:8-9`, `prepared/owner.zig:31-39`, `prepared/owner.zig:41-58`, `prepared/owner.zig:144-166`). The real owner is prepared-surface-owned render-surface payload storage.
- `prepared/owner.zig` creates the payload in `emitV0Payload()` and passes `protocol_v0_sprite_resources` to `emitPrepared()` (`prepared/owner.zig:231-241`). This is render-surface emission and sprite-resource storage, not protocol.
- `ffi/protocol_v0.zig` is an ABI layout mirror file. It mirrors token, rect, damage, resource, upload, create, glyph, command, retire, host ack, and frame structs, asserts constants, and asserts layout (`ffi/protocol_v0.zig:9-139`, `ffi/protocol_v0.zig:141-188`). The real file owner should be render-surface ABI layout assertions.
- `ffi/prepared_surface.zig` exposes the banned function `protocolV0()` and forwards to `owner.protocolV0Frame()` (`ffi/prepared_surface.zig:46-59`). Diagnostics copy `protocol_v0_emit_status` (`ffi/prepared_surface.zig:109-118`).
- `libhowl_render.zig` imports `ffi/protocol_v0.zig`, forces it into comptime, and exports `howl_render_prepared_surface_protocol_v0` (`libhowl_render.zig:8-12`, `libhowl_render.zig:35-38`).

### Render Docs

- `docs/render-api-v0.md` title/status/purpose still use `Render API V0`, `V0-only`, `prepared terminal frames`, `V0 frame tokens`, and `howl_render_prepared_surface_protocol_v0()` (`docs/render-api-v0.md:1-15`, `docs/render-api-v0.md:28-39`). This conflicts with current user law even though it was a partial cleanup from earlier sprint.
- Docs list public `HOWL_RENDER_PROTOCOL_V0_VERSION` and `HOWL_RENDER_V0_*` constants (`docs/render-api-v0.md:67-85`) and conceptual `HowlRenderV0Frame` with `protocol_version` (`docs/render-api-v0.md:92-224`).
- Docs correctly describe real owner facts: render owns resource IDs, glyph identity, atlas packing, damage, upload bytes, command stream; host owns backend resources, wake, presentation, swap, platform UX (`docs/render-api-v0.md:36-65`). These ownership paragraphs should survive with `render-surface` vocabulary.

### Host Consumers

- Host retained render names `PreparedUpload.protocol_v0_probe`, `protocol_v0_resource_plan`, and `protocol_v0_frame` hide a prepared render-surface sidecar, resource plan, and surface pointer (`howl-linux-host/src/terminal/render/retained.zig:66-87`).
- Host resource store and backend operation names use `ProtocolV0ResourceStore`, `ProtocolV0BackendOperation`, and `ProtocolV0StoredResource` while actually validating render-owned resources and recording host backend texture operations (`retained.zig:108-182`, `retained.zig:184-216`).
- Host context diagnostics are named `ProtocolV0SubmitDiagnostics` with many `v0_*_frame_count` counters (`context.zig:82-122`), and context fields are `protocol_v0_textures` and protocol-v0 diagnostics (`context.zig:124-130`). These describe render-surface realization, texture upload, and presentation outcomes, not host wake policy.
- Host render turn uses `bootstrap_surface`, `needsRenderSurface()`, `term_texture`, and `host_surface_id` (`context.zig:412-420`, `context.zig:415-418`). These are already closer to the real owner name.
- Host context realizes and uploads `prepared_upload.protocol_v0_frame` through `protocol_v0_textures.realizeFrame(frame)` and `uploadProtocolV0Commands()` (`context.zig:618-644`, `context.zig:659-706`). Under user law, the render object argument must be `render_surface`, not `frame`; presentation-specific counters use `present` when tied to backend presentation.
- Host GL resource file `term_texture.zig` names `ProtocolV0Textures`, but it owns backend texture slots for render-owned resources (`term_texture.zig:24-43`). `realizeFrame()` creates/uploads/retires GL textures from the render object (`term_texture.zig:110-197`, `term_texture.zig:370-418`). This should become texture/resource/upload vocabulary, not protocol/v0/frame.
- `term_texture.zig` validates `frame.protocol_version` against `HOWL_RENDER_PROTOCOL_V0_VERSION` (`term_texture.zig:210-217`). That is a direct banned render-side protocol/version bucket leak in host consumer code.

### Render Test Ownership

- Render tests have one entrypoint only. The legitimate source entrypoint is `howl-render/src/test.zig`; it imports `libhowl_render.zig`, `test/ffi.zig`, and `test/unit/root.zig` from one test root (`howl-render/src/test.zig:3-7`).
- `howl-render/src/test/ffi.zig` is the ABI/FFI test owner reached through `src/test.zig`. It ref-all-decls `libhowl_render.zig` and tests exported FFI contracts, status values, prepared diagnostics layout, lifecycle seams, VT surface storage, prepare/submit seams, and token validation (`howl-render/src/test/ffi.zig:3-26`, `howl-render/src/test/ffi.zig:28-100`, `howl-render/src/test/ffi.zig:102-260`).
- ABI layout assertions for render-surface structs are reached through `src/test.zig` because `src/test.zig` imports `libhowl_render.zig` (`howl-render/src/test.zig:3-5`), and `libhowl_render.zig` imports the render-surface ABI mirror at comptime after the rename, as `protocol_v0` is imported today (`howl-render/src/libhowl_render.zig:8-12`).
- `howl-render/src/test/unit/root.zig` is the unit/oracle test owner reached through `src/test.zig`. It imports the render-surface realizer, render-surface emitter, geometry tests, and render-surface oracle tests after the rename; today it imports the old fake-owner files and `render_api_v0_oracle.zig` (`howl-render/src/test/unit/root.zig:1-6`).
- `howl-render/build.zig` currently points `test:unit` at deleted duplicate root `src/test_unit.zig` and `test:abi` at deleted duplicate root `src/test_abi.zig` (`howl-render/build.zig:37-83`). That build shape violates project test ownership law. The build root for render tests must be `src/test.zig` for all render test steps (`test`, `test:build`, `test:unit`, `test:unit:build`, `test:abi`, `test:abi:build`). Narrow test steps may filter the single `src/test.zig` artifact; they must not create separate root modules.
- Duplicate wrapper entrypoints are banned. `src/test_abi.zig` and `src/test_unit.zig` must not be restored, recreated, and must not be replaced with equivalent wrapper roots under different names.

## Noun Mapping

| Current Fake Name | Real Owner Hidden | Replacement Vocabulary |
| --- | --- | --- |
| `protocol_v0` file/import/bucket | Render ABI layout and render-surface consequence contract | `render_surface` |
| `ProtocolV0` host/source prefix | Host realization of render-surface resources and render-surface submit diagnostics | `RenderSurface` for render-surface object/contract identifiers; `RenderResource` for render-owned resource state; `TextureResource` and `TextureUpload` for host backend texture paths |
| `V0` public type prefix | Product-phase bucket | Remove; use `HowlRenderSurface*` |
| `HOWL_RENDER_PROTOCOL_V0_VERSION` | Render-surface ABI version field | `HOWL_RENDER_SURFACE_VERSION` |
| `HOWL_RENDER_V0_*_MAX` | Render-surface public bounds | `HOWL_RENDER_SURFACE_*_MAX` |
| `HOWL_RENDER_V0_DAMAGE_*` | Render-surface damage kind | `HOWL_RENDER_SURFACE_DAMAGE_*` |
| `HOWL_RENDER_V0_RESOURCE_*` | Render-owned resource kind | `HOWL_RENDER_RESOURCE_*` |
| `HOWL_RENDER_V0_UPLOAD_*` | Render upload format | `HOWL_RENDER_UPLOAD_*` |
| `HOWL_RENDER_V0_COMMAND_*` | Render-surface command kind | `HOWL_RENDER_SURFACE_COMMAND_*` |
| `HowlRenderV0Token` | Render-surface identity/version/epoch token | `HowlRenderSurfaceToken` |
| `frame_seq` | Render-surface sequence | `surface_seq` |
| `HowlRenderV0Rect` | Render pixel rect | `HowlRenderSurfaceRect` |
| `HowlRenderV0DamageItem` | Render-surface damage item | `HowlRenderSurfaceDamageItem` |
| `HowlRenderV0DamageSpan` | Damage span | `HowlRenderSurfaceDamageSpan` |
| `HowlRenderV0ResourceId` | Render-owned resource identity | `HowlRenderResourceId` |
| `HowlRenderV0Upload` | Render-owned upload event | `HowlRenderResourceUpload` |
| `HowlRenderV0UploadSpan` | Upload span | `HowlRenderResourceUploadSpan` |
| `HowlRenderV0Create` | Render-owned resource create event | `HowlRenderResourceCreate` |
| `HowlRenderV0CreateSpan` | Create span | `HowlRenderResourceCreateSpan` |
| `HowlRenderV0GlyphRef` | Glyph atlas reference | `HowlRenderGlyphRef` |
| `HowlRenderV0GlyphRunSpan` | Row-local glyph run refs | `HowlRenderGlyphRunSpan` |
| `HowlRenderV0Command` | Render-surface command | `HowlRenderSurfaceCommand` |
| `HowlRenderV0CommandSpan` | Command span | `HowlRenderSurfaceCommandSpan` |
| `HowlRenderV0Retire` | Render-owned resource retire event | `HowlRenderResourceRetire` |
| `HowlRenderV0RetireSpan` | Retire span | `HowlRenderResourceRetireSpan` |
| `HowlRenderV0HostAck` | Host resource ack | `HowlRenderResourceAck` |
| `HowlRenderV0HostAckSpan` | Host ack span | `HowlRenderResourceAckSpan` |
| `HowlRenderV0Frame` | Prepared render-surface consequence object | `HowlRenderSurface` |
| `protocol_version` field | Render-surface ABI version | `surface_version` |
| `howl_render_prepared_surface_protocol_v0` | ABI accessor for prepared render-surface consequences | `howl_render_prepared_surface_render_surface` |
| `protocol_v0_emit_status` | Render-surface emission status | `render_surface_emit_status` |
| `v0_frame_emitter.zig` | Render-surface emitter from prepared surface | `render_surface_emitter.zig` |
| `v0_frame_realizer.zig` | Software oracle/realizer for render-surface commands/resources | `render_surface_realizer.zig` |
| `V0Payload`, `v0_payload` | Prepared render-surface payload storage | `RenderSurfacePayload`, `render_surface_payload` |
| `protocolV0Frame()` | Prepared owner surface accessor | `renderSurface()` |
| `PreparedProtocolV0ResourcePlan` | Prepared render-resource plan | `PreparedRenderResourcePlan` |
| `ProtocolV0ResourceStore` | Host mirror of render-owned resource state | `RenderResourceStore` |
| `ProtocolV0BackendOperation` | Host backend texture/resource operation | `TextureResourceOperation` |
| `ProtocolV0Textures` | Host GL texture store for render resources | `RenderResourceTextures` |
| `realizeFrame(frame)` in host texture store | Realize render-surface resources into host textures | `realizeSurface(surface)` |
| `protocolV0SpriteFrame`, `protocolV0GlyphFrame`, `protocolV0FillOnly` | Render-surface shape classifiers | `renderSurfaceSprite`, `renderSurfaceGlyphs`, `renderSurfaceFillOnly` |
| `v0_*_frame_count` diagnostics | Render-surface shape counts | `render_surface_*_count`; use `present_count` only for actual backend presentation success |

## Proposed ABI Vocabulary

- Public C prefix: `HowlRenderSurface*` for the render-surface object and its command/damage spans.
- Public resource prefix: `HowlRenderResource*` for resource IDs, creates, uploads, retires, and acks.
- Public glyph prefix: `HowlRenderGlyph*` for glyph refs and glyph run spans.
- Public constants: `HOWL_RENDER_SURFACE_VERSION`, `HOWL_RENDER_SURFACE_DAMAGE_ITEMS_MAX`, `HOWL_RENDER_SURFACE_UPLOADS_MAX`, `HOWL_RENDER_SURFACE_COMMANDS_MAX`, `HOWL_RENDER_SURFACE_GLYPHS_PER_RUN_MAX`, `HOWL_RENDER_SURFACE_UPLOAD_BYTES_MAX`, `HOWL_RENDER_SURFACE_ATLAS_PAGES_MAX`, `HOWL_RENDER_SURFACE_RESOURCES_MAX`, `HOWL_RENDER_SURFACE_CREATES_MAX`, `HOWL_RENDER_SURFACE_RETIRES_MAX`, `HOWL_RENDER_SURFACE_HOST_ACKS_MAX`.
- Public kind constants: `HOWL_RENDER_SURFACE_DAMAGE_RECT`, `HOWL_RENDER_SURFACE_DAMAGE_FULL`, `HOWL_RENDER_RESOURCE_GLYPH_ATLAS_ALPHA`, `HOWL_RENDER_RESOURCE_GLYPH_ATLAS_COLOR`, `HOWL_RENDER_RESOURCE_SPRITE_ALPHA`, `HOWL_RENDER_RESOURCE_SPRITE_COLOR`, `HOWL_RENDER_UPLOAD_ALPHA8`, `HOWL_RENDER_UPLOAD_RGBA8`, `HOWL_RENDER_SURFACE_COMMAND_CLEAR_RECT`, `HOWL_RENDER_SURFACE_COMMAND_FILL_RECT`, `HOWL_RENDER_SURFACE_COMMAND_DRAW_GLYPH_RUN`, `HOWL_RENDER_SURFACE_COMMAND_DRAW_SPRITE`.
- Accessor: `howl_render_prepared_surface_render_surface(HowlRenderPreparedSurfaceHandle, const HowlRenderSurface **surface_out)`.
- No aliases: delete old names instead of defining compatibility macros/types/functions.
- Version field: `surface_version`.

## Host Wake Vocabulary

- Host wake is event-loop, scheduling, wakeup, work, dirty, request, and frame scheduling policy. Source-backed wake names include `event`, `schedule`, `wake`, `dirty`, `request`, `work`, and `frame`.
- Host wake names must use `frame` where the owner is SDL/event-loop frame scheduling. This does not authorize `frame` for render-surface, backend realization, texture upload, or presentation.

## Presentation And Backend Vocabulary

- Presentation is where `HowlRenderSurface` is presented through GL or another backend. Backend/GL presentation does not run at the same cadence as host wake and does not know about SDL's frame scheduling.
- Names that consume `HowlRenderSurface` must not use `frame`: `prepared_upload.render_surface`, `render_surface_resource_plan`, `render_surface_probe`, `realizeSurface(surface)`, `uploadRenderSurfaceCommands(surface)`, `render_surface_*_count`.
- Backend/resource names use resource/texture/upload vocabulary: `RenderResourceTextures`, `TextureResourceSlot`, `TextureResourceOperation`, `createTexture`, `uploadTextureRect`, `retireTexture`, `RenderResourceStore`, `RenderResourceStoreStatus`.
- Existing `PresentInFlight` is presentation vocabulary and may remain because it models present state (`retained.zig:28-31`). Existing `present_pending`, `present_snapshot_seq`, and `*_present_count` are presentation outcomes and may remain (`retained.zig:33-39`, `context.zig:72-78`, `context.zig:107-121`).
- Existing `term_texture` file name is host backend resource vocabulary and may remain; its internal `ProtocolV0Textures` must change.
- This research proposes no `frame` replacement names for render ABI, render source, render docs, render tests, presentation, or backend realization. Host wake/scheduling is the only owner allowed to use `frame` vocabulary.

## Test Vocabulary And Ownership Plan

- One render test entrypoint: `howl-render/src/test.zig`.
- Build root for every render test step: `src/test.zig`.
- FFI/ABI contract tests: `src/test/ffi.zig`, imported only through `src/test.zig`.
- Unit/oracle tests: `src/test/unit/root.zig`, imported only through `src/test.zig`.
- Render-surface layout assertions: `src/ffi/render_surface.zig`, imported by `src/libhowl_render.zig`, reached by `src/test.zig` through `std.testing.refAllDecls(@import("libhowl_render.zig"))` and the lib root import.
- Render-surface unit owners after rename: `src/render/render_surface_realizer.zig`, `src/prepared/render_surface_emitter.zig`, `src/test/unit/geometry.zig`, and `src/test/unit/render_surface_oracle.zig`, all reached through `src/test/unit/root.zig` and then `src/test.zig`.
- Banned test roots: `src/test_abi.zig`, `src/test_unit.zig`, and any equivalent duplicate wrapper entrypoint.
- Narrow build steps may exist for developer ergonomics, but they must use the single `src/test.zig` test artifact with filters. They must not introduce separate root modules.

## Slice Boundary Recommendation

Recommendation: one broad product rename slice.

Reasons:

- The public C ABI, FFI export, render owners, docs, tests, and host consumers all share the same fake layer. Splitting into accepted partial slices would preserve banned public names and create a misleading halfway product.
- No compatibility aliases are allowed, and downstream compatibility is irrelevant. This makes a direct broad rename safer than adapter staging.
- The slice includes ABI/header/layout mirror rename, render owner/source/test rename, host consumer/backend rename, docs rename, build test-root correction, and final grep cleanup.
- Completion is allowed only after final grep gates pass.

## Risks

- ABI break is intentional but large. Every layout assertion must be renamed and remain equivalent.
- Broad rename can hide accidental semantic changes. Review should reject behavior changes not required by naming until tests prove the same bounded behavior.
- `frame_seq` replacement must not become host cadence language. Use `surface_seq` consistently.
- Host diagnostics currently mix render object shape counts with presentation counts. Rename only render-object counts to `render_surface_*_count`; preserve `present_count` for actual host presentation success.
- Existing tests use `render API V0` phrasing heavily. Tests must be renamed without weakening assertions.
- Build currently references deleted duplicate test roots. The product fix is to route all render test steps through `src/test.zig`, not to restore duplicate wrapper entrypoints.

## Stop Conditions

- Stop when any worker proposes compatibility macros, typedef aliases, wrapper functions, and old-name shims.
- Stop when any render ABI/source/doc symbol uses `protocol`, `protocol_v0`, `V0`, or render-side `frame` after the rename.
- Stop if any host backend/resource/presentation name uses `frame` for a render-surface object, texture upload, backend realization, or present path.
- Stop when layout assertions are deleted and weakened instead of renamed.
- Stop when docs preserve `Render API V0`, `protocol`, and `frame` as render vocabulary.
- Stop when `src/test_abi.zig`, `src/test_unit.zig`, and any duplicate render test wrapper entrypoint is restored.
- Stop if any render test build step uses a root source file other than `src/test.zig`.
- Stop when a worker proposes `frame` as a replacement name in render ABI, render source, render docs, render tests, presentation, or backend realization. Host wake/scheduling may use `frame`.
- Stop when a worker collapses host wake, presentation, backend realization, and render-surface ownership into one naming bucket.

## Verification And Grep Gates

Run these gates from `/home/home/personal/projects/howl` after implementation. Final readiness requires all banned-symbol gates to return no product/source/docs/host matches except vendored references and intentionally excluded research/cache history.

- `rg -n "protocol_v0|ProtocolV0|PROTOCOL_V0" howl-render howl-linux-host docs build.zig build.zig.zon`
- `rg -n "protocol" howl-render/include howl-render/src howl-linux-host/src docs --glob '!docs/**/official*'`
- `rg -n "RenderV0|RENDER_V0|render-api-v0|Render API V0|\bV0\b" howl-render howl-linux-host docs build.zig build.zig.zon`
- `rg -n "HowlRenderV0|HOWL_RENDER_V0|HOWL_RENDER_PROTOCOL" howl-render/include howl-render/src howl-linux-host/src docs`
- `rg -n "\bframe\b|\bFrame\b|FRAME" howl-render/include howl-render/src docs howl-linux-host/src/terminal/render howl-linux-host/src/window/term_texture.zig`
- Host wake/scheduling `frame` vocabulary in `howl-linux-host/src/terminal/context.zig` is allowed only for SDL/event-loop frame scheduling and must not describe render-surface presentation, backend realization, texture upload, or resources.
- `rg -n "prepared_surface_protocol|protocolV0|protocol_v0_emit_status|v0_payload|V0Payload|v0_frame" howl-render howl-linux-host docs`
- `rg -n "test_abi|test_unit|src/test_abi\.zig|src/test_unit\.zig" howl-render`
- `rg -n "root_source_file = b\.path\(\"src/test\.zig\"\)" howl-render/build.zig`
- Positive gate: `rg -n "HowlRenderSurface|HOWL_RENDER_SURFACE|render_surface|RenderSurface|surface_seq|howl_render_prepared_surface_render_surface" howl-render howl-linux-host docs`
- Positive gate: `rg -n "HowlRenderResource|HOWL_RENDER_RESOURCE|RenderResource|TextureResource|uploadTextureRect|retireTexture" howl-render howl-linux-host docs`

Expected exceptions:

- Reference trees under `utils/dev_references/` are not product paths.
- Historical research/cache/scratchpad files may retain old vocabulary only when explicitly historical. Product docs must not.
- This research allows `frame` only for host wake/scheduling. Product render paths and host presentation/backend paths in the `frame` gate stay clean.

## Required Assertions And Tests For Worker Seed

- Preserve compile-time ABI size/alignment/offset assertions currently in `ffi/protocol_v0.zig` under the new render-surface mirror (`ffi/protocol_v0.zig:169-188`, `ffi/protocol_v0.zig:325-347`).
- Preserve fixed bound assertions in emitter limits (`prepared/v0_frame_emitter.zig:25-33`, `prepared/v0_frame_emitter.zig:56-66`).
- Preserve validation of surface version, span counts, damage kinds, resource kinds, upload bounds, command kinds, and resource lifetime order under new names (`render/v0_frame_realizer.zig:256-300`, `term_texture.zig:210-278`).
- Preserve host texture realization rollback/fail-closed behavior while renaming (`term_texture.zig:130-197`).
- Rename tests to render-surface vocabulary and keep all existing assertions over commands, uploads, resources, damage, and realization equality.
- Preserve single render test entrypoint ownership: all ABI/layout assertions, FFI tests, and unit/oracle tests must be reachable from `src/test.zig`; no duplicate test roots may be created.

## Readiness Judgment

READY FOR SCRATCHPAD: evidence supports a broad no-alias rename from fake `protocol_v0`/product `V0`/render `frame` vocabulary to `render-surface`, `render-resource`, `texture`, `upload`, `damage`, `command`, `glyph-run`, host wake `event`/`schedule`/`dirty`/`request`/`work`/`frame`, and presentation `present` vocabulary. References do not provide a direct embeddable render ABI noun, but Ghostty and Alacritty support `renderer`, `surface`, `atlas`, `glyph cache`, `run`, `damage`, `resource`, `texture`, backend realization, and separate scheduling/presentation boundaries. Under user law, Howl's smallest invented ABI noun is `render-surface`.
