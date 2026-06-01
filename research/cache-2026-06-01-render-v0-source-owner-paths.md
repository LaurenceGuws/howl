# Render V0 Source Owner Paths Research Cache

Date: 2026-06-01

Owner: research cache only. This is not a scratchpad, not `current.txt`, and not an implementation.

## Sources Read In Order

1. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
3. `AGENTS.md`
4. `loop.txt`
5. `current.txt`
6. `research/cache-2026-06-01-render-api-language-deletion.md`
7. `research/2026-06-01-render-api-language-deletion-sprint.md`
8. Current `howl-render/src/**/*.zig` inventory by glob.
9. Current `howl-render/src` grep inventory for `protocol_v0`, `protocol v0`, `render_api_v0`, `V0`, `realize`, `emitPrepared`, and `protocolV0Frame`.
10. Current `howl-render/build.zig`.
11. Current `howl-render` recent commit log.

## Governing Evidence

- `TIGER_STYLE.md:273-289` requires exact nouns and verbs. Replacement paths must name the concrete owner behavior, not preserve `protocol` as an internal bucket.
- `TIGER_STYLE.md:315-335` says order and naming matter for readability and top-down review. A source move should make imports point at the true owner path.
- `TIGER_STYLE.md:96-140` requires explicit bounds, assertions, and negative tests. The source-bucket deletion must preserve existing emitter, realizer, oracle, and ABI layout tests.
- `AGENTS.md:9-15` says ABIs are the product and Howl owns render ABI contracts and consequences.
- `AGENTS.md:95-103` says `howl-render` owns render contracts, retained-frame state, prepare/submit scheduling, render-surface contracts, and text shaping.
- `AGENTS.md:105-116` says public roots curate exports, namespace wrappers aggregate owners only, owner files own state and mutation, FFI translates contracts only, and behavior moves toward the smallest true owner.
- `loop.txt:28-36` says Researcher produces research cache only and does not edit product code.
- `loop.txt:133-145` hard-stops if workers need to invent owner names or if public ABI changes appear without an ABI-product slice.
- `current.txt:20-24` says this stage exists only to produce evidence for deleting `howl-render/src/protocol_v0/` as an internal source bucket, and authorizes no product code.
- `current.txt:28-34` asks exactly for replacement owner paths, FFI move decision, import/test changes, and grep gates.
- `research/2026-06-01-render-api-language-deletion-sprint.md:18-20` says this sprint does not authorize public ABI renames.
- `research/2026-06-01-render-api-language-deletion-sprint.md:210-239` defines Slice 3 as deleting `src/protocol_v0/`, preserving public ABI symbols and behavior, moving `emit.zig` and `realize.zig` to noun-owner paths, and updating imports only.
- `research/2026-06-01-render-api-language-deletion-sprint.md:240-248` requires `zig build test:unit`, `zig build test:abi`, `zig build test`, `zig build check`, `git diff --check`, and a grep gate proving no `src/protocol_v0` imports remain.

## Current Post-Commit Facts

- `howl-render` recent commit log shows `aa1749d render: move v0 oracle tests under unit` and `6bf6388 render: delete protocol proof test bucket` are present.
- `howl-render/build.zig:37-60` now wires only `unit_mod` from `src/test_unit.zig` and `test:unit`.
- `howl-render/build.zig:61-83` wires `abi_mod` from `src/test_abi.zig` and `test:abi`.
- `howl-render/build.zig:85-99` defines `test`, `test:build`, `test:unit`, and `test:abi`; there is no `test:protocol-proof` or `protocol_proof` build bucket after `6bf6388`.
- `howl-render/src/test_unit.zig:1-3` imports `test/unit/root.zig` for unit discovery.
- `howl-render/src/test.zig:3-7` imports both FFI tests and `test/unit/root.zig` for aggregate test discovery.
- `howl-render/src/test_abi.zig:3-6` imports `libhowl_render.zig` and `test/ffi.zig` for ABI testing.
- `howl-render/src/test/unit/root.zig:1-6` still imports `../../protocol_v0/realize.zig`, `../../protocol_v0/emit.zig`, `geometry.zig`, and `render_api_v0_oracle.zig`.
- `howl-render/src/test/unit/render_api_v0_oracle.zig:8-9` still imports `../../protocol_v0/emit.zig` and `../../protocol_v0/realize.zig`.
- Current grep found only source-path bucket imports in these product/test files: `src/test/unit/root.zig`, `src/test/unit/render_api_v0_oracle.zig`, `src/session/text.zig`, `src/ffi/protocol_v0.zig`, and `src/prepared/owner.zig`.

