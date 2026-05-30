# Howl Hygiene Sprint Roadmap

Date: 2026-05-30

## Scope

This roadmap scopes the hygiene sprint into reviewable bytes. The sprint target is structural product hygiene, not feature work: C ABI lane grammar, render C lane and taxonomy, VT wrapper and FFI ownership, deeper VT terminal/screen owner seams, source-backed host hygiene, in-file organization rules, and research backlog items that are not worker-ready.

The ABI boundary remains the product boundary. Hosts embed `howl-pty`, `howl-vt`, `howl-render`, and `howl-hosts/vendor/*` contracts only. No slice may add a Zig-shaped host shortcut, umbrella runtime, manager, controller, engine, compatibility shim, or ownerless `types.zig` file.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `project-memory.md`
- `libs.yaml`
- `research/2026-05-30-hygiene-audit/researcher-a.md`
- `research/2026-05-30-hygiene-audit/researcher-b.md`
- `research/2026-05-30-hygiene-audit/researcher-c.md`
- `research/2026-05-30-hygiene-audit/synthesis.md`

## Phase 1: C ABI Lane/Header Grammar And Root Exports

Goal: make the ABI lane read as one factory-clean product surface across PTY, VT, and render before semantic owner movement starts.

Dependencies: none. This phase must go first because later render and VT slices need the C lane convention to avoid moving root shims into another vague shape.

Acceptance criteria:

- One written C header grammar exists and is specific enough for review.
- Header implementation changes preserve C symbols, enum values, struct layout, and behavior unless a later slice explicitly promotes an ABI break.
- `libhowl_*.zig` roots remain export tables only.
- FFI files translate C contracts only; owner mutation stays behind owner APIs.

Exit gates:

- Root `zig build check` and `zig build test` pass.
- `git diff --check` passes.
- Public headers have no ornamental numbered banners or one-off section prose.
- Header lines are at most 100 columns.

### Slice 1.1: Define C ABI Header Grammar

Owner/repo: workspace root, research documentation.

