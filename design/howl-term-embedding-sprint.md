# Howl-Term Embedding Sprint

Purpose: lock the `howl-term` embedding sprint in writing so the work does not drift. This sprint is about making `howl-term` a beta-quality embedding product with the right ownership shape, one canonical semantic API, and a host-driven default execution model. It is not the sprint that solves every performance problem or freezes a forever ABI.

Last updated: 2026-05-12

## Position

This sprint is a foundation sprint for `howl-term` as a product.

Longer-term product target:
- make `howl-term` the default terminal embedding surface for Howl hosts and external embedders.

This sprint target:
- replace the current runtime-heavy package shape with an embedding contract whose default architecture is host-driven, bounded, and explicit.
- raise the API, ABI, and ownership standard to match the clarity of `ghostty`'s public VT surface and the explicitness of `tigerbeetle`'s design discipline.

This sprint does not claim success by shipping a final stable forever ABI.
This sprint claims success only if the default package shape becomes the right shape.

## Renderer Sprint Lessons

Keep from the renderer sprint:
- locked scope before implementation churn
- milestone gates with explicit pass and fail conditions
- reference-pressure sections instead of vague inspiration
- exit artifacts that survive the sprint

Improve from the renderer sprint:
- proof must match the layer of the claim
- architecture completion must not be mistaken for live-product completion
- benchmark proof, runtime proof, and host proof must be named separately
- milestone language must say whether a claim is contract, implementation, runtime, or host-visible
- no broad milestone pass if the user repro still lives in an unmeasured layer

## Locked Scope

In scope:
- `howl-term` public root, namespace wrapper, and owner boundaries
- one canonical semantic API for terminal embedding
- a C ABI and a Zig facade with the same capabilities, ownership model, and sequencing
- default host-driven execution and bounded progress surfaces
- optional convenience runtime only if it stays small, explicit, and secondary
- example embedders and proof surfaces for Zig and C
- minimal `howl-linux-host` changes only where needed to consume the corrected contract cleanly

Out of scope:
- renderer-path redesign
- new PTY variants
- final multi-language client bindings beyond C and Zig
- final semver or forever-stable ABI promises
- host UI redesign
- Android parity work
- speculative runtime features that do not serve the embedding contract directly

Layer rules:
- `howl-term` owns terminal state, VT/session integration contract, render snapshot contract, input publication contract, callback contract, and lifecycle rules
- `howl-session` owns PTY variants and child transport behavior
- `howl-render-core` owns renderer internals and backend behavior
- hosts own event loops, scheduling, pacing, and presentation cadence
- `howl-term` may expose an optional convenience runtime path, but it must not define the default architecture
- do not pull host scheduling down into `howl-term`
- do not push `howl-term` semantic policy down into lower modules

## Locked Non-Negotiables

- No fake progress.
- No hidden mandatory thread in the default embedding path.
- No hidden global state.
- No surprise wake policy.
- No host event loop ownership inside the default `howl-term` contract.
- No public API split where Zig has materially different semantics from C without an explicit documented reason.
- No broad compatibility layer that keeps the old runtime-owned architecture alive under new names.
- No milestone passes on pretty examples if the real host still depends on hidden library scheduling policy.
- No undocumented ABI drift in symbol names, calling convention, extern layout, or numeric result codes.

## Reference Pressure Points

### Ghostty Pressure Points

Use `ghostty` as the public-surface and ownership-shape reference, not as a line-for-line cargo cult target.

Pressure points:
- public root curates exports and gates C symbols only
- namespace wrapper indexes owner files and should not own behavior
- owner files carry the state and mutation logic
- C ABI is a real product surface, not an afterthought
- examples exercise the public surface directly without host-only hidden behavior

Reference files:
- `utils/dev_references/terminals/ghostty/src/lib_vt.zig`
- `utils/dev_references/terminals/ghostty/src/terminal/main.zig`
- `utils/dev_references/terminals/ghostty/example/zig-vt/src/main.zig`
- `utils/dev_references/terminals/ghostty/example/c-vt/src/main.c`

### TigerBeetle Pressure Points

Use `tigerbeetle` as the simplicity, safety, and public-contract discipline bar.

Pressure points:
- explicit, bounded control flow
- fixed limits and known capacities
- pair assertions on public-contract invariants
- clear control-plane versus data-plane separation
- design before churn
- explicit API change discipline instead of accidental breakage

