# Whole-path timing and design decision · 22 October 2026

This diagnostic round changes the next experiment's priority: test precise reuse
through preparation and retained painting under the existing pacer. No product
architecture or runtime installation changed.

## Compiler scope correction

The desktop host explicitly builds with LLVM; separately maintained core artifacts
and the previous isolated VT experiment use self-hosted code generation.
The old +12.56% plain VT CPU result therefore cannot estimate the desktop host's
canonical cost. It remains a valid self-hosted core result.

A matching Fast LLVM comparison of the same withdrawn refined block implementation
has eight reversed adjacent pairs per workload, 80 fresh process runs, explicit
module modes and the existing compile-time imported-mode check. Both variants
include the accepted scalar-ownership fix. The deterministic workload is now about
128 MiB per sample rather than the earlier 32 MiB. This is a separate compiler-lane
comparison, not a controlled compiler-only delta against that earlier cohort.

| Workload | Median candidate CPU change | Slower pairs |
|---|---:|---:|
| Plain | +3.39% | 6/8 |
| Colour | +1.75% | 7/8 |
| Unicode | +1.29% | 5/8 |
| Sparse | +1.39% | 7/8 |
| Scroll | +1.89% | 6/8 |

These costs are paid without a downstream reuse consumer. They reject no complete
end-to-end design and establish no application CPU delta. Both implementations
remain withdrawn. The core/compiler distinction must stay visible in acceptance.

## Current-path trace

Source is accepted main 69dc45d. Independent control and diagnostic Fast LLVM
artifacts use the same source. Temporary timestamp hooks cover canonical service,
Render refresh, complete frame materialization, publication, GUI transfer locking,
resource application, target repaint, window-content submission and SDL present.

A bounded 262,144-record mmap trace stores monotonic timestamps and matching source/
render/content identities. The probe has no per-event logging or extra renderer
thread. Every hook and original file is retained in source-manifest.json and
probe-source.patch; all five modified source files are restored byte-exact.

Native RGBA corner qualification passes for both artifacts: 1920×1080 scale 1,
384×83 cells, four exact 5×13 corner cells. All runs use a private kwin-seat under
whole-workload containment, never the physical desktop or daily preferences.

Sixteen fresh 20s runs include two orders of sparse/plain/Unicode/rain diagnostics,
plus same-source control and trace-disabled comparisons for sparse/Unicode.
The producer requests 240Hz. Recorded present-return cadence is about 60Hz in
this private environment. Actual displayed timing and physical Hyprland 240Hz
responsiveness are not measured.

## Preparation survives the handoff

After excluding one second of warmup and the final 50ms of prepared cuts,
**9,097 coherent prepared cuts** are checked against the complete trace, including
the shutdown tail. None went unacquired; none of those acquired cuts lacked a
window-content submission. Prepared source/render/content keys are unique in the
measured intervals. No publication failure or unmatched span is hidden.

No credit was recorded while an unread publication was pending. GUI transfer-lock
P99 is at most 0.27 microseconds across the eight traces; maximum is 58.52
microseconds. The possible lock/credit interleaving identified during source review
does not appear as a material bottleneck in these runs. It remains an unmeasured
risk in other pacing/workload conditions, not an established explanation.

## Work persists after coalescing

The source repair threshold removes glyph-row repair hints in **all 9,120**
measured refresh decisions. Sparse prepares typically repair 79–80 of 83 rows;
rain repairs 82; plain and Unicode repair 83.

Yet those similar row counts describe very different retained scenes:

| Workload | Mean content commands, forward / reverse |
|---|---:|
| Sparse cells | 29,720 / 29,705 |
| Plain cells | 31,873 / 31,873 |
| Unicode cells | 39,890 / 39,890 |
| Rain 240 | 572 / 572 |

Sparse cells start with a populated scene and make small changes. Rain has little
retained ink despite touching nearly every row. Dirty-row count alone does not
describe the rebuild or paint cost. This explains why the strong rain result does
not establish sparse efficiency on a densely populated screen.

Mean instrumented wall time per operation follows. Service and preparation have
different execution counts; do not add a service mean once to every output frame.

| Workload | Canonical service µs | Render refresh ms | Frame materialization ms | Content target paint ms |
|---|---:|---:|---:|---:|
| Sparse | 15.115 / 13.734 | 0.610 / 0.619 | 0.281 / 0.270 | 1.409 / 1.404 |
| Plain | 194.596 / 200.945 | 0.633 / 0.648 | 0.301 / 0.282 | 1.546 / 1.550 |
| Unicode | 277.604 / 262.621 | 1.667 / 1.665 | 0.303 / 0.306 | 2.310 / 2.282 |
| Rain 240 | 133.558 / 129.151 | 0.266 / 0.254 | 0.007 / 0.007 | 0.100 / 0.093 |

For sparse content, small canonical updates lead to approximately 0.9ms of
preparation/materialization and 1.4ms of target repaint. This corroborates the
earlier separate profiles and geometry counters: repeated complete-scene work is
a stronger first target than discarded prepared publications.

## Tails, state age and pacing

| Workload | Service-through-publication P99 ms | Maximum ms | Target repaint P99 ms | Maximum ms |
|---|---:|---:|---:|---:|
| Sparse | 1.200 / 1.296 | 1.779 / 1.824 | 2.097 / 2.105 | 3.215 / 3.136 |
| Plain | 1.283 / 1.441 | 1.530 / 2.322 | 2.227 / 2.212 | 3.093 / 2.767 |
| Unicode | 3.016 / 2.868 | 3.970 / 6.615 | 3.336 / 3.690 | 5.154 / 6.083 |
| Rain 240 | 0.855 / 0.565 | 3.152 / 0.969 | 0.353 / 0.155 | 0.596 / 0.217 |

