# Render Protocol Symbol Deletion Research Cache

Date: 2026-06-01

Owner: research cache only. This is not a scratchpad, not `current.txt`, and not an implementation.

Status: rejected/incomplete. This cache is useful only as a local occurrence
inventory. It is not scratchpad-ready because it proposed replacement vocabulary
from local grep instead of asking Ghostty and Alacritty what the real owner names
and ABI shape should be.

Correct premise for the next research round:

- The made-up `protocol_v0` / `V0` / `render API V0` abstraction is rejected.
- Do not preserve its vocabulary.
- Do not ask references whether it is rejected; the user already decided that.
- Ask Ghostty, Alacritty, and TigerBeetle what the idiomatic owner names and
  concrete C ABI shape should be.
- Replace the fake layer with concrete render/display/texture/glyph/damage/upload
  owners and symbols.

## Sources Read In Order

1. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
3. `AGENTS.md`
4. `loop.txt`
5. `current.txt`
6. `research/2026-06-01-render-api-language-deletion-sprint.md`
7. `research/cache-2026-06-01-render-api-language-deletion.md`
8. `research/cache-2026-06-01-render-v0-source-owner-paths.md`
9. `research/cache-2026-06-01-render-protocol-language-cleanup.md`
10. Current `howl-render/include/howl_render.h`.
11. Current `howl-render/src/ffi/protocol_v0.zig`.
12. Current `howl-render/src/ffi/prepared_surface.zig`.
13. Current `howl-render/src/libhowl_render.zig`.
14. Current `howl-render/src/prepared/owner.zig`.
15. Current `howl-render/src/session/text.zig`.
16. Current `howl-render/src/prepared/v0_frame_emitter.zig` occurrence inventory.
17. Current `howl-render/src/render/v0_frame_realizer.zig` occurrence inventory.
18. Current `howl-render/src/test/unit/render_api_v0_oracle.zig` occurrence inventory.
19. Current `howl-render/src/test/ffi.zig` occurrence inventory.
20. Current `docs/render-api-v0.md`.
21. Current `current.txt`.
22. Current `howl-linux-host/src/terminal/render/retained.zig`.
23. Current `howl-linux-host/src/terminal/context.zig`.
24. Current `howl-linux-host/src/window/term_texture.zig`.

## Governing Facts

- `AGENTS.md:9-15` says ABIs are the product, hosts embed `howl-render`, Howl owns ABI contracts and consequences, and the repository has no downstream. Therefore public C ABI symbols containing `protocol` are in scope and downstream compatibility is not a reason to preserve old names.
- `AGENTS.md:95-103` assigns `howl-render` ownership of render contracts, retained-frame state, prepare/submit scheduling, render-surface contracts, and text shaping. Hosts own backend resource realization and presentation policy.
- `AGENTS.md:105-116` says FFI translates contracts only, owner files own state and mutation, and behavior moves toward the smallest true owner.
- `loop.txt:83-98` requires research caches to be line-backed evidence, not implementation planning. `loop.txt:133-145` hard-stops on public ABI changes without an explicit ABI-product slice and on compatibility shims without authorization.
- `TIGER_STYLE.md:273-289` requires exact nouns and verbs. `protocol` is not an owner-true noun for render API V0 frames because current code owns bounded frame emission, frame realization, ABI layout, diagnostics, and host texture realization.
- `TIGER_STYLE.md:96-140` requires explicit bounds, assertions, and negative tests. The rename must preserve constant/layout assertions and invalid-frame/probe tests.
- `current.txt:23-33` states the prior sprint did not complete deletion because public render ABI symbols, FFI names, docs, tests, and host consumers still contain banned `protocol` language.
- Historical caches now say their public-ABI preservation premise is rejected: `research/2026-06-01-render-api-language-deletion-sprint.md:5-10`, `research/cache-2026-06-01-render-v0-source-owner-paths.md:7-11`, and `research/cache-2026-06-01-render-protocol-language-cleanup.md:8-12`.

## Current Occurrence Inventory

### `howl-render/include`

