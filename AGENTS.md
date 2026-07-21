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

`howl-vt/reference_sequences.yml` is the protocol census. From Nushell, source
`howl-vt/protocol_coverage.nu` and use the `protocol coverage` command family
for summaries, filtered records, gaps, proof review, and census-aware tab
completion.

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

The root build exposes public modules and publication artifacts. Root-only
development steps are composed through `build/dev.zig`. Tools implement their
own narrow behavior and do not become product dependencies.

QAgent is Howl's first real embedder. It pressures Howl through use without
owning Howl's domain or importing application policy into the terminal family.