The service-through-publication section begins at canonical service entry and ends
at successful publication return; it excludes the final host notification. It is
wall time, including scheduling effects, not an uninterrupted CPU-residency measure.

Unicode's reverse trace has two such sections over 4.17ms. Its target repaint has
one / six operations over 4.17ms in forward / reverse. These are observed spans in
a perturbed 60Hz environment, not displayed deadline misses or a 240Hz failure proof.
Preparation and painting can both matter to a future high-refresh schedule, even
when no prepared cuts are discarded.

Cut-age measurements begin at the first service completion observing the published
semantic state and end at the first window-content submission using that cut.
They exclude earlier producer/PTY waiting and later actual display:

| Workload | Mean cut-to-window submit ms | P99 ms |
|---|---:|---:|
| Sparse | 3.836 / 4.650 | 6.699 / 6.027 |
| Plain | 4.247 / 4.949 | 6.234 / 6.368 |
| Unicode | 5.331 / 5.892 | 7.483 / 8.043 |
| Rain 240 | 2.441 / 1.436 | 4.367 / 4.427 |

## Observer controls and limits

The same diagnostic artifact with tracing disabled still contains hook calls and
different generated code. It is not interchangeable with the unmodified control.

| Workload/order | Control CPU | Hooks, trace off | Hooks, trace on | On/control relative change |
|---|---:|---:|---:|---:|
| sparse/0 | 15.331% | 15.414% | 15.454% | +0.80% |
| sparse/1 | 15.067% | 15.306% | 15.243% | +1.17% |
| unicode/0 | 50.447% | 52.191% | 54.650% | +8.33% |
| unicode/1 | 50.897% | 56.861% | 53.402% | +4.92% |

Sparse trace-on overhead is +0.80/+1.17% relative to control. Unicode changes by
+8.33/+4.92%; the disabled-hook build changes by +3.46/+11.72%. Hook/code-layout
effects and run variability are material. Do not subtract one constant overhead
or call these uninstrumented latency measurements. Lower-perturbation replication
is required before a time-based scheduling acceptance decision.

Producer skips are retained: Unicode trace-disabled runs miss 2 and 7 slots; the
reverse trace-enabled Unicode run misses 3. All other runs emit 4,800 frames with
zero skips. These differences limit strict observer-overhead comparisons. No miss
is silently replaced by another run.

Both graphical qualification/measurement jobs and the LLVM cost job are sealed
with zero containment resource events, throttling or output loss. Trace buffers
have zero dropped/partial records. Ordinary application CPU/memory acceptance is
not claimed from instrumented runs. Memory ownership remains a separate open
measurement; mmap trace storage is not a product memory measurement.

## Design decision for the next complete experiment

1. Keep the current pacer as the control. It uses every prepared cut in these 60 Hz
   runs; a new scheduler has no demonstrated discarded-work saving here.
2. Test finer source evidence, Render-owned shaping/ink dependency expansion and
   last-painted reconciliation as one complete slice. The already proved block
   witness can be an experimental input; it is not promoted to accepted VT.
3. Preserve complete immutable frames and one backend lease. Initially retain the
   existing flat command reconstruction as the recovery/reference path. A bounded
   optional prepared-piece index can test whether target-paint savings repay source
   and preparation cost before introducing shared immutable command storage.
4. Compare accepted baseline, evidence-only control and complete reuse consumer
   with matching app LLVM code generation. Keep the self-hosted core cost visible
   and avoid charging VT-only users for an unused presentation capability.
5. Reuse identities must survive skipped prepared observations and refer to the
   painted target. Render owns cluster/overhang/resource invalidation. Partial
   painting must include old and new ink and redraw unchanged intersecting ink
   without double blending. Whole-frame recovery stays exact.
6. Measure the full application on sparse, dense plain/colour/Unicode and rain;
   include idle/cursor paths, repaint/geometry counts, memory and both successful/
   failed reconstruction. Dense fallback must remain cheap. Do not repeat a
   per-cell command-signature cache or per-rectangle whole-command-list scan.
7. Revisit deadline-aware preparation/overlap after these costs are measured on a
   real high-refresh observation path. Resumable work or another worker requires
   a stable source lifetime and explicit snapshot/copy bounds; no new thread follows
   merely from this diagnostic round.

## Reproducibility and retained state

Raw evidence on Home:

`/home/home/.local/state/workstreams/howl-current/day-20261022/performance/system-timing/`

The directory retains exact compiler commands/modes, 80 LLVM observations, independent
control/probe artifacts and hashes, hook sources/manifest/patch, native qualification,
16 process trials, raw bounded traces, producer receipts, every analysis JSON,
source restoration checks, and Walker/Cairn receipts.

All diagnostic source edits are restored. The daily Safe launch artifacts remain
SHA-256 `814928a8c09503673158d5c1622a6755cb03b5a8d1dee16c9edaf6b1a9ded7e1`.

Restored-source test/check/audit/protocol gates pass all 335 graph steps (799
reported tests plus cached proofs). The 6 GiB gate receipt is sealed with zero
resource events or throttling; measured peak charge is 237,355,008 bytes.
All source baseline hashes and both installed Safe hashes are rechecked.

The withdrawn refined block witness also passes all six contract proofs under
ReleaseSafe LLVM, including independent observers, skipped/cancelling writes,
Unicode/structural edits, transactional resize failures and generic column widths.
This qualifies the experimental witness; it does not accept its runtime cost.
