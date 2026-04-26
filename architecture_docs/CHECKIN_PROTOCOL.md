# Checkin Protocol

This document defines the required shape of an engineering checkin for the Howl workspace.
It is the authority for handover reports, local validation evidence, and residual-risk disclosure.

## Required Checkin Schema

Every checkin must include these sections in this order:

1. `#DONE`
2. `#OUTSTANDING`
3. `commits` with `hash + subject`
4. `validation results`
5. `files changed`
6. `findings` ordered `High`, `Medium`, `Low`

## Required Review Links

1. Every checkin must link the active review artifact used to authorize the work.
2. Every checkin must link the matching checkpoints artifact when one exists.
3. If the checkin closes a discipline sprint, it must link the sprint review and checkpoint files from `architecture_docs/reviews/...`.

## Required Residual Risk Statement

1. Every checkin must state the remaining compromise, if any.
2. The residual-risk statement must be explicit about scope, automation limits, and any allowlist or manual fallback that remains.
3. If there is no residual risk, the checkin must say `none` or an equivalent direct statement.
4. Vague phrases such as "minor issues remain" are not acceptable.

## Required Local Validation Fields

Every validation report must list:

1. The exact command run.
2. The repo or repos it was run against.
3. The exit status.
4. A short result summary.
5. Whether the command was skipped, and why, if it was not run.

## Validation Block Template

Use this template in handovers and sprint checkins:

```md
## Validation
- `zig build` — `<repo>` — `<exit status>` — `<short result>`
- `zig build test --summary all` — `<repo>` — `<exit status>` — `<short result>`
- `zig build package` — `<repo or n/a>` — `<exit status or n/a>` — `<short result>`
- `utils/hygene/architecture_guard.sh <repo...>` — `<repo or repos>` — `<exit status>` — `<short result>`
- `rg -n "compat[^ib]|fallback|workaround|shim" --glob '*.zig' src` — `<repo>` — `<exit status>` — `<short result>`
```

## Enforcement Notes

1. Local validation is mandatory for handover gates.
2. Remote CI is not part of the approval path.
3. If a rule cannot be automated cleanly, the checkin must name the limitation and the manual fallback checklist item.
