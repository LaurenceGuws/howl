# Render API Language Deletion Research Cache

Date: 2026-06-01

Owner: research cache only. This is not a scratchpad, not `current.txt`, and not an implementation plan.

## Sources Read In Order

1. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
3. `AGENTS.md`
4. `loop.txt`
5. `current.txt`
6. `research/2026-05-31-howl-render-protocol-sprint.md` as stale historical context only.
7. `research/2026-05-30-hygiene-audit/render-test-build-coverage.md`
8. `research/2026-05-30-hygiene-audit/render-surface-taxonomy.md`
9. Current source/build/docs/host files listed in the inventory below.

## Governing Facts

- `AGENTS.md:9-15` says the ABIs are the product and Howl owns render ABI contracts and consequences.
- `AGENTS.md:95-101` says `howl-render` owns render contracts, geometry policy, retained-frame state, prepare/submit scheduling, render-surface contracts, and text shaping.
- `AGENTS.md:105-116` says public roots curate exports, namespace wrappers aggregate owners only, owner files own state and mutation, FFI translates contracts only, and behavior moves toward the smallest true owner.
- `AGENTS.md:151-165` and `loop.txt:1-24` separate research, scratchpad, current slice, and code work.
- `TIGER_STYLE.md:273-289` requires exact nouns and verbs. `protocol` as a render internal bucket is suspect because it does not name the concrete owner state or mutation.
- `TIGER_STYLE.md:96-140` requires explicit bounds, assertions, and exhaustive negative tests. Any deletion must preserve these gates in the unified render API test path.

## Inventory Scope And Method

Searched these current paths for `protocol_v0`, `protocol_proof`, `test:protocol-proof`, `render-protocol`, and `protocol v0`:

- `howl-render/`
- `howl-linux-host/src/`
- `docs/`
- root `build.zig`
- `current.txt`

The search found 372 relevant current occurrences. This cache groups consecutive and same-purpose occurrences by exact file and exact line numbers or ranges.

## Source-Backed Inventory

### Active Current Slice References

- `current.txt:21-23` lists `howl-render/src/ffi/protocol_v0.zig`, `howl-render/src/protocol_v0/realize.zig`, and `howl-render/src/test_protocol_proof.zig` in an active slice allowlist.
- `current.txt:29` lists `docs/render-protocol-v0.md`.
- `current.txt:70-71` requires `zig build test:unit -- "protocol v0"` and `zig build test:protocol-proof -- "protocol v0"`. These are stale against the user's stated gate.

### Root Build And Docs

- Root `build.zig`: no current match for the searched render protocol terms.
- `docs/render-protocol-v0.md:9` uses `howl-render-protocol` as document title vocabulary.
- `docs/render-protocol-v0.md:30` names the public ABI function `howl_render_prepared_surface_protocol_v0()`.

### Render Build Bucket

- `howl-render/build.zig:56-69` creates `protocol_proof_mod` rooted at `src/test_protocol_proof.zig`.
- `howl-render/build.zig:70-77` creates and configures `protocol_proof_tests` and `run_protocol_proof_tests`.
- `howl-render/build.zig:109-116` declares `test:protocol-proof` and `test:protocol-proof:build` steps.
- `howl-render/build.zig:121-122` wires the build and run steps for protocol proof.
- `howl-render/build.zig:126` makes `test:build` depend on `test_protocol_proof_build_step`.
- `howl-render/build.zig:129` makes `test` depend on `test_protocol_proof_step`.

### Public Render ABI Product Names

- `howl-render/include/howl_render.h:19-31` declares public V0 constants such as `HOWL_RENDER_PROTOCOL_V0_VERSION` and V0 bounds.
- `howl-render/include/howl_render.h:33-44` declares public V0 damage/resource/upload/command kind macros.
- `howl-render/include/howl_render.h:54-65` declares public `HowlRenderV0EmitStatus` values.
- `howl-render/include/howl_render.h:184-314` declares public `HowlRenderV0*` ABI structs.
- `howl-render/include/howl_render.h:520` exposes `protocol_v0_emit_status` in public prepared diagnostics.
- `howl-render/include/howl_render.h:644-646` exposes `howl_render_prepared_surface_protocol_v0()`.

