# Module Contract Shape Sprint

## Goal

Make every Howl module boundary boring, curated, and enforceable.

Ghostty's `src/lib_vt.zig` is the reference for contract shape and hygiene, not symbol names. The desired pattern is a clear public catalog that points at owned implementation files, groups special contract areas deliberately, and avoids leaking private implementation convenience through package roots.

## Operating Rules

- Work sequentially. Finish the current sprint checkpoint before starting the next one.
- Keep package roots as curated contract catalogs.
- Keep runtime owner files obvious and allowed to contain real state.
- Export only deliberate public API, not aliases used only for internal convenience.
- Route cross-domain imports through package roots and owner files.
- Keep hosts on `howl-term`; hosts must not import VT, session, or render internals directly.
- Avoid fake progress. Missing Android runtime proof stays an explicit open item until real code exists.
- Verify with parent `zig build test --summary all` after each checkpoint.

## Active Focus

Sprint 0 is active.

Complete and checkpoint the current `howl-term` public alias trim before broader module movement.

## Sprint 0: Baseline Checkpoint

Purpose: finish the already-started `HowlTerm` alias trim as a clean baseline.

Tasks:

- Keep Linux-host-used `HowlTerm` aliases intact: `LifecycleState`, `SurfaceHandle`, `SurfaceMetrics`, `FramePixels`, `SurfaceState`, `LinkUnderlineStyle`, `ScrollState`.
- Remove internal-only `HowlTerm.*` public aliases.
- Point internal signatures at their real owners: `runtime/contract.zig`, `render/pipeline.zig`, `render/snapshot.zig`.
- Run `howl-term` tests.
- Run parent workspace tests.
- Commit and push once the checkpoint is clean and approved.

Acceptance:

- `howl-term`: `zig build test --summary all` passes.
- parent: `zig build test --summary all` passes.
- `./status.sh` is empty after commit and push.

## Sprint 1: Shape Enforcement

Purpose: make the target shape machine-checkable.

Tasks:

- Define root categories in `tools/check_module_shape.sh`: package root, runtime owner, executable owner, test root.
- Enforce small package roots where expected.
- Enforce allowed runtime owner exceptions: `howl-term/src/howl_term.zig`, `howl-hosts/howl-linux-host/src/main.zig`.
- Fail wrong-direction imports.
- Fail host imports of lower modules: `vt_core`, `howl_session`, `howl_render`.

Acceptance:

- `zig build` fails on root bloat or wrong-direction deps.
- Parent workspace checks still pass.

## Sprint 2: `howl-vt-core`

Purpose: keep VT core as the model package root.

Tasks:

- Keep `src/vt_core.zig` as a curated public catalog.
- Keep `src/terminal.zig` as the runtime/protocol owner.
- Keep VT input vocabulary and terminal-mode-dependent input encoding owned by VT.
- Remove remaining public aliases that only serve internal convenience.
- Add or keep root public-surface tests.

Acceptance:

- Consumers use `vt_core.Input`, `vt_core.Grid`, `vt_core.Parser`, `vt_core.Snapshot`, `vt_core.Selection`, and `vt_core.VtCore` only where intended.
- `vt_core.zig` stays small and boring.

## Sprint 3: `howl-render-core`

Purpose: make the render root expose render contracts, not backend internals by accident.

Tasks:

- Audit `howl_render.zig` exports: `Backend`, `BackendError`, `RenderReport`, `PreparedTextScene`, `TextSceneRenderReport`, `Renderer`.
- Keep public only what `howl-term` and tests need.
- Move backend-specific public surface under a deliberate namespace only if it must stay public.
- Keep `render_core.zig` as the render contract owner.
- Keep `renderer.zig` as selected backend runtime owner.

Acceptance:

- Linux host has no direct `howl_render.*` dependency.
- `howl-term` uses only intended render root contracts.

## Sprint 4: `howl-session`

Purpose: make session root a clear contract catalog without making test PTYs look like production API.

Tasks:

- Keep public session contracts: `Session`, config/status/snapshot/ops, `Pty`, `OwnedPty`, `ControlSignal`, `PtyLaunchConfig`, `initPty`.
- Move `MemPty`, `PartialPty`, and `FailPty` behind a deliberate testing namespace or private test imports.
- Keep PTY variants owned by session.

Acceptance:

- `howl-session/src/root.zig` is a boring contract catalog.
- Test PTYs are not mistaken for normal production API.

## Sprint 5: `howl-term`

Purpose: keep `src/howl_term.zig` as the public runtime owner while separating public API from internal owner modules.

Tasks:

- Keep only host-facing aliases at `HowlTerm.*`.
- Prefer internal references to concrete owners.
- Organize methods by lifecycle, frame queue, input, render, viewport, metrics/state.
- Do not split this into `runtime/term.zig`.
- Do not rebrand VT input vocabulary into term-specific symbols.

Acceptance:

- `HowlTerm` public surface is small and host-safe.
- Internal modules name their real owners.

## Sprint 6: Host Boundary

Purpose: make host dependency direction obvious.

Tasks:

- Keep Linux host terminal runtime dependency on `howl-term` only.
- Keep platform UX/runtime code in host modules.
- Keep `main.zig` as executable owner exception.
- Keep `test_host.zig` as a thin test root.

Acceptance:

- Shape checks enforce no host imports of lower modules.
- Host tests and parent workspace tests pass.

## Sprint 7: FFI And Android Proof Gate

Purpose: keep native ABI and platform proof honest.

Tasks:

- Keep FFI ABI fields stable unless intentionally changing ABI.
- Preserve `FfiPrepareMetrics.term_us`.
- Keep FFI implementation explicit and boring.
- Keep Android runtime proof marked open until real runtime code exists.

Acceptance:

- Native checks pass.
- Android compile-only proof remains documented.
- Missing Android runtime proof remains an explicit skip, not a stub.

## Definition Of Done

- Parent `zig build test --summary all` passes.
- Parent `zig build` emits `module_shape_ok=1`.
- `tools/check_module_shape.sh` catches root bloat and wrong-direction imports.
- Package roots read like curated public contracts.
- Runtime owner files read like owners, not accidental package roots.
- No public alias exists only because an internal file wanted shorter syntax.
- `./status.sh` is empty after approved commits and pushes.