Status: worker-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/c-abi-header-grammar.md`

Exact non-goals:

- Do not edit `howl-pty/include/howl_pty.h`.
- Do not edit `howl-vt/include/howl_vt.h`.
- Do not edit `howl-render/include/howl_render.h`.
- Do not change C symbols, numeric values, layout, Zig exports, or tests.

Invariants:

- Grammar order is: include guard, includes, `extern "C"`, opaque handles, limits/macros, status/result enums, product enums, structs, functions grouped by owner handle.
- Comments explain ABI consequences or lifetime only; ordering does navigation.
- Header function prototypes must be wrappable under 100 columns.
- The document must state that Howl is not copying Ghostty's broad multi-header Zig lane.

Verification commands:

- `git diff --check`

Grep gates:

- `rg "include guard|opaque handles|status/result enums|functions grouped by owner" research/2026-05-30-hygiene-audit/c-abi-header-grammar.md`
- `rg "compatibility alias|Zig-shaped host shortcut" research/2026-05-30-hygiene-audit/c-abi-header-grammar.md` must show these as banned, not proposed.

Reviewer checklist:

- Confirms the grammar is exact enough that a worker cannot invent ordering.
- Confirms no implementation slipped into the planning slice.
- Confirms TigerBeetle line length, comment, naming, and top-down order pressure is cited.
- Confirms Howl ABI law and no-downstream ABI break policy are represented correctly.

Risks and stop conditions:

- Stop if the grammar tries to add generation tooling; build/test architecture is a separate blocker.
- Stop if the document cannot decide a single handle/status/function order.

### Slice 1.2: Apply Header Grammar Without ABI Semantic Changes

Owner/repo: `howl-pty`, `howl-vt`, `howl-render` public C ABI headers.

Status: worker-ready after Slice 1.1 lands.

Exact files likely edited:

- `howl-pty/include/howl_pty.h`
- `howl-vt/include/howl_vt.h`
- `howl-render/include/howl_render.h`

Exact non-goals:

- No symbol renames.
- No enum numeric changes.
- No struct field additions, removals, reorderings, or type changes.
- No Zig source edits except if formatting exposes an impossible header dependency, in which case stop.
- No compatibility typedefs or old-name aliases.

Invariants:

- Header grammar from Slice 1.1 is followed exactly.
- PTY remains compact and direct; VT loses numbered banners; render loses one-off section prose.
- Function prototypes are wrapped to at most 100 columns.
- Declaration order must satisfy C dependency order.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `awk 'length($0)>100 {print FILENAME ":" FNR ":" $0}' howl-*/include/*.h` prints nothing.
- `rg '/\* -{5,}|/\* [0-9]+\.|Shell input enums|Owned prepared-surface' howl-*/include/*.h` prints nothing.
- `rg 'typedef .*Handle|enum|struct|howl_' howl-*/include/*.h` supports manual review of grammar order.

Reviewer checklist:

- Diffs are order/comment/wrapping only.
- C declaration dependencies are valid.
- ABI layout tests still import headers.
- No product feature or vocabulary rename was smuggled in.

Risks and stop conditions:

- Stop if any layout or value change appears necessary; promote a separate ABI break slice.
- Stop if a header cannot be made grammar-compliant without changing an exported contract.

### Slice 1.3: Normalize ABI Export Root Order

Owner/repo: C ABI public roots.

Status: worker-ready after Slice 1.2 lands.

Exact files likely edited:

- `howl-pty/src/libhowl_pty.zig`
- `howl-vt/src/libhowl_vt.zig`
- `howl-render/src/libhowl_render.zig`

Exact non-goals:

- Do not move render translator files yet.
- Do not rename exported C symbols.
- Do not change `ffi.zig` behavior.

Invariants:

- Public roots curate exports only.
- Export order follows the header grammar and owner/function order.
- PTY and VT remain single-`ffi` export tables.
- Render may still import current translators in this slice, but order must be explicit and mechanical.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg '^const .* = @import|@export\(' howl-pty/src/libhowl_pty.zig howl-vt/src/libhowl_vt.zig howl-render/src/libhowl_render.zig`
- `rg 'pub fn|var |const [A-Z].*= struct' howl-pty/src/libhowl_pty.zig howl-vt/src/libhowl_vt.zig howl-render/src/libhowl_render.zig` must not reveal owner behavior in roots.

Reviewer checklist:

- Root files are export tables only.
- Ordering matches headers.
- No translator movement or ABI behavior change is hidden in the diff.

Risks and stop conditions:

- Stop if render root order cannot be made intelligible without moving translators; that belongs to Phase 2.

## Phase 2: Render C Lane And Taxonomy

Goal: make render's C ABI translator lane explicit, then remove one stale taxonomy seam at a time.

Dependencies: Phase 1. Render root movement depends on header/root grammar so reviewers can distinguish C translator files from render owners.

Acceptance criteria:

- `howl-render/src/libhowl_render.zig` exports from an explicit C ABI translator lane, not scattered root files that look like owners.
- Root shim movement preserves C symbols and behavior.
- Render accepted direction remains `source/*`, `prepared/*`, `session/*`, `render/*`, and text owners.
- No `pipeline` owner vocabulary remains after the implementation slice that proves the replacement name.

Exit gates:

- Root `zig build check`, `zig build test`, and `git diff --check` pass.
- Render package `zig build check` and `zig build test` pass if root verification is blocked.
- Grep gates prove no accidental `surface` umbrella or `pipeline` owner expansion.

### Slice 2.1: Render C Translator Lane Decision

Owner/repo: `howl-render`, research documentation.

Status: worker-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/render-c-lane.md`

Exact non-goals:

- Do not edit render code.
- Do not move files.
- Do not rename ABI symbols.

Invariants:

- Decide whether render uses one `ffi.zig` translator or an `ffi/*` translator lane grouped by ABI nouns.
- Root-level files named like owners (`vt_surface.zig`, `prepare_request.zig`, `submission.zig`, `prepared_surface.zig`, `text_session.zig`, `surface_geometry.zig`) must be classified as translator, owner, or stale.
- Decision must preserve render ownership: source owns VT-derived input snapshots; prepared owns prepared output; session composes the C handle; render/text own rendering and shaping.

Verification commands:

- `git diff --check`

Grep gates:

- `rg 'vt_surface.zig|prepare_request.zig|submission.zig|prepared_surface.zig|text_session.zig|surface_geometry.zig' research/2026-05-30-hygiene-audit/render-c-lane.md`
- `rg 'manager|controller|engine|runtime|types.zig' research/2026-05-30-hygiene-audit/render-c-lane.md` must not propose banned owners.

Reviewer checklist:

- Confirms every current render root shim is classified.
- Confirms first implementation file move is selected and bounded.
- Confirms no source-folder movement is proposed before translator lane proof.

Risks and stop conditions:

- Stop if the document cannot distinguish translator files from true render owners.
- Stop if it proposes a generic `c/types.zig` file.

### Slice 2.2: Move `prepare_request.zig` Into The Render C Lane

Owner/repo: `howl-render`.

Status: worker-ready after Slice 2.1 lands.

Exact files likely edited:

- `howl-render/src/libhowl_render.zig`
- `howl-render/src/prepare_request.zig`
- New lane file from Slice 2.1, likely under `howl-render/src/ffi/prepare_request.zig` or folded into `howl-render/src/ffi.zig`
- Any direct imports of `prepare_request.zig`

Exact non-goals:

- Do not move `vt_surface.zig`, `submission.zig`, `prepared_surface.zig`, `text_session.zig`, or `surface_geometry.zig` in this slice.
- Do not change `HowlRender*` C names.
- Do not alter prepare request ownership or token semantics.

Invariants:

- Exported C functions behave identically.
- C translator code delegates to owner files and does not own render policy.
- Root `howl-render/src/prepare_request.zig` no longer exists unless Slice 2.1 explicitly accepts it as the translator lane location.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg '@import\("prepare_request.zig"\)' howl-render/src` only hits the accepted new lane or prints nothing.
- `rg 'howl_render_text_session_take_prepare_request|HowlRenderPrepareRequest' howl-render/src` supports review that symbols moved only.

Reviewer checklist:

- Diffs are file movement/import updates only.
- Export root still curates exports only.
- Translator does not mutate session/source state except through existing owner methods.

Risks and stop conditions:

- Stop if moving the file requires behavior changes; promote a narrower translator-helper slice.

### Slice 2.3: Move Remaining Render Root Translators One At A Time

Owner/repo: `howl-render`.

Status: worker-ready after Slice 2.2 is accepted; promote one file per current slice.

Exact files likely edited per promoted child slice:

- `howl-render/src/vt_surface.zig`
- `howl-render/src/submission.zig`
- `howl-render/src/prepared_surface.zig`
- `howl-render/src/text_session.zig`
- `howl-render/src/surface_geometry.zig`
- `howl-render/src/libhowl_render.zig`

Exact non-goals:

- Do not combine all files in one worker slice.
- Do not rename ABI vocabulary.
- Do not change source/prepared/session ownership.

Invariants:

- One translator file moves per slice.
- Layout assertions remain adjacent to the C ABI translator they prove.
- Failure result construction is exact and tested.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- Per child slice: `rg '@import\("<old_file>.zig"\)' howl-render/src` only hits accepted new lane or prints nothing.
- `rg '^const .* = @import\("(vt_surface|submission|prepared_surface|text_session|surface_geometry)\.zig"\)' howl-render/src/libhowl_render.zig` must shrink monotonically.

Reviewer checklist:

- Each child slice is one file move and import repair only.
- No old compatibility wrappers remain at root.
- ABI layout assertions did not get separated from C translator facts.

Risks and stop conditions:

- Stop if a root file is discovered to be a true owner; send it to taxonomy research instead of moving it mechanically.

### Slice 2.4: Render `pipeline.zig` Symbol Inventory

Owner/repo: `howl-render`, research documentation.

Status: research-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/render-pipeline-inventory.md`

Exact non-goals:

- Do not rename `howl-render/src/text/pipeline.zig`.
- Do not edit `libs.yaml`.
- Do not split text shaping or raster code.

Invariants:

- Read full `howl-render/src/text/pipeline.zig` and all imports.
- Classify every public symbol into true owner nouns.
- Decide whether a simple file rename is honest or a split is required.

Verification commands:

- `git diff --check`

Grep gates:

- `rg 'pipeline|text_pipeline|text_flow' howl-render/src libs.yaml project-memory.md` results are inventoried in the document.

Reviewer checklist:

- Confirms no mechanical rename is proposed without symbol-level proof.
- Confirms proposed names are nouns/verbs from render text domain, not broad process buckets.

Risks and stop conditions:

- Stop if proposed replacement is another vague process name such as `flow`, `pipeline`, `manager`, or `engine`.

### Slice 2.5: Rename Or Split Render Text Pipeline By Proven Owner

Owner/repo: `howl-render`.

Status: blocked until Slice 2.4 is accepted.

Exact files likely edited:

- `howl-render/src/text/pipeline.zig`
- `howl-render/src/session/text.zig`
- `howl-render/src/text/frame_preparer.zig`
- `howl-render/src/text/font/ft_hb/support.zig`
- `howl-render/src/prepared/surface.zig`
- `howl-render/src/prepared/submit_result.zig`
- `libs.yaml`

Exact non-goals:

- Do not change text shaping, rasterization, scene prep, or submit metrics behavior.
- Do not update historical scratchpads except canonical owner map if required.
- Do not use compatibility aliases.

Invariants:

- `pipeline` and `text_flow` vocabulary are removed from code and `libs.yaml` unless Slice 2.4 proves a non-owner occurrence should remain as historical text.
- Replacement file names map to true owners and symbols.
- Tests still cover scene preparation and prepared submit metrics.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg 'pipeline|text_pipeline|text_flow' howl-render/src libs.yaml` prints nothing or only accepted non-owner prose.

Reviewer checklist:

- Confirms this is not cosmetic: symbols moved to exact owners.
- Confirms no behavior changes are hidden in the rename/split.
- Confirms `libs.yaml` matches source truth.

Risks and stop conditions:

- Stop if the split expands beyond text pipeline symbols.

## Phase 3: VT Wrapper/Bucket Reduction And FFI Ownership

Goal: remove VT convenience buckets and move owner behavior out of C translation without changing the product ABI.

Dependencies: Phase 1. Render phases can run independently after Phase 1, but VT FFI slices must not run before header grammar so ABI translator conventions are settled.

Top-down flow note:

- Keep public ABI shape pristine first.
- Then make owners small and honest, even if they are not final.
- Slow down only where VT internals require wider design proof.
- Branch design-heavy VT seams into child scratchpads instead of letting them derail the outer hygiene roadmap.
- Current child scratchpads:
  - `research/2026-05-30-hygiene-audit/vt-selection-ghostty-shape.md`
  - `research/2026-05-30-hygiene-audit/vt-data-type-maturity.md`
- These child scratchpads keep Phase 3 honest without prematurely redesigning the whole VT layer. The rule for now is: first make it simple, then defensive, then good.

Acceptance criteria:

- Internal code imports exact VT owners instead of broad buckets where promoted.
- `ffi.zig` translates C contracts and delegates behavior to owner files.
- C enum values, C structs, function names, and ABI behavior remain unchanged unless explicitly promoted later.

Exit gates:

- Root `zig build check`, `zig build test`, `git diff --check` pass.
- VT-specific tests pass if available through the current build.
- Grep gates prove bucket imports and FFI policy functions were removed for promoted seams.

### Slice 3.1: Shrink VT `input.zig` Bucket

Owner/repo: `howl-vt`.

Status: worker-ready after Phase 1.

Exact files likely edited:

- `howl-vt/src/input.zig`
- Internal callers of `@import("input.zig")`
- Likely exact owners under `howl-vt/src/input/`: `event.zig`, `encode.zig`, `mouse.zig`, `keyboard.zig`, `tokens.zig`, `encoded.zig`
- `howl-vt/src/ffi.zig` only if it imports the bucket and can safely import exact owners

Exact non-goals:

- Do not change `howl-vt/include/howl_vt.h` enum values or input ABI.
- Do not rewrite input encoding.
- Do not touch `action.zig`, `parser.zig`, or `kitty.zig` buckets in this slice.
- Do not delete tests for convenience.

Invariants:

- C input constants preserve exact numeric values.
- Internal callers import exact owner files.
- If `input.zig` remains, it is a narrow module index or test aggregator, not a compatibility lane.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg '@import\("input\.zig"\)' howl-vt/src` is empty except explicitly justified test aggregators.
- `rg 'pub const key_|pub const mouse_|pub const encode' howl-vt/src/input.zig` is empty unless each line is justified as module indexing only.
- `rg 'HOWL_VT_|HowlVtInput|HowlVtMouse' howl-vt/include/howl_vt.h howl-vt/src` supports numeric ABI review.

Reviewer checklist:

- Confirms no C ABI values changed.
- Confirms imports became more exact, not just renamed.
- Confirms no new broad wrapper replaced `input.zig`.

Risks and stop conditions:

- Stop if tests/fuzzers rely on `input.zig` as a public test root and no exact replacement is planned.
- Stop if numeric ABI coupling is unclear.

### Slice 3.2: Extract VT Selection Projection/Copy From FFI

Owner/repo: `howl-vt`.

Status: paused for child-scratchpad proof after Slice 3.1.

Child scratchpad:

- `research/2026-05-30-hygiene-audit/vt-selection-ghostty-shape.md`

Reason:

- The original extraction looked mechanical, but Ghostty proves selection is a screen-owned, tracked-position concept, not merely an FFI helper. Howl may still do a bounded FFI extraction, but only after the child scratchpad defines the temporary owner honestly and records the later Ghostty-like screen/page proof gap.

Exact files likely edited:

- `howl-vt/src/ffi.zig`
- `howl-vt/src/selection.zig`
- `howl-vt/src/selection/state.zig`
- Possibly `howl-vt/src/screen_set.zig` or a new exact VT surface/view owner if current owner proof requires it

Exact non-goals:

- Do not change exported `howl_vt_*` function names.
- Do not introduce `HowlVt*` C structs into selection owner files unless an explicit C-only adapter is created.
- Do not change selection semantics across history/live rows.
- Do not redesign the selection product ABI.

Invariants:

- FFI retains pointer casts, C status mapping, and C span translation only.
- Selection owner owns selection text materialization and visible selection projection.
- Existing history-aware copy and visible-selection tests remain equivalent.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg 'fn copySelectionText|fn applyVisibleSelection|fn visibleSelectionRange|fn selectionRowSource' howl-vt/src/ffi.zig` prints nothing.
- `rg 'HowlVt' howl-vt/src/selection howl-vt/src/screen_set.zig` prints nothing unless the diff creates a clearly named C adapter.
- `rg 'selection' howl-vt/src/ffi.zig` supports review that remaining mentions are C entry translation only.

Reviewer checklist:

- Confirms selection behavior moved to selection/surface owner, not to another FFI helper bucket.
- Confirms invalid ranges and history/live row boundaries remain asserted/tested.
- Confirms allocation ownership for copied text is explicit.

Risks and stop conditions:

- Stop if selection owner cannot access required screen history without pulling C ABI types inward.
- Stop if tests are insufficient for history/live row semantics; add tests in the same slice only for moved behavior.

### Slice 3.3: Reduce VT `action.zig` Bucket

Owner/repo: `howl-vt`.

Status: research-ready until `input.zig` work proves the pattern.

Exact files likely edited:

- `howl-vt/src/action.zig`
- Internal callers of `@import("action.zig")`
- `howl-vt/src/action/route.zig`
- `howl-vt/src/action/vocabulary.zig`
- Parser or xterm callers that use action aliases

Exact non-goals:

- Do not change parser event semantics.
- Do not rename ESC/CSI/OSC action vocabulary without a protocol-backed slice.
- Do not combine with parser root cleanup.

Invariants:

- Action route remains the behavior owner for routing.
- Vocabulary remains the owner for action nouns.
- Bucket exports disappear only after all internal callers import exact owners.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg '@import\("action\.zig"\)' howl-vt/src`
- `rg 'pub const .* = .*\.' howl-vt/src/action.zig`

Reviewer checklist:

- Confirms direct imports improve owner clarity.
- Confirms no protocol vocabulary changed.

Risks and stop conditions:

- Stop if parser/action call graph is not fully inventoried.

### Slice 3.3a: VT Protocol Scalar Vocabulary

Owner/repo: `howl-vt`.

Status: child-scratchpad proposed; not promoted until selection FFI extraction is accepted or deliberately deferred.

Child scratchpad:

- `research/2026-05-30-hygiene-audit/vt-data-type-maturity.md`

Goal:

- Replace raw numeric protocol domains with small exact types where the type prevents semantic mixups, while preserving parser tables and ABI behavior.

Likely exact files:

- `howl-vt/src/xterm/c0.zig`
- `howl-vt/src/xterm/csi/params.zig`
- `howl-vt/src/action/vocabulary.zig`
- Direct screen/action call sites exposed by the type change.

Exact non-goals:

- Do not rewrite parser tables.
- Do not change public C ABI.
- Do not redesign screen storage.
- Do not create `types.zig` or any broad scalar bucket.

Invariants:

- Dense byte/state parser transitions remain table-driven and source-order auditable.
- Semantic dispatch remains union/switch-driven where that is clearer than lookup tables.
- Raw `u2` erase mode and raw handled C0 control meaning should become named protocol types if the diff remains bounded.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg 'erase_display: u2|erase_line: u2|selective_erase_display: u2|selective_erase_line: u2' howl-vt/src/action/vocabulary.zig` prints nothing after replacement.
- `rg '0x0A|0x0B|0x0C|0x0D|0x08|0x09' howl-vt/src/xterm/c0.zig` supports review that C0 byte constants are named or intentionally mapped.

Risks and stop conditions:

- Stop if type changes spread into ABI names or C structs.
- Stop if the slice starts packing screen cell/style storage; that belongs to Phase 4 child research.
- Stop if the new types only wrap values without improving owner truth or reviewability.

### Slice 3.4: Reduce VT `parser.zig` And `kitty.zig` Buckets

Owner/repo: `howl-vt`.

Status: research-ready.

Exact files likely edited:

- `howl-vt/src/parser.zig`
- `howl-vt/src/kitty.zig`
- Internal callers of those roots
- Exact owner files under `howl-vt/src/parser/*` and `howl-vt/src/kitty/*`

Exact non-goals:

- Do not change parser state machine behavior.
- Do not change Kitty protocol behavior.
- Do not delete useful test aggregators without replacing exact imports.

Invariants:

- Parser and Kitty roots may only aggregate owner modules if kept.
- No host integration path may target internal Zig roots.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg '@import\("parser\.zig"\)|@import\("kitty\.zig"\)' howl-vt/src`
- `rg 'pub const .* = .*\.' howl-vt/src/parser.zig howl-vt/src/kitty.zig`

Reviewer checklist:

- Confirms roots are module indexes only or gone.
- Confirms protocol tests still cover parser/Kitty paths.

Risks and stop conditions:

- Stop if parser or Kitty tests rely on broad roots in a way that requires a test taxonomy decision.

## Phase 4: VT Terminal/Screen Deeper Owner Roadmap

Goal: split the VT near-redo into exact owner seams rather than one giant rewrite.

Dependencies: Phase 3 should remove obvious wrappers first. Deeper terminal/screen work must start only with a child scratchpad for the promoted seam.

Acceptance criteria:

- `Terminal` remains the state transition entrypoint unless a slice proves a narrower entrypoint.
- Each extracted owner owns one state group and its invariants.
- No slice moves unrelated terminal, screen, selection, host, Kitty, and parser behavior together.

Exit gates:

- Existing terminal surface tests stay green.
- Grep gates prove the exact field/method seam moved and no broad replacement bucket appeared.

### Slice 4.1: Extract VT Surface Publication State

Owner/repo: `howl-vt`.

Status: worker-ready after Phase 3.2 or research-ready if selection ownership remains unclear.

Exact files likely edited:

- `howl-vt/src/terminal.zig`
- New exact owner file, likely `howl-vt/src/surface/publication.zig` or an existing proven owner
- `howl-vt/src/ffi.zig` only if calls need updated owner methods
- Existing surface tests, likely under `howl-vt/src/test/terminal_surface.zig`

Exact non-goals:

- Do not change C ABI.
- Do not move selection, host consequences, runtime obligation, parser stream, or Kitty state.
- Do not rename `Terminal`.

Invariants:

- `Terminal` composes the publication owner and remains the external mutation entrypoint.
- `surface_snapshot_*` fields leave `terminal.zig`.
- Ack idempotence, dirty row clearing, scrollback snapshot change, alternate-screen snapshot change, and invalid snapshot zero are asserted/tested.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg 'surface_snapshot_' howl-vt/src/terminal.zig` prints nothing.
- `rg 'ackSurface|surfaceSnapshot|visibleMeta|noteSurfacePublication' howl-vt/src/terminal.zig` shows only thin delegation or nothing.

Reviewer checklist:

- Confirms publication owner is not a vague `surface` bucket; it owns publication state only.
- Confirms dirty generation and snapshot validity invariants are paired with assertions/tests.
- Confirms FFI still translates only.

Risks and stop conditions:

- Stop if choosing the owner path requires inventing a broad `surface` umbrella.
- Stop if surface publication semantics are not covered by tests.

### Slice 4.2: VT Host Consequence Capacity Plan

Owner/repo: `howl-vt`, research documentation.

Status: research-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/vt-host-consequence-capacity.md`

Exact non-goals:

- Do not change allocation behavior.
- Do not convert `ArrayList` storage.
- Do not alter OSC 52, hyperlink, title, or report semantics.

Invariants:

- Inventory every `ArrayList`, `dupe`, and allocation path in `howl-vt/src/host`, `howl-vt/src/parser/events.zig`, and control report paths.
- Record existing bounds: pending output bytes, retained payload bytes, title bytes, hyperlink count, queued parser events.
- Decide one first bounded-storage implementation slice or record why no slice is ready.

Verification commands:

- `git diff --check`

Grep gates:

- `rg 'ArrayList|dupe|alloc' howl-vt/src/host howl-vt/src/parser/events.zig howl-vt/src/control` results are inventoried in the document.

Reviewer checklist:

- Confirms this is capacity proof, not runtime invention.
- Confirms every dynamic path has an owner and bound or a proof gap.

Risks and stop conditions:

- Stop if a proposed static allocation would bloat memory without a capacity argument.

### Slice 4.3: Screen Owner Seam Inventory

Owner/repo: `howl-vt`, research documentation.

Status: research-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/vt-screen-owner-seams.md`

Exact non-goals:

- Do not edit `howl-vt/src/screen.zig`.
- Do not move cursor, margins, history, dirty rows, tabs, or resize code.

Invariants:

- Read `howl-vt/src/screen.zig` and `howl-vt/src/screen/*` fully enough to map fields to true owner files.
- Identify first extractable seam with exact tests and grep gates.
- Preserve `Screen` as owner unless source proves a narrower owner already exists.

Verification commands:

- `git diff --check`

Grep gates:

- `rg 'cursor|margins|history|dirty|tabs|resize' howl-vt/src/screen.zig howl-vt/src/screen` findings are recorded in the document.

Reviewer checklist:

- Confirms no giant screen rewrite is proposed.
- Confirms first seam has field names, methods, tests, and stop conditions.

Risks and stop conditions:

- Stop if the inventory produces more than one implementation slice without ordering dependencies.

### Slice 4.4: VT Runtime Obligation Vocabulary Decision

Owner/repo: `howl-vt`, research documentation.

Status: research-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/vt-runtime-obligation-vocabulary.md`

Exact non-goals:

- Do not rename `howl_vt_terminal_query_runtime_obligation`.
- Do not change ABI.
- Do not create a runtime owner.

Invariants:

- Decide whether `runtime` is accepted protocol/ABI vocabulary or banned owner vocabulary leaking into ABI.
- Inventory host call sites and behavior expectations.

Verification commands:

- `git diff --check`

Grep gates:

- `rg 'runtime_obligation|RuntimeObligation|runtime' howl-vt howl-linux-host project-memory.md`

Reviewer checklist:

- Confirms vocabulary decision is source-backed.
- Confirms no implementation is mixed into research.

Risks and stop conditions:

- Stop if changing ABI vocabulary would require a broader host/render contract decision.

## Phase 5: Host Context/Main Hygiene Slices

Goal: apply host hygiene only where Alacritty/Ghostty/Howl memory backs the seam. Do not split host files merely because they are large.

Dependencies: none after Phase 1 for documentation-only gates. Implementation host slices can run after VT/render work if they do not touch shared call sites.

Acceptance criteria:

- Main-thread control flow remains centralized.
- Per-terminal `Context` remains the embedded terminal widget/session aggregate.
- Extracted host owners have crisp state and invariants.
- No fake runtime/controller split appears.

Exit gates:

- Host package `zig build check` and `zig build test` pass if package verification is available.
- Root `zig build check`, `zig build test`, and `git diff --check` pass.

### Slice 5.1: Host Main Future-Slice Admission Gate

Owner/repo: workspace root, research documentation.

Status: worker-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/host-admission-gate.md`

Exact non-goals:

- Do not edit `howl-linux-host/src/main.zig`.
- Do not move tests.
- Do not create a host app/runtime split.

Invariants:

- Future host slices may not add top-level structs/functions to `main.zig` unless they prove app ownership.
- Splitting `main.zig` is banned unless the target owner is exact and source-backed.
- Host consumes PTY/VT/render only through C ABI translated modules.

Verification commands:

- `git diff --check`

Grep gates:

- `rg 'main\.zig|app ownership|runtime|controller|manager' research/2026-05-30-hygiene-audit/host-admission-gate.md`

Reviewer checklist:

- Confirms the gate prevents fake progress.
- Confirms accepted host direction from project memory is preserved.

Risks and stop conditions:

- Stop if the document proposes splitting app event loop ownership.

### Slice 5.2: Host Cursor Blink Owner Extraction

Owner/repo: `howl-linux-host`.

Status: worker-ready after fresh read of current `context.zig` confirms line ranges.

Exact files likely edited:

- `howl-linux-host/src/terminal/context.zig`
- New exact owner file such as `howl-linux-host/src/terminal/cursor_blink.zig`
- Existing host terminal tests that cover cursor blink cadence

Exact non-goals:

- Do not move render turn sequencing.
- Do not move clipboard policy.
- Do not move VT runtime obligation adaptation.
- Do not change host wake/present cadence.

Invariants:

- Main-thread sequencing remains in `Context`/app owner.
- Cursor blink owner owns only deadline/phase policy and exact reset/tick calculations.
- VT cursor blink truth remains VT-owned; host owns cadence.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- `rg 'cursor_blink_deadline_ns|cursor_blink' howl-linux-host/src/terminal/context.zig howl-linux-host/src/terminal` shows fields and logic live in the new owner with only composition/delegation in context.

Reviewer checklist:

- Confirms this is not an anemic pass-through.
- Confirms cadence policy remains host-owned and VT truth is not overwritten.
- Confirms no runtime/controller vocabulary was introduced.

Risks and stop conditions:

- Stop if extraction requires moving event-loop or render-turn control.

### Slice 5.3: Host Main Tests Relocation Decision

Owner/repo: `howl-linux-host`, research documentation first.

Status: research-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/host-main-tests.md`

Exact non-goals:

- Do not move tests yet.
- Do not make private helpers public just for tests.
- Do not invent a repo-wide test taxonomy; that is the build/test architecture backlog.

Invariants:

- Inventory tests currently embedded in `howl-linux-host/src/main.zig` and the private helpers they exercise.
- Decide whether helpers belong in true owner files with tests, or whether tests should stay until build/test taxonomy is resolved.

Verification commands:

- `git diff --check`

Grep gates:

- `rg '^test "' howl-linux-host/src/main.zig` results are inventoried in the document.

Reviewer checklist:

- Confirms no broad public aliases are proposed.
- Confirms test movement is blocked if taxonomy is not worker-ready.

Risks and stop conditions:

- Stop if relocation requires adding public test-only product APIs.

## Phase 6: In-File Organization Convention

Goal: write a strict convention, then apply it only when touching files for real owner work or for one proven ABI translator demonstration.

Dependencies: Phase 1. The convention must not become a license for style-only churn across the repo.

Acceptance criteria:

- Convention is documented once.
- Implementation usage is tied to a specific owner/ABI translator and verified by tests.
- No decorative banners are introduced.

Exit gates:

- Convention document passes review.
- First application slice shows no behavior changes except explicitly tested helper extraction.

### Slice 6.1: Document In-File Organization Convention

Owner/repo: workspace root, research documentation.

Status: worker-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/in-file-organization.md`

Exact non-goals:

- Do not edit product code.
- Do not add formatter tooling.
- Do not create section banners.

Invariants:

- Imports first, grouped by std/C ABI/local owners.
- Constants and compile-time assertions near the top.
- Owner structs order fields, nested simple types, methods.
- Public lifecycle/control/data methods precede private helpers; single-caller helpers stay adjacent when clearer.
- Tests last except package test aggregators.
- Comments explain why/protocol facts; assertions prove invariants.

Verification commands:

- `git diff --check`

Grep gates:

- `rg 'fields.*nested.*methods|compile-time assertions|Tests last|No banner' research/2026-05-30-hygiene-audit/in-file-organization.md`

Reviewer checklist:

- Confirms TigerBeetle references are represented accurately.
- Confirms convention is not vague style advice.
- Confirms no repo-wide rewrite is implied.

Risks and stop conditions:

- Stop if convention conflicts with owner movement rules.

### Slice 6.2: Apply Convention To One ABI Translator

Owner/repo: selected ABI library.

Status: blocked until Slice 6.1 and a candidate file are accepted.

Exact files likely edited:

- Candidate: `howl-render/src/vt_surface.zig` or its new render C lane path after Phase 2.

Exact non-goals:

- Do not combine with ABI symbol renames.
- Do not combine with broad file moves unless the file has already moved in Phase 2.
- Do not change behavior.

Invariants:

- Layout assertions stay paired with C translator structs.
- Repeated failure result literals may become a helper only if helper ownership is exact and tests prove identical behavior.
- Function length and line length pressure are improved without hiding control flow.

Verification commands:

- `zig build check`
- `zig build test`
- `git diff --check`

Grep gates:

- Candidate-specific grep for repeated failure literals, layout assertions, and exported names before/after.

Reviewer checklist:

- Confirms diff is organization plus exact helper extraction only.
- Confirms no C ABI behavior changed.

Risks and stop conditions:

- Stop if a style rewrite obscures behavior; split into smaller helper or abandon.

## Phase 7: Research/Backlog Slices Not Worker-Ready

Goal: keep unresolved proof gaps out of implementation slices.

Dependencies: none, but these do not block Phases 1-3 unless they touch the same files.

Acceptance criteria:

- Each backlog item has a research scratchpad before any code work.
- No feature gap is mixed into hygiene implementation.

### Slice 7.1: Header Generation Versus Hand-Maintained Grammar

Owner/repo: workspace root, build/test architecture research.

Status: research-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/header-generation-gap.md`

Exact non-goals:

- Do not add generation tooling.
- Do not edit build files.

Invariants:

- Compare hand-maintained generated-looking headers against generated ABI metadata.
- Respect project-memory build/test architecture blocker.

Verification commands:

- `git diff --check`

Grep gates:

- `rg 'header generation|hand-maintained|build/test architecture' research/2026-05-30-hygiene-audit/header-generation-gap.md`

Reviewer checklist:

- Confirms no tooling is proposed without build taxonomy plan.

Risks and stop conditions:

- Stop if this becomes a build-system implementation slice.

### Slice 7.2: Render `surface/*` Taxonomy Proof

Owner/repo: `howl-render`, research documentation.

Status: research-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/render-surface-taxonomy.md`

Exact non-goals:

- Do not move `howl-render/src/surface/*`.
- Do not edit `libs.yaml` until implementation is accepted.

Invariants:

- Decide whether current `surface/*` files are true owners or stale after accepted render direction.
- Produce one first worker-ready move or record blocked status.

Verification commands:

- `git diff --check`

Grep gates:

- `rg 'surface/' howl-render/src libs.yaml project-memory.md` findings are recorded.

Reviewer checklist:

- Confirms `surface` remains product ABI vocabulary, not umbrella source folder, unless proved otherwise.

Risks and stop conditions:

- Stop if proposed movement spans source, prepared, session, and render owners together.

### Slice 7.3: VT `howl_vt.zig` Internal Root Decision

Owner/repo: `howl-vt`, research documentation.

Status: research-ready.

Exact files likely edited:

- `research/2026-05-30-hygiene-audit/vt-internal-root.md`

Exact non-goals:

- Do not edit `howl-vt/src/howl_vt.zig`.
- Do not change tests.

Invariants:

- Inventory all imports of `howl_vt.zig`.
- Decide whether it is a test aggregator, internal package root, or stale Zig-shaped lane.

Verification commands:

- `git diff --check`

Grep gates:

- `rg '@import\("howl_vt\.zig"\)|howl_vt\.zig' howl-vt howl-linux-host`

Reviewer checklist:

- Confirms no host path targets this root.
- Confirms any retained root has a narrow purpose.

Risks and stop conditions:

- Stop if root deletion would require a test taxonomy decision.

### Slice 7.4: Product Feature Gap Backlog Isolation

Owner/repo: workspace root, research documentation.

Status: verification-only.

Exact files likely edited:

- None unless updating future sprint planning after user approval.

Exact non-goals:

- Do not implement hyperlinks, selection product ABI, OSC 52 query/reply, dynamic colors, resize truth, signal target truth, style preservation, title propagation, or cursor blink ABI truth in this hygiene sprint.

Invariants:

- Feature gaps remain in `project-memory.md` backlog and are not smuggled into hygiene slices.

Verification commands:

- `git diff --check`

Grep gates:

- During review, inspect diffs for `OSC 52`, `hyperlink`, `dynamic color`, `resize`, `signal`, `title`, `DECSCUSR` changes unless the active slice explicitly allows them.

Reviewer checklist:

- Confirms hygiene slices do not implement feature backlog items.

Risks and stop conditions:

- Stop any worker that bundles feature work into structure work.

## First 3 Slices To Promote

1. `Define C ABI Header Grammar`.
Rationale: synthesis marks this as safest and highest-leverage. It targets the ABI product boundary and gives later workers exact gates instead of style vibes.

2. `Apply Header Grammar Without ABI Semantic Changes`.
Rationale: once grammar exists, the implementation is bounded to comments, order, and wrapping in three public headers. It improves the product lane before deeper code movement.

3. `Render C Translator Lane Decision`.
Rationale: render has the messiest Zig export/translator lane. A short decision scratchpad prevents fake movement of root shims into another vague bucket and prepares one-file-at-a-time render implementation slices.

## Documentation/Planning Slices

- Slice 1.1: `Define C ABI Header Grammar`.
- Slice 2.1: `Render C Translator Lane Decision`.
- Slice 2.4: `Render pipeline.zig Symbol Inventory`.
- Slice 4.2: `VT Host Consequence Capacity Plan`.
- Slice 4.3: `Screen Owner Seam Inventory`.
- Slice 4.4: `VT Runtime Obligation Vocabulary Decision`.
- Slice 5.1: `Host Main Future-Slice Admission Gate`.
- Slice 5.3: `Host Main Tests Relocation Decision`.
- Slice 6.1: `Document In-File Organization Convention`.
- Slice 7.1: `Header Generation Versus Hand-Maintained Grammar`.
- Slice 7.2: `Render surface/* Taxonomy Proof`.
- Slice 7.3: `VT howl_vt.zig Internal Root Decision`.

## Implementation Slices

- Slice 1.2: `Apply Header Grammar Without ABI Semantic Changes`.
- Slice 1.3: `Normalize ABI Export Root Order`.
- Slice 2.2: `Move prepare_request.zig Into The Render C Lane`.
- Slice 2.3: `Move Remaining Render Root Translators One At A Time`.
- Slice 2.5: `Rename Or Split Render Text Pipeline By Proven Owner`.
- Slice 3.1: `Shrink VT input.zig Bucket`.
- Slice 3.2: `Extract VT Selection Projection/Copy From FFI`.
- Slice 3.3: `Reduce VT action.zig Bucket` after research/pattern proof.
- Slice 3.4: `Reduce VT parser.zig And kitty.zig Buckets` after research.
- Slice 4.1: `Extract VT Surface Publication State`.
- Slice 5.2: `Host Cursor Blink Owner Extraction`.
- Slice 6.2: `Apply Convention To One ABI Translator`.

## Do Not Do

- Do not create `manager`, `controller`, `engine`, `runtime`, `pipeline`, `queue`, or `types.zig` owners.
- Do not add Zig-shaped host integration shortcuts to internal terminal modules.
- Do not copy Ghostty's broad Zig module lane or multi-header public shape wholesale.
- Do not make compatibility aliases for old ABI names or stale render vocabulary.
- Do not rename `pipeline.zig` mechanically before symbol inventory.
- Do not split host `main.zig` merely because it is large.
- Do not move tests by making product helpers broadly public.
- Do not rewrite VT terminal/screen in one slice.
- Do not mix feature backlog items with hygiene structure work.
- Do not add header generation tooling before the build/test architecture blocker is resolved.
- Do not use decorative section banners as a substitute for owner order.

## Commit Strategy

Use one accepted slice per commit in the package repo that owns the files, then commit the workspace root pointer/update only after the package commit is accepted. This keeps binary reverts cheap and preserves submodule/root accountability.

Required sequence after each accepted implementation slice:

1. Inspect package `git status`, `git diff`, and recent log.
2. Run the slice verification commands.
3. Commit only intended package files with a concise owner-first message such as `render: move prepare request ABI translator` or `vt: shrink input bucket`.
4. Return to workspace root.
5. Inspect root `git status`, `git diff`, and recent log.
6. Commit the root pointer or planning file update separately with a message such as `root: record render C lane slice`.

Documentation-only slices in the root should be committed as root-only commits after review acceptance. Do not commit unaccepted worker diffs. Do not amend unless explicitly requested. Do not push unless explicitly requested.

## Open Proof Gaps

Status note, 2026-05-30: parts of this roadmap are now historical. Before
promoting any listed worker-ready slice, verify current source and
`project-memory.md`. In particular, the render `ffi/*` C translator lane, render
`surface/*` source-bucket deletion, and VT scalar `C0`/`EraseMode` vocabulary are
already complete in current source.

- Capacity design for VT host consequences using `ArrayList`, `dupe`, and allocation in protocol paths.
- First true owner seam inside `howl-vt/src/screen.zig` beyond surface publication.
- Test taxonomy for moving host `main.zig` tests without adding public helper aliases.
- Build/test architecture strategy for adding durable grep gates or generated checks.
