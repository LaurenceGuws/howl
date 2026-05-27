# Render Surface Hardening Scratchpad

Owner: workspace root.

Purpose:

- Define the render hardening campaign as a sequence of promotable slices.
- Keep the work centered on semantics, owner truth, bounds, and proof quality.
- Replace weak or misleading shapes with cleaner ones, even when that requires local rewrites.
- Use Ghostty for owner shape, Kitty for graphics UX/spec truth, and TigerBeetle for assertions, bounds, and proof posture.

## Mission

- Make `howl-render` materially more mature, intuitive, bounded, and owner-true.
- Stop relying on inferred or reconstructed truth where a better owner can publish it directly.
- Eliminate silent fallback and ambiguous ABI semantics where practical.
- Build a render surface that is easier to reason about than the current Ghostty-like baseline and stricter in proof quality.

## Working Rules

- Research before code when owner truth or shape is unclear.
- Prefer one subsystem at a time.
- Prefer one worker for rewrites or owner-boundary changes.
- Use parallel workers only when file scopes are genuinely disjoint and review can remain extremely strict.
- Accept larger rewrites when local code shape is fundamentally wrong.
- Reject “compatibility” or “helper” layers that preserve bad semantics without a concrete need.

## Source Order

1. Ghostty for owner shape and terminal/render seams.
2. Kitty for graphics protocol facts and UX expectations.
3. TigerBeetle for truth, bounds, invariants, and proof discipline.

## Campaign State

### Completed Foundation

- VT now exports resolved placeholder runs.
- Render now ingests VT-exported placeholder runs directly.
- Render no longer reconstructs placeholder runs from raw cells in the primary path.
- Render cluster scratch now respects real multi-codepoint cell input counts.
- Render ingress is stricter about dirty-row byte domain, metadata counts, image references, and screen identity.
- Placeholder composition ordering is tighter and uses stronger published truth.
- Prepared/export truth is improved for prepare-time metrics.
- Render owns submitted-frame retained-base truth only.
- Host owns present-in-flight identity and VT acknowledgement.
- Host publish path now carries placeholder-run metadata across the ABI.
- Integration proof surfaces were recovered after the placeholder-run ABI expansion.

### Remaining Major Themes

- Prepared/export surface semantics are still muddier than they should be.
- Placeholder semantics may still have residual divergence from ideal Kitty behavior.
- Text/render input truth may still have remaining blind spots beyond the style/presentation slice already landed.

## Canonical Questions

Every slice should answer one or more of these directly:

1. What is the real owner of this truth?
2. What should be validated at the boundary versus asserted internally?
3. What data model shape best expresses the truth without duplication or ambiguity?
4. What hidden sentinels, impossible states, or lifecycle transitions need to be explicit?
5. What proof matrix makes this subsystem TigerBeetle-grade?

## Promotable Slices

### Slice F: Placeholder Semantic Residuals

Status: open, but no longer the first blocker.

Goal:

- Revisit any residual divergence from ideal Kitty placeholder semantics now that VT owns placeholder-run truth.

Primary files:

- `howl-vt` placeholder-run export and semantics
- `howl-render` composition ordering / draw math only as consumers

Questions:

- Are one-axis placement semantics perfect?
- Is cross-kind ordering fully authoritative or still locally inferred?
- Does any render-side fallback remain that should move to VT?

Stop condition:

- Render is a pure consumer of VT placeholder truth, not a semantic co-owner.

## Promotion Order

Recommended next promotions:

1. Slice F: Placeholder Semantic Residuals

## Review Standard

- Reject slices that add helper indirection without sharpening truth.
- Reject slices that preserve ambiguous field meanings without a concrete reason.
- Reject slices that broaden ABI churn without enough semantic gain.
- Prefer moving policy toward the smallest true owner.
- Prefer exactness over convenience.
- Prefer assertions and boundary rejection over silent fallback.

## Ready-To-Promote Item

- `Slice F: Placeholder Semantic Residuals`

Why first:

- Slice A made token ingress reject impossible prepared/export states.
- Slice B made prepared-handle lifetime explicit and safely rejectable.
- Slice C made submit execution upload/dimension truth checked before render mutation.
- Slice D made dirty metadata canonical before equality/dedupe.
- Slice E moved presentation acknowledgement to the host and removed render-owned retire-present state.
- The remaining item needs focused research before coding because placeholder semantics cross VT, render, and Kitty protocol truth.
