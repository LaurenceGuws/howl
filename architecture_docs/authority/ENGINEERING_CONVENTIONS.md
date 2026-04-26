# Engineering Conventions

This document is parent-level authority for code and test conventions in the Howl workspace.
If a repo-local convention conflicts with this document, the parent rule wins.

## Zig Doc Comment Rules

1. Every Zig source file under `src/` must begin with a `//!` file or module header.
2. The `//!` header must describe the file's ownership or purpose before any public declarations.
3. Every exported public type, function, method, or constant that is part of a stable API must have a `///` doc comment immediately above the declaration.
4. Public API docs must state behavior, ownership, and any observable error or mutation boundary.
5. New public symbols are not complete until their `///` docs are present in the same commit set.

## Naming Conventions

1. Source file names and directory names under `src/` must use lowercase snake_case.
2. Source file names must not contain uppercase letters.
3. Source file names must not contain hyphens.
4. Public type names must use `UpperCamelCase`.
5. Public function and method names must use `lowerCamelCase`.
6. Struct fields and local variables must use lowercase snake_case.
7. Error set tags and enum tags must use `UpperCamelCase`.
8. Abbreviations must be consistent within a repo; do not mix naming styles for the same symbol class.

## Test Naming Policy

1. New tests must describe observable behavior, not milestone status.
2. New test names must not contain ticket labels, milestone labels, or queue labels.
3. Disallowed labels include `M0`-style milestone tags and batch/ticket prefixes such as `RC-`, `RB-`, `HOST-`, `DS-`, `QH-`, and similar process tags.
4. Test names must describe the asserted behavior or regression condition in plain language.
5. Legacy test names with milestone or ticket tags may remain only if they are listed in the explicit allowlist used by local hygiene tooling.
6. Legacy cleanup may be staged repo-by-repo, but each handover must state which repos were guarded and whether an allowlist was used.
7. Any new test added after this authority exists must follow the behavior-first rule; legacy exemptions are not a template for new work.

## Ticket-To-Commit Isolation

1. One ticket maps to one commit.
2. A commit must not mix unrelated ticket intent.
3. A commit may span multiple files only when all touched files are required for the same ticket.
4. Shared prerequisites must be split into a separate ticket or commit set instead of being hidden inside the current ticket.
5. If a ticket cannot be completed without touching another ticket's scope, stop and split the work before committing.
6. Handover reporting must describe any residual coupling that prevented perfect isolation.

## Enforcement Principle

These conventions are mandatory for new code, new tests, and new handover evidence.
If a rule cannot be satisfied automatically, the repo must document the exact limitation and the manual check that remains.

## Local Guard Coverage

`utils/hygene/architecture_guard.sh` enforces the current automated subset:

1. `//!` file headers for Zig source files under `src/`.
2. lowercase snake_case source file and directory names under `src/`.
3. `///` comments immediately above public declarations.
4. behavior-first test names with no ticket or milestone tags.
5. dependency direction rules for active product repos.
6. ambiguous source language bans for `adapter` and `bootstrap`.
7. compatibility-language bans for `compat[^ib]`, `fallback`, `workaround`, and `shim`.