Reference files:
- `utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/coding/system-architecture.md`
- `utils/dev_references/zig_maturity/tigerbeetle/docs/coding/api-changes.md`

### Howl Pressure Points

Current pressure points inside this repo:
- `howl-term` currently mixes embedding contract and runtime orchestration too heavily
- the public export surface is broad and not yet organized around one canonical semantic contract
- command-output latency evidence suggests scheduling and publication policy are still in the wrong layer
- `howl-linux-host` must become an embedder of the right `howl-term` contract, not the proof that hidden library scheduling is acceptable

Reference files:
- `howl-term/sprintscope.txt`
- `design/module-owner-responsibilities.md`
- `howl-term/src/howl_term.zig`
- `howl-term/src/ffi.zig`

## Sprint Done Definition

This sprint is done only when all of the following are true:

- `howl-term` has one canonical semantic API for embedding
- the Zig facade and C ABI expose the same capabilities, sequencing, and ownership model
- the public root curates exports and symbols only
- the namespace wrapper is an index, not a behavior owner
- the default embedding path is host-driven and bounded
- no hidden background runtime thread or hidden wake cadence is required for the default path
- if a convenience runtime path remains, it is optional, narrow, and visibly secondary
- Zig and C examples prove the public surface directly
- docs and tests can point to one clear owner chain for lifecycle, input, snapshot publication, and frame preparation

If any one of these is false, the sprint is not done.

## Milestone 1: Freeze The Product Contract And Layer Boundaries

Milestone goal:
- lock what `howl-term` is, what it is not, and where ownership stops before implementation churn begins.

Scope done:
- one locked product statement exists for `howl-term`
- one locked owner chain exists from public root to behavior owners
- the sprint has named proof surfaces for contract, runtime, and host-visible claims

### Checkpoint 1.1: Canonical Product Statement

Goal against `ghostty`:
- define `howl-term` as an embedding package, not as an app runtime that happens to be embeddable.

TigerBeetle hygiene gate:
- positive space and negative space are both explicit
- ownership statements are direct and bounded
- no broad words like "just a helper" or "temporary glue"

Done when:
- the design can state exactly what `howl-term` owns
- the design can state exactly what hosts own

### Checkpoint 1.2: Canonical Layer Shape

Goal against `ghostty`:
- keep the public root thin, the namespace wrapper index-like, and the owners responsible for behavior.

TigerBeetle hygiene gate:
- one file role per layer
- no behavior in roots or namespace wrappers
- owner boundaries are named before code motion starts

Done when:
- the design can name the role of `src/howl_term.zig`, `term_namespace.zig`, owner files, and `c_api/*`

### Checkpoint 1.3: Canonical Proof Ladder

Goal against the renderer sprint:
- never use a lower or narrower proof surface to overclaim a higher-layer result.

TigerBeetle hygiene gate:
- every claim names its proof layer
- every benchmark or example has a bounded purpose
- no milestone gate relies on reviewer intuition about missing layers

Done when:
- the sprint text names separate contract proof, `howl-term` runtime proof, and host proof

### Milestone 1 Gate

Pass only if:
- the sprint has one locked product target
- the owner chain is clear from public root to behavior owner
- the proof ladder prevents the renderer-sprint mismatch between local proof and live repro

Fail if:
- `howl-term` is still described as both embedding contract and default runtime owner without a boundary
- roots and wrappers are still allowed to accumulate behavior
- milestone claims can still outrun the proof surface that actually measured them

Milestone 1 lock artifacts:
- `design/howl-term-contract-boundaries.md` is the canonical product statement, owner chain, and proof ladder for this milestone
- `design/module-owner-responsibilities.md` records the repository owner map aligned with that contract

## Milestone 2: Define One Canonical Semantic API Across Zig And C

Milestone goal:
- make `howl-term` one product with two public surfaces, not two loosely related products.

Scope done:
- one semantic contract exists for lifecycle, input, callbacks, snapshots, and frame work
- Zig and C are different syntax over the same behavior

### Checkpoint 2.1: Lifecycle And Ownership Contract

Goal against `ghostty`:
- expose a clean public surface that embedder code can understand from init to deinit without reading internals.