## Emit Owner Evidence

Current file: `howl-render/src/protocol_v0/emit.zig`.

- `emit.zig:4-10` imports FFI C ABI types, text contract, geometry contract, `prepared/surface.zig`, local `realize.zig`, text types, and `session/text.zig`. The import set is render/prepared/text emission, not generic protocol ownership.
- `emit.zig:12-16` aliases public ABI V0 frame structs and exports `Frame = c.HowlRenderV0Frame`; the file emits a public V0 frame payload.
- `emit.zig:17-33` declares V0 emission/resource bounds with compile-time assertions against public ABI maxima.
- `emit.zig:35-67` defines emission errors and limits; this is bounded frame construction.
- `emit.zig:69-97` defines fill/sprite/prepared-sprite emission input shapes.
- `emit.zig:99-177` defines `SpriteResourceStore`, including retained sprite entries, retained bytes, resource id sequence, glyph atlas resource, atlas entries, and atlas packing cursors.
- `emit.zig:175-224` implements persistent/transient/reused sprite resource selection from prepared sprite data.
- `emit.zig:226-255` implements alpha atlas region allocation and upload/create status.
- `emit.zig:340-359` defines `Emitter` frame storage arrays for damage, creates, uploads, commands, glyphs, retires, upload bytes, counters, and frame storage.
- `emit.zig:371-383` has legacy fixture `emit()` for synthetic fixtures, but this is used by file-local tests and oracle helper coverage, not a host-facing owner path.
- `emit.zig:385-404` defines `emitPrepared()`, which emits a V0 frame from `prepared_surface.PreparedSurface`, mutates `SpriteResourceStore` only after successful staging, publishes frame storage, and returns `*const Frame`.
- `emit.zig:421-439` resets prepared frame metadata from prepared-surface token, render pixel size, cell size, and grid.
- `emit.zig:469-550` emits prepared clear/background/decoration/cursor fill commands.
- `emit.zig:591-689` emits prepared sprite commands, glyph atlas creates/uploads, persistent/transient sprite resources, and transient retires.
- `emit.zig:1204-1208` uses `realize.realize()` only for test oracle helper `realizeFixture()`.
- `emit.zig:1210-1489` contains file-local unit tests for V0 emitter frame emission, bounds, errors, and alpha atlas exhaustion.
- `prepared/owner.zig:8` imports the emitter from `../protocol_v0/emit.zig`.
- `prepared/owner.zig:37-43` stores the emitted V0 payload as `const V0Payload = protocol_v0_emit.Emitter(.{})` and `v0_payload` on the prepared owner.
- `prepared/owner.zig:65-82` emits the V0 payload during prepared owner creation and maps emission errors to diagnostics.
- `prepared/owner.zig:144-153` exposes the prepared owner's `protocolV0Frame()` and test-only frame accessor.
- `prepared/owner.zig:231-242` calls `payload.emitPrepared(&self.session_owner.protocol_v0_sprite_resources, &self.session_owner.session, &self.prepared)`.
- `prepared/owner.zig:271-282` maps every internal emitter error to public `HOWL_RENDER_V0_EMIT_*` diagnostics.
- `session/text.zig:342-358` shows `TextSessionOwner` stores `protocol_v0_sprite_resources: protocol_v0_emit.SpriteResourceStore = .init()`, so the emitter owns the resource-store type while the session owner owns the retained state instance.