- `howl-render/include/howl_render.h:19` defines public macro `HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: public C ABI macro. Consequence: host cimports, docs, FFI constant assertions, render realizer/emitter, and host validators must rename together.
- `howl-render/include/howl_render.h:303` defines public field `HowlRenderV0Frame.protocol_version`. Classification: public C ABI struct field. Consequence: FFI layout mirror, offset assertion, render/host version checks, docs C snippet, and frame literals must rename together.
- `howl-render/include/howl_render.h:520` defines public field `HowlRenderPreparedSurfaceDiagnostics.protocol_v0_emit_status`. Classification: public C ABI diagnostics field. Consequence: prepared owner diagnostics, FFI diagnostics translation, render ABI tests, host diagnostics capture/logging must rename together.
- `howl-render/include/howl_render.h:644-647` declares public function `howl_render_prepared_surface_protocol_v0()`. Classification: public C ABI exported function name. Consequence: export symbol, FFI function owner, docs, render ABI tests, and host cimport call must rename together.

### `howl-render/build.zig`

- Current grep found no `protocol`, `protocol_v0`, `protocolV0`, `PROTOCOL_V0`, or `render-protocol` occurrence in `howl-render/build.zig`. Classification: no product occurrence in this file after prior cleanup.

### `docs`

- `docs/render-api-v0.md:30` names public call `howl_render_prepared_surface_protocol_v0()`. Classification: docs code token for public ABI. Consequence: must track ABI function rename.
- `docs/render-api-v0.md:73` names public macro `HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: docs code token for public ABI. Consequence: must track ABI macro rename.
- `docs/render-api-v0.md:212` names public field `protocol_version`. Classification: docs C snippet for public ABI. Consequence: must track ABI frame field rename.
- Current docs grep found no `render-protocol` path/prose occurrence. Classification: the stale doc path is already gone.

### `current.txt`

- `current.txt:8`, `15`, `20-25`, and `32-38` contain historical/status text with `protocol`, `protocol_v0`, `test:protocol-proof`, and `docs/render-protocol-v0.md`. Classification: current workflow record, not product code. Consequence: historical status only; do not edit from research role. Scratchpad may choose whether current records must be updated outside product gates.

### Historical Research Records

- `research/2026-06-01-render-api-language-deletion-sprint.md:5-22`, `36-63`, `362-363`, and `396-397` explicitly record that public render ABI `protocol` vocabulary remains and requires fresh research. Classification: historical research/sprint record.
- `research/cache-2026-06-01-render-api-language-deletion.md:63-81`, `155-177`, and `222-252` inventory the old public ABI/FFI/host risk but preserve old names. Classification: historical research only.
- `research/cache-2026-06-01-render-v0-source-owner-paths.md:147-175`, `234-240`, and `252-256` record the now-rejected decision to leave `ffi/protocol_v0.zig` and public ABI spelling. Classification: historical research only.
- `research/cache-2026-06-01-render-protocol-language-cleanup.md:137-168`, `241-243`, and `336-342` record the old public-ABI exemption as superseded. Classification: historical research only.

## Render Source Occurrence Inventory

### FFI Layout Owner

- `howl-render/src/ffi/protocol_v0.zig:1-7` is a compile-time ABI mirror/assertion wrapper. The filename contains `protocol_v0`. Classification: FFI translation/layout assertion owner path.
- `howl-render/src/ffi/protocol_v0.zig:127-139` defines mirror `Frame` with field `protocol_version`. Classification: FFI layout mirror for public C ABI field.
- `howl-render/src/ffi/protocol_v0.zig:141-167` asserts public V0 constants, including `c.HOWL_RENDER_PROTOCOL_V0_VERSION == 0` at line 142. Classification: FFI ABI constant assertion.
- `howl-render/src/ffi/protocol_v0.zig:325-338` asserts `HowlRenderV0Frame` layout and `protocol_version` offset at line 327. Classification: FFI ABI layout assertion.
- `howl-render/src/libhowl_render.zig:8` imports `ffi/protocol_v0.zig` as `protocol_v0`, line 11 references it, and line 37 exports `howl_render_prepared_surface_protocol_v0`. Classification: FFI ABI assertion import plus public export symbol.

