# Render efficiency: cache pressure and glyph geometry

23 October 2026. Baseline e65c7a755fa7782899b4bd241573bc1b7efc503e,
installed LLVM ReleaseFast ad407a2e. This is a first Render-owned improvement,
not a resolution of the sparse reuse or high-refresh presentation targets.

Follow-up: [Atlas working sets and lookup policy](ATLAS_WORKING_SET.md)
records the accepted bounded index/compact-reference change, larger-corpus
measurements and the still-open atlas admission and publication memory design.

## Findings

Printable ASCII already has dense shape/atlas lookup and cached integer placement.
Other text follows the general shaping lookup, atlas lookup and fractional placement
path even when the glyph is warm. Both caches currently scan non-ASCII entries
linearly. In the matched UTF-8 corpus there are only 16 shapes, so large dictionary
scans alone cannot explain its cost.

The desktop recipe also conflated shape retention with frame admission. Its
256 entries / 512 scalars / 512 glyphs could reject a complete valid view. A
one-time cache reset restarted the whole projection; the same view could exceed
the budget again. The real random combining tape failed ShapeScalarFull at frame 1.
A CJK churn tape failed ShapeEntryFull at frame 8. The earlier selected-sample font
coverage/width qualification did not establish changing full-view Render capacity.

Shape records have a shorter lifetime than atlas pixels: each run is consumed
before the next lookup, while commands retain copied geometry. Reclaiming shape
records mid-projection is safe. Reclaiming atlas pixels would invalidate commands
already emitted into the same complete frame.

## Changes

A successful shaping miss now reclaims retained shapes at the point of pressure,
then admits the new run and continues the existing projection. A run larger than
glyph retention uses the already bounded caller scratch. Hits and physical cache
budgets are unchanged. Failed shaping does not clear retained records. The obsolete
whole-frame shape retry and exhaustion error mappings were removed.

General glyph placement now floors fractional pen/offset coordinates before adding
integral raster bearings and the integral baseline. This preserves negative-fraction
rounding, removes repeated conversion of integer geometry into 26.6 coordinates,
and retains checked pen arithmetic and final coordinate-range checks. No additional
cache, per-cell record, worker, allocator, or retained memory was introduced.

## Public-module diagnostic

The external probe constructs public VT and Render owners with the exact desktop
regular font recipe (one Iosevka Nerd 10px FontSet with Arabic/CJK/colour-emoji fallbacks), 384x83 cells of
5x13 pixels, and desktop cache budgets. It times VT feed, Render update and final
command projection separately. Each sample parses a real frozen TUI-Zoo frame.
It forces complete content construction, without row hints, a GPU or compositor.
It is not the app's coalescing, publication, painting or displayed-frame timing.

32 deterministic frames per tape, seed 20261020, slot/cell dose 4096 (sparse 64).
Each ordinary process repeats the tape 16 times: 32 warmup and 480 measured frames.
The expensive combining tape uses 32 warmup and 32 measured frames. Eight paired
fresh processes per comparison, alternating both variant and lane order, pinned
to CPU 2. All pairs, including outliers, are retained. 304 timed processes total.

Median paired Render-update changes (negative is faster):

| Lane | Shape-pressure change vs baseline | Geometry change vs pressure control |
| --- | ---: | ---: |
| Matched ASCII | -1.44% | -1.94% |
| Matched UTF-8 | +0.16% | -5.93% |
| Matched UTF-8 + background | +1.37% | -6.33% |
| Emoji | -0.93% | -2.35% |
| Combining | Baseline cannot render | -2.96% |
| Legacy ASCII | -0.58% | -1.13% |
| Legacy Unicode + background | +0.79% | -0.79% |
| Sparse prefix | -0.62% | +0.15% |
| Rain | +0.27% | -0.16% |

These are two sequential A/B cohorts, not additive end-to-end improvements.
Geometry's UTF-8, UTF-8/background and emoji lanes improved in all eight pairs.
Matched UTF-8 median update time moved from 1.242 to 1.165ms; background from
1.361 to 1.277ms. Frame command counts match in every pair. Smaller deltas are
not compelling evidence of improvements. Peak process RSS includes font mappings,
the input tape and preallocated output buffers; it is not Render-only memory.

The sparse tape is only a repeated 32-frame prefix, with roughly 1,000 emitted
commands per frame. It does not establish savings on a fully populated sparse
scene. The actual desktop comparison separately exercises the ordinary longer
producer. No sparse architecture improvement is claimed by this patch.

## Remaining design work

The CJK churn tape now advances past shaping but reaches CacheFull at the same
frame: one complete view needs more than the desktop's 256 retained atlas glyphs.
All 4096 churn scalars have font coverage, which is a separate fact. We cannot
rank this workload as equally painted work while one client rejects the view.