### Proposed Emit Replacement Path

`howl-render/src/prepared/v0_frame_emitter.zig`

Reasoning:

- `prepared` is source-backed by the call owner: `prepared/owner.zig:37-43`, `65-82`, `144-153`, and `231-242` allocate, expose, and release the emitted V0 payload as part of prepared-surface handle lifecycle.
- `v0_frame` is source-backed by `emit.zig:12-16`, `340-359`, and `385-404`, which build and publish `c.HowlRenderV0Frame` storage.
- `emitter` is source-backed by the public internal type name `Emitter` at `emit.zig:340` and by `emitPrepared()` at `emit.zig:385-404`.
- This path does not invent a vague bucket such as `api`, `protocol`, `common`, `utils`, `manager`, `engine`, or `controller`.
- This path preserves public ABI spelling. Internal aliases may keep local public ABI names such as `Frame = c.HowlRenderV0Frame` because those are ABI vocabulary, not source-bucket ownership.

Rejected alternatives:

- `src/protocol_v0/emit.zig`: preserves the blocked internal bucket.
- `src/render_api_v0/emit.zig` or `src/api/v0_emit.zig`: uses the vague `api` bucket explicitly banned by the sprint constraints.
- `src/render/v0_frame_emitter.zig`: source-backed enough as render contract emission, but weaker than `prepared/` because the active product call path and payload lifetime are owned by `prepared/owner.zig`.

## Realize Owner Evidence

Current file: `howl-render/src/protocol_v0/realize.zig`.

- `realize.zig:3-12` imports only public FFI C ABI V0 frame component types. This file consumes/validates a public V0 frame layout.
- `realize.zig:17-39` defines `ResourceStore`, a retained V0 resource store for software realization.
- `realize.zig:40-53` commits frame creates/uploads/retires into retained resources.
- `realize.zig:55-109` validates retained resource transition bounds, duplicates, uploads, and retires before mutation.
- `realize.zig:179-194` declares realization/validation errors.
- `realize.zig:196-207` exposes `realize()` and `realizeRetained()` for stateless and retained software realization.
- `realize.zig:209-254` validates the frame, copies or clears the pixel base, draws commands in order, and commits retained resource mutations only after validation and drawing.
- `realize.zig:256-263` validates frame version, damage, create, retire, upload, and command spans.
- `realize.zig:265-380` starts explicit validation of damage/create/upload spans against public ABI maxima and resource rules.
- `realize.zig:1020-1032` bounds pixel buffer length and pixel indexing.
- `realize.zig:1046-1951` contains file-local unit tests for constants, realizer behavior, negative validation, retained resource mutation, sequencing, upload totals, and coordinate clipping.
- `test/unit/render_api_v0_oracle.zig:8-9` imports the emitter and realizer together for oracle/equivalence tests.
- `test/unit/render_api_v0_oracle.zig:20-44`, `111-137`, `309-335`, `336-365`, `809-829`, `830-944`, and later tests compare emitted/prepared frames against software RGBA oracle behavior.
- `ffi/protocol_v0.zig:349-351` imports the realizer only in a test block, so ABI layout assertions remain independent of runtime behavior.

### Proposed Realize Replacement Path

`howl-render/src/render/v0_frame_realizer.zig`

Reasoning:

- `render` is source-backed by `AGENTS.md:95-101`, which assigns `howl-render` ownership of render contracts, retained-frame state, prepare/submit scheduling, render-surface contracts, and text shaping.
- The file realizes and validates `HowlRenderV0Frame` render contracts, not prepared owner lifecycle. Evidence: `realize.zig:196-254` and `256-380` operate on `Frame`, spans, commands, resources, and pixels.
- `v0_frame` is source-backed by `realize.zig:3-12`, `196-207`, and `256-263`, which consume public V0 frame ABI structures.
- `realizer` is source-backed by exported internal function names `realize()` and `realizeRetained()` at `realize.zig:196-207` and by test names at `realize.zig:1061`, `1074`, `1087`, and many later tests.
- This path matches existing `src/render/` ownership for render contracts/geometry/tokens and avoids creating a new vague bucket.

