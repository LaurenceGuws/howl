# Cold admission and service turns · 24 October 2026

A private native-raster budget makes cold Unicode much more interruptible on the
existing terminal worker. It trades later complete projection and repeated prefix
work for shorter uninterrupted service turns. Immediate retry after canonical
service is materially better than treating earned admission progress as font-store
contention. This earns a targeted implementation direction, not promotion of the
prototype or a claim that the 4.17 ms target is solved.

The installed LLVM Fast artifact remains 0983f38b from ed244fe. Only this report
and its index are accepted from this round. No new public API, runtime budget,
font recipe, backend, worker, allocator or pacer is installed.

## Experiment and scope

The private source snapshot is ed244fe. Every variant has the same allocation
ledgers, nested stage timers and bounded attempt records. Unlimited admission is
the experimental control; it is not an uninstrumented race of the installed binary.
All builds use the pinned Zig0.17.0 and LLVM ReleaseFast.

A budget charges only a native font-raster miss. Cached glyphs, generated glyphs,
shaping, traversal, commands, resource binding and publication are not time-bounded
by that count. The counter is scoped to one synchronous update. No borrowed VT
state survives returning. Warm atlas and shape knowledge remain owned; partial
commands cannot become a frame. Construction/font replacement stay synchronous.

Runtime returns credit on deferral, retains the pending publication, services
canonical/input work again, then retries the newest observation. The first cohort
uses the existing1 ms busy deadline; the second uses poll0 after earned progress.
Actual text-store contention retains its1 ms wait. One atlas-reset allowance is
retained across deferrals, so the stationary over-capacity case eventually fails.
This prototype's reset allowance still needs target identity, as described below.

The private KWin track is1920×1080 scale1, native fullscreen384×83 cells at5×13
pixels. This is not a physical Hyprland240 Hz qualification. Three calibration
captures prove the complete corner lattice. The10 paced streams target240 Hz
for8 seconds, using the identical frozen32-frame CJK tape in both directions.
The stationary payload fills the screen with4,096 distinct CJK scalars and then
stops writing. Each trial uses a fresh application and independent configuration.

There are12 first-cohort trials and10 immediate-retry trials, plus three separate
calibrations. Experiment builds do not overlap collection. All completed job
receipts are sealed, without memory/task-limit events or CPU throttling.

The timing endpoint called complete below is the successful renderer update,
before immutable-frame materialization and SDL presentation. It is not a displayed
frame timestamp or input latency. Whole-turn maxima include canonical service and
preparation. All times are instrumented wall spans, including scheduling effects;
cumulative spans are not CPU measurements.

## Initial budget and retry coupling

Forward/reverse observations, milliseconds. First complete projection is measured
from immediately before the producer starts writing.

| Case / miss cap | Longest refresh to first complete | Cumulative refresh to first complete | First complete projection | Whole service/prepare maximum |
| --- | ---: | ---: | ---: | ---: |
| stationary / unlimited |44.29 /46.14|44.29 /46.14|46.13 /48.07|45.49 /47.40|
| stationary /128 |3.93 /4.06|53.55 /54.66|88.16 /89.25|4.78 /4.95|
| stationary /512 |7.95 /7.91|48.05 /46.06|57.10 /55.20|8.78 /8.79|
| changing / unlimited |41.14 /39.71|41.14 /39.71|42.31 /40.76|41.81 /40.30|
| changing /128 |3.66 /4.04|63.54 /54.47|106.39 /85.58|4.74 /5.12|
| changing /512 |8.02 /7.81|49.21 /48.50|55.10 /53.81|9.02 /8.75|

A stationary128-cap refresh needs32 attempts, with31 deferrals. A512 cap needs
eight attempts. The1 ms retry deadline adds avoidable delay on the stationary
screen, while smaller admission batches also repeat projection of cached prefixes.
These are separate effects. The512 cap leaves substantially longer uninterrupted
turns; it is not a substitute for the128-cap responsiveness result.

Paced producer skips, forward/reverse: unlimited9/8, cap1280/0, cap5124/4.
No observation is removed from the cohort.

## Immediate retry after earned progress

The second cohort separates productive deferral from contention. After admission
work returns, poll0 checks readiness and the normal loop applies queued commands
and services canonical PTY/VT before attempting more projection. It does not spin
inside Render or keep a source borrow alive.

| Case / miss cap | Longest refresh to first complete | Cumulative refresh to first complete | First complete projection | Whole service/prepare maximum |
| --- | ---: | ---: | ---: | ---: |
| stationary / unlimited |45.12 /48.80|45.12 /48.80|46.98 /50.76|47.86 /50.16|
| stationary /128 |3.99 /3.90|53.45 /53.14|55.59 /55.14|4.96 /4.79|
| changing / unlimited |40.23 /41.11|40.23 /41.11|41.25 /42.26|40.83 /41.87|
| changing /128 |3.60 /3.50|56.07 /53.15|68.99 /63.04|4.73 /4.60|

The budget keeps the long cold refresh out of any single service turn, without
requiring another worker. The extra cumulative projection span remains. Removing
the deliberate sleeps does not remove that restart cost.

Every recorded runtime attempt in this cohort has a distinct, increasing canonical
service counter. The trace proves return through service between attempts; it does
not measure actual key-to-display latency or establish input deadlines.

