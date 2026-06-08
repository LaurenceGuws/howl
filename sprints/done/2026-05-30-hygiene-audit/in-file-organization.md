# In-File Organization Convention

Date: 2026-05-30

## Purpose

Define a strict local organization rule for files touched during real owner work. This convention is
not permission for style-only churn or a repo-wide rewrite.

## Sources Read

- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `AGENTS.md`
- `loop.txt`
- `research/2026-05-30-hygiene-audit/roadmap.md` Slice 6.1

## Convention

- Imports come first.
- Import order is standard library, C ABI/build imports when present, then local owner imports.
- Local imports should name the owner path directly; do not route through broad compatibility roots.
- Constants and compile-time assertions sit near the top, before owner state.
- Owner structs order fields first, then nested simple types, then methods.
- Public lifecycle/control/data methods precede private helpers unless a single-caller helper is
  clearer immediately adjacent to its caller.
- Tests are last except package test aggregators.
- Comments explain ABI consequences, protocol facts, lifetime, ownership, or surprising invariants.
- Assertions prove bounds, type sizes, preconditions, postconditions, and compile-time relationships.
- No decorative banners. Ordering does navigation.
- No `types.zig`, `api.zig`, `abi.zig`, manager, controller, runtime, queue, or pipeline buckets.

## Application Rule

Apply this convention only when:

- touching the file for a promoted owner/ABI slice; or
- demonstrating it on one accepted ABI translator slice with behavior-preserving tests.

Do not open a style-only cleanup across unrelated files.

## Reviewer Checks

- The diff improves source order without hiding control flow.
- Helpers are extracted only when ownership or function length requires it.
- Compile-time assertions stay close to the constants or C layout they prove.
- Tests remain at the end and still prove the same behavior.
- No new broad owner name appears.

## Grep Gate

- `rg 'fields.*nested.*methods|compile-time assertions|Tests are last|No decorative banners' research/2026-05-30-hygiene-audit/in-file-organization.md`

## Verification

- `git diff --check`