Rejected alternatives:

- `src/protocol_v0/realize.zig`: preserves the blocked internal bucket.
- `src/test/unit/render_api_v0_realizer.zig`: too narrow because `emit.zig:1204-1208` uses the realizer for file-local emitter oracle tests and `ffi/protocol_v0.zig:349-351` imports it in ABI test discovery. A test path would make product owner files import test owner code or force a broader test split outside this slice.
- `src/prepared/v0_frame_realizer.zig`: weaker ownership because the realizer validates/draws arbitrary V0 frames and retained resources, not only prepared-owner payloads.
- `src/render_api_v0/realize.zig` or `src/api/v0_realize.zig`: uses the vague `api` bucket banned by the sprint constraints.

## FFI ABI Boundary Decision

`howl-render/src/ffi/protocol_v0.zig` should remain in place for this slice, with only its test import updated from the old realizer path to `../render/v0_frame_realizer.zig`.

Evidence:

- `ffi/protocol_v0.zig:1-7` is a compile-time ABI mirror/assertion wrapper.
- `ffi/protocol_v0.zig:9-139` defines `extern struct` mirrors for public `HowlRenderV0*` layouts.
- `ffi/protocol_v0.zig:141-167` asserts public V0 constants, including `HOWL_RENDER_PROTOCOL_V0_VERSION` and `HOWL_RENDER_V0_*` values.
- `ffi/protocol_v0.zig:169-338` asserts ABI struct sizes, alignments, and offsets against public C ABI types.
- `ffi/protocol_v0.zig:349-351` is only a test block import of the internal realizer.
- `libhowl_render.zig:8`, `11`, and `37` import this FFI owner and export the public symbol `howl_render_prepared_surface_protocol_v0`.
- `test/ffi.zig:48`, `94`, `312`, and `333` assert public `protocol_v0_emit_status` ABI diagnostics/offset behavior.

Reasoning:

- FFI files translate contracts only per `AGENTS.md:105-116`; this file is exactly the ABI-layout assertion owner.
- Moving or renaming `ffi/protocol_v0.zig` in Slice 3 would conflate internal source-bucket deletion with an FFI owner/file rename. The public ABI still contains `protocol_v0` vocabulary, and this sprint explicitly preserves public ABI symbols.
- Keeping the FFI file avoids implying that public `HOWL_RENDER_PROTOCOL_V0_VERSION`, `HowlRenderV0*`, diagnostics fields, or exported symbol names are renamed.
- The source-bucket deletion does not require moving this file because it is not under `src/protocol_v0/`.

Stop condition:

- If a worker wants to rename `ffi/protocol_v0.zig`, stop and require a separate ABI/FFI naming slice with explicit public ABI preservation rules and reviewer acceptance.

## Import And Test Inventory For Slice 3

Allowed source moves:

- Move `howl-render/src/protocol_v0/emit.zig` to `howl-render/src/prepared/v0_frame_emitter.zig`.
- Move `howl-render/src/protocol_v0/realize.zig` to `howl-render/src/render/v0_frame_realizer.zig`.
- Delete the now-empty `howl-render/src/protocol_v0/` directory.

Required import updates:

