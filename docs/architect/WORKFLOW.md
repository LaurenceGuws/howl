# Parent Architect Workflow

Purpose: drive cross-repo product direction, keep module boundaries coherent,
and publish execution queues that are large enough for dual-mode engineering but
still reviewable.

## Document Lanes

- `architecture_docs/authority/`: durable product authority, module map, dependency rules, milestone ladder, and conventions.
- `docs/architect/`: workflow, reviews, sprint planning, and milestone progress for parent-level coordination.
- `docs/engineer/`: current execution queue and handover/report requirements.
- child repo `app_architecture/`: repo-local authorities and contracts only.
- child repo `docs/`: repo-local workflow, queues, progress, and evidence.

## Architect Owns

- cross-module direction and milestone sequencing
- architecture and contract decisions
- decomposition of hygiene or product work into reviewable execution cuts
- queue authoring and acceptance/rejection
- naming/layout/doc-comment rules when they affect public API or module ownership

## Host Proof Rule

- SDL host and Android host are the first abstraction proofs.
- Both hosts must act as equivalent callers of the primary terminal boundary
  (`howl-term`, currently housed in `howl-term-surface`).
- Host repos own platform/windowing code first; app-state features (for example
  multiplexing) come later.
- `howl-session` owns PTY/platform process differences and must present
  first-class caller behavior by default.
- `howl-render-core` owns backend abstraction and contract shape; backend repos
  must behave as first-class targets by default.

## Engineer Owns

- implementation of architect-issued execution cuts
- validation evidence and concise self-review findings
- no independent re-scoping, milestone invention, or authority-doc edits unless explicitly assigned

## Iteration Loop

1. Read parent authority docs, current review docs, and touched child repo authorities.
2. Pick the largest coherent execution cut that stays reviewable.
3. Publish the execution queue in `docs/engineer/ACTIVE_QUEUE.md`.
4. Each ticket must include target repos/files, allowed change type, non-goals, validation, and stop conditions.
5. Review the engineer report against diffs, tests, and authority docs.
6. Accept, reject, or publish a correction queue.
7. On acceptance, update checkpoint/progress docs and publish the next queue.

## Acceptance Gate

Accept work only when all are true:

- scope matches the ticket boundaries
- claims match `git show --name-status`
- product hygiene guard passes for product repos
- relevant `zig build` and `zig build test --summary all` pass
- no vague names or filler doc comments were introduced
- no public API names changed without explicit authority update
- no platform types leak into shared modules
- no render planning policy moves outside `howl-render-core`
- no session/transport policy moves into host entrypoints
- no host retakes ownership that belongs to the terminal boundary

## Product Hygiene Guard

Run the product gate from workspace root:

```bash
./utils/hygene/architecture_guard.sh \
  howl-vt-core \
  howl-session \
  howl-term-surface \
  render/howl-render-core \
  render/howl-render-gl \
  render/howl-render-gles \
  render/howl-render-metal \
  render/howl-render-software \
  render/howl-render-vulkan \
  howl-hosts/howl-sdl-host \
  howl-hosts/howl-android-host
```

`utils/*` repos are outside the terminal MVP product hygiene gate.