Paced producer skips are unlimited8/28 and cap1280/0. The adverse28-slot control
stays recorded. Across both cohorts,10 streams emit19,139 of19,200 requested slots,
with61 skips. All four cap128 streams deliver7,680 frames with zero skips. These
are producer-slot observations, not presented-frame counts.

## Exhaustion, stopped output and pixels

A separate stationary9,000-glyph payload exceeds the host's8,192-entry atlas bound.
After three seconds it sends a small replacement screen. There is one trial per
variant; this is a hostile progress proof, not a distribution estimate.

| Immediate-retry variant | Time to capacity failure | Attempts to failure | Longest refresh before failure | Whole service/prepare maximum | Replacement projection after write |
| --- | ---: | ---: | ---: | ---: | ---: |
| unlimited |180.97 ms|1|178.54 ms|179.11 ms|1.51 ms|
| cap128 |248.08 ms|129|11.34 ms|11.34 ms|1.68 ms|

Cap128 returns pending128 times, then reports CacheFull after its single reset
allowance. It does not recycle forever after the child stops writing. The later
canonical replacement recovers, and both final recovery images match exactly.
The trace records130 distinct service turns, including recovery.

This case also exposes the count budget's limit: an update can spend time walking
an already-cached prefix and shaping without admitting another native raster.
The11.34 ms span disproves any universal4.17 ms guarantee from the native-miss
counter. Shape-miss counts/totals also rise with restart work:16,400/15.21 ms in the
unlimited failure versus32,783/28.93 ms in cap128. These are diagnostic counters,
not additive frame CPU costs or attribution of every microsecond in that maximum.

All10 stationary4,096-glyph final captures have identical decoded RGBA. Both
capacity-recovery captures match. The stopped-output cases complete or fail without
another byte being needed to drive retries. In the immediate-retry cohort, every deferred update is also checked
against the frame-pixel query: partial preparation must remain unavailable.
The six tracked allocation domains balance to zero in every trial; counters and
histograms reconcile, with no attempt/snapshot overflow. No RSS saving is claimed.

## What the design must now align

| Factor | Evidence | Consequence |
| --- | --- | --- |
| Native raster admission |Splitting cold misses sharply reduces the long turn.|Keep native ownership in Text and terminal-local atlas ownership in Render; let the host choose admission policy.|
| Retry scheduling |Busy deadlines add about31 ms to the stationary128 case.|Earned progress should return through canonical service promptly; contention needs a different retry decision.|
| Prefix work |Cumulative refresh spans increase; capacity pressure produces an11 ms turn.|A miss count alone cannot bound traversal/shaping or eliminate repeated preparation.|
| Complete publication |Partial preparation stays unavailable; final pixels match.|Retain complete immutable frames and the existing single backend lease.|
| Target replacement |Only ordinary coalescing and replacement after failure are exercised.|Define progress/recycle identity before exposing a public resumable contract.|
| Construction |A candidate is warmed before transaction commit.|Do not repeatedly destroy a deferred font/reconfiguration candidate.|

The smallest next implementation should distinguish ready, productive pending and
fatal failure, with explicit per-call admission rather than a new pacing owner.
The ordinary unlimited lane must remain available. Pending is not an exact-content
presentation failure and must not engage the host's blocked-content gate.

Progress must be scoped to the current terminal occurrence and canonical content
cut, viewport and presentation. The current prototype carries one reset allowance
across all deferred views. A different fitting view could inherit an earlier
view's exhaustion history. That is a reason not to promote this private code.
A new target must retire obsolete failure/progress provenance without discarding
useful atlas knowledge; a quiescent fitting target must complete, and a quiescent
over-capacity target must fail within bounded work. Perpetual output churn is not
permission for an unbounded queue, borrow, reset loop or busy service turn.

Required hostile proofs include target replacement immediately before/after reset,
fit-to-overfull-to-fit changes, skipped observations, history/alternate-screen and
geometry changes, hide/reveal/cancel/deinit, shared-store contention, command-growth
failure and a held immutable backend lease. Complete image equivalence must cover
styles, fitting, generated glyphs, combining sequences and colour glyphs.

Construction/font replacement need their own explicit choice: synchronous work
with its measured limitation, or a retained owned candidate transaction. This
round proves neither asynchronous construction nor bounded native single-glyph cost.

Only after that contract is qualified should ordinary uninstrumented ASCII,
sparse, Unicode/background and emoji guards decide whether the new lane earns its
steady-state cost. They were not collected for this deliberately unpromoted probe.
Warm sparse painted-state reuse and SDL's graphics-startup footprint remain
separate questions; this experiment does not resolve them.

Accepted documentation verification: root check/test/consumer/protocol/audit
passes341/341 steps,800 reported tests plus cached suites; diff checks pass.
These gates validate the unchanged accepted source and report checkpoint, not the
private prototype as a promoted implementation.

Raw workstream:
~/.local/state/workstreams/howl-current/day-20261024/cold-admission/
Contains BASE.json, prototype source patches/pins, both complete cohort manifests,
raw attempt/stage/ledger records, native captures, summary.json, fold.py and sealed
Walker receipts. Private archives and diagnostic binaries are retired after this
round; source patches remain only for the open progress-contract investigation.
