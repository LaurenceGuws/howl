# Parent Engineer Report Checklist

Use this checklist for parent-level cross-repo execution queues.

## Before Execution

- Read `architecture_docs/authority/ENGINEERING_CONVENTIONS.md`.
- Read `architecture_docs/authority/MVP_STRUCTURE.md`.
- Read `docs/architect/product_structure/REVIEW.md`.
- Read `docs/architect/product_structure/CHECKPOINTS.md`.
- Read the current ticket in `docs/engineer/ACTIVE_QUEUE.md`.

## Human Rules

1. Do not change public API names unless the ticket explicitly authorizes it.
2. Do not move code only to reduce line count; every move must improve ownership clarity.
3. Keep `root.zig` as export/wiring/module-test only unless a ticket explicitly permits a temporary exception.
4. Keep executable entrypoints thin; durable behavior belongs in named modules.
5. Keep `//!` and `///` comments short, accurate, and domain-focused.
6. No vague boundary words banned by the product hygiene guard.
7. No compatibility/fallback/workaround/shim paths.
8. No platform types in shared modules.
9. No renderer planning policy outside `howl-render-core`.
10. No session/transport policy in host entrypoints.

## Required Report Format

- `#DONE`
- `#OUTSTANDING`
- commits: hash + subject
- validation results: command, repo, exit status, result
- files changed
- findings ordered High, Medium, Low

## Required Validation

Run the product hygiene guard from workspace root:

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

Run `zig build` and `zig build test --summary all` in every product repo touched by code.
Run `zig build package` when touching `howl-hosts/howl-sdl-host` package/runtime wiring.
Run Gradle compile when touching Android Java/Gradle files.

Run iteration naming grep on touched files and report every hit:

```bash
git diff --name-only -- '*.zig' '*.java' '*.kt' '*.md' \
  | xargs -r rg -n -i '\b(adapter|bootstrap|bridge|native|terminal|host)\b' || true
```

Interpretation rule:

- hits are not auto-fail by themselves.
- every hit must be justified against module ownership and public contract language.
- unowned filler naming (for example stacked boundary words with no behavior meaning) must be renamed before handover.