- `howl-render/src/prepared/owner.zig:8` from `@import("../protocol_v0/emit.zig")` to `@import("v0_frame_emitter.zig")`.
- `howl-render/src/session/text.zig:16` from `@import("../protocol_v0/emit.zig")` to `@import("../prepared/v0_frame_emitter.zig")`.
- `howl-render/src/test/unit/root.zig:2` from `@import("../../protocol_v0/realize.zig")` to `@import("../../render/v0_frame_realizer.zig")`.
- `howl-render/src/test/unit/root.zig:3` from `@import("../../protocol_v0/emit.zig")` to `@import("../../prepared/v0_frame_emitter.zig")`.
- `howl-render/src/test/unit/render_api_v0_oracle.zig:8` from `@import("../../protocol_v0/emit.zig")` to `@import("../../prepared/v0_frame_emitter.zig")`.
- `howl-render/src/test/unit/render_api_v0_oracle.zig:9` from `@import("../../protocol_v0/realize.zig")` to `@import("../../render/v0_frame_realizer.zig")`.
- `howl-render/src/ffi/protocol_v0.zig:350` from `@import("../protocol_v0/realize.zig")` to `@import("../render/v0_frame_realizer.zig")`.
- Inside moved `prepared/v0_frame_emitter.zig`, update its local realizer import from `@import("realize.zig")` at old `emit.zig:8` to `@import("../render/v0_frame_realizer.zig")`.
- Inside moved `prepared/v0_frame_emitter.zig`, update imports that were relative to `src/protocol_v0/`: old `emit.zig:4-7` and `9-10` use `../` paths and remain valid from `src/prepared/` only where appropriate: `../ffi.zig`, `../text/contract.zig`, `../render/geometry_contract.zig`, `surface.zig`, `../text/text.zig`, and `../session/text.zig`.
- Inside moved `render/v0_frame_realizer.zig`, old `realize.zig:3` `@import("../ffi.zig")` remains valid from `src/render/`.

Required tests preserved under `zig build test:unit`:

- File-local emitter tests move with `prepared/v0_frame_emitter.zig`: old `emit.zig:1210-1489`.
- File-local realizer tests move with `render/v0_frame_realizer.zig`: old `realize.zig:1046-1951`.
- Oracle/equivalence tests remain in `howl-render/src/test/unit/render_api_v0_oracle.zig`; its imports update only. Examples: `render_api_v0_oracle.zig:20-44`, `46-77`, `111-137`, `366-428`, `830-944`, `945-1020`.
- Unit root continues importing both moved owner files so file-local tests are discovered: current `test/unit/root.zig:1-6`.

Required tests preserved under `zig build test:abi`:

- `howl-render/src/test_abi.zig:3-6` remains unchanged.
- `howl-render/src/ffi/protocol_v0.zig:1-338` ABI layout assertions remain unchanged.
- `howl-render/src/ffi/protocol_v0.zig:349-351` updates only the test import path to the moved realizer.
- Public ABI diagnostics tests in `howl-render/src/test/ffi.zig:48`, `94`, `312`, and `333` remain unchanged.

No build.zig change is required for Slice 3:

- `build.zig:37-60` discovers unit tests through `src/test_unit.zig` and imports, not through explicit source file paths to `protocol_v0`.
- `build.zig:61-83` discovers ABI tests through `src/test_abi.zig` and imports.
- `build.zig:85-99` already has no protocol-proof step after `6bf6388`.

## Grep And Verification Gates

Verification commands for worker slice:

- From `howl-render`: `zig build test:unit`
- From `howl-render`: `zig build test:abi`
- From `howl-render`: `zig build test`
- From `howl-render`: `zig build check`
- From `howl-render`: `git diff --check`

Source-bucket deletion grep gates:

- From workspace root: `rg 'src/protocol_v0|\.\./protocol_v0|protocol_v0/' howl-render/src` prints nothing.
- From workspace root: `rg 'protocol_v0/(emit|realize)\.zig' howl-render/src` prints nothing.
- From workspace root: `rg '@import\("\.\./protocol_v0/|@import\("\.\./\.\./protocol_v0/' howl-render/src` prints nothing.
- From workspace root: `rg 'test:protocol-proof|protocol_proof|test_protocol_proof' howl-render/build.zig howl-render/src` prints nothing.

Allowed public ABI vocabulary grep gates:

