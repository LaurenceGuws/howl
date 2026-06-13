# Historical Authority

- Historical authority at time: completed six-target ownership and hygiene sprint contract for `orch-2026-06-14-six-target-ownership-01`.
- Why superseded or done: all planned slices accepted and sprint archived.
- Must not be used for: active execution authority after archive; use `sprints/current.txt` and any newly seeded active sprint instead.

# Six-Target Ownership Hygiene Sprint

Status:

- Active execution sprint contract.
- Orchestrator session id: `orch-2026-06-14-six-target-ownership-01`.
- Researcher session id: `research-2026-06-14-six-target-ownership-01`.
- Reviewer session id: `review-2026-06-14-six-target-ownership-01`.
- Planning seed receipt: `bbf5ca7` `Seed six-target ownership planning`.
- Accepted planning receipt: `16591b9` `Accept six-target ownership planning`.
- Sprint seed receipt: `bf0da6e` `Seed six-target ownership sprint`.

Problem:

- Interrogate the six targeted owners without treating size as guilt.
- Preserve true large owners that are reference-shaped and owner-true.
- Cut only the falsely concentrated seams proved by current source plus references.

Unscheduled keep-large targets for this sprint:

- `howl-linux-host/src/terminal/surface.zig`
- `howl-render/src/surface/emitter.zig`
- `howl-render/src/surface/realizer.zig`

These remain explicitly keep-large for this sprint unless new current-source plus reference proof re-promotes them.

## Slice 1: `ft_hb` loaded-face owner cut

- Coder session id: `coder-2026-06-14-six-target-ownership-slice-01`.
- Allowed files:
  - `howl-render/src/text/ft_hb/support.zig`
  - `howl-render/src/text/ft_hb/loaded_faces.zig`
  - `howl-render/src/text/ft_hb/support_test.zig`
- Required shape:
  - Add a true child owner in `loaded_faces.zig` for FT/HB primary/fallback face lifecycle and face lookup only.
  - Move only the lifecycle and lookup symbols proved by the accepted planning package.
  - Keep cached metrics policy, resolve-stage policy, provider cache policy, and shaping-input scratch in `support.zig` under `FtHbSupport`.
  - Replace the mixed owner shape with delegation from `support.zig` to the new loaded-face owner.
  - Preserve behavior for fallback loading, deterministic test fallback, and metrics derivation.
  - No C ABI change, no package-root export change, no host-facing API churn.
- Exact tests: from `howl-render`, run `zig build test:unit`.
- Non-goals:
  - No shaping-cache redesign.
  - No run-builder cut in the same slice.
  - No benchmark work.
  - No fallback-policy change.
  - No new generic helper or bucket owner.
  - No movement of cached metrics policy into `loaded_faces.zig`.
- Stop conditions:
  - Stop if the cut requires touching files outside the allowed set.
  - Stop if the new owner cannot stay limited to face lifecycle and face lookup without pulling policy with it.
  - Stop if preserving behavior would require public render-session or ABI churn.
- Required receipt fields: planning seed receipt `bbf5ca7`, accepted planning receipt `16591b9`, orchestrator session id, researcher session id, reviewer session id, coder session id, verification result `zig build test:unit` in `howl-render`, commit-hash handoff required on slice acceptance.

## Slice 2: cluster run-planning cut into existing `shape/run.zig`

- Coder session id: `coder-2026-06-14-six-target-ownership-slice-02`.
- Allowed files:
  - `howl-render/src/text/shape/cluster.zig`
  - `howl-render/src/text/shape/run.zig`
- Required shape:
  - Do not create a new owner file.
  - Move provisional run planning from `cluster.zig` into `run.zig`, because `run.zig` is already the run owner.
  - Rename `OwnedRuns` to `OwnedProvisionalRuns` during the move so the run-owner vocabulary is explicit and does not collide with shaped-run owners already in `run.zig`.
  - Move `buildProvisionalRuns`, `buildProvisionalRunsScratch`, and `resolvedRun` into `run.zig`.
  - Add run-local scratch ownership in `run.zig` as `RetainedProvisionalRunScratch` and remove run scratch storage from `cluster.RetainedScratch`.
  - Leave `cluster.zig` owning text-cache assembly, renderable assembly, cluster extraction, and complex selection only.
  - No C ABI change, no package-root export change, no render-session policy change.
- Exact tests: from `howl-render`, run `zig build test:unit`.
- Additional proof obligations:
  - Preserve or relocate the current run proofs from `cluster.zig:867-892` and `cluster.zig:913-946` into owner-true inline tests after the move.
  - Preserve or add run-scratch overflow proof under the new run-local scratch owner.
- Non-goals:
  - No new `provisional_run.zig` file.
  - No movement of text-cache assembly or renderable-cell assembly out of `cluster.zig`.
  - No font-resolution work.
  - No shape-run behavior change in `run.zig` beyond owning provisional run planning.
  - No generic scratch bucket shared back across owners.
- Stop conditions:
  - Stop if the slice cannot remove `ResolvedRun` scratch ownership from `cluster.RetainedScratch` cleanly.
  - Stop if the move requires touching files outside the allowed set.
  - Stop if the only viable outcome is inventing a new file instead of using `run.zig`.
  - Stop if moved tests cannot remain reachable through the existing render unit root without adding a new test root.
- Required receipt fields: planning seed receipt `bbf5ca7`, accepted planning receipt `16591b9`, orchestrator session id, researcher session id, reviewer session id, coder session id, verification result `zig build test:unit` in `howl-render`, commit-hash handoff required on slice acceptance.

## Slice 3: parser keep-large proof hygiene

- Coder session id: `coder-2026-06-14-six-target-ownership-slice-03`.
- Allowed files:
  - `howl-vt/src/parser.zig`
- Required shape:
  - Keep `parser.zig` structurally large and owner-true.
  - Add parser-owner-local inline tests in `parser.zig` proving the control spine directly.
  - Do not cut new parser child files.
  - Do not move UTF-8 or string-control logic back into `parser.zig`.
  - Use inline tests only so the VT package keeps its current curated test root shape.
- Exact tests: from `howl-vt`, run `zig build test:unit`.
- Minimum proof coverage:
  - exit/transition/entry phase ordering
  - active-control exclusivity
  - CSI parameter and separator assembly
  - DCS hook boundary behavior
- Non-goals:
  - No parser ownership cut.
  - No parse-table redesign.
  - No new test root.
  - No protocol feature expansion.
  - No benchmark or simulation work.
- Stop conditions:
  - Stop if direct parser-owner-local proof cannot be added within `parser.zig`.
  - Stop if the slice requires touching files outside the allowed set.
  - Stop if the work drifts from proof into parser architecture redesign.
- Required receipt fields: planning seed receipt `bbf5ca7`, accepted planning receipt `16591b9`, orchestrator session id, researcher session id, reviewer session id, coder session id, verification result `zig build test:unit` in `howl-vt`, commit-hash handoff required on slice acceptance.

Sprint stop rule:

- Stop the sprint after Slice 3 unless new current-source plus reference proof re-promotes one of the remaining keep-large targets.
