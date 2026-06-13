# Sprint: Render API Owner Surgery

Date: 2026-06-13.

Owner: orchestrator.

Status: sprint closed.

Orchestrator session id: `orch-2026-06-13-render-api-owner-surgery-01`.

Researcher session id: `research-2026-06-13-render-api-owner-surgery-01`.

Reviewer session id: `review-2026-06-13-render-api-owner-surgery-01`.

Commit-hash receipt: planning package closed in root commit `e5f7e4b`; final sprint close receipt root `8aa8327`.

## Problem Statement

- `howl-render` is not cut into real idiomatic owners.
- `howl-render/src/tv_surface` is presumed fake owner structure.
- `howl-render/src/tv_surface/vt.zig` is specifically suspect because it uses renderer C imports and redefines VT structs instead of respecting the VT/render ABI boundary.
- `howl-render/src/session` is presumed fake and must be checked against Alacritty renderer cache/store/session naming and ownership pressure.
- `howl-render/src/prepared` is a broad fake bucket until reference and current-source proof says otherwise.
- File names are unacceptable as current authority; names must move toward true owners, not buckets.
- `text`, effects, geometry, prepared surfaces, and API contracts are mixed together and must be recut from source-backed owner seams.
- Current render API structure is presumed wrong until Alacritty, Ghostty embedding/VT seams, TigerBeetle ownership law, and Howl C ABI constraints prove each shape.

## User Direction

- New sprint focus: cut render into real idiomatic owners.
- Do not preserve fake compatibility wrappers, fake buckets, or stale file names for comfort.
- Check Alacritty for renderer organization and naming pressure, especially cache/store/session equivalents.
- Preserve the non-negotiable C ABI boundary: hosts consume render contracts; render must not become a Zig-shaped host or VT integration shortcut.

## Planning Boundary

- Research must re-prove current facts from current source after root commit `22454e3` and current nested heads.
- Research must be reference-first: Alacritty for renderer organization, Ghostty for VT/embedding seams, TigerBeetle for ownership/assertion/test discipline, official docs only for ABI/protocol facts.
- Planning must cover the full render API owner problem, not a smaller v1, unless the user explicitly narrows scope.
- Planning must produce sequential slices with exact allowed files, required shape, tests, non-goals, stop conditions, accountable session ids, and commit-hash receipt demands.

## Execution Authorization

- The reviewer accepted the planning package in session `review-2026-06-13-render-api-owner-surgery-01`.
- The accepted research artifact is `/home/home/personal/projects/howl/research/2026-06-13-render-api-owner-surgery-plan.md`.
- Planning commit-hash receipt is closed in root `e5f7e4b`.
- Execution is authorized only through the condensed Slice 1 contract in `/home/home/personal/projects/howl/loops/render-api-owner-surgery-live-loop.txt`.
