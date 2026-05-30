# Render C Translator Lane Decision

Date: 2026-05-30

Owner: workspace root.

Purpose: decide the exact C translator lane shape for `howl-render` before moving
root translator files, classify the current root ABI files, and select one
bounded first implementation move.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `current.txt`
- `research/2026-05-30-hygiene-audit/roadmap.md` Slice 2.1
- `research/2026-05-30-hygiene-audit/synthesis.md`
- `research/2026-05-30-hygiene-audit/c-abi-header-grammar.md`
- `howl-render/design.md`
- `howl-render/include/howl_render.h`
- `howl-render/src/libhowl_render.zig`
- `howl-render/src/vt_surface.zig`
- `howl-render/src/prepare_request.zig`
- `howl-render/src/submission.zig`
- `howl-render/src/prepared_surface.zig`
- `howl-render/src/text_session.zig`
- `howl-render/src/surface_geometry.zig`
- `howl-render/src/work_state.zig`

## Decision

Use an `ffi/` translator lane grouped by ABI nouns.

Render should not use one large `ffi.zig` translator. The public render header has
two handles, many ABI nouns, and a long function list: text-session functions at
`howl-render/include/howl_render.h:376-466` and prepared-surface functions at
`howl-render/include/howl_render.h:468-482`. A single file would flatten these
nouns and recreate the root scatter inside one oversized C bucket.

The accepted lane shape is:

- `howl-render/src/ffi.zig` remains the C import and shared boundary entry.
- `howl-render/src/ffi/text_session.zig` translates text-session lifecycle and
  font/session configuration C entries.
- `howl-render/src/ffi/surface_geometry.zig` translates layout and geometry C
  entries.
- `howl-render/src/ffi/vt_surface.zig` translates VT-derived source-slot C
  entries.
- `howl-render/src/ffi/prepare_request.zig` translates prepare-request C entries
  and token conversion.
- `howl-render/src/ffi/submission.zig` translates prepared-publication, submit
  decision, submit, and submit-result C entries.
- `howl-render/src/ffi/prepared_surface.zig` translates prepared-surface handle C
  entries.
- `howl-render/src/ffi/work_state.zig` translates session-work-state C entries.

`howl-render/src/libhowl_render.zig` remains an export table only. It imports the
accepted `ffi/*` translator nouns and exports the existing `howl_render_*` symbols
without renaming them.

## Ownership Facts Preserved

- Render owns backend-agnostic render contracts and text rendering work:
  `howl-render/design.md:7-11`.
- The shipped embedding contract is `include/howl_render.h` plus exported
  `howl_render_*` symbols, and hosts must not integrate with internal Zig files:
  `howl-render/design.md:13-18`.
- `src/ffi.zig` translates the C ABI only:
  `howl-render/design.md:20-23`.
- `source/*` owns VT-derived input snapshots, source cells, dirty metadata,
  publication slots, and prepare requests: `howl-render/design.md:25`.
- `prepared/*` owns prepared output and submit result contracts:
  `howl-render/design.md:26`.
- `session/*` composes the render text session behind the C handle:
  `howl-render/design.md:22-24`.
- `render/*` owns render geometry policy and geometry contracts:
  `howl-render/design.md:28`.
- `text/*` owns shaping, classification, scene building, raster cache use, and
  font-provider integration: `howl-render/design.md:29`.
- FFI files cast and validate contracts only; source, session, prepared, render,
  and text owners own behavior: `howl-render/design.md:50-58`.

## Classification

### `vt_surface.zig`

Classification: translator. Its root placement is stale, but the file is not a
true owner.

Exported C functions:

- `reserveVtSurfaceSlot`: `howl-render/src/vt_surface.zig:13-26`.
- `commitVtSurface`: `howl-render/src/vt_surface.zig:28-50`.
- `rejectVtSurface`: `howl-render/src/vt_surface.zig:52-59`.
- `cancelVtSurface`: `howl-render/src/vt_surface.zig:61-64`.

Owner calls and translator evidence:

- Imports `ffi.zig`, `handle.zig`, `source/*`, and `surface/tokens.zig`:
  `howl-render/src/vt_surface.zig:1-7`.
- Resolves the C handle through `handle_owner.textSessionOwner`:
  `howl-render/src/vt_surface.zig:21`, `howl-render/src/vt_surface.zig:32`,
  `howl-render/src/vt_surface.zig:56`, `howl-render/src/vt_surface.zig:62`.
- Delegates VT source-slot mutation to the session owner with
  `owner.reserveVtSurfaceSlot`, `owner.commitVtSurface`,
  `owner.rejectVtSurface`, and `owner.cancelVtSurface`:
  `howl-render/src/vt_surface.zig:23`, `howl-render/src/vt_surface.zig:37`,
  `howl-render/src/vt_surface.zig:58`, `howl-render/src/vt_surface.zig:63`.
- Converts owner types to C structs through `vtSurfaceSlotOut`,
  `sourceCellsOut`, `vtSurfacePublishResultOut`, `colorStateIn`,
  `selectionIn`, and `cursorIn`: `howl-render/src/vt_surface.zig:66-134`.
- Keeps ABI layout assertions beside the translator:
  `howl-render/src/vt_surface.zig:136-206`.

### `prepare_request.zig`

Classification: translator. Its root placement is stale, but the file is not a
true owner.

Exported C functions:

- `takePrepareRequest`: `howl-render/src/prepare_request.zig:6-16`.

Owner calls and translator evidence:

- Imports `ffi.zig`, `handle.zig`, and `surface/tokens.zig`:
  `howl-render/src/prepare_request.zig:1-4`.
- Resolves the C handle through `handle_owner.textSessionOwner`:
  `howl-render/src/prepare_request.zig:12`.
- Delegates to the session owner with `owner.prepare()`:
  `howl-render/src/prepare_request.zig:13`.
- Converts owner request/token facts at the C boundary through
  `prepareRequestOut` and `prepareTokenIn`:
  `howl-render/src/prepare_request.zig:18-50`.

### `submission.zig`

Classification: translator. Its root placement is stale, but the file is not a
true owner.

Exported C functions:

- `publishPrepared`: `howl-render/src/submission.zig:8-16`.
- `publishPreparedHandle`: `howl-render/src/submission.zig:18-30`.
- `takeSubmitDecision`: `howl-render/src/submission.zig:32-48`.
- `takeSubmitHandle`: `howl-render/src/submission.zig:50-85`.
- `acceptSubmitted`: `howl-render/src/submission.zig:87-95`.
- `submit`: `howl-render/src/submission.zig:97-117`.
- `submitHandle`: `howl-render/src/submission.zig:178-204`.

Owner calls and translator evidence:

- Imports `ffi.zig`, `handle.zig`, `surface/prepared_owner.zig`,
  `submit_result.zig`, and `surface/tokens.zig`:
  `howl-render/src/submission.zig:1-6`.
- Resolves text-session C handles through `handle_owner.textSessionOwner`:
  `howl-render/src/submission.zig:12`, `howl-render/src/submission.zig:22`,
  `howl-render/src/submission.zig:38`, `howl-render/src/submission.zig:56`,
  `howl-render/src/submission.zig:91`, `howl-render/src/submission.zig:105`,
  `howl-render/src/submission.zig:185`.
- Resolves prepared-surface C handles through `prepared_owner.Owner.fromHandle`:
  `howl-render/src/submission.zig:23`, `howl-render/src/submission.zig:71`,
  `howl-render/src/submission.zig:106`, `howl-render/src/submission.zig:188`.
- Delegates retained submit state and consequences through `owner.publishPrepared`,
  `owner.submit`, `owner.acceptSubmitted`, `prepared.submit`, and
  `prepared.submitOwned`: `howl-render/src/submission.zig:28`,
  `howl-render/src/submission.zig:39`, `howl-render/src/submission.zig:57`,
  `howl-render/src/submission.zig:93`, `howl-render/src/submission.zig:109`,
  `howl-render/src/submission.zig:194`, `howl-render/src/submission.zig:197`.