### Render FFI Product Translation

- `howl-render/src/ffi/protocol_v0.zig:1-7` is a compile-time C ABI mirror wrapper.
- `howl-render/src/ffi/protocol_v0.zig:9-139` defines internal `extern struct` mirrors for public `HowlRenderV0*` structs.
- `howl-render/src/ffi/protocol_v0.zig:141-167` asserts public V0 constants.
- `howl-render/src/ffi/protocol_v0.zig:169-338` asserts layout and offsets for public V0 structs.
- `howl-render/src/ffi/protocol_v0.zig:349-351` imports `../protocol_v0/realize.zig` through an unfiltered test block.
- `howl-render/src/ffi/prepared_surface.zig:46-59` translates the public `howl_render_prepared_surface_protocol_v0()` call to `Owner.protocolV0Frame()`.
- `howl-render/src/ffi/prepared_surface.zig:109-127` maps `protocol_v0_emit_status` into public diagnostics.
- `howl-render/src/libhowl_render.zig:8`, `11`, and `37` import the FFI mirror and export `howl_render_prepared_surface_protocol_v0`.

### Render Internal Bucket Occurrences

- `howl-render/src/protocol_v0/emit.zig:1-1489` is the render-side V0 frame emitter and resource store. The path is a stale internal bucket name.
- `howl-render/src/protocol_v0/emit.zig:12-16` aliases public ABI V0 structs and `Frame`.
- `howl-render/src/protocol_v0/emit.zig:17-33` declares emitter/resource bounds and compile-time assertions.
- `howl-render/src/protocol_v0/emit.zig:35-67` declares emitter errors and limits.
- `howl-render/src/protocol_v0/emit.zig:69-97` names fill/sprite/prepared-sprite emission inputs.
- `howl-render/src/protocol_v0/emit.zig:99-177` defines `SpriteResourceStore`, which owns renderer-side persistent sprite resources, bytes, atlas resource, atlas entries, packing cursors, and resource IDs.
- `howl-render/src/protocol_v0/emit.zig:175-260` shows `resourceFor()` and atlas allocation are resource ownership, not generic protocol ownership.
- `howl-render/src/protocol_v0/emit.zig:1210-1454` contains unit tests named `protocol v0 emitter ...`.
- `howl-render/src/protocol_v0/realize.zig:1-2207` is an internal software realizer/oracle and retained resource validator. The path is a stale internal bucket name.
- `howl-render/src/protocol_v0/realize.zig:17-177` defines `ResourceStore`, which owns retained V0 resource entries and uploaded bytes for software realization.
- `howl-render/src/protocol_v0/realize.zig:179-194` declares realizer errors.
- `howl-render/src/protocol_v0/realize.zig:196-254` realizes a frame into pixels and optionally mutates retained resources.
- `howl-render/src/protocol_v0/realize.zig:256-360` starts frame/damage/create/retire/upload validation.
- `howl-render/src/protocol_v0/realize.zig:1046-1951` contains unit tests named `protocol v0 realizer ...` and `protocol v0 rejects ...`.

### Render Prepared Owner And Session Occurrences

