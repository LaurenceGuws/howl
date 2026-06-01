# Render Protocol Language Cleanup Research Cache

Date: 2026-06-01

Owner: research cache only. This is not a scratchpad, not `current.txt`, and not an
implementation.

Supersession note: this cache is accepted only as history for partial doc/test
wording cleanup completed in `66bf363` and the root doc rename. Its premise that
public render ABI `protocol` vocabulary could remain out of scope is rejected.
ABIs are the product, and public ABI/FFI/docs/tests/host-consumer symbols
containing `protocol` require fresh research before any complete deletion slice.

## Sources Read In Order

1. `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
2. `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
3. `AGENTS.md`
4. `loop.txt`
5. `current.txt`
6. `research/cache-2026-06-01-render-api-language-deletion.md`
7. `research/cache-2026-06-01-render-v0-source-owner-paths.md`
8. `research/2026-06-01-render-api-language-deletion-sprint.md`
9. Current occurrence inventory under `howl-render`, `docs`, selected root files, and host files.
10. `docs/render-protocol-v0.md`
11. `howl-render/src/test/unit/render_api_v0_oracle.zig`
12. `howl-render/src/prepared/v0_frame_emitter.zig`
13. `howl-render/src/render/v0_frame_realizer.zig`
14. `howl-render/src/prepared/owner.zig`
15. `howl-render/src/ffi/protocol_v0.zig`
16. `howl-render/src/ffi/prepared_surface.zig`
17. `howl-render/src/libhowl_render.zig`
18. `howl-render/include/howl_render.h`
19. `howl-render/src/test/ffi.zig`

## Governing Facts

- `TIGER_STYLE.md:273-289` requires exact nouns and verbs. After the source bucket was deleted,
  remaining internal test/doc language should say what is being proved: render API V0 frame
  emission, realization, owner lifetime, diagnostics, and ABI layout.
- `TIGER_STYLE.md:315-335` says order and naming affect review. Stale test names that still say
  `protocol v0` obscure the true owner paths introduced by Slice 3.
- `AGENTS.md:9-15` says the ABIs are the product. The prior conclusion that public C ABI
  vocabulary could remain outside this cleanup was wrong and is superseded.
- `AGENTS.md:95-103` assigns `howl-render` ownership of render contracts, retained-frame state,
  prepare/submit scheduling, render-surface contracts, and text shaping.
- `AGENTS.md:105-116` says FFI translates contracts only. `src/ffi/protocol_v0.zig` remains an FFI
  ABI assertion owner while the public ABI still contains `protocol` spelling.
- `research/2026-06-01-render-api-language-deletion-sprint.md:19-21` previously kept public
  exported C ABI names containing `protocol` or `V0` out of scope. That premise is rejected for
  future planning.
- Completed slices in `current.txt:14-18` and
  `research/2026-06-01-render-api-language-deletion-sprint.md:84-287` already moved proof tests
  under unit, deleted `test:protocol-proof`, and deleted `src/protocol_v0/`.

## Occurrence Inventory And Classification

### Stale Internal Test Names

These are test names only. Renaming them changes no ABI assertions, no symbols, no behavior, and no
test discovery.

- `howl-render/src/test/unit/render_api_v0_oracle.zig:14` says
  `protocol v0 prepared proof target imports owner oracle`. The file path already says
  `render_api_v0_oracle`; this is stale proof-bucket language.
- `howl-render/src/test/unit/render_api_v0_oracle.zig:20`, `46`, `79`, `111`, `138`, `177`, `228`,
  `269`, `309`, `336`, `366`, `429`, `487`, `548`, `609`, `649`, `689`, `730`, `767`, and `809`
  are oracle/emitter tests named `protocol v0 emitter ...`. The source imports the true owners at
  `render_api_v0_oracle.zig:8-9`: `prepared/v0_frame_emitter.zig` and
  `render/v0_frame_realizer.zig`. The test names should say render API V0 frame emitter/oracle, not
  protocol.
- `howl-render/src/test/unit/render_api_v0_oracle.zig:830`, `876`, `909`, `945`, `970`, `1000`, and
  `1020` are prepared-owner and FFI borrowed-frame tests named `protocol v0 prepared ...`. They can
  become `render API V0 prepared ...` or `prepared V0 frame ...` without changing assertions.
