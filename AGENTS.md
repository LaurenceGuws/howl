# Howl Agent Contract

Howl is a native Zig terminal family with no downstream compatibility obligation. Build it Foot-direct and TigerBeetle-defensive. Every tracked character is debt unless it buys capability, correctness, clarity, or deterministic evidence.

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

Use Fleet's installed `zig` from `PATH` and require `zig version` to match the tracked `.zigversion`; never create a project-local Zig symlink or substitute a mismatched compiler.

The installed operator/agent entrypoint is `~/.local/bin/howl`. It is a client of
`howl-sessiond`, not a second session authority. Agents normally reach a node
through Remoter and invoke this CLI there; do not add Remoter, SSH, Cloudflare,
or node-discovery policy to Howl's session client. Captain Control currently
dogfoods that exact CLI-through-Remoter path with explicit/event-driven reads.
That is an outer-client choice, not permission to move Remoter policy into Howl
or to promote the experimental Dart socket client without measured need.

## Core bars

1. Prefer direct singular code lanes and deletion. Foot is the simplicity reference.
2. Bounds, ownership, cleanup, exact errors, invariants, and hostile proofs are mandatory. TigerBeetle is the Zig-quality reference.
3. VT owns terminal semantics only. It must never wait for or publish to a renderer or observer.
4. Session owns one canonical PTY and VT lifetime. Observers may disappear or stall without affecting canonical progress.
5. PTY owns Linux process and descriptor mechanics. Platform policy never leaks downward.
6. The standalone `howl-text` repository owns native font metrics, shaping, source clusters, glyph lookup, and bounded natural rasterization. Renderer, window, terminal-cell, session, and client policy never leaks downward.
7. Public authority boundaries must be mechanically enforceable, not comments pretending fields are private.
8. Tests prove positive and negative space, failure cleanup, bounds, and ownership.

When a foundation is structurally wrong, replace it beside the old implementation and prove the better architecture. Do not preserve sunk cost. When a narrow later experiment polluted a sound foundation, delete the experiment instead of rewriting the foundation.

## Evidence

Runtime claims require bounded reproducible evidence. Temporary probes, captures, A/B embedders, and instrumentation live outside accepted source or under ignored `.zig/work/`; delete them after the question is answered. Git keeps only the implementation and conclusions that remain useful.

Do not turn profiling, logging, test scaffolding, or one host's presentation needs into product architecture. References inform behavior and quality, not source structure.

## Git

`main` is accepted integration. `release/$VERSION` is historical. Work directly on `main`; do not create worktrees or task branches unless Captain explicitly asks for one. Keep unrelated dirty work untouched, commit only coherent green checkpoints, and push important state so it does not live only in an agent session.

Before a checkpoint: run the affected package proofs, root core gate, protocol validation when relevant, source audit, formatting, and `git diff --check`.

## Workspace

This repository is the session/VT/PTY workspace, not an authority boundary for every Howl-named package. Cairn carries substantial cross-repository context; repository adjacency is only development convenience.

The root gate owns local `howl-vt`, `howl-session`, `howl-pty`, and `howl-cli`, and delegates the exact pinned standalone `howl-text` package's own checks and tests. Other local packages are experiments until explicitly promoted. QAgent and other embedders may pressure the core but never own its policy.
