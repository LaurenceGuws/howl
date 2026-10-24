# Bounded glyph admission — 24 October 2026

The desktop can retain the real 4,096-glyph CJK working set without eagerly
allocating a larger atlas for every pane. This is an admission improvement;
font coverage, cold responsiveness and the sparse painted-state contract remain
separate work.

## Ownership and bounds

`AtlasConfig.growth` and `ShapeCacheConfig.growth` are optional Zig policies.
Omitting them preserves fixed bounds. Atlas width stays fixed; alpha and RGBA
planes have separate shelves, initial heights and ceilings. Height growth copies
old pixels into the same coordinates. Entry and shape arrays grow geometrically
under explicit limits. Shape pressure beyond its ceiling still recycles.

The desktop policy is:

| Storage | Initial | Ceiling |
| --- | --- | --- |
| Per-renderer alpha | 512×512, 256 KiB | 512×4096, 2 MiB |
| Per-renderer RGBA | Lazy 512×128, 256 KiB on first use | 512×1024, 2 MiB |
| Per-renderer atlas records | 256 | 8,192 |
| Shared shapes per recipe/physical size | 256 records / 512 scalars / 512 glyphs | 8,192 / 32,768 / 16,384 |

SDL's reported maximum texture dimension clamps the heights. Font discovery
stays in the host, native shape/raster work stays in Text, and glyph storage and
presentation stay in Render. The C ABI and fixed native-owner policy do not
change. No paging, new resource identities, worker or pacing mechanism is added.

Render binds resource identities and colour height in one pass after projection.
Alpha command heights are repaired only when a later admission grows that plane,
including already-emitted/reused commands. Stable projections avoid those stores. Height changes force a full presentation baseline; retained GPU
geometry cannot keep UV normalization from an older texture extent. Complete
frames and exact identity/generation/format/extent residency remain authoritative.
Held publications own their copied bytes. Reset retains bounded high-water
storage; allocation failure preserves prior cache keys and pixels, without
promising whole-update rollback.

## Correctness

The fixed accepted desktop rejects the full corpus with `CacheFull` at frame 0.
The candidate admits 4,096 shape and atlas records. A control built from the
exact accepted d94f7a2 source uses an explicit larger eager ceiling for that one
comparison; it is not the old default desktop.

The public oracle matches 512 frame pairs across full CJK, capped CJK256,
ASCII, sparse, rain, Unicode/background, emoji and combining. It validates exact
resource residency/extents and hashes every referenced raster texel plus command
geometry, colour and cursor. Only atlas placement and unused plane extent are
canonicalized; resource identities and generations remain checked. Layout and
padding bytes are not treated as visible pixels.

Maintained proofs cover independent packing, index/entry/plane growth, all
allocation failure prefixes, exact capacity/pixel ceilings, prior texel/key
preservation, reset high water, shape recycling, reused glyph extent repair,
colour-only growth with alpha still resident, stale extent residency, immutable
held frames and incremental-to-full fallback. Fixture colour uses the supported
U+1F600 glyph with four explicit style keys; unsupported emoji never substitute
for a colour-growth proof.

Final E source gates: Render ReleaseSafe check/test/audit 35 steps, 55 reported
passing tests plus cached suites; ReleaseFast test 32 steps (cached); LLVM Fast
desktop check/test/audit/install 14 steps, 154 tests; root
check/test/consumer/protocol/audit 341 steps, 1,131 reported tests plus cached
suites. The earlier D gate reported 64 Render / 1,140 root tests; the nine-test
difference is cache reporting, not removed coverage. Formatting and diff checks pass.

## Isolated performance guard

160 fresh processes: eight reversed-order pairs per ten lanes, one CPU (2),
LLVM ReleaseFast, exact accepted-source control, no builds during timing.
The first 32 tape frames warm each process. Other than combining and full CJK
(32 measured frames), each process measures 480 feed/update/frame iterations.
The 512-pair semantic oracle runs separately and is not included in these times.
Whole time below means feed + Render update + frame copy, with no GPU/backend.

| Lane | Render update, paired median | Whole, paired median |
| --- | ---: | ---: |
| ascii | -0.06% | +0.04% |
| utf8 | +0.34% | +0.25% |
| utf8-bg | +0.21% | -0.39% |
| legacy-unicode-bg | -2.51% | -1.69% |
| sparse | -0.15% | -0.19% |
| rain | -0.20% | -0.39% |
| emoji | -1.51% | +0.50% |
| combining | -4.77% | -1.69% |
| cjk-256 | -0.06% | -0.21% |
| churn | -0.97% | -0.63% |

The full CJK comparison uses the larger eager control noted above. Its first
frame admits 3,635 glyphs; the set reaches 4,096 by frame 4. Median first-frame
update is 31.59 ms control / 32.37 ms candidate. Warm update is about 1 ms;
this establishes no 4.17 ms cold-frame budget or displayed 240 Hz claim.
The candidate retains 1 MiB alpha pixels (512×2048) for this corpus versus the
eager control's 2 MiB. Public-process peak RSS is 40.6–41.8 MiB candidate /
42.0–43.2 MiB control; these small process-specific differences are not a desktop
RAM claim.

Initial candidates are rejected, not pooled into the final results. A/B placed
independent colour extent handling inside the large glyph projection and showed
about +28% sparse / +14–15% rain update cost. Private 1 ms SIGPROF sampling puts
added time in existing cell scans, not allocation. Machine-code/layout
sensitivity is plausible but not a proven microarchitectural cause. Moving
colour finalization to binding (C) leaves about +5% on those lanes. D uses one alpha/colour binding pass and leaves glyph projection unchanged,
but its full-app CJK256 guard still regresses. Final E retains that binding pass
and repairs alpha command heights only on actual growth. Stable alpha commands
already carry the current extent; colour extents are finalized during binding.
No alignment or padding tuning is retained. All adverse pairs remain in the raw receipts.

