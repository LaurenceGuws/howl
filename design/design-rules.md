# Howl Docs Style Guide

## Purpose

Howl docs are product artifacts.

They exist to lock boundaries, flows, proofs, and contracts for a low-level terminal system. They are
not marketing copy, and they are not long-form architecture theater.

TigerBeetle discipline applies here too: every line is a cost. Cover more facts with fewer words.

## Macro

Howl docs are split by job, not by mood.

- Principles explain why a rule exists.
- Guides explain how to do a class of work.
- Proofs record what closes runtime behavior.
- Reference records exact owner, contract, and lifecycle facts.

Current repo layout maps roughly like this:

- `AGENTS.md` is the global work contract.
- `WORKFLOW.md` is the engineering guide for day-to-day changes.
- `design/*.md` is shared design reference.
- `*/design.md` is repo-local design reference.
- host proof docs under `howl-hosts/*/docs/` are runtime proof records.

If a document does not fit cleanly, prefer adding a short focused file over bloating an unrelated one.

## Design Doc Contract

Each repo `design.md` should describe the repo as implemented today.

Required sections:

- `Purpose`
- `Public Surface`
- `Ownership Rules`
- `Lifecycle`
- `Main Flows`
- `API Contracts`
- `Non-Goals`
- `Change Rules`

If one of these sections is not stable yet, say so directly.

## What Design Docs Must Show

- the public owner callers depend on
- which file or owner owns mutable state
- which owner owns lifecycle
- which thread owns the runtime path
- important call ordering
- the invariant that keeps the design safe

## What Design Docs Must Not Do

- mirror every file mechanically
- document private helpers with no boundary value
- speculate about future architecture without marking it future
- hide a real ownership conflict under neutral language

## Diagram Rules

- Use `classDiagram` for owners and contracts.
- Use `sequenceDiagram` for runtime flow.
- Use `stateDiagram-v2` for lifecycle.
- Use `flowchart TD` only when sequence or state would be worse.
- Keep diagrams small enough to read in raw Markdown and on GitHub.

## Documentation Writing Rules

- Write for raw Markdown first.
- Keep URLs and file names stable.
- Hard wrap at 100 columns.
- Use GitHub Flavored Markdown.
- Use `-` for lists.
- Prefer short paragraphs.
- Use Standard American English.
- Use the Oxford comma.
- Use `_underscores_` for weak emphasis and `**double asterisks**` for strong emphasis.

## Tone Rules

- Be direct.
- Be specific.
- Name the owner.
- Name the invariant.
- Name the proof.

Avoid filler such as:

- broad claims with no owner
- vague migration language after the migration is complete
- “helper” explanations that restate code shape without meaning

## Change Rules

- New public APIs update the owning `design.md` in the same change.
- Owner moves update owner tables and flow docs in the same change.
- Runtime proof changes update proof docs in the same change.
- If a doc is misleading, fix it immediately instead of waiting for a larger rewrite.

## Proof Docs

Proof docs are narrow.

They should record:

- what was being proved
- which runtime owned the proof
- the exact command or run shape used
- the signal that counted as success
- any explicit remaining gap

Proof docs should not drift into broad architecture docs.
