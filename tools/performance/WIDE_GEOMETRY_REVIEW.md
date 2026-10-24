# Ordinary wide-glyph geometry: qualified candidate, acceptance held

24 October 2026. Baseline c1271d5; installed LLVM Fast app1adc2beb.
Captain requested continued small Render/API-and-above optimization, not a VT
rewrite. This investigation reaches a real workload-priority decision. The
candidate is **not accepted or installed**; production source is restored to the
control. Its reviewable patch and exact qualified executable remain in the
workstream. No throughput claim below describes the installed app.

## Mechanism and scope

Canonical VT already distinguishes ordinary two-cell Unicode occupancy from
explicit multicell allocation. Render's general path nevertheless reconstructs
identity scaling, alignment and transformed clips for those ordinary wide cells.
The candidate recognizes exactly width2/height1/semantic-width cells, with no
continuation offsets, subscale, alignment or DEC line scaling. It keeps the full
two-cell destination, explicitly clips its allocation to the viewport, and uses
the existing unscaled glyph path. Explicit OSC66 allocation, all DEC transforms,
colour-glyph fitting, source sampling and cursor semantics retain their contracts.
ASCII placement retention remains narrow-only. No VT source, atlas budget,
retained cache, worker, pacer, ABI or public API changes.

The wide-only predicate is deliberately kept out of the large inlined projection
loop and is evaluated only after the existing narrow predicate fails. That version
(E) preserves the wide gain while substantially reducing the ordinary-path costs
of the earlier inlined versions. Exact compiler/layout attribution remains
unproven; these are measured artifact results, not a general noinline rule.

## Correctness and qualification

- Render Safe/Fast49tests, LLVM Fast app153tests, all341root steps with1124reported
  tests plus cached proofs, external consumer/protocol/source audits/Howl project
  audit/formatting/whitespace checks pass for candidate E.
-960complete frame pairs match the control across15ordinary and derived decorated
  tracks, including complete commands, cursor, uploads, removals and pixels.
- Eight native1920x1080 captures form four byte-identical RGBA pairs:
  UTF8/background, emoji, combining and capped CJK256. Each has substantial pixels
  outside its dominant background colour; corpus hashes differ. CJK and emoji
  captures were visually inspected. Capture replay explicitly omits producer
  cleanup after the last synchronized-output boundary.
- Private identity/negative-transform/viewport-edge proofs preserve exact bounds.
  An added decoration proof covers placement, explicit colour, invisible cells,
  removal and193rows without introducing a retained-row capacity restriction.
- Final candidate app SHA256:
  `f055045cdaa1bd328c92107bac391b1340dcb1872a67b81e8d2a8f2be8ffb539`.

## Selected E measurements

A four-pair72process isolated cohort follows the larger preliminary comparisons.
It feeds frozen public VT/Render inputs at384x83 cells and measures separate feed,
Render update and final-frame wall-time intervals. Median paired update changes:
CJK256-53.78%, emoji-47.17%, legacyUnicode/background-21.84%; ASCII+2.10%,
sparse-0.08%, rain+0.26%, combining-0.68%. Rain whole-path wall cost remains+3.11%.
These are not full-app CPU or displayed-frame measurements.

The ordinary app cohort uses private KWin1920x1080 scale1, native384x83/5x13,
fresh8second LLVM Fast processes, two reversed-order pairs per lane. Terminal
user+system CPU excludes producer/runner/compositor, after1second warmup and
strictly within producer lifetime. Emoji and combining run at20Hz; other lanes
run at240Hz.36trials emit55,040frames with zero missed producer slots and empty
app diagnostics. CJK128/256 are explicitly capped-alphabet frozen replays, not
unchanged4096-scalar TUI Zoo churn. New Unicode and legacy Cells doses stay distinct.

| Lane | Paired complete-app CPU changes |
| --- | --- |
| sparse | +0.42%, +0.26% |
| ascii | +0.57%, +3.27% |
| utf8-bg | -1.22%, -4.80% |
| legacy-unicode-bg | -6.55%, -2.55% |
| rain | -0.83%, -2.00% |
| cjk-128 | -18.53%, -18.51% |
| cjk-256 | -20.96%, -18.05% |
| emoji | -15.22%, -16.95% |
| combining | +0.29%, -0.89% |

Because ASCII was adverse in both primary pairs,16independent sparse/ASCII trials
followed, with30,720frames and zero missed slots. All pairs remain visible:

| Lane | Four independent paired changes | Median |
| --- | --- | --- |
| sparse | -0.61%, +2.23%, +0.36%, +0.77% | +0.57% |
| ascii | -0.19%, +3.47%, +4.16%, +0.00% | +1.73% |

The wide-glyph benefit survives the complete app. The ordinary-path cost is not
proven absent: isolated ASCII is adverse, primary app pairs are adverse, and the
independent cohort has two near-flat pairs and two+3–4% pairs. Calling the latter
noise or declaring a universal improvement would be unjustified. Sparse's
independent median is small but positive. Memory peaks remain variable; no general
RSS saving is established. Actual presentation cadence/deadlines, input latency,
physical240Hz operation and other machines remain unmeasured.

## Rejected approaches

A bounded decoration-row interval plus early scalar rejection preserved960frame
pairs but regressed isolated sparse update+28.25%, rain+15.16% (240processes).
B kept only early scalar rejection and still regressed sparse+22.98%, rain+13.85%
in a separate three-way360process comparison. Both are withdrawn.

C first recognized ordinary wide identity geometry: isolated CJK-54.30% and
emoji-43.40%, but sparse+7.46%/rain+5.16%. D tightened viewport clipping and removed
a long-lived flag. Its full36apptrial cohort still showed sparse+2.38/+4.41%,
ASCII+0.46/+4.95%, despite real wide savings. E isolates the wide-only recognition
and earns the best observed balance. These are distinct cohorts, not additive
percentages or one pooled score. No rejected artifact was installed.

## Decision and continuation

**Captain input is needed before accepting this tradeoff:** prioritize the
15–21% measured CJK/emoji CPU savings with a small ordinary ASCII cost, or require
ASCII/sparse non-regression and keep this optimization parked. The conservative
state is to leave c1271d5 installed until that preference is explicit. This is a
performance-priority decision, not a correctness failure or a request for a rewrite.

The default256entry atlas still rejects4096-glyph views. That admission policy,
independent glyph planes and complete durable sparse-paint reuse remain separate
work. This candidate does not resolve them or justify changing VT semantics.

Evidence and cleanly applicable proposal:

    ~/.local/state/workstreams/howl-current/night-20261024/decoration-projection/

`candidate-E.patch`, `E-final-pins.json`, `app-E/bin/howl-app`,
`summary-E.json`, `desktop-summary-E.json`, `desktop-summary-E-followup.json`,
`native-validation.json` and sealed Walker receipts retain the reviewable state.
Raw rejected A/B/C/D records are separate. All successful measured workloads have
zero cgroup limit events, OOM, CPU throttling and output loss. The one reconciliation
script syntax error was corrected before validating receipts; no trial was retried
or discarded to conceal an adverse result.

Restored control-source verification passes all341root steps with1122reported
tests plus cached proofs, consumer/protocol/audits/formatting/diff checks. Both
installed app paths still hash to1adc2beb. The proposal applies cleanly against
the restored tree; no candidate source or executable was silently promoted.
