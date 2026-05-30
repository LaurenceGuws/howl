# Header Generation Gap

Date: 2026-05-30

## Question

Should Howl keep hand-maintained generated-looking C ABI headers or introduce generated ABI metadata
and header generation tooling now?

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `research/2026-05-30-hygiene-audit/c-abi-header-grammar.md`
- `research/2026-05-30-hygiene-audit/synthesis.md`
- `research/2026-05-30-hygiene-audit/roadmap.md` Slice 7.1
- `project-memory.md` build/test architecture blocker
- package `build.zig` files for header install/translate-C facts

## Findings

- The accepted header grammar already defines a generated-looking hand-maintained shape.
- `howl-pty`, `howl-vt`, and `howl-render` package builds install checked-in public headers with
  `b.installFile`.
- `howl-linux-host` uses translated C modules for consumed ABI headers.
- No current source-backed generator, ABI metadata schema, or verification taxonomy exists.
- `project-memory.md` records a build/test architecture blocker: verification surfaces and build
  entrypoint contracts are fragmented, with no accepted taxonomy for generated artifacts or gates.
- The roadmap explicitly says not to add header generation tooling before that blocker is resolved.

## Decision

Keep headers hand-maintained with the strict generated-looking grammar for this sprint.

Do not add header generation tooling, ABI metadata schemas, scripts, build steps, or generated-file
checks until the build/test architecture blocker has an accepted plan.

## Accepted Guardrail

- Header edits must follow `c-abi-header-grammar.md`.
- Layout, value, and capacity facts stay paired with compile-time assertions in FFI/ABI translator
  code.
- Header generation remains a future build/test architecture topic, not a hygiene implementation
  shortcut.

## Verification

- `git diff --check`
- `rg 'header generation|hand-maintained|build/test architecture' research/2026-05-30-hygiene-audit/header-generation-gap.md`

## Follow-Up

No implementation slice is promoted from this scratchpad.
