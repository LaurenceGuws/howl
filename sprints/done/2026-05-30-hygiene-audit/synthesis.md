# Hygiene Audit Synthesis

Date: 2026-05-30

Inputs:

- `researcher-a.md`
- `researcher-b.md`
- `researcher-c.md`

Scope: top-down hygiene findings for host, PTY, VT, and render, with emphasis on C ABI lane shape, owner/file/symbol convention, and in-file organization.

## Consensus Findings

### 1. C ABI Lane Must Become Factory-Clean

All researchers found the C ABI lane is not uniform enough across `howl-pty`, `howl-vt`, and `howl-render`.

Evidence cited:

- PTY root exports only `ffi`: `howl-pty/src/libhowl_pty.zig:1`, `howl-pty/src/libhowl_pty.zig:3-18`.
- VT root exports only `ffi`: `howl-vt/src/libhowl_vt.zig:1`, `howl-vt/src/libhowl_vt.zig:3-31`.
- Render root exports from multiple root-level boundary files: `howl-render/src/libhowl_render.zig:1-7`, `howl-render/src/libhowl_render.zig:10-36`.
- VT header has hand banners: `howl-vt/include/howl_vt.h:83`, `howl-vt/include/howl_vt.h:247`, `howl-vt/include/howl_vt.h:295`, `howl-vt/include/howl_vt.h:302`.
- Render header has a long accumulated function list: `howl-render/include/howl_render.h:376-405`.
- PTY header is closest to the desired compact lane: `howl-pty/include/howl_pty.h:95-118`.

Reference pressure:

- ABIs are the product: `AGENTS.md:9`.
- Public roots curate exports only and FFI translates contracts only: `AGENTS.md:107`, `AGENTS.md:110`.
- TigerBeetle naming/top-down order/comment pressure: `TIGER_STYLE.md:273`, `TIGER_STYLE.md:315`, `TIGER_STYLE.md:360-367`, `TIGER_STYLE.md:463`.
- Ghostty shows a separate C lane, but Howl must not copy Ghostty's broad Zig module lane.

Synthesis:

- The first C-lane slice should define and apply a header grammar without changing ABI values or behavior.
- A second C-lane slice should normalize render's Zig export/translator lane so it does not look like scattered root owners.

### 2. VT Has The Worst Bucket/Wrapper Debt

All researchers flagged VT wrapper roots and broad ownership.

Evidence cited:

- `howl-vt/src/input.zig:7-93` re-exports keyboard, mouse, event, encoding, constants, and functions.
- `howl-vt/src/action.zig:6-22` re-exports parser events, vocabulary, route functions, and ESC actions.
- `howl-vt/src/parser.zig:3-17` re-exports parser internals.
- `howl-vt/src/kitty.zig:1-11` re-exports kitty owner files.
- `howl-vt/src/howl_vt.zig:1-14` forms a broad repo-local root.
- `howl-vt/src/terminal.zig:24-42` composes too much state directly.
- `howl-vt/src/ffi.zig:442-538` owns selection projection/copy behavior inside C translation.

Reference pressure:

- Namespace wrappers aggregate owners only; owner files own state and mutation: `AGENTS.md:107-110`.
- Internal terminal modules are not host Zig integration targets: `AGENTS.md:91`.
- TigerBeetle exact naming and top-down order: `TIGER_STYLE.md:273`, `TIGER_STYLE.md:315`.

Synthesis:

- `input.zig` is the safest first VT bucket slice because it is visibly a re-export bucket and likely has bounded call-site fallout.
- `ffi.zig` selection extraction is also high-value because it moves behavior out of C translation, but it touches semantics and needs stronger tests.
- VT terminal/surface publication extraction is promising but must remain one exact seam, not a broad VT redo.

### 3. Render Has Root Translator And Taxonomy Debt

Researchers agreed render is cleaner than VT in owner folders but still has stale root shims and banned vocabulary.

Evidence cited:

