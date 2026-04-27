# MVP Scope Alignment Review - 2026-04-27

## Scope

This review resets parent-level MVP direction after the terminal-boundary scope
correction.

Product repos in scope:

- `howl-vt-core`
- `howl-session`
- `howl-term-surface`
- `render/howl-render-core`
- `render/howl-render-gl`
- `render/howl-render-gles`
- `render/howl-render-metal`
- `render/howl-render-software`
- `render/howl-render-vulkan`
- `howl-hosts/howl-sdl-host`
- `howl-hosts/howl-android-host`

Utility repos under `utils/` remain outside the product hygiene gate.

## Corrected Product Model

The old linear `host -> session -> surface -> renderer` reading is not precise
enough for the actual product being built.

The corrected model is:

- hosts are platform shells and app containers
- the current `howl-term-surface` repo owns the effective `howl-term` boundary
- that boundary owns one embeddable terminal instance/widget
- the boundary composes `howl-session`, `howl-vt-core`, `howl-render-core`, and
  a selected renderer backend
- hosts may later manage multiple terminal instances, but app-level
  multiplexing stays host-owned, not terminal-boundary-owned
- renderer backends remain thin executors beneath `howl-render-core`

## Current Truth

### High: parent and child docs were underspecifying the primary terminal boundary

Cause:

- the older `surface` name kept steering docs toward a thinner Ghostty-style VT
  surface interpretation than the current code and product intent support
- host docs then drifted toward direct session/renderer composition language
- milestone and progress docs became Linux-host-centric in wording while Android
  simultaneously kept acting as a proof host

Correction:

- parent authority now explicitly treats the current `howl-term-surface` repo as
  the effective `howl-term` boundary
- child repo scope/boundary/milestone docs for session, terminal boundary,
  render-core, render-gl, SDL host, and Android host now describe the same
  ownership model

### High: MVP completion has been overstated by milestone labels, not by runtime truth

Current runtime truth:

- SDL host still needs real, correct text rendering and full interactive-shell
  quality closure
- Android host must remain a peer boundary-pressure lane, not a disconnected
  side path
- module architecture is far ahead of visible MVP completion

Required rule:

- sprint planning must track runtime truth, not optimistic local milestone
  labels
- parent queue/progress docs must point first to cleanup/alignment, then to MVP
  runtime closure

### Medium: previous hygiene sprint closed structural debt, but not full semantic alignment

The product-structure sprint successfully thinned roots, split entrypoints, and
hardened backend scaffold ownership. It did not finish the larger naming/scope
realignment caused by the terminal-boundary scope correction.

That remaining work is now Sprint 1, not background noise.

## Two-Sprint Plan

### Sprint 1: MVP Scope Alignment and Cleanup

Intent:

- align all participating MVP repo docs to the corrected terminal-boundary model
- clean stale milestone/current-target language and stale queue claims
- remove naming/documentation ambiguity introduced while previous sprints were
  executed in halves
- audit current code/docs against project conventions and record only explicit,
  reviewable residual debt

This sprint is allowed to change docs, queue state, naming, file ownership, and
non-behavioral code structure where required for architectural clarity.

It is not allowed to pretend the visible MVP is complete.

### Sprint 2: Scoped MVP Completion

Intent:

- finish scoped MVP honestly through runtime closure with a Linux-first release gate
- SDL host must show real text, correct input, resize, shell loop, and stable
  shutdown through the corrected terminal-boundary stack
- Android remains a peer proof host that validates abstraction pressure
- GL and GLES must move together on text-path policy and capability semantics

This sprint is allowed to change behavior, but only after Sprint 1 scope and
ownership clarity are closed.

## Required Discipline

1. Parent authority and child repo authorities must say the same thing.
2. Hosts must not retake ownership that belongs in the terminal boundary,
   session, render-core, or backend repos.
3. Backend repos must remain thin even when shared glyph/resource caches are
   introduced; those caches are backend-owned shared resources, not product-wide
   hidden singletons.
4. Android and SDL must be described as peer proof hosts over the same terminal
   boundary.
5. GL and GLES must move in lockstep for text-path policy changes unless bounded debt is recorded in the same iteration.
6. Session transport iterations must carry PTY-lane parity accounting (Linux POSIX PTY, Android bridge pressure, future ConPTY expectations) or bounded debt.
7. The Linux release gate is complete only when runtime behavior matches the docs.
