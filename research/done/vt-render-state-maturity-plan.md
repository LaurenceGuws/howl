Historical authority at the time: accepted VT render-state maturity plan, closed by root `fb7b0f6 Track VT surface ABI deletion`.
Why superseded or done: old VT surface ABI deletion is closed; current cleanup guidance lives in `research/howl-render-cleanup-plan.md`.
Must not be used for: current execution guidance, old compatibility payload staging, or preserving stale renderer `vt_surface` ownership.

# VT Render-State Maturity Plan

Status: closed sprint plus active renderer namespace residue cleanup.

Orchestrator session id: `orch-2026-06-18-render-vt-surface-residue-cleanup-01`.

Closed receipts:

- Recovery Slice 5 product commits: `howl-vt` `39c5f7d Add visible info and hyperlink ABI`, `howl-render` `0f9d339 Consume VT render state in renderer`, `howl-linux-host` `876c21e Use VT render state from host`.
- Recovery Slice 5 root receipt: `a83bb52 Track VT render state consumption`.
- Recovery Slice 6 product commit: `howl-vt` `f786252 Delete old VT surface ABI`.
- Recovery Slice 6 root receipt: `fb7b0f6 Track VT surface ABI deletion`.

Closed outcome:

- Host/render live prepare path consumes VT render-state C ABI.
- Old public VT monolithic surface ABI is deleted.
- Old surface payload compatibility shims, bridges, aliases, and renderer-owned VT mirrors are rejected.
- No Recovery Slice 6 root receipt remains pending.

Active follow-up problem:

- `howl-render/src/vt_surface` survived after the renderer stopped consuming the old VT surface mirror.
- The directory name itself is stale ownership because the old renderer VT-surface endpoint is rejected.
- The only live residue was cursor-presentation data/constants used by text scene owners.

Required cleanup shape:

- Move remaining cursor presentation data/constants to `howl-render/src/text/cursor_presentation.zig`.
- Re-export the bounded constants and data shapes through `howl-render/src/text/contract.zig`.
- Update text scene tests and defaults to use the text contract, not the old folder.
- Delete all tracked files under `howl-render/src/vt_surface` and remove the empty directory.
- Do not change host, VT ABI, renderer prepare behavior, or cursor presentation semantics.

Required verification:

- `rg "vt_surface|VtSurface|vtSurface|HowlVtSurface|invalidateForVtSurface" howl-render/src howl-render/include` returns no matches.
- `zig build test:unit` passes in `howl-render`.
- `zig build check` passes in `howl-render`.
- `zig build check` passes at workspace root.

Stop conditions:

- Any old surface payload, compatibility shim, bridge, alias, or renderer-retained VT mirror is reintroduced.
- Any host or VT ABI file must change.
- Any behavior change is needed beyond moving/deleting stale ownership names.

Historical note:

- Detailed prior research, blocker, review, and receipt history is preserved in git history before this cleanup. This active artifact is current-only and must not be used to resurrect old staged compatibility guidance.