- From workspace root: `rg 'HOWL_RENDER_PROTOCOL_V0_VERSION|HOWL_RENDER_V0_|HowlRenderV0|howl_render_prepared_surface_protocol_v0|protocol_v0_emit_status' howl-render/include howl-render/src/ffi howl-render/src/libhowl_render.zig howl-render/src/test/ffi.zig howl-render/src/prepared/owner.zig howl-render/src/ffi/prepared_surface.zig` may print matches because public ABI names are preserved.
- `@import("ffi/protocol_v0.zig")` and `src/ffi/protocol_v0.zig` remain allowed ABI-owner vocabulary in this slice.
- From workspace root: `rg 'protocol_v0' howl-render/src` may still print public ABI field/function/file vocabulary in `src/ffi/protocol_v0.zig`, `src/libhowl_render.zig`, `src/ffi/prepared_surface.zig`, `src/prepared/owner.zig`, `src/session/text.zig`, and tests that assert public ABI fields. It must not print source path imports or `protocol_v0/` directory references.

Directory/file existence gates:

- From workspace root: `test ! -d howl-render/src/protocol_v0`
- From workspace root: `test -f howl-render/src/prepared/v0_frame_emitter.zig`
- From workspace root: `test -f howl-render/src/render/v0_frame_realizer.zig`

## Risks

- Import-cycle risk: moving the emitter under `prepared/` preserves the existing conceptual cycle between session/prepared/emitter. The current code already has `session/text.zig:5` importing `prepared/owner.zig`, `session/text.zig:16` importing the emitter, and `prepared/owner.zig:8-9` importing the emitter and session owner. The move should update paths only and must not add new behavior or state ownership.
- Test-discovery risk: if `test/unit/root.zig` does not import both moved owner files, file-local emitter and realizer tests may silently fall out of `zig build test:unit`.
- ABI drift risk: public V0 names must remain unchanged. `ffi/protocol_v0.zig` must remain the layout assertion owner in this slice.
- Over-cleanup risk: internal variable names such as `protocol_v0_emit_status`, `protocolV0Frame()`, and public ABI test names may look stale, but renaming them is not part of Slice 3 because they touch public ABI vocabulary or behavior-facing prepared owner API.
- Product/test boundary risk: moving the realizer under `test/unit/` would force product owner files or ABI test imports to depend on test paths. Use `render/v0_frame_realizer.zig` instead.

## Stop Conditions

- Stop if a worker needs to invent any owner path other than `prepared/v0_frame_emitter.zig` and `render/v0_frame_realizer.zig`.
- Stop if public C ABI symbols, header names, exported symbol names, or host behavior change.
- Stop if `ffi/protocol_v0.zig` is renamed or moved in this slice.
- Stop if `howl-render/build.zig` needs modification; current post-`6bf6388` build wiring should not require it.
- Stop if `zig build test:unit` loses file-local emitter/realizer tests or oracle/equivalence tests.
- Stop if source grep still finds `src/protocol_v0`, `../protocol_v0`, or `protocol_v0/` under `howl-render/src` after the move.
- Stop if a compatibility shim or re-export file is added to `src/protocol_v0/`.

## Readiness Judgment

Worker-ready: yes.

Exact allowed files for Slice 3:

- `howl-render/src/protocol_v0/emit.zig` moved to `howl-render/src/prepared/v0_frame_emitter.zig`.
- `howl-render/src/protocol_v0/realize.zig` moved to `howl-render/src/render/v0_frame_realizer.zig`.
- `howl-render/src/prepared/owner.zig` import-only update.
- `howl-render/src/session/text.zig` import-only update.
- `howl-render/src/test/unit/root.zig` import-only update.
- `howl-render/src/test/unit/render_api_v0_oracle.zig` import-only update.
- `howl-render/src/ffi/protocol_v0.zig` test import-only update.

Exact non-goals:

- No public ABI renames.
- No host changes.
- No build step changes.
- No test deletion or filtering.
- No compatibility shim under `src/protocol_v0/`.
