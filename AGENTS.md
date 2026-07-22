# Howl Agent Contract

Howl is a private native Zig terminal family with no downstream compatibility
obligation. It aims to be an exceptionally small, correct, embeddable terminal:
Foot-direct, TigerBeetle-defensive, and native to Zig 0.16.

Every tracked character is maintenance debt. Howl accepts debt when it buys
terminal capability, correctness, clarity, or deterministic evidence.

## Read next

Read only the authority relevant to the work:

- `project_design.yml`: enduring family and runtime design.
- `project_rules.yml`: stable product and engineering invariants.
- `project_source_map.yml`: accepted production source and build ownership.
- `project_version_scope.yml`: the current development capability cut.
- `watch_list.yml`: active structural interventions blocking ordinary work.
- `CHANGELOG.TXT`: noteworthy accepted foundation changes when history matters.

`README.md` is the project landing page, not mandatory agent onboarding.

## Protocol coverage

`protocol_coverage.yml` is the family protocol census. From Nushell, source
`protocol_coverage.nu`; `protocol help` gives the short human and structured
query surface. Support describes implementation, disposition describes
the treatment of the remaining residual obligation, and owner names the real
module responsible for that residual. Full records normalize omitted
disposition to `none`; incomplete records normalize omission to `active`.

## Development flow

Ordinary work uses a disposable marathon scratch for the objective, review
findings, validation, and commit boundaries. Delete it when the work lands.

When ordinary work exposes systemic debt, record the concrete offenders in
`watch_list.yml`, preserve working capability, and finish the intervention
before resuming feature growth. The watch list is also deleted when resolved.

Sensitive Zig constructs are reviewed uses, not purity violations. The source
audit accepts exact justified sites and rejects accidental new sites.

Commit coherent reviewed capability in small checkpoints. Experiments earn
permanence through evidence and are otherwise deleted. References sharpen
judgment; they do not choose Howl's architecture.

## Source bars

1. Direct, small source code; use Foot as the reference.
2. Explicit ownership, cleanup, bounds, invariants, exact errors, and
   executable boundary checks; use TigerBeetle as the reference.
3. Zig 0.16 runtime and build interfaces are understood before replacement.
4. Terminal references provide protocol evidence without donating structure.

Comments describe current code and maintained decisions. Public symbols,
structs, generics, conversions, files, tests, tools, and documentation earn
their characters through domain meaning or reduced ambiguity.

## Workspace boundary

The monorepo exists only for Git, agent, and development ergonomics plus atomic
history. Every `howl-*` directory is an independent small Zig package that owns
its build identity, dependencies, native facts, and proofs. The root
`howl_workspace` exports no product module or artifact; it invokes child builds,
validates root evidence, and provides development aliases.

QAgent directly consumes the `howl-control` and `howl-vt` packages. It pressures
Howl through use without owning Howl's domain or importing application policy.