TigerBeetle hygiene gate:
- init, start, stop, and deinit sequencing are explicit
- allocator, config, and callback ownership are explicit
- opaque handles or owner values have clear destruction rules

Done when:
- the contract can state exactly who allocates, who starts, who stops, and who frees

### Checkpoint 2.2: Input, Output, And Event Contract

Goal against `ghostty`:
- model host interaction as explicit inputs and explicit host-consumed outputs.

TigerBeetle hygiene gate:
- no hidden side channels
- callback and drain semantics are explicit
- positive and negative event spaces are named

Done when:
- the contract can state how input enters, how host-facing events leave, and what remains owned by the terminal core

### Checkpoint 2.3: Snapshot And Frame Contract

Goal against current `howl-term` drift:
- make render-facing work explicit enough that a host can drive it without inheriting hidden scheduler policy.

TigerBeetle hygiene gate:
- prepare, render, wake, and snapshot semantics are explicit
- bounded work surfaces are named with limits
- no API requires the caller to guess library-owned pacing policy

Done when:
- the contract can state how a host learns that renderable work exists and how it drives that work forward

### Checkpoint 2.4: Zig And C Parity Proof

Goal against accidental API drift:
- prove both public surfaces describe the same terminal product.

TigerBeetle hygiene gate:
- examples and tests cover the same lifecycle on both surfaces
- result codes and statuses are explicit, not prose-only
- change-sensitive extern layouts and exported symbol names are treated as first-class proof targets

Done when:
- Zig and C examples exercise equivalent flows
- parity tests can show the same capability set exists on both surfaces

### Milestone 2 Gate

Pass only if:
- the semantic contract is singular
- C and Zig differ only where language shape truly requires it
- reviewers can explain lifecycle and ownership without translating between two mental models

Fail if:
- C and Zig expose materially different products
- lifecycle or callback ownership still relies on hidden implementation knowledge
- the public surface still looks like an organically grown export list instead of a coherent contract

Milestone 2 lock artifacts:
- `design/howl-term-semantic-contract.md` is the canonical Zig and C semantic contract for this milestone
- `howl-term/src/test/root.zig` carries executable parity proof for the public surface

## Milestone 3: Make Host-Driven Execution The Default Architecture

Milestone goal:
- move runtime scheduling policy out of the default `howl-term` architecture and into explicit host control.

Scope done:
- the default path is host-driven
- bounded progress calls or equivalent explicit execution surfaces exist
- library wake signals are observations, not hidden scheduling policy

### Checkpoint 3.1: Bounded Progress Contract

Goal against hidden runtime ownership:
- make progress surfaces explicit enough that hosts can drive terminal work at their own pace.

TigerBeetle hygiene gate:
- every progress surface has explicit bounds
- control flow is simple and reviewable
- work admission is explicit rather than event-reaction magic

Done when:
- the contract can name the bounded operations by which a host advances transport, apply, snapshot, and frame work

### Checkpoint 3.2: Remove Hidden Scheduler Policy From The Default Path

Goal against the current responsiveness confusion:
- make it impossible to confuse terminal correctness with library-owned pacing behavior.

TigerBeetle hygiene gate:
- wake and backpressure semantics are explicit
- no mandatory hidden thread remains in the default path
- policy and data plane are visibly separate

Done when:
- reviewers can point to the exact place where scheduling lives, and it is not hidden inside the default terminal contract

### Checkpoint 3.3: Runtime-Layer Proof Surface

Goal against proof mismatch:
- measure `howl-term` runtime behavior at the `howl-term` layer instead of overclaiming from renderer-only or host-only artifacts.

TigerBeetle hygiene gate:
- runtime proof names sync, copy, publication, and frame-prep costs distinctly
- known latency-sensitive flows have deterministic harness coverage
- proof can explain a user repro in the correct layer

Done when:
- `howl-term` proof can answer whether a slow-output repro is transport, apply, snapshot, or frame-prep work

### Milestone 3 Gate

Pass only if:
- the default architecture is host-driven
- hidden library scheduling policy is no longer required for correctness
- runtime-layer proof exists for runtime-layer claims

Fail if:
- the default path still depends on a hidden background runtime thread
- wake behavior still smuggles pacing policy into the library
- reviewers still need host internals to explain what the terminal contract means