- `howl-render/src/prepared/v0_frame_emitter.zig:1210`, `1228`, `1255`, `1282`, `1299`, `1322`,
  `1353`, `1366`, `1386`, `1406`, `1431`, and `1454` are file-local emitter tests named
  `protocol v0 ...`. The file owner is now `prepared/v0_frame_emitter.zig`; names should say
  `V0 frame emitter ...` or `V0 alpha atlas ...`.
- `howl-render/src/render/v0_frame_realizer.zig:1046`, `1061`, `1074`, `1087`, `1103`, `1118`,
  `1137`, `1154`, `1171`, `1176`, `1183`, `1189`, `1199`, `1206`, `1213`, `1219`, `1225`, `1231`,
  `1239`, `1255`, `1271`, `1280`, `1286`, `1294`, `1306`, `1313`, `1325`, `1333`, `1339`, `1345`,
  `1362`, `1378`, `1386`, `1394`, `1402`, `1409`, `1418`, `1431`, `1436`, `1450`, `1458`, `1465`,
  `1479`, `1493`, `1499`, `1505`, `1511`, `1520`, `1530`, `1543`, `1552`, `1569`, `1591`, `1607`,
  `1621`, `1636`, `1650`, `1667`, `1710`, `1725`, `1749`, `1773`, `1798`, `1816`, `1834`, `1845`,
  `1859`, `1871`, `1889`, `1905`, `1916`, `1928`, `1936`, and `1951` are file-local realizer tests
  named `protocol v0 ...`. The file owner is now `render/v0_frame_realizer.zig`; names should say
  `V0 frame realizer ...`, `V0 frame rejects ...`, or `retained V0 frame realizer ...`.
- `howl-render/src/prepared/owner.zig:639` is an owner test named
  `owner maps every protocol v0 emit error to diagnostics status`. The body maps internal emitter
  errors to public `HOWL_RENDER_V0_EMIT_*` status values at `owner.zig:640-675`; the test name can
  become `owner maps every V0 frame emit error to diagnostics status`.
- `howl-render/src/test/ffi.zig:63`, `338`, `354`, `366`, `381`, and `403` are FFI test names that
  say `protocol v0`. These names can be renamed without changing public ABI assertions, but they are
  ABI tests. If included in the next slice, only the test strings may change; the public call
  `prepared_surface.protocolV0`, exported symbol, header spelling, and asserted field names must not
  change.

### Stale Internal Aliases That Are Safe To Rename Only If The Slice Allows Identifier Cleanup

These are not public C ABI symbols, but they are code identifiers. Renaming them is safe only if the
implementation slice explicitly allows identifier-only internal cleanup and reruns render tests.

- `howl-render/src/test/unit/render_api_v0_oracle.zig:8-9` defines local aliases `protocol_emit` and
  `protocol_realize` for the true owner files. These can become `v0_frame_emitter` and
  `v0_frame_realizer` if the worker updates local call sites in the same file.
- `howl-render/src/prepared/owner.zig:8`, `39`, `144`, `150`, and `271` use local alias/type names
  around `protocol_v0_emit`. This is internal but adjacent to public ABI fields and methods. Leave it
  out of the next slice unless the scratchpad explicitly chooses identifier cleanup.
- `howl-render/src/session/text.zig:16` and `357` use `protocol_v0_emit` and
  `protocol_v0_sprite_resources`. The retained state instance supports public V0 frame emission; do
  not rename in a docs/test-name slice.

### Stale Documentation That Teaches Protocol As A Separate Product

- `docs/render-protocol-v0.md:1` titles the document `Howl Render Protocol V0 Contract Draft`. This
  conflicts with the sprint premise that the render API is the product.
- `docs/render-protocol-v0.md:9` introduces ``howl-render-protocol`` V0 as a named thing. This is the
  clearest stale product-boundary language.
- `docs/render-protocol-v0.md:33` says `prepared_buffer.compose()` is a proof oracle for protocol
  tests only. Current code has `src/test/unit/render_api_v0_oracle.zig`, not a protocol-proof lane.
- `docs/render-protocol-v0.md:40` says `Protocol frame tokens` in the ownership table. This should
  become V0 frame tokens or render API V0 frame tokens.
- `docs/render-protocol-v0.md:57-58` still says constants `must become public constants before ABI
  skeleton work`; the header already defines the constants at `howl_render.h:19-31`.