- `howl-render/src/prepared/owner.zig:8` imports `../protocol_v0/emit.zig`.
- `howl-render/src/prepared/owner.zig:31-35` includes `protocol_v0_emit_status` in prepared diagnostics.
- `howl-render/src/prepared/owner.zig:37-58` stores `v0_payload` and `protocol_v0_emit_status` on the prepared owner.
- `howl-render/src/prepared/owner.zig:75-80` emits the V0 payload on prepared-owner creation and maps errors.
- `howl-render/src/prepared/owner.zig:144-153` exposes `protocolV0Frame()` and `protocolV0FrameForTest()`.
- `howl-render/src/prepared/owner.zig:155-159` exposes a test-only V0 payload storage check.
- `howl-render/src/prepared/owner.zig:161-166` returns diagnostics containing V0 emit status.
- `howl-render/src/prepared/owner.zig:231-242` emits the payload using `session_owner.protocol_v0_sprite_resources`.
- `howl-render/src/prepared/owner.zig:271-282` maps every internal emitter error to public ABI diagnostics.
- `howl-render/src/prepared/owner.zig:439`, `565`, `635`, and `639` are tests/assertions around `protocol_v0_emit_status` and error mapping.
- `howl-render/src/session/text.zig:16` imports `../protocol_v0/emit.zig`.
- `howl-render/src/session/text.zig:357` stores `protocol_v0_sprite_resources` on `TextSessionOwner`.

### Render Unit And FFI Test Occurrences

- `howl-render/src/test/unit.zig:5-8` imports `../protocol_v0/realize.zig` and `../protocol_v0/emit.zig`, so `zig build test:unit` already discovers these tests.
- `howl-render/src/test/ffi.zig:48`, `63-74`, `94`, `312`, `333`, `338`, `354`, `366`, `381`, and `403` test public V0 diagnostics/status and the prepared-surface V0 FFI call.

### Separate Protocol Proof Test Bucket

- `howl-render/src/test_protocol_proof.zig:8-9` imports `protocol_v0/emit.zig` and `protocol_v0/realize.zig`.
- `howl-render/src/test_protocol_proof.zig:14-18` asserts the proof target imports the owner oracle.
- `howl-render/src/test_protocol_proof.zig:20`, `46`, `79`, `111`, `138`, `177`, `228`, `269`, `309`, `336`, `366`, `429`, `487`, `548`, `609`, `649`, `689`, `730`, `767`, `809`, `830`, `876`, `909`, `945`, `970`, `1000`, and `1020` are distinct tests named `protocol v0 ...`.
- `howl-render/src/test_protocol_proof.zig:995`, `1014`, and `1060` assert `protocol_v0_emit_status` outcomes.

### Linux Host Consumption Occurrences

- `howl-linux-host/src/terminal/render/retained.zig:66-72` stores `protocol_v0_probe`, `protocol_v0_resource_plan`, and `protocol_v0_frame` on prepared uploads.
- `howl-linux-host/src/terminal/render/retained.zig:78-106` defines `PreparedProtocolV0ResourcePlan` and its status enum.
- `howl-linux-host/src/terminal/render/retained.zig:108-124` defines host V0 resource store and backend operation status/kinds.
- `howl-linux-host/src/terminal/render/retained.zig:126-181` records backend create/upload/retire operations.
- `howl-linux-host/src/terminal/render/retained.zig:184-416` defines the host retained `ProtocolV0ResourceStore`.
- `howl-linux-host/src/terminal/render/retained.zig:418-502` validates command shapes, spans, and resource operation order.
- `howl-linux-host/src/terminal/render/retained.zig:504-538` defines `PreparedProtocolV0Probe` and status.
- `howl-linux-host/src/terminal/render/retained.zig:540-555` stores V0 probe/resource-plan counters on host retained render state.
- `howl-linux-host/src/terminal/render/retained.zig:752-767` fills `PreparedUpload` and calls `probePreparedProtocolV0()`.
- `howl-linux-host/src/terminal/render/retained.zig:770-795` calls public ABI `howl_render_prepared_surface_protocol_v0()`.
- `howl-linux-host/src/terminal/render/retained.zig:797-817` records V0 probe/resource-plan counters.
- `howl-linux-host/src/terminal/render/retained.zig:880-920` begins V0 probe validation against prepared-surface info and public bounds.
- `howl-linux-host/src/terminal/render/retained.zig:1702`, `1720`, `1754`, `1798`, `1814`, `1836`, `1853`, `1873`, and `1923` are host retained render tests named around protocol V0.
- `howl-linux-host/src/terminal/render/retained.zig:1816-1833`, `1914-1919`, and `2053-2058` assert V0 probe/resource counters.
- `howl-linux-host/src/terminal/context.zig:82-122` defines `ProtocolV0SubmitDiagnostics` and V0 counters.
- `howl-linux-host/src/terminal/context.zig:128-130` stores `protocol_v0_textures` and submit diagnostics.
- `howl-linux-host/src/terminal/context.zig:171-173` initializes those fields.
- `howl-linux-host/src/terminal/context.zig:196` deinitializes `protocol_v0_textures`.
- `howl-linux-host/src/terminal/context.zig:615-657` performs host V0 resource realization and command upload.
- `howl-linux-host/src/terminal/context.zig:659-724` selects V0 sprite/glyph/fill frame or patch upload paths.
- `howl-linux-host/src/terminal/context.zig:726-779` records unsupported-shape and missing-sidecar diagnostics.
- `howl-linux-host/src/terminal/context.zig:781-785` gates realization on `protocol_v0_frame != null`.
- `howl-linux-host/src/terminal/context.zig:931-940`, `944-956`, `962-967`, and `1012-1013` record/log V0 timing and diagnostics.
- `howl-linux-host/src/terminal/context.zig:1739`, `1777`, and `2319` are context tests named around protocol V0 diagnostics/gates.
- `howl-linux-host/src/window/term_texture.zig:1004`, `1019`, `1034`, `1062`, `1069`, `1114`, `1132`, `1159`, `1164`, `1191`, `1233`, `1261`, `1278`, `1306`, `1323`, `1340`, `1356`, `1383`, `1399`, `1427`, `1453`, `1481`, `1519`, `1549`, `1589`, `1613`, `1652`, `1692`, `1741`, `1770`, `1809`, `1840`, `1910`, and `1932` are host texture tests named around protocol V0.