Atlas working-set admission needs explicit bounded growth/paging policy, failure
atomicity, resource generations, immutable frame lifetimes, memory attribution
and a high-entropy proof. Raising every pane's eager budget is not established as
the right design. Larger dictionaries also put pressure on the current linear
lookup policy. Measure cold fill, warm reuse and churn separately.

Warm UTF-8 remains substantially more expensive than ASCII. The next Render audit
should distinguish cache lookup, reusable glyph-relative geometry, source/dependency
expansion, command construction and final projection; preserve contextual shaping,
combining offsets, overhang, styles, DEC sizing and colour glyph behavior.

The larger sparse design remains durable logical column evidence -> Render-owned
shaping/ink dependency expansion -> bounded prepared-piece index -> reconciliation
against the host's last successfully painted state. Keep complete flat frames,
the current pacer and one backend lease. A new worker or cell-signature cache is
not justified by this diagnostic.

Full combining pressure also spends substantial time in canonical VT feed.
These results do not establish that VT is uniformly efficient or that renderer
work is the only Unicode cost.

## Validation and desktop qualification

Render's Safe/Fast proofs and audits pass. The entry/scalar/glyph-pressure
frame-equivalence regression fails the old implementation and passes the new one.
It compares complete commands, resource uploads and pixels against roomy retention.
Placement proofs cover negative fractions, bearings, final i32 limits and overflowing
pen arithmetic. Root check/test/consumer/protocol/audit passes all 341 steps with
825 reported tests plus cached proofs. The LLVM Fast desktop passes all 14 steps
and 153 tests. An initially stale Instance error mapper was corrected and the
complete graph rerun. Formatting and diff checks pass.

Two reversed-order pairs of ordinary 8s desktop trials per lane, private kwin-seat
1920x1080 scale1, 384x83 cells. CPU is terminal components' user+system time,
excluding producer/runner/coordinator/compositor, after 1s warmup and strictly
inside the producer lifetime. The legacy and new-producer cohorts are separate;
new Unicode uses nominal two-cell slots and is not the old one-cell dose.

| Desktop lane | Baseline CPU, % of one core | Candidate CPU | Relative changes in the two pairs |
| --- | ---: | ---: | --- |
| Legacy sparse | 14.50 | 14.52 | -1.60%, +1.94% |
| Legacy ASCII | 29.36 | 29.47 | +0.88%, -0.12% |
| Legacy Unicode + background | 53.06 | 51.78 | -4.03%, -0.78% |
| Rain | 7.05 | 6.82 | -5.19%, -1.37% |
| New UTF-8 | 44.66 | 43.52 | -2.44%, -2.64% |
| New UTF-8 + background | 52.36 | 51.45 | -0.85%, -2.61% |

CPU columns are medians of two trials, not uncertainty estimates. This small
desktop cohort supports a modest improvement on these UTF-8 workloads, not a
general 6% terminal speedup. Sparse and ASCII remain effectively flat. There
were 24 timed trials, 46,080 producer frames and zero skipped producer slots.
No displayed-frame deadline or physical Hyprland result is established.

No persistent cache budget or allocation size was added. Observed anonymous
peaks still vary: new UTF-8 92.66-93.47MiB baseline / 92.86-94.18MiB candidate;
UTF-8/background 97.28-97.66 / 97.68-97.77MiB. Legacy Unicode/background varied
97.27-101.11 / 99.17-100.04MiB. This does not resolve memory attribution or
establish a memory improvement.

Native 1920x1080 RGBA captures of the final UTF-8/background and emoji workload
frames match the baseline pixel for pixel. Nonblank checks and distinct-corpus
hashes prevent accepting an empty view. The dense combining view renders without
the old retention error banner. These are regression oracles for those fixed
views, not a font-coverage or universal appearance proof. The first capture set
was explicitly rejected: producer cleanup had cleared all views. Corrected
replay omits cleanup after the final synchronized-output end. Diagnostic tapes
used for the earlier CPU pairs retain that cleanup in the last cut; both variants
consume the identical bytes.

All bounded job receipts are sealed, without resource-limit events, CPU throttling
or captured-output loss. Discarded compilation/harness failures remain in the
evidence. The qualified LLVM Fast ef749f7bfad2755785db596a61bc65a684e90e719f575f7ce982d418e00510bb
is installed as independent regular files to both hosts/howl-app/zig-out/bin/howl-app
and ~/.local/bin/howl-app. The previous ad407a2e binary is retained for rollback.

Raw sources, frozen tapes, hashes, all timings, failures, native captures and sealed
whole-workload receipts:

    ~/.local/state/workstreams/howl-current/day-20261023/render-efficiency/
