# Howl Agent Contract

Howl is a private native Zig terminal family with no downstream compatibility
obligation. It aims to be an exceptionally small, correct, embeddable terminal:
Foot-direct, TigerBeetle-defensive, and native to pinned Zig
0.17.0-dev.1454+5faa79730.

Every tracked character is maintenance debt. Howl accepts debt when it buys
terminal capability, correctness, clarity, or deterministic evidence.

## Read next

Read only the authority relevant to the work:

- `project_design.yml`: enduring family and runtime design.
- `project_rules.yml`: stable product and engineering invariants.
- `project_source_map.yml`: accepted production source and build ownership.
- `project_version_scope.yml`: the current development capability cut.
- `watch_list.yml`: active structural interventions blocking ordinary work,
  when the file is present.
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

Long interventions use four explicit lifetimes:

- A marathon YAML owns the complete intervention, invariants, exclusions,
  sprint order, and final acceptance gate.
- The active sprint YAML owns one coherent capability or ownership milestone,
  its ordered slices, and its sprint acceptance gate.
- A slice is one reviewable deletion, decision, implementation, or proof unit
  recorded by the sprint.
- The active scratchpad owns current-slice commands, findings, compiler output,
  review corrections, and immediate progress.

The current marathon and active sprint/scratch authorities are tracked so the
intervention survives agent sessions and compaction. Disposable research,
runtime captures, generated receipts, and exploratory indexes live under the
marathon's ignored `.zig/work/` playground. Accepted conclusions move into the
tracked authorities; raw playground artifacts never become hidden product
authority.

Only one sprint and one slice are active unless the marathon explicitly proves
that independent work can proceed. Accepted slice facts and commits move from
the scratchpad into the sprint; accepted sprint facts and commits move into the
marathon. Reset the scratchpad for the next slice or delete it when no slice is
active. Delete the sprint when its accepted outcome is recorded by the
marathon, and delete the marathon when its final gate lands.

When ordinary work exposes systemic debt, record the concrete offenders in
`watch_list.yml`, preserve working capability, and finish the intervention
before resuming feature growth. The watch list is also deleted when resolved.

## Evidence flow: YAML -> JSONL -> Git

Runtime implementation and debugging move through three distinct evidence
forms. Pure static research or documentation may move directly from reviewed
YAML evidence to Git when no executable behavior exists to capture.

1. YAML owns the query before execution: accepted policy, exact unknowns,
   reproduction procedure, event schema, bounds, exclusions, and acceptance
   gate. It never fabricates runtime facts.
2. JSONL owns factual runtime captures. Every runtime slice produces temporary
   structured evidence for review; GUI, CLI, simulation, fuzz, benchmark, and
   hostile-test runs differ only in who drives them. Use
   `tools/json_logger.zig`, emit bounded strongly typed events, and query the
   untouched capture with Nushell. Normal traces never use stdout, stderr, or
   prose records; stderr remains for genuine failures. JSONL is the default
   runtime authority, not a prohibition on better evidence shapes. When a
   matrix, relation, or fixed table is materially clearer as TSV or CSV, stop
   and define its ownership, schema, derivation, validation, and lifetime in
   the active YAML before creating it. Nushell may query either form. The
   operator drives GUI reproductions unless they explicitly authorize
   automation.
3. Git owns only reviewed conclusions and implementation. A capture does not
   authorize a fix, and passing tests do not replace review or an outstanding
   manual gate. Commit one coherent accepted slice and push it so important
   state does not exist only in an agent session.

Temporary product instrumentation is removed only after the capture has been
reviewed and cleanup is authorized. Never move, truncate, rewrite, or delete a
capture while it is under review. Keep the reusable logger in `tools`; keep
accepted normalized findings in the active ignored YAML evidence, not in
permanent product logging or committed raw traces.

Sensitive Zig constructs are reviewed uses, not purity violations. The source
audit accepts exact justified sites and rejects accidental new sites.

Commit coherent reviewed capability in small checkpoints. Experiments earn
permanence through evidence and are otherwise deleted. References sharpen
judgment; they do not choose Howl's architecture.

## Source bars

1. Direct, small source code; use Foot as the reference.
2. Explicit ownership, cleanup, bounds, invariants, exact errors, and
   executable boundary checks; use TigerBeetle as the reference.
3. Pinned Zig runtime and build interfaces are understood before replacement.
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

Workspace commands use `./.zig/zig`; child-local commands inherit that pin or
use `../.zig/zig`. Never substitute ambient Zig for the tracked `.zigversion`.

QAgent is an experimental embedder outside the accepted package graph. It may
pressure Howl through use without owning Howl's domain or importing application
policy.
