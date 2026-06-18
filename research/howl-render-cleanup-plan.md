# Howl Render Cleanup Plan

Status: active planning seed after VT render-state maturity closure.

Orchestrator session id: `orch-2026-06-18-render-cleanup-accountability-01`.

Purpose:

- Clean up already-landed Howl render slop with deletion-first discipline.
- Make stale concepts impossible to preserve by accident.
- Build deterministic search and review habits for dead code, fuzzy duplication, and breached ownership.

Current accepted context:

- VT render-state maturity is closed by root `fb7b0f6`.
- Renderer old-surface residue was found after closure: `howl-render/src/vt_surface` survived.
- That residue cleanup is the first proof that passing tests and narrow search gates are not enough.

Immediate completed cleanup awaiting commit:

- Added `howl-render/src/text/cursor_presentation.zig` for the remaining live cursor presentation contract data.
- Updated `howl-render/src/text/contract.zig`, `scene.zig`, and `scene_rects.zig` to use the text-owned data.
- Deleted `howl-render/src/vt_surface/cursor.zig`, `damage.zig`, `surface.zig`, `text_input.zig`, and `theme.zig`.
- Removed the empty `howl-render/src/vt_surface` directory.
- Verification passed before this seed: no old surface names in `howl-render/src` or `howl-render/include`, `howl-render` `zig build test:unit`, `howl-render` `zig build check`, and root `zig build check`.

Next research task:

- Inventory `howl-render/src` and `howl-render/include` for stale/bucket/fake nouns and dead code.
- Produce exact findings with file paths, importers, reachability roots, proposed delete/rename/move shape, required tests, and whole-package negative search gates.
- Start from current source only. Historical artifacts are navigation, not authority.

Terms requiring scrutiny:

- `contract`
- `session`
- `owner`
- `pipeline`
- `context`
- `state`
- `options`
- `info`
- `data`
- `result`
- stale source-reference names or comments, including direct product use of reference project names.

Folder pressure:

- Keep `text/` only for real text concepts.
- Move breached scope sideways into shallow exact owners only when source proves them.
- Candidate sideways owners must be source-proved before creation, for example `color/`, `effects/`, `metrics/`, `scene/`, or `cursor/`.
- Do not create nested buckets to hide scope creep.

Dead-code rule:

- Every declaration must be reachable from an explicit product, ABI, test, or benchmark root, or be removed.
- If a missing caller is the real bug, add that caller only when the owner contract proves it should exist.
- Test-only code in product files requires loud banner comments and owner-local proof; no test-only public substitute is allowed.

C ABI rule:

- Translated C modules are canonical ABI truth.
- Only thin C/ABI boundary files should import translated C modules directly once that cleanup is planned.
- Zig wrappers around C constants or structs are allowed only at true owner boundaries and only when they add behavior, safety, or domain decisions.
- Hand-written ABI mirrors without behavior are suspicious by default.

Readiness:

- Not worker-ready for broad cleanup yet.
- Researcher must produce the exact first deletion/naming slice and reviewer must gate it before implementation.