### Prepared-Surface FFI Translation

- `howl-render/src/ffi/prepared_surface.zig:46-59` defines FFI function `protocolV0()` and calls `owner.protocolV0Frame()`. Classification: FFI translation function for public prepared-frame ABI.
- `howl-render/src/ffi/prepared_surface.zig:109-127` maps `protocol_v0_emit_status` into/out of public diagnostics. Classification: FFI diagnostics translation.

### Prepared Owner Internals

- `howl-render/src/prepared/owner.zig:8` imports the emitter as `protocol_v0_emit`. Classification: render owner internal identifier.
- `howl-render/src/prepared/owner.zig:31-35` declares internal `PreparedDiagnostics.protocol_v0_emit_status`. Classification: render owner internal diagnostics field that feeds public ABI diagnostics.
- `howl-render/src/prepared/owner.zig:37-58` stores `V0Payload` and `protocol_v0_emit_status`. Classification: render owner internal state.
- `howl-render/src/prepared/owner.zig:75-80` stores emitter error mapping into `protocol_v0_emit_status`. Classification: render owner internal mutation.
- `howl-render/src/prepared/owner.zig:144-155` exposes `protocolV0Frame()`, `protocolV0FrameForTest()`, and `protocolV0FrameStorageEmptyForTest()`. Classification: render owner internal methods used by FFI/tests.
- `howl-render/src/prepared/owner.zig:161-166` returns diagnostics with `.protocol_v0_emit_status`. Classification: render owner internal-to-FFI diagnostics.
- `howl-render/src/prepared/owner.zig:237` passes `session_owner.protocol_v0_sprite_resources` to emitter. Classification: render owner internal retained resource state access.
- `howl-render/src/prepared/owner.zig:267-271` initializes `.protocol_v0_emit_status` and defines `protocolV0EmitStatus()`. Classification: render owner internal error-to-ABI translation helper.
- `howl-render/src/prepared/owner.zig:436-439`, `565`, `635`, and `642-674` assert `protocolV0Frame`, `protocol_v0_emit_status`, and `protocolV0EmitStatus()` behavior. Classification: render unit tests/assertions.

### Text Session Retained State

- `howl-render/src/session/text.zig:16` imports `v0_frame_emitter.zig` as `protocol_v0_emit`. Classification: render owner internal identifier.
- `howl-render/src/session/text.zig:357` stores `protocol_v0_sprite_resources: protocol_v0_emit.SpriteResourceStore`. Classification: render owner internal retained resource state owned by text session.

### Frame Emitter And Realizer