## Development D app evidence

The initial 34 private KWin trials use a native 1920×1080 scale-1 fullscreen
384×83 grid (5×13 cells), eight seconds per process, one-second timing warmup.
Terminal-component user+system CPU includes every app thread and excludes the
runner, producer, compositor and coordinator. Twenty-four ordinary trials use
240 Hz; eight emoji/combining trials use 20 Hz. Two candidate-only warmed full-CJK
trials use 240 Hz after one tape cycle preloads outside timing. Every completed
producer receipt reconciles: 51,200 frames, zero skipped slots, equal paired
payload/codepoint/nominal-cell counts or exact frozen replay hashes. No trial is
discarded. These private KWin CPU results are not physical Hyprland/displayed
frame/deadline measurements.

| Case | Initial app pair 1 | Initial app pair 2 |
| --- | ---: | ---: |
| sparse | -1.92% | +4.11% |
| ascii | +3.39% | -0.29% |
| utf8-bg | -0.10% | -2.27% |
| legacy-unicode-bg | -0.01% | +0.82% |
| rain | +3.56% | -0.18% |
| cjk-256 | +7.75% | -0.66% |
| emoji | -1.14% | -1.40% |
| combining | +0.45% | +0.65% |

The full-CJK candidate-only runs use 34.43% and 32.77%
of one core, with anonymous peaks 100.21 and
98.94 MiB. The old default cannot supply a matched
full-view CPU comparison. This is a warmed admission proof, not cold 240 Hz
responsiveness.

Four ordinary native capture pairs (Unicode/background, emoji, combining,
CJK256) are byte-exact after RGBA decoding; all are nonblank and distinct. The
ninth capture shows full CJK4096. Its pixels also match the earlier A correctness
build exactly. Both binaries pass native four-corner calibration. Every app
diagnostic stream is empty.

The additional D cohort keeps four more reversed-order pairs per ASCII, CJK256
and rain (24 trials, 46,080 frames, zero skips). Paired medians: ASCII +0.65%
(including a +9.08% adverse outlier), rain -1.78%, CJK256 +3.00% with all four
pairs adverse (+2.53/+3.48/+4.66/+2.03%). This blocks D promotion.

## Final E direct app comparison

Four fresh-process CJK256 triads compare old default, D and E in one cohort:
12 trials, 23,040 frames, zero skips, same frozen tape and native grid. D versus
old has a +4.83% paired median. E versus old is +0.002%, with individual pairs
+3.46/-2.71/-3.20/+2.71%. E versus D is lower in all four triads:
-2.10/-1.88/-7.63/-2.04%, median -2.07%. Pairwise medians are not additive.
This supports making alpha extent repair conditional on growth. It does not
prove a specific hardware/cache mechanism. E needs no extra steady alpha stores.

Final E adds 18 fresh-process trials: two reversed-order pairs for sparse,
ASCII, Unicode/background and rain, plus two candidate-only warmed full-CJK
runs. All target 240 Hz and the same native 384×83 grid. Combined with the four
CJK triads above, this is 30 app runs and 57,600 producer frames with zero skipped
slots. Producer doses/hashes reconcile; no trial is discarded.

| Final E ordinary app case | Pair 1 | Pair 2 |
| --- | ---: | ---: |
| sparse | +1.01% | -1.68% |
| ascii | +0.59% | -2.09% |
| utf8-bg | -0.13% | +0.10% |
| rain | +0.22% | -0.49% |

Final E full-CJK warmed CPU is 32.96% / 31.45% of one core;
anonymous peaks are 98.38 / 99.43 MiB.
It remains candidate-only because old default admission fails. This does not
establish low total desktop memory or physical 240 Hz presentation.

Nine native captures repeat on E: four ordinary old/new pairs are exact, and the
full-CJK pixels match D/A. Four-corner calibrations pass; every diagnostic stream
is empty. Source, binary and accepted font pins match after qualification.
Final source/test, isolated timing, direct triad and native jobs are sealed with
zero memory/task-limit events or CPU throttling. No builds overlap timing.

The promoted app uses LLVM ReleaseFast on Zig 0.17.0, SHA-256
`69eed7fabe160b7465ba305a87e1fe8407a641e62141e9dc6b6610964a8052e1`.
The prior d94f7a2/f055 artifact is retained as rollback. Installation targets are
independent regular files at `hosts/howl-app/zig-out/bin/howl-app` and
`~/.local/bin/howl-app`; running sessions are not restarted. Ordinary GitHub
SSH push succeeded for both the accepted wide-glyph change and this atlas
promotion. The earlier authentication blocker is resolved; no credentials were
changed by this work.



## Memory and limits

The 4 MiB combined raw-plane ceiling excludes atlas records/index, shared shape
storage, native fonts, complete commands, three retained publication slots, SDL
alpha-to-RGBA conversion scratch, GPU textures and external images. Growth may
briefly retain old and replacement allocations. Lazy colour reduces its initial
raw allocation from the old 1 MiB to 256 KiB. No universal RSS reduction is claimed.
The caps do not promise every corpus at every font size; fixed width and explicit
bounds remain real admission limits.

Source and private evidence: `night-20261024/atlas-admission` beneath
`~/.local/state/workstreams/howl-current/`: `qualified-E-pins.json`,
`qualification-E-*`, `preflight-E.json`, `timing-pairs-E-full.json`,
`timing-summary-E-full.json`, `cold-storage-E.json`, `desktop-E`, `desktop-E-triad`, `native-E`, the separate development D
cohorts and rejected A/B/C trials. No historical race score is replaced by this cohort.