## Public ABI/Product Names Versus Internal Bucket Names

Public ABI/product names that cannot be assumed safe to rename in the same slice:

- `HOWL_RENDER_PROTOCOL_V0_VERSION`, `HOWL_RENDER_V0_*`, `HowlRenderV0*`, `HowlRenderV0EmitStatus`, `HowlRenderPreparedSurfaceDiagnostics.protocol_v0_emit_status`, and `howl_render_prepared_surface_protocol_v0()` in `howl-render/include/howl_render.h:19-65`, `184-314`, `520`, and `644-646`.
- FFI mirror/layout assertions in `howl-render/src/ffi/protocol_v0.zig:9-338` because they prove the shipped C ABI layout.
- Host consumption of those public ABI symbols in `howl-linux-host/src/terminal/render/retained.zig:782-783`, `888`, `898-927`, and throughout host validation/upload code.

Internal bucket/test/build/doc names that are stale candidates:

- Source folder `howl-render/src/protocol_v0/`.
- Source files `howl-render/src/protocol_v0/emit.zig` and `howl-render/src/protocol_v0/realize.zig`.
- FFI mirror filename `howl-render/src/ffi/protocol_v0.zig` if the public ABI name remains but internal file owner can be made product/ABI-specific without changing exported symbols.
- Separate root `howl-render/src/test_protocol_proof.zig`.
- Build identifiers and steps `protocol_proof_mod`, `protocol_proof_tests`, `run_protocol_proof_tests`, `test_protocol_proof_step`, `test:protocol-proof`, and `test:protocol-proof:build` in `howl-render/build.zig:56-77` and `109-129`.
- Doc path/title `docs/render-protocol-v0.md` and `howl-render-protocol` term in `docs/render-protocol-v0.md:9` are stale if render API is the product and there is no separate render-protocol bucket.
- Test names containing `protocol v0` are stale only if they are internal bucket names; ABI-level tests may need to keep `V0` product vocabulary while deleting `protocol proof` as a category.

Consequences:

- Renaming public C ABI identifiers would affect header, FFI layout assertions, exported symbol names, host cimport call sites, and tests. That is ABI work, not a naming cleanup unless explicitly authorized.
- Removing the separate proof bucket without moving its tests into `test:unit` would delete API equivalence coverage.
- Keeping the public V0 ABI while deleting internal `protocol` buckets requires careful distinction between product ABI version vocabulary and source/test category vocabulary.