- `docs/render-protocol-v0.md:62`, `63`, and `71` contain public ABI constant spelling and must keep
  the code tokens, but the descriptions `Frame protocol version`, `Prepared protocol frames`, and
  `Live protocol resources` should be rewritten as public ABI V0 frame/resources wording.
- `docs/render-protocol-v0.md:251-254`, `312`, `328`, and `481` use prose such as `protocol
  identities`, `protocol resource`, `protocol-valid`, `protocol input`, and `protocol identity`.
  These are stale when used as product nouns; rewrite as render-owned V0 resource/frame identity or
  valid V0 frame input.
- `docs/render-protocol-v0.md:783` says `Before protocol emission`; this should become `Before V0
  frame emission`.
- `docs/render-protocol-v0.md:806` says `protocol emission` in test gates; this should become
  `V0 frame emission`.

### Rejected Public ABI Scope From This Sprint

These occurrences were previously kept out of scope. That premise is now rejected: public render ABI
symbols are product symbols and require fresh research for complete `protocol` deletion.

- `howl-render/include/howl_render.h:19` defines public `HOWL_RENDER_PROTOCOL_V0_VERSION`.
- `howl-render/include/howl_render.h:19-31` defines public V0 bounds.
- `howl-render/include/howl_render.h:33-44` defines public V0 kind constants.
- `howl-render/include/howl_render.h:53-65` defines public `HowlRenderV0EmitStatus` values.
- `howl-render/include/howl_render.h:184-314` defines public `HowlRenderV0*` structs; line `303`
  contains public field `protocol_version`.
- `howl-render/include/howl_render.h:516-522` defines public diagnostics field
  `protocol_v0_emit_status`.
- `howl-render/include/howl_render.h:644-647` declares public exported function
  `howl_render_prepared_surface_protocol_v0()`.
- `howl-render/src/ffi/protocol_v0.zig:1-351` is the FFI ABI layout/assertion owner. It mirrors public
  `HowlRenderV0*` layout at `9-139`, asserts `HOWL_RENDER_PROTOCOL_V0_VERSION` and public constants
  at `141-167`, and asserts public layout/offsets at `169-338`. Its filename remains allowed because
  the public ABI still uses this vocabulary.
- `howl-render/src/ffi/prepared_surface.zig:46-59` translates the public prepared-surface V0 call and
  must keep function `protocolV0` unless a separate ABI/FFI naming slice says otherwise.
- `howl-render/src/ffi/prepared_surface.zig:109-127` translates public diagnostics field
  `protocol_v0_emit_status`.
- `howl-render/src/libhowl_render.zig:8`, `11`, and `37` import the FFI ABI owner and export the
  public symbol `howl_render_prepared_surface_protocol_v0`.
- `howl-render/src/test/ffi.zig:46-49`, `63-75`, `77-99`, `307-314`, `328-335`, and `394-397` assert
  public ABI status values, layout offsets, diagnostics fields, and frame version. The test names may
  change, but the asserted public tokens must remain.
- `docs/render-protocol-v0.md:30`, `62`, and all C snippets using `HOWL_RENDER_PROTOCOL_V0_VERSION`,
  `HowlRenderV0*`, `protocol_version`, `protocol_v0_emit_status`, or
  `howl_render_prepared_surface_protocol_v0()` are public ABI facts and must remain as code tokens
  even if surrounding prose changes.

### Relevant Root File Occurrences

- `current.txt:17-18`, `22`, `30-31`, and `34` are the active research stage and historical completed
  slice statements. Do not update from this research role.
- `README.md:10` says `howl-vt` owns host-facing protocol consequences. This is VT-domain protocol
  language, not render V0 cleanup.
- Root `build.zig` had no targeted render protocol cleanup occurrence in the current grep.

### Host Out Of Scope

Host occurrences consume public V0 frames and should not be edited in a render-doc/test-name cleanup
slice. They need a separate host research cache if the project wants host internal naming cleanup.

- `howl-linux-host/src/terminal/render/retained.zig:69-71` stores `protocol_v0_probe`,
  `protocol_v0_resource_plan`, and `protocol_v0_frame` on prepared uploads.
- `howl-linux-host/src/terminal/render/retained.zig:200-231` defines host retained resource storage and
  backend operation buffers for V0 realization.
