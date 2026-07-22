# Render capability reset scratchpad

Current slice: `bootstrap_durable_workflow`

This tracked file contains only current-slice working state. Promote accepted
facts and commits into `sprint_render_capability_reset.yml`, then reset it for
the next slice or delete it when no slice remains active.

## Required outcome

Establish the durable marathon, sprint, slice, and scratchpad workflow; index
the first render sprint and its authority-alignment entry gate without changing
product implementation.

## Settled facts

- Every module allocation uses an explicit caller-provided allocator.
- VT owns terminal protocol semantics, state, dirty facts, input encoding,
  replies, and terminal consequences.
- PTY owns Linux PTY transport and child-process lifecycle.
- Control optionally composes PTY and VT into ID-addressable terminal instances
  with bounded interfaces.
- Render owns backend-neutral terminal visual knowledge and plain values. It
  owns no runtime publication, synchronization, threads, GPU device, window,
  layout, or executable scheduling policy.
- The executable owns threads, publication storage, GPU resources, windowing,
  layout, sessions, tabs, panes, and presentation. Its noun and final topology
  remain unsettled.

## First substantive slice prepared

After this bootstrap is accepted, reset this scratchpad for
`align_durable_authorities`. That slice owns the following known offenders.

## Authority offenders to remove or quarantine

### project_design.yml

- Standalone `text` and `frame` components.
- Control composition of frame and ownership of publication.
- Frame-owned renderer acknowledgement.
- Render borrowing immutable frames as enduring architecture.
- Previous host/thread/frame topology stated as settled design.
- `consumer-vt` isolation proof after that package was deleted.

### project_rules.yml

- Concrete window-loop and EGL/GLES render-thread topology as a family rule.
- Missing explicit caller-provided allocator invariant.

### project_source_map.yml

- Deleted `consumer-vt`, `howl-text`, `howl-frame`, and `howl-window` paths.
- Control-owned immutable frame publication.
- Old renderer ownership stated as accepted current design.
- Deleted probe files and probe vocabulary.

### project_version_scope.yml

- Accepted capabilities built around frame publication, shared runtime render
  preparation, old host topology, and control-owned immutable publication.
- Gates requiring deleted packages, paths, or rejected architecture.

## Current validation

- [x] Planning YAML parses.
- [x] Marathon active sprint and scratch paths resolve.
- [x] Sprint current slice matches this scratchpad.
- [x] Diff contains workflow and planning changes only.
- [x] No render API, executable topology, or control interface shape is inferred.

The following checks belong to the prepared authority-alignment slice, not this
bootstrap:

- [ ] `project_design.yml` parses and matches settled ownership.
- [ ] `project_rules.yml` parses and includes the allocator invariant.
- [ ] `project_source_map.yml` parses and distinguishes accepted source from
      quarantined reconstruction evidence.
- [ ] `project_version_scope.yml` parses and scopes reconstruction without
      certifying the rejected topology.
- [ ] Repository search finds no permanent authority retaining deleted probe,
      standalone frame/text, or control-render-publication claims.
- [ ] Diff contains documentation/workflow changes only.

## Immediate next action

Review and accept this workflow bootstrap. Then record its commit in the sprint,
activate `align_durable_authorities`, and reset this scratchpad before changing
the permanent project YAML authorities.