- Converts C token and submit-result facts through `preparedSurfaceTokenOut`,
  `preparedSurfaceTokenIn`, `samePreparedSurfaceToken`, and
  `submit_result.*`: `howl-render/src/submission.zig:119-176`.

### `prepared_surface.zig`

Classification: translator. Its root placement is stale, but the file is not a
true owner.

Exported C functions:

- `prepareHandle`: `howl-render/src/prepared_surface.zig:8-21`.
- `release`: `howl-render/src/prepared_surface.zig:23-26`.
- `describe`: `howl-render/src/prepared_surface.zig:28-44`.
- `buffer`: `howl-render/src/prepared_surface.zig:46-62`.
- `diagnostics`: `howl-render/src/prepared_surface.zig:64-80`.

Owner calls and translator evidence:

- Imports `ffi.zig`, `handle.zig`, `surface/prepared_owner.zig`,
  `prepare_request.zig`, and `submit_result.zig`:
  `howl-render/src/prepared_surface.zig:1-6`.
- Resolves the text-session C handle through `handle_owner.textSessionOwner`:
  `howl-render/src/prepared_surface.zig:15`.
- Resolves prepared-surface C handles through `prepared_owner.Owner.fromHandle`:
  `howl-render/src/prepared_surface.zig:24`,
  `howl-render/src/prepared_surface.zig:33`,
  `howl-render/src/prepared_surface.zig:51`,
  `howl-render/src/prepared_surface.zig:69`.
- Delegates prepared output ownership to `owner.prepareHandle`, `owner.release`,
  `owner.info`, `owner.buffer`, and `owner.diagnostics`:
  `howl-render/src/prepared_surface.zig:18`,
  `howl-render/src/prepared_surface.zig:25`,
  `howl-render/src/prepared_surface.zig:42`,
  `howl-render/src/prepared_surface.zig:60`,
  `howl-render/src/prepared_surface.zig:78`.
- Converts prepared owner facts to C results through `preparedInfoOut`,
  `preparedBufferOut`, `preparedDiagnosticsOut`, and failure constructors:
  `howl-render/src/prepared_surface.zig:82-148`.

### `text_session.zig`

Classification: translator. Its root placement is stale, but the file is not a
true owner.

Exported C functions:

- `init`: `howl-render/src/text_session.zig:8-16`.
- `deinit`: `howl-render/src/text_session.zig:18-21`.
- `isValidFont`: `howl-render/src/text_session.zig:23-26`.
- `setFontSize`: `howl-render/src/text_session.zig:28-33`.
- `setFontPath`: `howl-render/src/text_session.zig:35-46`.
- `setFallbackFontPaths`: `howl-render/src/text_session.zig:48-68`.
- `setCursorBlinkVisible`: `howl-render/src/text_session.zig:70-74`.

Owner calls and translator evidence:

- Imports `ffi.zig`, `handle.zig`, `surface_geometry.zig`, `session/text.zig`,
  and text font support: `howl-render/src/text_session.zig:1-6`.
- Creates the true session owner with `TextSessionOwner.create`:
  `howl-render/src/text_session.zig:11-14`.
- Resolves the C handle through `handle_owner.textSessionOwner`:
  `howl-render/src/text_session.zig:19`, `howl-render/src/text_session.zig:24`,
  `howl-render/src/text_session.zig:29`, `howl-render/src/text_session.zig:40`,
  `howl-render/src/text_session.zig:53`, `howl-render/src/text_session.zig:71`.
- Delegates session/text ownership through `owner.destroy`, `owner.isValidFont`,
  `owner.setFontSizePx`, `owner.setFontPathBytes`,
  `owner.setFallbackFontPathPtrs`, and `owner.setCursorBlinkVisible`:
  `howl-render/src/text_session.zig:20`, `howl-render/src/text_session.zig:25`,
  `howl-render/src/text_session.zig:31`, `howl-render/src/text_session.zig:42`,
  `howl-render/src/text_session.zig:61`, `howl-render/src/text_session.zig:72`.