- `howl-render/src/prepared/v0_frame_emitter.zig:952` writes `.protocol_version = c.HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: render owner internal frame construction using public ABI field/macro.
- `howl-render/src/render/v0_frame_realizer.zig:257` checks `frame.protocol_version != c.HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: render owner internal validation using public ABI field/macro.
- `howl-render/src/render/v0_frame_realizer.zig:1970` constructs a fixture with `.protocol_version = c.HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: render unit test/fixture.

### Render Unit And ABI Tests

- `howl-render/src/test/unit/render_api_v0_oracle.zig:8-9` aliases owner files as `protocol_emit` and `protocol_realize`; lines `17`, `63`, `67`, `100`, `104`, `164`, `168`, `206`, `210`, `256`, `260`, `274`, `278`, `280`, `306`, `391`, `395`, `405`, `413`, `425`, `473`, `477`, `531`, `535`, `592`, `596`, `634`, `639`, `674`, `678`, `714`, `718-721`, `752`, `757-758`, `763`, `789`, `793`, `805`, `868`, `905`, `937`, `1078`, `1082`, and `1084` use those aliases. Classification: test internal aliases and call sites.
- `howl-render/src/test/unit/render_api_v0_oracle.zig:861`, `871`, `899`, `938`, `963`, `967`, `992`, `1011`, and `1062` call `protocolV0Frame*()` or FFI `protocolV0()`. Classification: tests consuming internal FFI/prepared names.
- `howl-render/src/test/unit/render_api_v0_oracle.zig:995`, `1014`, and `1060` assert diagnostics field `protocol_v0_emit_status`. Classification: test assertion of diagnostics consequence.
- `howl-render/src/test/ffi.zig:48`, `312`, and `333` assert `diagnostics.protocol_v0_emit_status`; line `94` asserts offset of `protocol_v0_emit_status`. Classification: ABI/FFI tests.
- `howl-render/src/test/ffi.zig:344`, `350`, `362`, `376`, `390`, `412`, `421`, and `436` call `prepared_surface.protocolV0()`. Classification: FFI tests for public prepared-frame call.
- `howl-render/src/test/ffi.zig:395-396` assert `HOWL_RENDER_PROTOCOL_V0_VERSION` and `value.protocol_version`. Classification: ABI/FFI tests for frame version field and macro.

## Host Consumer Occurrence Inventory

### `howl-linux-host/src/terminal/render/retained.zig`

- `retained.zig:66-71` stores `protocol_v0_probe`, `protocol_v0_resource_plan`, and `protocol_v0_frame` on `PreparedUpload`. Classification: host consumer internal state.
- `retained.zig:78-106` defines `PreparedProtocolV0ResourcePlan` and status enum. Classification: host consumer internal type names for prepared frame resource planning.
- `retained.zig:108-134` defines `ProtocolV0ResourceStoreStatus`, `ProtocolV0BackendOperationKind`, `ProtocolV0BackendOperation`, and recorder types. Classification: host retained resource realization internals.
- `retained.zig:184-233` defines `ProtocolV0ResourceState`, `ProtocolV0StoredResource`, `protocol_v0_resource_store_empty`, `protocol_v0_backend_operations_max`, and `ProtocolV0ResourceStore`. Classification: host retained resource store internals.
- `retained.zig:504-538` defines `PreparedProtocolV0Probe` and status enum. Classification: host prepared-frame probe internals.
- `retained.zig:540-555` stores last probe/plan and `protocol_v0_*` counters on host retained state. Classification: host diagnostics/counters.
- `retained.zig:752-795` initializes upload state, calls `probePreparedProtocolV0()`, calls public C ABI `c.howl_render_prepared_surface_protocol_v0()` at line 783, then validates plan/probe. Classification: host cimport/consumer symbol plus host internal names.
- `retained.zig:797-818` records `last_protocol_v0_*` and `protocol_v0_*` counters. Classification: host diagnostics/counters.
- `retained.zig:880-944` validates `frame.protocol_version` against `HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: host consumer validation of public ABI field/macro.
- `retained.zig:958-981` validates resource plan and `frame.protocol_version` against `HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: host consumer validation of public ABI field/macro.
- `retained.zig:1438` constructs `.protocol_version = c.HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: host test/fixture.
- `retained.zig:1702`, `1720`, `1754`, `1798`, `1814`, `1836`, `1853`, `1873`, and `1923` are host tests named with `protocol v0`; lines `1816-1833`, `1914-1919`, and `2053-2058` assert `protocol_v0_*` counters and last statuses. Classification: host tests/assertions.

### `howl-linux-host/src/terminal/context.zig`

- `context.zig:82-122` defines `ProtocolV0SubmitDiagnostics` with fields `protocol_v0_emit_status` and `protocol_v0_resource_plan_status` at lines `91-92`. Classification: host diagnostics type and fields.
- `context.zig:128-130` stores `protocol_v0_textures`, `protocol_v0_submit_diagnostics`, and logged copy. Classification: host retained runtime state.
- `context.zig:171-173`, `196`, `565-566`, and `889-890` initialize/deinit/increment `protocol_v0_*` state. Classification: host runtime state mutation.
- `context.zig:615-786` owns upload decision flow with `shouldRealizeProtocolV0()`, `protocol_v0_frame`, `protocol_v0_textures`, `protocol_v0_submit_diagnostics`, `uploadProtocolV0Commands()`, `recordUnsupportedProtocolV0Shape()`, `recordProtocolV0NoSidecar()`, and calls to `term_texture.protocolV0*` and `uploadProtocolV0*`. Classification: host consumer implementation, no host behavior change intended beyond renames.
- `context.zig:930-956` records/logs `ProtocolV0` diagnostics and `protocol_v0_*` fields. Classification: host diagnostics implementation.
- `context.zig:974-1034` prints diagnostics and uses `ProtocolV0SubmitDiagnostics`, `term_texture.ProtocolV0Textures.Diagnostics`, and `submit_diag.protocol_v0_*`. Classification: host diagnostics implementation.
- `context.zig:1140-1144`, `1150-1234` define `protocolV0Label()`, `printProtocolV0GlDiagnostics()`, `printProtocolV0FailureDiagnostics()`, and `protocolV0FailureTotal()`. Classification: host diagnostics helpers.
- `context.zig:1739`, `1777`, and `2319` are tests named with `protocol v0`; related fixtures around `1714-1715`, `1745-1746`, `1766-1773`, `1787`, and `2123-2125` use `protocol_v0_*` state. Classification: host tests/assertions.