- `howl-render/src/libhowl_render.zig:1-7` imports root files rather than a single C lane.
- `howl-render/src/vt_surface.zig:1`, `howl-render/src/submission.zig:1`, `howl-render/src/prepare_request.zig:1`, and related root files look like owners or shims.
- `howl-render/src/text/pipeline.zig` uses banned `pipeline` vocabulary.
- `howl-render/src/session/text.zig:17` imports `text/pipeline.zig` as `text_pipeline`.
- `howl-render/src/text/frame_preparer.zig:6` imports it as `pipeline`.

Reference pressure:

- Project memory rejects vague owner buckets and `pipeline`: `project-memory.md:29-31`.
- Render accepted direction is source/prepared/session/render owners and no broad surface/pipeline bucket: `project-memory.md:168-192`.

Synthesis:

- Do not mechanically rename `pipeline.zig` without reading its full symbol set.
- The smallest render implementation slice may be `prepare_request.zig` root-shim deletion/move, but only after deciding the render C lane convention.

### 4. In-File Organization Needs A Written Convention Before Style Rewrites

Researchers converged on a TigerBeetle-derived convention:

- Imports first, grouped by std/C ABI/local owners.
- Constants and compile-time assertions near the top.
- For owner structs: fields, nested simple types, methods.
- Public lifecycle/control/data methods before private helpers, with helpers adjacent to single callers unless reused.
- Tests last, except package test aggregators.
- No default banner sections in Zig files.
- Header banners should be replaced by consistent declaration order.
- Comments explain why/protocol facts; assertions prove invariants.

Source pressure:

- Struct order: `TIGER_STYLE.md:315-332`.
- Assertions and invariant proof: `TIGER_STYLE.md:104-147`.
- Comments: `TIGER_STYLE.md:360-370`.
- Line length: `TIGER_STYLE.md:463`.

## Recommended First Slice

Promote a planning/documentation slice first:

Name: `Define C ABI Header Grammar`.

Why first:

- It directly targets the user's highest symptom: C ABI root layout should look factory-generated.
- It is safer than touching VT semantics or render root shims.
- It gives later workers exact ordering/formatting rules instead of style vibes.

Scope:

- Add a concise documented convention, likely under `research/2026-05-30-hygiene-audit/c-abi-header-grammar.md` or `project-memory.md` if accepted.
- Inventory current header order in:
  - `howl-pty/include/howl_pty.h`
  - `howl-vt/include/howl_vt.h`
  - `howl-render/include/howl_render.h`
- Decide exact grammar:
  - include guard
  - C includes
  - `extern "C"`
  - opaque handles
  - limits/macros
  - status/result enums
  - product enums
  - structs
  - functions grouped by owner handle
  - no ornamental banners
  - wrapped prototypes under 100 columns
- Do not change symbols, numeric values, struct layout, or behavior in the planning slice.

Verification for later implementation:

- `zig build check`, `zig build test` in root and each ABI repo.
- `git diff --check`.
- Long-line grep over `howl-*/include/*.h`.
- Grep no ornamental banners in public headers.
- Existing ABI layout tests still pass.

## Alternative First Implementation Slices

If skipping the planning slice:

1. Header-only grammar pass across all three headers, no ABI semantic changes.
2. VT `input.zig` bucket shrink/delete by replacing internal callers with exact owner imports.
3. Render C lane normalization for `libhowl_render.zig` and root translator files.
4. Extract VT FFI selection copy/projection behavior from `ffi.zig`.
5. Research-only `text/pipeline.zig` symbol inventory before renaming or splitting.

## Open Questions

- Should C headers be generated from an ABI description or hand-maintained with generated-looking rules?
- Should ABI layout assertions live in one `ffi.zig` per library or beside owner-specific ABI adapters?
- Is `howl-vt/src/howl_vt.zig` still useful as repo-local test aggregation, or should tests import exact owners?
- Is `runtime` acceptable as shipped ABI vocabulary in VT obligations, or does it violate the project vocabulary ban?
- Is render `surface/*` still source-backed owner truth or stale taxonomy that needs a separate cleanup?
