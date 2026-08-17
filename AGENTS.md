# Howl Agent Contract

Howl is a private native Zig terminal family with no downstream compatibility obligation. Build it Foot-direct and TigerBeetle-defensive. Every tracked character is debt unless it buys capability, correctness, clarity, or deterministic evidence.

## Authority

Read only what the task needs:

- `project_design.yml`: current architecture and ownership.
- `project_rules.yml`: non-negotiable engineering rules.
- `project_source_map.yml`: accepted and experimental source boundaries.
- `project_version_scope.yml`: current capability cut and gates.
- `protocol_coverage.yml`: terminal-protocol census when protocol behavior is involved.

Official docs and maintained references are local development inputs:

- `/home/home/personal/projects/official_docs`
- `/home/home/personal/projects/dev_references`

Use the tracked Zig pin through `.zig/zig`; never substitute ambient Zig.

## Core bars

1. Prefer direct singular code lanes and deletion. Foot is the simplicity reference.
2. Bounds, ownership, cleanup, exact errors, invariants, and hostile proofs are mandatory. TigerBeetle is the Zig-quality reference.
3. VT owns terminal semantics only. It must never wait for or publish to a renderer or observer.
4. Session owns one canonical PTY and VT lifetime. Observers may disappear or stall without affecting canonical progress.
5. PTY owns Linux process and descriptor mechanics. Platform policy never leaks downward.
6. Text owns native font metrics, shaping, source clusters, and bounded rasterization. Renderer, window, session, and client policy never leaks downward.
7. Public authority boundaries must be mechanically enforceable, not comments pretending fields are private.
8. Tests prove positive and negative space, failure cleanup, bounds, and ownership.

When a foundation is structurally wrong, replace it beside the old implementation and prove the better architecture. Do not preserve sunk cost. When a narrow later experiment polluted a sound foundation, delete the experiment instead of rewriting the foundation.

## Evidence

Runtime claims require bounded reproducible evidence. Temporary probes, captures, A/B embedders, and instrumentation live outside accepted source or under ignored `.zig/work/`; delete them after the question is answered. Git keeps only the implementation and conclusions that remain useful.

Do not turn profiling, logging, test scaffolding, or one host's presentation needs into product architecture. References inform behavior and quality, not source structure.

## Git

`main` is accepted integration. `release/$VERSION` is historical. Use one short-lived task branch for unfinished work, keep unrelated dirty work untouched, and commit only coherent green checkpoints. Push important state so it does not live only in an agent session.

Before a checkpoint: run the affected package proofs, root core gate, protocol validation when relevant, source audit, formatting, and `git diff --check`.

## Workspace

The monorepo provides atomic Git history and development ergonomics. Each `howl-*` directory is an independent package with its own build identity and proofs.

The root gate currently owns `howl-vt`, `howl-session`, `howl-pty`, and `howl-text`. Other packages are experiments until explicitly promoted. QAgent and other embedders may pressure the core but never own its policy.