### `howl-linux-host/src/window/term_texture.zig`

- `term_texture.zig:24-80` defines `ProtocolV0Textures` and diagnostics. Classification: host backend texture realization owner.
- `term_texture.zig:205-214` validates `frame.protocol_version` against `HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: host consumer validation of public ABI field/macro.
- `term_texture.zig:963` constructs `.protocol_version = render_c.HOWL_RENDER_PROTOCOL_V0_VERSION`. Classification: host fixture.
- `term_texture.zig:1004`, `1019`, `1034`, `1062`, `1069`, `1114`, `1132`, `1159`, `1164`, `1191`, `1233`, `1261`, `1278`, `1306`, `1323`, `1340`, `1356`, `1383`, `1399`, `1427`, `1453`, `1481`, `1519`, `1549`, `1589`, `1613`, `1652`, `1692`, `1741`, `1770`, `1809`, `1840`, `1910`, and `1932` are host tests named with `protocol v0`. Classification: host tests.
- `term_texture.zig:1188`, `1224`, `1258`, `1275`, `1303`, `1320`, `1337`, `1353`, `1380`, `1396`, `1424`, `1610`, `1649`, `1689`, `1738`, `1766-1767`, `1806`, and `1837` call `protocolV0*` shape helpers. Classification: host test call sites.
- `term_texture.zig:2020`, `2045`, `2071`, `2080`, `2089`, and `2098` call `protocolV0*` helpers in upload selection helpers. Classification: host implementation call sites.
- `term_texture.zig:2198-2455` defines `protocolV0FillOnly`, `protocolV0FillPatch`, `protocolV0FillCoverage`, `protocolV0FrameSummary`, `protocolV0SpriteFrame`, `protocolV0SpritePatch`, `protocolV0GlyphFrame`, `protocolV0GlyphPatch`, `protocolV0FillCommand`, `protocolV0SpriteCommand`, `protocolV0GlyphCommand`, and `protocolV0FullClear`. Classification: host backend texture realization helper names.
- `term_texture.zig:2431` calls `unpackProtocolV0Rgba()`. Classification: host helper call; the helper definition is another host internal occurrence found by the wider `ProtocolV0|protocolV0` grep.

## Replacement Vocabulary

### Public C ABI

- Replace `HOWL_RENDER_PROTOCOL_V0_VERSION` with `HOWL_RENDER_API_V0_VERSION`.
- Replace `HowlRenderV0Frame.protocol_version` with `api_version`.
- Replace `HowlRenderPreparedSurfaceDiagnostics.protocol_v0_emit_status` with `v0_frame_emit_status`.
- Replace `howl_render_prepared_surface_protocol_v0()` with `howl_render_prepared_surface_v0_frame()`.

Justification:

- `render_api_v0` is source-backed by the accepted doc path and title: `docs/render-api-v0.md:1` says `Howl Render API V0 Contract`, and lines `9-16` define Render API V0 as the C ABI consequence surface for prepared terminal frames.
- `api_version` is a field noun for the version of the Render API V0 frame. `docs/render-api-v0.md:69-85` already presents the value as a public V0 ABI contract, not a transport protocol.
- `v0_frame_emit_status` is source-backed by the owner path and behavior: `prepared/v0_frame_emitter.zig` emits V0 frames; `prepared/owner.zig:75-80` maps emitter errors; `prepared_surface.zig:109-127` translates diagnostics. The status describes V0 frame emission, not a protocol.
- `howl_render_prepared_surface_v0_frame()` is source-backed by `howl_render.h:640-647`, where the call belongs to prepared-surface handle access, and by `prepared/owner.zig:144-147`, which returns a `HowlRenderV0Frame`. The noun order follows existing ABI prefix style and TigerStyle noun clarity: prepared surface -> V0 frame.
- Do not rename `HowlRenderV0*` types or `HOWL_RENDER_V0_*` constants solely to remove `protocol`; they do not contain the banned word. Renaming them would broaden the slice without source-backed need.

Rejected public names:

- `HOWL_RENDER_V0_VERSION`: shorter, but less explicit than `API_V0_VERSION` and easier to confuse with non-ABI internal V0 fixtures.
- `version`: too generic for a public frame field; `api_version` carries the contract boundary.
- `howl_render_prepared_surface_api_v0()`: names the API, but not the returned object. `v0_frame` is the returned consequence.
- `howl_render_prepared_surface_render_api_v0_frame()`: redundant with the `howl_render` prefix and too long.
- Compatibility aliases retaining old `protocol` names: banned by user instruction and `loop.txt:144-145` unless explicitly authorized.

### Render Zig FFI/Internal Names

- Rename file `howl-render/src/ffi/protocol_v0.zig` to `howl-render/src/ffi/render_api_v0.zig` or `howl-render/src/ffi/v0_frame.zig`. Stronger recommendation: `render_api_v0.zig` because the file asserts the whole public V0 ABI layout, not only `Frame` (`protocol_v0.zig:9-139`, `141-167`, `169-338`).
- Rename `libhowl_render.zig` local import `protocol_v0` to `render_api_v0`.
- Rename FFI function `prepared_surface.protocolV0()` to `prepared_surface.v0Frame()`.
- Rename prepared owner methods `protocolV0Frame()`, `protocolV0FrameForTest()`, and `protocolV0FrameStorageEmptyForTest()` to `v0Frame()`, `v0FrameForTest()`, and `v0FrameStorageEmptyForTest()`.
- Rename prepared owner helper `protocolV0EmitStatus()` to `v0FrameEmitStatus()`.
- Rename local module aliases `protocol_v0_emit` to `v0_frame_emitter`, `protocol_emit` to `v0_frame_emitter`, and `protocol_realize` to `v0_frame_realizer`.
- Rename text session state `protocol_v0_sprite_resources` to `v0_sprite_resources` or `v0_frame_sprite_resources`. Stronger recommendation: `v0_sprite_resources` because the type is `SpriteResourceStore` and `session/text.zig:357` stores retained sprite resources, not a frame.

### Host Consumer Names

- Rename public cimport uses according to public ABI replacements: `HOWL_RENDER_API_V0_VERSION`, `frame.api_version`, `diagnostics.v0_frame_emit_status`, and `c.howl_render_prepared_surface_v0_frame()`.
- Rename host prepared probe/plan types from `PreparedProtocolV0Probe` and `PreparedProtocolV0ResourcePlan` to `PreparedV0FrameProbe` and `PreparedV0ResourcePlan`. Evidence: `retained.zig:752-795` probes a prepared handle for a frame and validates resource planning.
- Rename host retained resource types from `ProtocolV0ResourceStore*` to `V0ResourceStore*`, because `retained.zig:184-233` applies create/upload/retire resource lifecycle, not protocol semantics.
- Rename host texture owner `ProtocolV0Textures` to `V0Textures` or `V0FrameTextures`. Stronger recommendation: `V0Textures` because `term_texture.zig:24-80` owns texture slots and diagnostics, while functions consume frames as input.
- Rename host shape helpers from `protocolV0FillOnly`, `protocolV0SpriteFrame`, etc. to `v0FillOnly`, `v0SpriteFrame`, `v0GlyphPatch`, `v0FrameSummary`, etc. These are host-side frame-shape predicates (`term_texture.zig:2198-2455`).
- Rename host upload helpers `uploadProtocolV0*` to `uploadV0*` or `uploadV0Frame*` depending on current definitions outside the read windows. The call sites at `context.zig:659-724` show upload selection by V0 frame shape.
- Rename host diagnostics helpers `recordProtocolV0Realization`, `logProtocolV0Diagnostics`, and related names to `recordV0Realization`, `logV0Diagnostics`, etc. They log V0 frame/texture realization, not protocol state.

## Slice Boundary Judgment

- The public ABI rename and host consumer rename can be one broad implementation slice if the scratchpad allows all affected render ABI, FFI, docs, tests, and host consumer files together. This is source-backed because the public C ABI names are used immediately by render FFI assertions and host cimports; changing only the header/export or only the host would break builds.
- Staging without compatibility shims is possible only at build-boundary granularity, not by preserving old aliases. Example staging: first rename all render public ABI, FFI, render tests, docs, and the host cimport call/field/macro uses in one slice; then a follow-up host-internal-only cleanup can rename remaining host helper/type/test names if the first slice intentionally permits temporary host-internal `protocol` names. However, that would not satisfy the user's complete deletion goal until the follow-up lands.
- For complete deletion proven by a grep gate, prefer one broad slice covering render ABI + render FFI/internal names + docs + render tests + host consumers/internal names. The repo has no downstream, and compatibility aliases are banned.
- Stop if the worker needs to choose different public names than this cache proposes. Public ABI vocabulary must be fixed before coding.

## Likely First Implementation Scope

Files likely in scope for a complete first sprint:

- `howl-render/include/howl_render.h`
- `howl-render/src/ffi/protocol_v0.zig` moved to `howl-render/src/ffi/render_api_v0.zig`
- `howl-render/src/libhowl_render.zig`
- `howl-render/src/ffi/prepared_surface.zig`
- `howl-render/src/prepared/owner.zig`
- `howl-render/src/session/text.zig`
- `howl-render/src/prepared/v0_frame_emitter.zig`
- `howl-render/src/render/v0_frame_realizer.zig`
- `howl-render/src/test/unit/render_api_v0_oracle.zig`
- `howl-render/src/test/ffi.zig`
- `docs/render-api-v0.md`
- `howl-linux-host/src/terminal/render/retained.zig`
- `howl-linux-host/src/terminal/context.zig`
- `howl-linux-host/src/window/term_texture.zig`
- Any generated or cimport integration file only if the build reports it as a direct consequence; no generated compatibility aliases.

Tests and assertions that must change but not weaken:

- FFI constant assertion `c.HOWL_RENDER_PROTOCOL_V0_VERSION == 0` at `ffi/protocol_v0.zig:142` must become an assertion for `HOWL_RENDER_API_V0_VERSION`.
- FFI frame mirror field and offset assertion at `ffi/protocol_v0.zig:127-139` and `325-338` must assert `api_version` at the same offset.
- Render realizer version rejection at `v0_frame_realizer.zig:257` and fixture at `1970` must use `api_version` and `HOWL_RENDER_API_V0_VERSION`.
- Render emitter frame construction at `v0_frame_emitter.zig:952` must use `api_version` and `HOWL_RENDER_API_V0_VERSION`.
- FFI tests in `test/ffi.zig:48`, `94`, `312`, `333`, `344-396`, `412`, `421`, and `436` must use renamed diagnostics field, FFI function, version macro, and frame field.
- Render oracle tests in `test/unit/render_api_v0_oracle.zig:8-17`, `861-905`, `937-1014`, and `1060-1062` must use renamed aliases, prepared owner methods, FFI method, and diagnostics field.
- Prepared owner tests around `owner.zig:436-439`, `565`, `635`, and `642-674` must use renamed diagnostics and helper names.
- Host retained tests around `retained.zig:1702-2058`, context tests around `context.zig:1739`, `1777`, `2319`, and texture tests around `term_texture.zig:1004-1932` must rename test strings and assertions without changing behavior.

## Verification And Grep Gates

Build/test verification to define in a scratchpad:

- From `howl-render`: `zig build test:unit`
- From `howl-render`: `zig build test:abi`
- From `howl-render`: `zig build test`
- From `howl-render`: `zig build check`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

Product/source/host grep gates after complete deletion:

- `rg -i 'protocol' howl-render/include howl-render/src howl-render/build.zig docs howl-linux-host/src current.txt` should print nothing except `current.txt` if the scratchpad explicitly excludes workflow history. For a strict complete sprint, update `current.txt` outside the worker slice or exclude it consciously.
- `rg 'protocol_v0|protocolV0|PROTOCOL_V0|render-protocol|howl_render_prepared_surface_protocol_v0|HOWL_RENDER_PROTOCOL_V0_VERSION|protocol_version|protocol_v0_emit_status' howl-render/include howl-render/src docs howl-linux-host/src` prints nothing.
- `rg 'ffi/protocol_v0|src/ffi/protocol_v0|@import\("ffi/protocol_v0\.zig"\)|@import\(".*protocol_v0\.zig"\)' howl-render/src` prints nothing.
- `test ! -e howl-render/src/ffi/protocol_v0.zig`.
- `test -f howl-render/src/ffi/render_api_v0.zig` if the scratchpad accepts that filename.
- Historical records under `research/` should be excluded from product gates unless the scratchpad explicitly chooses history churn.

## Risks

- ABI break risk is intended but must be exact: header, export, FFI mirror, docs, tests, and host cimports must rename as one coherent ABI-product change. No old symbol may remain as an alias.
- Build break risk is high if the header is renamed without host cimport call sites, `@cImport` field users, or FFI layout assertions.
- Layout risk: renaming `protocol_version` to `api_version` must preserve field type, order, size, alignment, and offset. FFI assertions must prove this.
- Diagnostics risk: renaming `protocol_v0_emit_status` to `v0_frame_emit_status` must preserve the status values and error mapping in `prepared/owner.zig:75-80` and `271-282`.
- Host behavior risk: host upload decision flow in `context.zig:615-786` and texture realization in `term_texture.zig:205-2455` should be symbol-only rename. Any behavior change needs a separate host behavior slice.
- Grep false-positive risk: TigerBeetle architecture docs and VT-domain protocol language are unrelated; gates should target render product/source/docs/host paths and exclude `utils/dev_references` and broad root history.

## Stop Conditions

- Stop if public replacement names are not accepted before implementation.
- Stop if any compatibility alias, wrapper export, macro alias, or fallback old field name is proposed.
- Stop if the worker needs to preserve `protocol` in a public ABI symbol to keep host compatibility.
- Stop if the host requires behavior changes beyond cimport and internal symbol/test renames.
- Stop if FFI layout assertions cannot prove the same layout after field rename.
- Stop if grep gates require editing historical `research/` records to pass.
- Stop if `protocol` remains in `howl-render/include`, `howl-render/src`, `docs/render-api-v0.md`, or `howl-linux-host/src` after a slice that claims complete deletion.

## Proof Gaps

- This cache did not run builds or tests; it is research-only.
- `term_texture.zig` has additional `ProtocolV0`/`protocolV0` definitions outside the read windows found by grep, including upload helpers and `unpackProtocolV0Rgba()`. The occurrence classes are clear, but a worker scratchpad should either list every helper definition or allow the whole file for symbol-only rename.
- `context.zig` grep reported 141 `ProtocolV0|protocolV0|protocol_v0|protocol v0|PROTOCOL_V0` matches; this cache groups them by owner ranges, not one row per call site.
- `retained.zig` grep reported 337 `ProtocolV0|protocolV0|protocol_v0|protocol v0|PROTOCOL_V0` matches; this cache groups them by owner ranges, not one row per call site.

## Readiness Judgment

Scratchpad-ready: yes, if the scratchpad accepts the public ABI replacement vocabulary above exactly.

The evidence is strong enough for a broad ABI-product deletion slice with no compatibility aliases. If the main agent wants a narrower first slice, it must explicitly mark it incomplete and must not claim the banned render `protocol` language is deleted until the host/internal follow-up and grep gates pass.