### `surface_geometry.zig`

Classification: translator. Its root placement is stale, but the file is not a
true owner.

Exported C functions:

- `deriveLayout`: `howl-render/src/surface_geometry.zig:5-19`.
- `syncGeometry`: `howl-render/src/surface_geometry.zig:21-38`.

Owner calls and translator evidence:

- Imports `ffi.zig`, `handle.zig`, and `render/geometry_contract.zig`:
  `howl-render/src/surface_geometry.zig:1-3`.
- Resolves the C handle through `handle_owner.textSessionOwner`:
  `howl-render/src/surface_geometry.zig:10`,
  `howl-render/src/surface_geometry.zig:25`.
- Delegates geometry derivation and synchronization through `owner.session` and
  `owner.syncGeometry`: `howl-render/src/surface_geometry.zig:11-17`,
  `howl-render/src/surface_geometry.zig:26-37`.
- Converts C geometry to render geometry contracts through `pixelIn` and
  `geometryOut`: `howl-render/src/surface_geometry.zig:40-53`.

### `work_state.zig`

Classification: translator. Its root placement is stale, but the file is not a
true owner.

Exported C functions:

- `workState`: `howl-render/src/work_state.zig:5-17`.

Owner calls and translator evidence:

- Imports `ffi.zig`, `handle.zig`, and `session/text.zig`:
  `howl-render/src/work_state.zig:1-3`.
- Resolves the C handle through `handle_owner.textSessionOwner`:
  `howl-render/src/work_state.zig:10`.
- Delegates to the session owner through `owner.workState()`:
  `howl-render/src/work_state.zig:15`.
- Converts owner work-state facts to C structs through `sessionWorkStateOut` and
  `sessionWorkStateFailure`: `howl-render/src/work_state.zig:19-35`.

## Root Export Evidence

`howl-render/src/libhowl_render.zig` imports all seven root translator files at
`howl-render/src/libhowl_render.zig:1-7` and exports their functions at
`howl-render/src/libhowl_render.zig:9-37`. That confirms the root is already an
export table, but its imports point at root files that look like owners instead
of an explicit C translator lane.

## First Implementation Move

Move `howl-render/src/prepare_request.zig` to
`howl-render/src/ffi/prepare_request.zig` first.

Why this is bounded:

- It has one exported C function: `takePrepareRequest` at
  `howl-render/src/prepare_request.zig:6-16`.
- Its only direct owner call is `owner.prepare()` at
  `howl-render/src/prepare_request.zig:13`.
- Its conversion surface is one C request struct and one token conversion pair:
  `howl-render/src/prepare_request.zig:18-50`.
- It is imported by the export root at `howl-render/src/libhowl_render.zig:5` and
  by `prepared_surface.zig` at `howl-render/src/prepared_surface.zig:5`, so the
  import repair is small and reviewable.
- It does not require moving VT source-slot layout assertions, prepared-surface
  handle state, submit state, or text-session lifecycle code.

## Next Slice Files

Exact files for the next implementation slice:

- `howl-render/src/libhowl_render.zig`
- `howl-render/src/prepare_request.zig`
- `howl-render/src/ffi/prepare_request.zig`
- `howl-render/src/prepared_surface.zig`

The next slice must not edit any other file unless the build exposes a direct
import path missed by this document. If that happens, stop and report the exact
import before broadening scope.

## Next Slice Non-Goals

- Do not move `vt_surface.zig`.
- Do not move `submission.zig`.
- Do not move `prepared_surface.zig`.
- Do not move `text_session.zig`.
- Do not move `surface_geometry.zig`.
- Do not move `work_state.zig`.
- Do not rename any `HowlRender*` C type.
- Do not rename any `howl_render_*` symbol.
- Do not change `howl-render/include/howl_render.h`.
- Do not change token validation semantics.
- Do not change prepare scheduling semantics.
- Do not add compatibility aliases.

