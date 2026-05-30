# Render Surface Taxonomy

Date: 2026-05-30

## Question

Decide whether current `howl-render/src/surface/*` files are true owners or stale after the accepted
render direction, and produce one first worker-ready move.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `project-memory.md` render sections
- `research/2026-05-30-hygiene-audit/roadmap.md` Slice 7.2
- `libs.yaml`
- `howl-render/src/surface/buffer.zig`
- `howl-render/src/surface/prepared_owner.zig`
- `howl-render/src/surface/tokens.zig`
- `howl-render/src/surface/publication_source.zig`
- `howl-render/src/surface/clip_rect.zig`
- `howl-render/src/surface/geometry.zig`
- `howl-render/src/surface/input.zig`
- `howl-render/src/surface/rgba.zig`
- importers reported by `rg 'surface/' howl-render/src libs.yaml project-memory.md`

## Findings

- `surface` remains valid product vocabulary at the ABI boundary, but `howl-render/src/surface/` is
  a stale mixed source bucket.
- `surface/buffer.zig` composes prepared RGBA pixels from a prepared text frame and retained base
  pixels. It belongs with prepared output realization, not a broad surface folder.
- `surface/prepared_owner.zig` owns prepared handle lifecycle, publication/submit state, copied RGBA
  payload, diagnostics, and prepared-handle release/consume. It belongs under `prepared/`.
- `surface/tokens.zig` defines snapshot/prepared/submitted tokens, damage kind, submit validation,
  render result, and a latest-mailbox helper. It is a cross-owner render contract. It needs a separate
  token-contract slice because source, prepared, session, FFI, and damage owners import it.
- `surface/publication_source.zig` defines VT-source publication structs and layout assertions. It
  belongs under `source/` if still needed after `source/vt.zig` owns source types.
- `surface/clip_rect.zig` and `surface/geometry.zig` are render geometry helpers. They belong under
  `render/` or an exact geometry contract owner, not `surface/`.
- `surface/input.zig` adapts VT/source cells/colors into text frame input. It is source-to-text
  adaptation and is too large to move without a dedicated source/text seam review.
- `surface/rgba.zig` is a tiny color struct re-exported by `text/contract.zig`; it is likely stale
  and should be folded into a true color/contract owner in a separate slice.

## First Worker-Ready Move

Move `howl-render/src/surface/buffer.zig` to `howl-render/src/prepared/buffer.zig`.

Why first:

- It has one clear owner: prepared output pixel realization.
- It does not require moving source, session, FFI, render geometry, or token contracts.
- Its direct dependency from `surface/prepared_owner.zig` can become `../prepared/buffer.zig` while
  `prepared_owner.zig` remains in place until a later slice.
- Behavior is pure file movement/import rewiring.

Exact files:

- Move `howl-render/src/surface/buffer.zig` to `howl-render/src/prepared/buffer.zig`.
- Update `howl-render/src/surface/prepared_owner.zig` import.
- Update `libs.yaml` owner metadata.

Verification:

- `zig build check`
- `zig build test`
- `git diff --check`
- `rg 'surface/buffer\.zig|@import\("buffer\.zig"\)' howl-render/src libs.yaml`

Stop conditions:

- Stop if moving `buffer.zig` requires moving prepared-owner lifecycle or submit/session behavior.
- Stop if an umbrella replacement folder or compatibility alias appears.

## Later Slices

- Move `prepared_owner.zig` under `prepared/` after buffer move lands.
- Decide token contract owner before moving `tokens.zig` because it crosses source/prepared/session/FFI.
- Move or fold `publication_source.zig` only after checking overlap with `source/vt.zig` and
  `source/cell.zig`.
- Review `input.zig` as a source-to-text adaptation owner before movement.
- Move geometry/clip helpers only after checking render geometry contract naming.