- `howl-linux-host/src/terminal/render/retained.zig:548-555` stores host counters and last probe/plan
  state with `protocol_v0` names.
- `howl-linux-host/src/terminal/render/retained.zig:762-783` probes the prepared frame and calls public
  `c.howl_render_prepared_surface_protocol_v0`.
- `howl-linux-host/src/terminal/render/retained.zig:798-816` records probe/resource-plan counters.
- `howl-linux-host/src/terminal/render/retained.zig:1702`, `1720`, `1754`, `1798`, `1814`, `1836`,
  `1853`, `1873`, and `1923` are host retained render test names around protocol V0 consumption.
- `howl-linux-host/src/terminal/context.zig:91-92`, `128-130`, and later upload/diagnostic code use
  `protocol_v0` names for host submit diagnostics and texture realization.
- `howl-linux-host/src/window/term_texture.zig:1004`, `1019`, `1034`, `1062`, `1069`, `1114`, `1132`,
  `1159`, `1164`, `1191`, `1233`, `1261`, `1278`, `1306`, `1323`, `1340`, `1356`, `1383`, `1399`,
  `1427`, `1453`, `1481`, `1519`, `1549`, `1589`, `1613`, `1652`, `1692`, `1741`, `1770`, `1809`,
  `1840`, `1910`, and `1932` are host texture test names. The prior sprint scratchpad already marks
  a full read of this file as required for any host follow-up.

## Documentation Action

`docs/render-protocol-v0.md` should be renamed and rewritten, not deleted.

Evidence for rename:

- The path and title (`docs/render-protocol-v0.md:1`) present `render-protocol` as a product boundary.
- The opening line (`docs/render-protocol-v0.md:9`) names ``howl-render-protocol`` V0 directly.
- The active sprint says docs should describe render API V0 as the ABI/product surface, not
  `howl-render-protocol` as a separate product (`research/2026-06-01-render-api-language-deletion-sprint.md:309-312`).

Evidence against deletion:

- The document contains current public ABI constants and bounds (`docs/render-protocol-v0.md:62-74`).
- It contains frame/object model definitions (`docs/render-protocol-v0.md:81-213`).
- It contains resource lifetime and same-frame ordering rules (`docs/render-protocol-v0.md:246-353`).
- It contains span lifetime, damage, upload, command, glyph atlas, invalid-input, and test-gate facts
  (`docs/render-protocol-v0.md:366-818`).

Proposed path/action:

- Move `docs/render-protocol-v0.md` to `docs/render-api-v0.md`.
- Rewrite title to `Howl Render API V0 Contract`.
- Rewrite prose from `protocol` as a product noun to `render API V0`, `V0 frame`, `V0 resource`, or
  `V0 frame input`.
- Preserve public code tokens exactly: `HOWL_RENDER_PROTOCOL_V0_VERSION`, `HOWL_RENDER_V0_*`,
  `HowlRenderV0*`, `protocol_version`, `protocol_v0_emit_status`, and
  `howl_render_prepared_surface_protocol_v0()`.

## Test Names That Can Be Renamed Without Public ABI Changes

- All test string names listed under stale internal test names can be renamed because Zig test names
  are not public ABI symbols.
- Next slice should include the internal/unit names in
  `howl-render/src/test/unit/render_api_v0_oracle.zig`,
  `howl-render/src/prepared/v0_frame_emitter.zig`,
  `howl-render/src/render/v0_frame_realizer.zig`, and `howl-render/src/prepared/owner.zig`.
- FFI test names in `howl-render/src/test/ffi.zig:63`, `338`, `354`, `366`, `381`, and `403` can also
  be renamed if and only if the body remains unchanged.
- Historical wrong-scope limit: this cache did not rename public ABI symbols, fields, exported
  symbols, header constants, `src/ffi/protocol_v0.zig`, or host names. Fresh research must cover
  those symbols before complete deletion work.

## Proposed Worker-Ready Slice

Goal:

- Remove stale render-internal unit test names and documentation language that teach `protocol` as a
  separate product. This goal was partial and did not complete the user's public-symbol ban.

Allowed files:

- `docs/render-protocol-v0.md` moved to `docs/render-api-v0.md`.
- `howl-render/src/test/unit/render_api_v0_oracle.zig` test string names, and local aliases only if
  the scratchpad chooses alias cleanup.