## Next Slice Invariants

- The public root curates exports only.
- `howl_render_text_session_take_prepare_request` keeps the same exported symbol.
- `HowlRenderPrepareRequest` layout and field meanings do not change.
- `takePrepareRequest` still zeroes the output before owner access.
- Missing output, missing handle, idle, ready, and failed status behavior remains
  identical.
- `prepareTokenIn` remains the single C-to-owner token translator used by
  `prepared_surface.zig`.
- The translator calls the session/source owner; it does not own source state.

## Next Slice Verification

Run from `/home/home/personal/projects/howl`:

```sh
zig build check
zig build test
git diff --check
```

If root build verification is blocked by unrelated build architecture, run the
render package equivalent if available and report the blocker with the exact
failure.

## Next Slice Grep Gates

```sh
rg '@import\("prepare_request\.zig"\)' howl-render/src
rg 'howl_render_text_session_take_prepare_request|HowlRenderPrepareRequest' howl-render/src
rg 'vt_surface.zig|submission.zig|prepared_surface.zig|text_session.zig|surface_geometry.zig|work_state.zig' howl-render/src/libhowl_render.zig
```

Expected results:

- The first gate prints only the accepted `ffi/prepare_request.zig` import path
  or no stale root import.
- The second gate supports manual review that symbols and C request translation
  moved only.
- The third gate proves the next slice did not move other translators.

## Reviewer Checklist

- Confirms the next diff is a file move plus import repair only.
- Confirms `libhowl_render.zig` remains an export table.
- Confirms the old root `howl-render/src/prepare_request.zig` is gone.
- Confirms no compatibility wrapper remains at the old root path.
- Confirms token validation conditions are byte-for-byte equivalent or clearly
  unchanged by a pure move.
- Confirms status mapping for missing output, missing handle, idle, ready, and
  failed paths is unchanged.
- Confirms no source, prepared, session, render, or text owner behavior moved.

## Risks

- `prepared_surface.zig` currently imports `prepare_request.zig` directly at
  `howl-render/src/prepared_surface.zig:5`; a careless move could leave a stale
  root import or duplicate translator alias.
- Moving later translators will be less trivial because `vt_surface.zig` carries
  layout assertions and `submission.zig` mutates retained submit-handle fields
  through existing owner state.
- The selected lane fixes translator placement only. It does not resolve render
  text taxonomy debt such as `text/pipeline.zig`.

## Stop Conditions

- Stop if moving `prepare_request.zig` requires changing behavior.
- Stop if the new lane needs a compatibility wrapper at the old root path.
- Stop if an import cycle appears between `ffi/prepare_request.zig` and another
  translator.
- Stop if the next worker cannot preserve `prepareTokenIn` as the exact C token
  translation used by `prepared_surface.zig`.
- Stop if review cannot distinguish translator files from true render owners.

## Explicit Rejections

- Reject generic `types.zig`: ABI facts must stay beside the translator noun they
  prove, not in an ownerless bucket.
- Reject generic `api.zig`: the C ABI lane is `ffi/`, and the public root exports
  exact symbols.
- Reject `manager`, `controller`, `engine`, and `runtime` buckets as banned owner
  vocabulary; this document mentions them only as rejected shapes.
- Reject compatibility aliases and old root compatibility wrappers.
- Reject Zig-shaped host shortcuts; hosts consume `include/howl_render.h` and the
  exported `howl_render_*` symbols.

## Verification For This Slice

Run from `/home/home/personal/projects/howl`:

```sh
git diff --check
```

Grep gates for this document:

```sh
rg 'vt_surface.zig|prepare_request.zig|submission.zig|prepared_surface.zig|text_session.zig|surface_geometry.zig|work_state.zig' research/2026-05-30-hygiene-audit/render-c-lane.md
rg 'manager|controller|engine|runtime|types.zig|api.zig' research/2026-05-30-hygiene-audit/render-c-lane.md
```

The second grep must show rejected or banned context only.
