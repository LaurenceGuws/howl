# Style Enforcement Sprint

Owner: workspace root.

Purpose: make Howl documentation, workflow, and style observability explicit enough to enforce a
TigerBeetle-grade style bar across cleanup work and future feature work.

Status: temporary sprint doc.

Delete this doc after the surviving rules are promoted into long-lived workspace docs and the
temporary checkpoint language is no longer needed.

## References

Read these before editing:

- `/home/home/personal/projects/howl/AGENTS.md`
- `/home/home/personal/projects/howl/WORKFLOW.md`
- `/home/home/personal/projects/howl/design/design-rules.md`
- `/home/home/personal/projects/howl/style.nu`
- `/home/home/personal/projects/howl/utils/hygene/style_scan.py`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/TIGER_STYLE.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/internals/docs.md`
- `/home/home/personal/projects/howl/utils/dev_references/zig_maturity/tigerbeetle/docs/ARCHITECTURE.md`

## Sprint Goal

Close three gaps:

1. workspace style rules are still too principle-level and not explicit enough to enforce
2. `style.nu` is useful as a summary but is not a real checkpoint gate yet
3. workflow/docs do not force style observability strongly enough before checkpoint closure

## Non-Goals

- no renderer architecture rewrite
- no host/runtime behavior rewrite unless a tiny doc/tool correction is required
- no speculative lint framework
- no large new doc tree

## Done Definition

This sprint is complete only when all of the following are true:

- Howl has one explicit style law document strong enough to review against line by line
- `AGENTS.md` and `WORKFLOW.md` require style observability as a checkpoint gate
- `style.nu` can expose touched-file style regressions clearly enough to block closure
- the surviving rules are short, exact, and durable
- future feature work can be rejected on explicit style grounds without hand-waving

## Global Gates

Every checkpoint must pass all gates.

### Clarity Gate

Before editing, answer:

- which file owns the rule?
- which file owns the observability?
- which file owns the workflow gate?
- what proof closes the change?

If any answer is unclear, stop and mark `work-not-clear`.

### Style Gate

- prefer explicit rules over principle summaries
- prefer deletion over overlap
- prefer small exact commands over prose about commands
- no new wrapper doc around an existing stronger doc

### Tool Gate

- `style.nu` must become more useful as a gate, not just more complicated
- no metric may be added without a clear review use
- do not add metrics that cannot inform pass/fail or investigation

### Proof Gate

Each checkpoint closes only with proof from the workspace root:

- exact files changed are listed
- `git diff --check` on changed repos
- commands added to docs are runnable or already proven runnable
- any new `style.nu` output path is exercised directly

## Milestone 1: Write The Style Law

Goal:

- create an explicit Howl style law derived from TigerBeetle and adapted to Howl owners/runtime

Primary scope:

- `AGENTS.md`
- `WORKFLOW.md`
- `design/design-rules.md`
- new style-law doc if needed

### Checkpoint 1.1: Style Law Surface

Done when:

- one obvious style law exists
- it states exact pass/fail expectations for function shape, assertions, control flow, naming, and
  options/defaults where applicable
- overlapping style wording is removed from weaker docs

Status:

- closed by `design/style-law.md`

### Checkpoint 1.2: Workspace Integration

Done when:

- `AGENTS.md` and `WORKFLOW.md` point to the style law clearly
- checkpoint closure rules mention style gating explicitly
- doc set remains minimal and non-overlapping

Status:

- closed by workspace doc pointers and workflow gate wording

Milestone 1 gate:

- a reviewer can cite one doc as the workspace style law
- no remaining ambiguity about where strict style rules live

## Milestone 2: Make Style Observability A Gate

Goal:

- upgrade `style.nu` from summary surface to checkpoint-gate surface

Primary scope:

- `style.nu`
- `utils/hygene/style_scan.py`
- root docs that describe the gate

### Checkpoint 2.1: Useful Metrics Only

Done when:

- current metrics are justified or removed
- any new metrics directly support pass/fail or investigation
- output can identify touched-file regressions clearly

### Checkpoint 2.2: Gate Shape

Done when:

- command model is explicit before behavior grows
- each invocation has one primary mode
- deeper combined inspection, if it exists, has its own explicit mode name
- default mode is a quiet checkpoint gate
- touched-file review is fast
- deeper repo and file inspection remains available on demand
- `style.nu` has an obvious mode for checkpoint review
- reviewers can see touched-file regressions without scanning the whole workspace blindly
- long-function and `usize` regressions are visible enough to block closure

Milestone 2 gate:

- `style.nu` can be used during review as a practical gate
- output is still short enough to read
- query surface is broader, not narrower
- default mode stays quiet while file and repo inspection stay first-class

### Milestone 2 Command Model

- Primary modes are exclusive.
- Refinement flags do not change the review question, only the slice or ordering.
- If a combined deep view is useful, it has its own explicit mode name.

Primary modes:

- default checkpoint gate
- failures view
- touched-files view
- touched-repos view
- by-file deep inspection
- by-repo deep inspection
- deep combined inspection

Refinement flags:

- root/path filters
- `--sort`
- `--blame`

Invalid combinations:

- more than one primary mode in the same invocation
- refinement flags that do not apply to the selected primary mode

## Milestone 3: Wire The Gate Into Workflow

Goal:

- make style observability mandatory for cleanup work and future feature work

Primary scope:

- `AGENTS.md`
- `WORKFLOW.md`
- `design/design-rules.md`
- `style.nu`

### Checkpoint 3.1: Checkpoint Closure Rule

Done when:

- workflow docs explicitly require style review before checkpoint closure where style is in scope
- style cleanup work cannot close without `style.nu` proof

Status:

- closed by workflow gate wording and explicit `style.nu` invocation path

### Checkpoint 3.2: Feature Work Rule

Done when:

- future feature work has an explicit no-regression style rule
- touched-file style regressions require justification or rejection

Status:

- closed by workspace law and workflow closure rules

Milestone 3 gate:

- a future engineer handover can require style proof with no extra explanation

Status:

- closed

## Suggested Rule Targets

These are candidate areas the style law should make explicit if they survive review:

- simple explicit control flow only
- bounded work and bounded queues
- explicit-sized integers preferred over `usize`
- assertions as invariants, not decoration
- pair assertions where practical
- split compound assertions when clarity improves
- centralize control flow in parent functions
- avoid wrapper forwarders that add no boundary
- docs are part of the checkpoint and style gate

Do not copy TigerBeetle mechanically where the ownership boundary differs. Adapt the rule only if it
stays true to Howl.

## First Active Milestone

Start with Milestone 1.

Reason:

- the explicit law must exist before the observability gate can enforce it
- otherwise tool output has no strict contract behind it
- style enforcement should be rule-first, tool-second, workflow-third