Milestone 3 lock artifacts:
- `design/howl-term-semantic-contract.md` names the bounded host-driven transport, apply, snapshot, and frame surfaces
- `howl-term/src/test/root.zig` asserts the explicit progress inventory on Zig and C
- `howl-term/src/test/benchmark.zig` measures transport, apply, publication, and frame-prep cost separately at the `howl-term` layer

## Milestone 4: Eliminate The Convenience Runtime Path And Legacy Scheduler Structures

Milestone goal:
- delete the convenience runtime path as a product-defining concept and remove the dead scheduler structures that belonged to the old library-owned default path.

Scope done:
- the host-driven core is the only real default execution path
- convenience lifecycle aliases, if any remain, are thin entry aliases only and do not carry separate scheduler semantics
- dead and legacy runtime-owned scheduler structures from the pre-host-driven path are deleted

### Checkpoint 4.1: Delete Product-Level Convenience Ownership

Goal against architectural drift:
- stop treating convenience runtime behavior as something the architecture still needs to debate.

TigerBeetle hygiene gate:
- there is one default path, not a negotiated coexistence
- convenience entrypoints do not carry separate ownership or scheduler meaning
- dead ownership structures are not kept around as architectural fog

Done when:
- the design can state that the host-driven core is the only real execution model
- any remaining convenience entrypoints are documented as thin aliases only

### Checkpoint 4.2: Core Contract Independence

Goal against default-path corruption:
- make the core terminal product usable without the convenience runtime.

TigerBeetle hygiene gate:
- tests and examples exercise the core path directly
- convenience entrypoints cannot add semantic requirements to the core path
- negative space is asserted: core path works without convenience helpers
- dead scheduler fields, thread files, and stale comments do not remain in the core path as misleading leftovers

Done when:
- the public contract remains complete and coherent with convenience scheduler ownership removed
- reviewers can trace the core path without crossing dead runtime-thread structures that no longer own correctness

### Checkpoint 4.3: Host Proof Of Sole Default Status

Goal against accidental dependency:
- prove that real hosts embed the core contract directly and no longer depend on convenience runtime behavior.

TigerBeetle hygiene gate:
- host integration uses the core contract intentionally
- no hidden fallback to old runtime-owned behavior remains
- no surviving convenience path is required for host correctness

Done when:
- host proof can show that the core path is the only real default path in practice, not only in prose

### Milestone 4 Gate

Pass only if:
- the convenience runtime no longer exists as a separate architectural path
- the host-driven core remains the real product
- no semantic ownership leaks back into convenience aliases
- dead or misleading pre-host-driven runtime structures no longer blur the owner chain

Fail if:
- convenience code still defines what the core contract means
- hosts still depend on convenience behavior for basic correctness
- reviewers still need to ask whether the convenience path is optional or architectural
- dead runtime-thread fields, files, or comments still imply that the old library-owned scheduler is part of the real default path

## Milestone 5: Prove Host-Visible Top-Class Pressure On The API

Milestone goal:
- prove at the real host layer that the `howl-term` API shape does not block top-class latency, throughput, CPU efficiency, or frame cadence, and force any remaining API weakness into explicit evidence.

Scope done:
- host-visible proof exists for latency, throughput, CPU, and FPS or frame-cadence behavior under the real embedder path
- the API is judged under production-style host pressure, not only package-local proofs
- any remaining host-visible deficit is tied back to an explicit API, scheduler, or renderer boundary instead of folklore

### Checkpoint 5.1: Canonical Host Scorecard

Goal against hand-wavy success:
- define one severe scorecard for host-visible behavior that the API must survive.

TigerBeetle hygiene gate:
- scorecard metrics are explicit and bounded
- workload set is explicit and repeatable
- proof artifacts are retained, not paraphrased from memory

Done when:
- the sprint defines a host-visible scorecard covering at least latency, throughput, CPU, and FPS or frame cadence
- the scorecard names the exact workloads, artifact format, and peer references when used

### Checkpoint 5.2: Host Proof Under Real Embedder Pressure

Goal against package-local overclaim:
- force the API to survive the real host loop, not just synthetic internal harnesses.

TigerBeetle hygiene gate:
- host proof uses the real host-driven core path
- proof distinguishes package-layer from host-visible results
- bottlenecks are attributed to explicit layers

Done when:
- the host proof can explain whether latency, throughput, CPU, and cadence are limited by API shape, host scheduling, renderer work, or lower-module behavior