## Ownership Findings

- `emit.zig` is not truly a generic protocol owner. It emits render API V0 frames from `prepared_surface.PreparedSurface` and owns prepared V0 emission storage, limits, command/upload/create/retire spans, resource IDs, persistent sprite resource state, alpha atlas packing, and glyph-run batching. Source evidence: `emit.zig:12-67`, `99-177`, and `175-260`.
- `realize.zig` is not truly a generic protocol owner. It is a software V0 frame realizer and retained resource validation oracle. Source evidence: `realize.zig:17-177`, `179-194`, `196-254`, and `256-360`.
- `ffi/protocol_v0.zig` is an ABI layout assertion wrapper. It translates the shipped C ABI into compile-time checks and should remain an FFI owner unless renamed by an ABI-safe file move. Source evidence: `ffi/protocol_v0.zig:1-7`, `9-139`, `141-167`, and `169-338`.
- `test_protocol_proof.zig` is a separate proof bucket containing render API equivalence tests against the full RGBA oracle, plus owner/FFI lifetime tests. Source evidence: `test_protocol_proof.zig:14-20`, `830-945`, and `970-1020`.
- `prepared/owner.zig` is the true owner for prepared handle lifecycle, V0 payload lifetime, diagnostics, and submit/consume state. Source evidence: `prepared/owner.zig:37-58`, `65-82`, `144-166`, `215-242`, and `271-282`.
- `session/text.zig` owns `TextSessionOwner` and currently stores the V0 sprite resource store as session-retained render state at `session/text.zig:342-357`.
- `howl-linux-host/src/terminal/render/retained.zig` owns host retained render state and ABI probing/resource-plan validation for prepared uploads. Source evidence: `retained.zig:66-72`, `504-555`, and `752-795`.
- `howl-linux-host/src/terminal/context.zig` owns host upload decision flow and diagnostics for whether V0 frames are realized/presented. Source evidence: `context.zig:615-724` and `726-779`.
- `howl-linux-host/src/window/term_texture.zig` owns backend texture realization and upload tests; host-side `protocol v0` names there describe host consumption of public V0 frames but still use the stale `protocol` wording in internal tests.

Potential owner nouns are source-backed only as roles, not final rename instructions:

- Emission owner role: prepared V0 frame emission, because `Owner.emitV0Payload()` calls `payload.emitPrepared()` on prepared surfaces in `prepared/owner.zig:231-240`.
- Realization owner role: software V0 frame realization/oracle, because `realizeWithStore()` validates and draws a public V0 frame into pixels in `realize.zig:209-254`.
- ABI mirror role: render V0 ABI layout assertions, because `ffi/protocol_v0.zig:141-338` asserts constants, layout, and offsets.
- Test gate role: render API unit proof, because `test/unit.zig:5-8` already imports `emit.zig` and `realize.zig`, while `test_protocol_proof.zig` duplicates a separate proof root.

## Test And Build Findings

- The intended proof gate from the user is `zig build test:unit`, not `zig build test:unit -- "protocol v0"` and not `zig build test:protocol-proof`.
- `howl-render/src/test/unit.zig:5-8` already imports `../protocol_v0/realize.zig` and `../protocol_v0/emit.zig`, so their file-local tests are already under `test:unit`.
- `howl-render/src/test_protocol_proof.zig` tests are not under `test:unit`; they are wired only through the separate `protocol_proof_mod` root in `howl-render/build.zig:56-77`.
- `howl-render/build.zig:125-129` currently makes package `test` include `test:protocol-proof`, but this preserves the banned separate proof bucket.
- If the separate proof bucket goes away, the proof gate must move the behavioral/equivalence tests from `src/test_protocol_proof.zig` into unit-test discovery, or `test:unit` would lose these exact tests.
- `howl-render/src/test/ffi.zig:63-74` and `338-403` are ABI/FFI contract tests and should stay in the ABI/FFI test lane unless a scratchpad explicitly redefines test categories.

