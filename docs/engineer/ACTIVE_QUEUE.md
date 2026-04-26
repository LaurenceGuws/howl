# Parent Active Queue

## Current State

Product structure hygiene sprint is ready for dual-mode execution. Start with `PSH-A2`.

## Read Before Execution

- `architecture_docs/authority/ENGINEERING_CONVENTIONS.md`
- `architecture_docs/authority/MVP_STRUCTURE.md`
- `architecture_docs/authority/MODULE_MAP.md`
- `architecture_docs/authority/DEPENDENCY_RULES.md`
- `docs/architect/WORKFLOW.md`
- `docs/architect/product_structure/REVIEW.md`
- `docs/architect/product_structure/CHECKPOINTS.md`
- `docs/engineer/REPORT_CHECKLIST.md`

## Sprint: Product Structure Hygiene

Goal: align file/folder layout, symbol names, doc comments, root facade thickness, executable entrypoints, and module ownership across product repos before new feature work continues.

### PSH-A1: Parent Workflow Setup

Status: done.

Intent:
- create parent `docs/` workflow lane
- move review/checkpoint docs out of `architecture_docs`
- define dual-mode report and validation rules

Target files:
- `docs/architect/WORKFLOW.md`
- `docs/architect/MILESTONE_PROGRESS.md`
- `docs/architect/product_structure/REVIEW.md`
- `docs/architect/product_structure/CHECKPOINTS.md`
- `docs/engineer/ACTIVE_QUEUE.md`
- `docs/engineer/REPORT_CHECKLIST.md`

Closeout:
- parent `docs/` workflow lane created
- product-structure review/checkpoint docs moved out of `architecture_docs`
- report checklist and sprint queue published
- `architecture_docs/README.md` now points workflow readers to `docs/`

### PSH-A2: Thin Root Facades

Status: active.

Intent:
- make product `root.zig` files export/wiring/module-test only
- move non-trivial conformance tests out of root files into named test modules
- preserve all public exports and test coverage

Primary targets:
- `howl-vt-core/src/root.zig`
- `howl-session/src/root.zig`
- `howl-term-surface/src/root.zig` if review finds non-trivial tests

Non-goals:
- no public API rename
- no behavior change
- no test deletion

Stop conditions:
- any public symbol must change
- moved tests lose discovery under `zig build test --summary all`

### PSH-A3: SDL Host Entrypoint Ownership

Status: pending.

Intent:
- reduce `howl-hosts/howl-sdl-host/src/main.zig` to executable entrypoint ownership
- move durable frame loop, presentation, SDL app/event handling, and runtime config logic into named modules
- preserve current runtime behavior

Primary target:
- `howl-hosts/howl-sdl-host/src/main.zig`

Expected new modules may include:
- `src/frame_loop.zig`
- `src/presentation.zig`
- `src/platform/sdl_app.zig`
- `src/config/runtime_config.zig`

Non-goals:
- no renderer feature changes
- no session/surface behavior changes
- no SDL dependency change

Stop conditions:
- render-core planning policy appears in host modules beyond invocation
- session/transport policy is introduced in host entrypoint code

### PSH-A4: Session Core Ownership Split

Status: pending.

Intent:
- split `howl-session/src/session/core.zig` by behavior ownership
- keep public `Session` API stable
- preserve all tests

Expected ownership lanes:
- session data/config/state invariants
- lifecycle start/stop/deinit
- I/O feed/apply/feedProcessOutput
- resize/control observability
- VT engine integration

Non-goals:
- no API churn
- no transport behavior change
- no line-count-only movement

Stop conditions:
- any test requires weakening
- transport/session boundary becomes less clear

### PSH-A5: Backend Scaffold Maturity

Status: pending.

Intent:
- ensure GLES, Metal, Software, and Vulkan backend repos each state backend-specific execution constraints
- add minimal tests proving public backend shape consumes render-core-facing config/capability model

Targets:
- `render/howl-render-gles`
- `render/howl-render-metal`
- `render/howl-render-software`
- `render/howl-render-vulkan`

Non-goals:
- no full renderer implementation
- no host integration
- no render-core API change unless a real contract gap is found and escalated

### PSH-A6: Closeout Review

Status: pending.

Intent:
- update `docs/architect/product_structure/CHECKPOINTS.md`
- record validation results
- document any remaining maturity debt with cause and next gate

Required validation:
- product hygiene guard passes
- builds/tests pass for touched repos
- report lists unresolved findings High/Medium/Low