### Checkpoint 5.3: Top-Class Or Explicitly Open

Goal against vague aspiration:
- either prove the host-visible path is top-class on the chosen scorecard or leave an explicit open failure boundary that keeps pressure on the API.

TigerBeetle hygiene gate:
- no soft language like "pretty good" or "close enough"
- positive and negative performance space are both named
- if top-class is not met, the failing metric and owning boundary are explicit

Done when:
- the milestone can state which host-visible metrics are top-class now and which remain open with explicit owner and evidence

### Milestone 5 Gate

Pass only if:
- host-visible proof exists on a locked scorecard for latency, throughput, CPU, and FPS or cadence
- the real host-driven embedder path is the thing being judged
- the API is under real pressure rather than protected by lower-layer-only wins

Fail if:
- host-visible claims still rely on package-local proof only
- the scorecard is vague or shifting
- a host-visible deficit is described without naming the owning boundary

Milestone 5 lock artifacts:
- `design/howl-term-host-scorecard.md` defines the canonical host-visible workload, metrics, and artifact rules
- `howl-hosts/howl-linux-host/tools/benchmark_terminals.py` writes the retained host scorecard and raw artifacts for the real embedder path

## Milestone 6: Lock Regressions, Examples, And Change Discipline

Milestone goal:
- turn the sprint's architecture risks into explicit checks, examples, and change rules so the package does not slide back after the sprint.

Scope done:
- known contract regressions are named
- examples and tests lock the public product shape
- API and ABI change expectations are explicit

### Checkpoint 6.1: Explicit Regression Classification

Goal against drift:
- name the ways this sprint could silently fail after the first clean refactor.

TigerBeetle hygiene gate:
- regressions are named as positive and negative spaces
- public-contract invariants are asserted in more than one place when practical
- no reviewer-memory-only warnings

Done when:
- the design can state which regressions are now impossible or explicitly trapped

### Checkpoint 6.2: Public Surface Proof

Goal against surface rot:
- keep examples and tests as executable proof of the product.

TigerBeetle hygiene gate:
- Zig example, C example, and parity tests all exercise the intended public path
- proof covers lifecycle, input, output, and frame-driving basics
- ABI-sensitive structures and symbols have explicit checks or generated proof

Done when:
- a future change cannot silently break the public surface without failing proof

### Checkpoint 6.3: Change Discipline

Goal against accidental breakage:
- make API and ABI change cost visible before changes ship.

TigerBeetle hygiene gate:
- public changes require named rationale
- externally visible changes have an update record
- semantics and syntax changes are distinguished

Done when:
- the repo has a durable place to record `howl-term` public-surface changes and migration notes

### Milestone 6 Gate

Pass only if:
- the sprint's known contract and ownership regressions are locked by docs, tests, examples, or ABI proof
- the public surface has executable proof in Zig and C
- external-facing change discipline is explicit

Fail if:
- the only memory of the sprint lives in prose
- public-surface breakage can still slip in silently
- change cost is still discoverable only after an embedder breaks

## Review Rule For The Whole Sprint

The review standard is intentionally severe.

The reviewer must reject any milestone that:
- keeps the old runtime-owned architecture alive for comfort
- hides scheduler policy behind library wake behavior
- accepts a split where C and Zig are different products
- passes on example folklore instead of proof
- uses a lower-layer benchmark to overclaim a higher-layer result
- adds convenience at the cost of ownership clarity

The reviewer may approve the next milestone only when the current one passes on all three axes:
- product shape is clearer against `ghostty` public-surface discipline
- determinism and explicitness are stronger against `tigerbeetle` standards
- ownership is visibly simpler, not merely redistributed

## Exit Artifacts

By sprint end, the repository must contain:
- a long-lived `howl-term` embedding contract doc
- a sprint artifact proving the owner chain and proof ladder used during the work
- Zig and C examples exercising the public surface directly
- tests or generated proof for exported symbol and ABI-sensitive surface expectations
- `howl-term` runtime proof artifacts for latency-sensitive output paths
- host proof artifacts showing the real embedder consumes the corrected contract
- a durable change record location for public `howl-term` API and ABI changes

This sprint doc should be deleted only after its locked rules are promoted into long-lived design and embedding-contract docs.