Exact tests that must become part of `zig build test:unit` if `test:protocol-proof` is deleted:

- All `howl-render/src/protocol_v0/emit.zig:1210-1454` emitter tests.
- All `howl-render/src/protocol_v0/realize.zig:1046-1951` realizer tests.
- All current `howl-render/src/test_protocol_proof.zig` proof/equivalence tests at lines `14`, `20`, `46`, `79`, `111`, `138`, `177`, `228`, `269`, `309`, `336`, `366`, `429`, `487`, `548`, `609`, `649`, `689`, `730`, `767`, `809`, `830`, `876`, `909`, `945`, `970`, `1000`, and `1020`.
- The proof target should not depend on a filter string. Running `zig build test:unit` with no `-- "protocol v0"` filter must discover them.

Host tests that are consumption proof, not render API unit proof:

- `howl-linux-host/src/terminal/render/retained.zig:1702`, `1720`, `1754`, `1798`, `1814`, `1836`, `1853`, `1873`, and `1923`.
- `howl-linux-host/src/terminal/context.zig:1739`, `1777`, and `2319`.
- `howl-linux-host/src/window/term_texture.zig:1004-1932` test names listed in the inventory.

These host tests should remain host gates because hosts own backend resource realization and upload decisions per `AGENTS.md:11-14` and `95-103`.

## Risks

- ABI break risk: public `HowlRenderV0*`, `HOWL_RENDER_V0_*`, and `howl_render_prepared_surface_protocol_v0()` names are shipped header/export names. Renaming them in a cleanup slice would be ABI work.
- Coverage loss risk: deleting `test:protocol-proof` without moving `src/test_protocol_proof.zig` tests into unit discovery would remove oracle equivalence tests.
- False cleanup risk: renaming only build steps while keeping `src/protocol_v0/` recreates the banned bucket under a different gate.
- Host drift risk: host code still consumes public V0 frames and has many internal `protocol_v0` fields/counters. A render-only rename can break host build if public ABI names or cimport field names move.
- Documentation risk: `docs/render-protocol-v0.md` currently teaches `howl-render-protocol` as a product boundary at line 9, conflicting with the user statement that render API is the product.
- Ambiguous owner-name risk: the source supports roles such as frame emission, software realization, ABI layout mirror, and render API unit proof, but this cache does not authorize final file names.

## Stop Conditions For A Scratchpad

- Stop if any proposed slice renames public C ABI/export symbols without explicitly treating it as ABI product work.
- Stop if the scratchpad cannot state where every `src/test_protocol_proof.zig` test will be discovered by `zig build test:unit`.
- Stop if `zig build test:unit` remains filter-dependent on `-- "protocol v0"`.
- Stop if `test:protocol-proof` remains as a build/test step after claiming separate proof bucket deletion.
- Stop if `protocol` survives as a render internal source/build/test category rather than public ABI version vocabulary.
- Stop if host consumption is changed by accident while doing render naming cleanup.
- Stop if final owner file names are invented without mapping to source-backed responsibilities listed above.

## Proof Gaps

- This cache inventories current occurrences and ownership roles, but does not choose final replacement paths or names.
- The cache did not run builds or tests because the task is research-only; a scratchpad must define verification commands before coding.
- The full host `term_texture.zig` source was not read from top to bottom; inventory is source-backed for occurrence lines and host ownership is source-backed by the test names and context/retained reads, but a host rename slice needs a targeted read.
- The current active slice in `current.txt` still authorizes files and commands that include banned names; this cache did not update it.

## Readiness Judgment

Scratchpad-ready: yes, with constraints.

The cache is source-backed enough to write a scratchpad for deleting the separate render internal/build/test/doc `protocol` bucket language while preserving public ABI product names unless a separate ABI slice is explicitly authorized. The scratchpad must encode `zig build test:unit` as the render API proof gate and must move every `src/test_protocol_proof.zig` test into unit discovery before deleting `test:protocol-proof`.
