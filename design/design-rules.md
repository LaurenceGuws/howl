# Documentation Rules

Owner: workspace root.

Howl docs lock boundaries, flows, proofs, and contracts. Each line is a cost.

## Doc Set

- `AGENTS.md`: principles and workspace boundaries.
- `WORKFLOW.md`: change loop and proof cadence.
- `design/reference-index.md`: explicit local reference map.
- `design/style-law.md`: strict code style law.
- other `design/*.md`: shared reference.
- `*/design.md`: repo boundary reference.
- repo-local support docs: narrow proof, protocol, or operational reference only.

## Doc Shapes

- Principles explain why.
- Guides explain how.
- Proofs record what closes behavior.
- Reference records exact owner, contract, and lifecycle facts.

If a document does not fit cleanly, fold it into a stronger entrypoint or delete it.

Prefer one source per rule.

## Design Doc Contract

Each repo `design.md` describes the repo as implemented today.

Required sections:

- `Purpose`
- `Public Surface`
- `Ownership Rules`
- `Lifecycle`
- `Main Flows`
- `API Contracts`
- `Non-Goals`
- `Change Rules`

Add a short doc-set pointer when the repo keeps supporting docs.

## What Design Docs Must Show

- the public owner callers depend on
- the owner of mutable state
- the owner of lifecycle
- the owner thread for the runtime path
- important call ordering
- the invariant that keeps the design safe

## What Design Docs Must Not Do

- mirror every file mechanically
- document private helpers with no boundary value
- speculate about future architecture
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
- Spend words only on durable facts.

## Change Rules

- New public APIs update the owning `design.md` in the same change.
- Owner moves update the owning boundary and flow docs in the same change.
- Runtime proof changes update proof docs in the same change.
- If a doc is misleading, fix it immediately instead of waiting for a larger rewrite.

## Proof Docs

Proof docs record:

- what was being proved
- which runtime owned the proof
- the exact command or run shape used
- the signal that counted as success
- any explicit remaining gap

Proof docs should not drift into architecture or planning docs.
