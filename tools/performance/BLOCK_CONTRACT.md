# Column-block mutation contract · 22 October 2026

The logical contract works, but both write-path implementations are rejected.
All block metadata and public observation additions are withdrawn. No renderer,
host, painter, thread or installed binary changed.

A separate pre-existing scalar-ownership panic found by the structural oracle is
fixed: overlapping row edits now move cell values with their allocated scalar
tails. Six operation families have an exact cell-and-scalar regression proof.

## Contract tested

VT already has durable, non-consuming row identities and a separate background
source witness. The missing logical precision is columns, not missed-observation
support in general.

The prototype adds one persistent identity per 16 logical columns, plus one
whole-row reset identity. Ordinary ASCII batches and scalar writes stamp touched
blocks; conservative structural edits reset a row without walking its blocks.
Reads clear nothing, consumers retain independent baselines, and VT accepts no
observer acknowledgment. Storage follows physical rows and respects generic u16
geometry. History returns no block witness and requires complete fallback.

At 384×83 this is 1,992 block stamps (15,936 bytes) per screen bank, plus row
reset metadata. The witness describes possible logical mutation, not resolved
colors, shaping dependencies, ink extents or display pixels. Palette/default/
reverse, font/resource/image changes remain separate invalidation requirements.
No identifiers were carried into prepared frames or painted state in this experiment.

## Correctness

Six external contract proofs pass in explicitly selected Safe modules:

- Independent observers at different cadences, skipped cuts, repeated reads and
  cancelling writes; foreground changes preserve the existing background witness.
- Complete cell and scalar snapshots verify unchanged witnesses through 288
  structural/Unicode trace steps, both byte-fragmented and complete feeds.
  Cases include wide/combining/allocated clusters, sized text, erase, insertion,
  scrolling, margins, rectangular edits, DEC line geometry and bank transitions.
- Four unobserved sparse phases change all 83 rows but only **332 of 1,992 blocks**
  (16.67%). Untouched block identities survive the skipped observations exactly.
- Presentation changes deliberately leave logical cell identities unchanged.
- Every resize allocation failure preserves the old observation and releases
  completed allocations; geometry replacement invalidates prior block identities.
- 65,535 columns and a partial final block work without renderer geometry limits.

These prove logical coverage and precision only. They do not demonstrate a faster
projection, less SDL work, better presentation timing or lower application CPU.

## Write-path cost

Both comparison variants include the identical scalar-move correctness fix.
The difference is the mutation metadata. Each qualified cohort has eight
adjacent reversed-order pairs per lane: **80 fresh process runs per cohort**.
The VT is 83×384 with no history. Each process warms four fixtures and times about
32 MiB of deterministic input. Plain, colour and Unicode fill the complete grid;
sparse moves through rows, while scroll exercises 64-character output lines.

Compiler is the exact tracked Zig 0.17.0, Fast mode and self-hosted code generation/
linking. Every module has an explicit optimization option, and a compile-time
probe verifies the imported VT mode. Each cohort is pinned to one recorded CPU.
No compilation, profiling or screenshots overlap timing. Fixtures, commands,
hashes, all observations and sealed whole-workload receipts are retained.

The first qualified implementation adds **7.90% median Unicode wall time**, with
all eight pairs slower. The refined version retains the already computed physical
row, uses shifts for block indexing and directly stores a one-block stamp.
Its Unicode observations have no repeatable penalty, but plain writes regress.

| Lane | Refined median process CPU change | Slower pairs | Median wall-time change |
|---|---:|---:|---:|
| Plain | +12.56% | 8/8 | +12.40% |
| Colour | -3.50% | 1/8 | -3.57% |
| Unicode | -0.14% | 4/8 | -0.42% |
| Sparse | -0.70% | 3/8 | -0.56% |
| Scroll | +1.61% | 8/8 | +1.54% |

Positive values mean more time. All refined process-CPU pairs are retained below;
no outlier was discarded.

| Pair | Plain | Colour | Unicode | Sparse | Scroll |
|---|---:|---:|---:|---:|---:|
| 1 | +30.21% | -1.82% | -1.12% | -6.74% | +1.99% |
| 2 | +6.68% | -0.78% | +0.39% | -2.69% | +1.16% |
| 3 | +9.90% | -3.70% | +1.81% | -1.07% | +3.15% |
| 4 | +12.61% | +2.01% | +2.38% | +3.38% | +0.67% |
| 5 | +9.67% | -5.13% | +0.26% | -4.03% | +2.74% |
| 6 | +13.14% | -7.00% | -0.92% | +0.78% | +1.52% |
| 7 | +14.57% | -6.80% | -0.54% | -0.34% | +1.70% |
| 8 | +12.50% | -3.31% | -0.65% | +0.92% | +1.37% |

Both qualified cohorts have zero containment resource events, throttling and
output loss. The first cohort's plain wall-time observations include a -77%
paired outlier; it remains in the raw data and is not evidence of a speedup.
The refined cohort includes an initial +30.21% plain CPU pair; even its smallest
plain regression is +6.68%. Every plain pair is adverse.

An earlier partial cohort is rejected because per-module command options left
the VT dependency in Debug. Its percentages are excluded from these conclusions.
Failed proof/qualification attempts remain explicit in the evidence.

The dense write-path gate fails before presentation integration. VT-to-complete-
frame performance was therefore not measured; no application or display-cadence
claim follows from this experiment. No further painter variant was attempted.

## Scalar ownership fix

A baseline source copy reproduces InvalidRange during insertion beside an
allocated combining tail. The old helper transfers scalar ranges before moving
the corresponding cells. During an overlap, later transfers validate stale
cell lengths against already moved ranges, and vacated source cells can retain
stale scalar ownership information.

The helper now moves a cell and its scalar range together in the safe direction,
clearing vacated source cells before the next transfer. Cells without allocated
tails keep the bulk move path. The regression proof checks every resulting cell
and complete scalar sequence for character insertion/deletion, column insertion/
deletion and row shifts in both directions, including truncation and vacated cells.

## Decision and evidence

Keep the scalar correctness fix. Retain existing module ownership, row/background
identities, complete immutable reconstruction and the cursor path. The block
contract is a demonstrated logical capability, **not an accepted implementation**.
Its write cost needs a different explanation/mechanism before renderer integration;
the next experiment must not repeat this as an untested painter proposal.

Raw evidence on Home:

`/home/home/.local/state/workstreams/howl-current/day-20261022/performance/block-contract/`

This includes baseline and candidate sources, candidate-final.patch, six contract
proofs, the baseline panic and fixed proof, qualified commands/build-mode probe,
both 80-run cohorts, process CPU/wall times, provenance, independent validated.json,
and Walker/Cairn receipts. Final source has no block allocation, write hook or API.
The installed Safe binaries remain SHA-256
`814928a8c09503673158d5c1622a6755cb03b5a8d1dee16c9edaf6b1a9ded7e1`.

Final retained-source validation passes the affected 735-test VT suite and the
complete root test/check/audit/protocol graph in Safe mode: 335/335 steps and
1,633 reported tests pass. Formatting and
git diff --check pass. The sealed 4 GiB whole-build receipt records 1,166
memory.max reclaim events, no OOM and no CPU throttling. This correctness run
does not carry a zero-resource-event claim; neither performance cohort overlapped
it. No runtime artifact was installed.

Scalar ownership fix: 1938f4115b6c41c058f72c79c44d05c659e2abc0.