- `howl-render/src/prepared/v0_frame_emitter.zig` test string names only.
- `howl-render/src/render/v0_frame_realizer.zig` test string names only.
- `howl-render/src/prepared/owner.zig` test string name at line `639` only.
- Optional ABI-test string-only renames in `howl-render/src/test/ffi.zig` at lines `63`, `338`, `354`,
  `366`, `381`, and `403`.

Required shape:

- Rename doc path to `docs/render-api-v0.md` and rewrite product language around render API V0.
- Test strings should use `render API V0`, `V0 frame emitter`, `V0 frame realizer`, `retained V0
  frame realizer`, `prepared V0 frame`, `V0 frame diagnostics`, or equivalent owner-true nouns.
- Preserve all test bodies and assertions.
- Historical wrong-scope limit: public ABI tokens in code, docs code spans, C snippets, FFI
  assertions, header, exports, prepared diagnostics, and public call names were not renamed.
- Make no host edits.
- Make no build edits.

Non-goals:

- Historical wrong-scope non-goals, superseded for future planning:
- No public C ABI rename.
- No `src/ffi/protocol_v0.zig` rename.
- No `howl_render_prepared_surface_protocol_v0()` rename.
- No `protocol_v0_emit_status` field rename.
- No host behavior or host internal naming cleanup.
- No test deletion, filtering, movement, or assertion weakening.

## Grep And Verification Gates

Verification commands:

- From `howl-render`: `zig build test:unit`
- From `howl-render`: `zig build test:abi`
- From `howl-render`: `zig build test`
- From workspace root: `zig build check`
- From workspace root: `zig build test`
- From workspace root: `git diff --check`

Required grep gates after the slice:

- From workspace root: `rg 'render-protocol|howl-render-protocol' docs howl-render README.md build.zig`
  prints nothing.
- From workspace root: `test ! -e docs/render-protocol-v0.md`.
- From workspace root: `test -f docs/render-api-v0.md`.
- From workspace root: `rg 'test "[^"]*protocol v0|protocol tests only|Before protocol emission|protocol emission' howl-render/src docs/render-api-v0.md`
  prints nothing.
- From workspace root: `rg 'protocol_proof|test:protocol-proof|test_protocol_proof|src/protocol_v0|\.\./protocol_v0|protocol_v0/' howl-render/build.zig howl-render/src`
  prints nothing.
- From workspace root: `rg 'HOWL_RENDER_PROTOCOL_V0_VERSION|HowlRenderV0|howl_render_prepared_surface_protocol_v0|protocol_v0_emit_status|protocol_version' howl-render/include howl-render/src docs/render-api-v0.md`
  may print public ABI matches and must not be used as a failure gate.
- From workspace root: `rg 'protocol_v0' howl-linux-host/src` may still print host out-of-scope matches.

## Risks

- ABI break risk: overzealous cleanup could rename public C symbols or fields. Stop rather than
  renaming any public token listed above.
- Documentation drift risk: rewriting `docs/render-protocol-v0.md` could accidentally change contract
  meaning. The next slice should be wording/path cleanup only; preserve all bounds, constants,
  lifetime rules, and invalid-input rules.
- Test coverage risk: test names can change, but test bodies, imports, discovery, assertions, and
  verification gates must not be weakened.
- Host scope risk: host internal names still contain `protocol_v0`; they consume the public V0 ABI and
  require a separate host cache.
- Grep false-positive risk: historical research caches and scratchpads intentionally contain old
  terms. Gates should target `docs`, `howl-render`, root product files, and exclude `research` unless
  the scratchpad explicitly wants historical cache churn.

## Stop Conditions

- Stop if any public ABI symbol, header field, exported name, FFI layout assertion, or host cimport
  call must change.
- Stop if a doc rewrite implies an ABI break or semantic contract change.
- Stop if host code must be edited to pass builds.
- Stop if any test body, assertion, import, test discovery root, or build step needs more than string
  renaming.
- Stop if `docs/render-api-v0.md` cannot preserve the contract facts from the old doc while removing
  separate-product `protocol` language.
- Stop if grep gates require editing historical `research/` files.

## Readiness Judgment

Worker-ready: yes.

The exact next slice described here was source-backed only as partial doc/test cleanup. It is not
authority for complete render `protocol` symbol deletion. Fresh research is required across render
ABI, FFI, docs, tests, and host consumers.
