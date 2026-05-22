# Redesign Scratch Pad

Owner: workspace root.

Purpose: temporary checkpoint tracker for the current cross-repo bad-style cleanup.

## Rules

- Judge acceptable shape by `WORKFLOW.md` source order.
- Review every touched file against `design/style-law.md`.
- Close each checkpoint only when the owning repo boundary, docs, and proof stay true.
- Delete this scratch pad when the tracked cleanup is closed.

## Active Checkpoints

### 1. Workspace root docs

- Owner: workspace root.
- Goal: remove stale planning and checkpoint-doc drift from active root docs.
- Closed work:
  - deleted stale root planning doc `design/render-geometry-review-sprint.md`
  - kept source-order ownership in `WORKFLOW.md` instead of repeating the full rule in
    `design/reference-index.md`
- Open work:
  - review remaining root docs for the same planning-drift posture

### 2. `howl-linux-host`

- Owner: `howl-linux-host`.
- Goal: move host runtime shape toward a smaller Alacritty-like control spine.
- Closed work:
  - deleted stale host sprint doc drift
  - removed the reviewed non-guardrail source comments in touched host files
- Open work:
  - split `src/main.zig` by true owner without hiding the control spine

### 3. `howl-pty`

- Owner: `howl-pty`.
- Goal: make PTY ABI seams typed, exact, and owner-true.
- Open work:
  - use typed public enum contracts at the C ABI seam instead of raw byte posture
  - stop collapsing distinct FFI failures into generic `failed` or `null`
  - remove Zig-shaped transport-injection preservation that muddies the C ABI boundary
  - reduce duplicated Unix and Android transport lifecycle control flow
  - remove non-guardrail source comments and fix design-doc drift

### 4. `howl-render`

- Owner: `howl-render`.
- Goal: keep render novelty minimal and keep owner files owner-true.
- Open work:
  - fix local doc drift against workspace source order
  - split oversized benchmark control flow by true owner
  - move proof-harness behavior out of `src/ffi.zig`, or rename the owner truthfully
  - remove non-owning mutex wrappers
  - remove umbrella wrapper posture in `src/text/text.zig`

### 5. `howl-vt`

- Owner: `howl-vt`.
- Goal: keep VT-core Ghostty-first and remove fake root layering.
- Open work:
  - remove wrapper roots and other namespace-bag posture that does not own a real boundary
  - stop curated-root bypasses in repo-local roots
  - split oversized benchmark control flow and remove pure forwarding roots
  - remove stale planning and migration-doc drift from active docs
  - re-check parser bound rationale against Ghostty-first VT ownership
  - remove what-comments that do not lock a local invariant

### 6. Cross-repo root posture

- Owner: workspace root, with child-repo owners per file.
- Goal: keep public roots curated and keep internal owners out of fake Zig integration posture.
- Open work:
  - align `src/howl_*.zig` and other root surfaces with true curated-root rules
  - remove wrapper roots that only aggregate or re-export without a boundary difference
  - reconcile repo `design.md` files with the code that still exists today

## Closure Gate

- owner still true
- source-order match is explicit
- no Zig-module-shaped host bypass was added or preserved
- bounds and assertions tightened where the invariant lives
- touched-file style gate is clean or the remaining gap is exact and owned
- docs changed with the code
- proof was run and recorded in the report
