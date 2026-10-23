# Atlas working sets and lookup policy

23 October 2026. Control: 79370ff1a6e26b405c139d3511616f6bca422bcf,
LLVM ReleaseFast ef749f7b. This round separates working-set admission, warm
lookup, cold native text cost and complete-app consequences. The compact indexed follow-up E is accepted, with the desktop cache limits
unchanged. Larger-budget results below do not establish that the default desktop
renders the 4096-glyph view.

## What limits the current path

The default desktop has 256 shape entries, 512 retained scalars/glyphs and a
512x512 atlas with 256 glyph entries. Shape retention can recycle during a frame;
atlas pixels cannot, because already emitted commands refer to them.

A frozen dose 4096 CJK churn tape fails CacheFull on its first full view with the
desktop limits. Font coverage is sufficient for all 4096 scalars. Admission,
coverage and speed are separate questions.

Explicitly increasing atlas limits to 1024x1024/8192 entries admits the tape, but
leaving shape retention small repeatedly reshapes. Increasing both dictionaries
makes warm projection slower with the original linear scans: about 16.5ms versus
21.3ms per update in the paired cohort. Capacity must be designed with lookup
policy, not raised as a stand-alone throughput fix.

## Indexed prototype C

A private lazy open-addressed index stores only numeric entry references. Exact
keys remain in the existing shape/atlas records and collisions require complete
equality. Up to 64 retained records keep the original short scan; printable ASCII
retains its dense path. Index storage begins on the 65th record and stays at least
half empty, with checked growth, bounded probes, reset and ownership cleanup.
No new terminal state, host setting, worker or atlas capacity is introduced.

The last prototype also separates shaping/raster admission from warm lookup.
That reduces generated warm routines but does not eliminate common-case costs.

Each table entry is the median of eight paired fresh processes, alternating lane
and variant order, pinned to CPU 2. Same public VT and Render modules, regular
Iosevka Nerd 10px with Arabic/CJK/colour-emoji fallbacks, 384x83 cells of 5x13 pixels.
Every sample feeds actual bytes and constructs a complete frame, without repair
hints, GPU, compositor or a retained host paint. Ordinary processes use 32 warmup
and 480 measured frames; combining/churn use 32 warmup and 32 measured frames.

| Lane and bounds | Control update | Indexed update | Paired change |
| --- | ---: | ---: | ---: |
| ASCII, desktop | 0.433ms | 0.443ms | +2.40% |
| UTF-8, desktop | 1.166ms | 1.176ms | +0.54% |
| UTF-8/background, desktop | 1.276ms | 1.296ms | +1.73% |
| Legacy Unicode/background, desktop | 1.357ms | 1.334ms | -1.82% |
| Sparse prefix, desktop | 0.099ms | 0.108ms | +9.63% |
| Rain, desktop | 0.161ms | 0.171ms | +6.02% |
| Emoji, desktop | 1.863ms | 1.867ms | +0.03% |
| Combining, desktop | 2.533ms | 2.553ms | +0.41% |
| CJK32, desktop | 1.686ms | 1.600ms | -5.06% |
| CJK64, desktop | 1.850ms | 1.760ms | -5.23% |
| CJK128, desktop | 2.133ms | 1.604ms | -24.83% |
| CJK256, desktop | 2.750ms | 1.630ms | -40.60% |
| CJK4096, larger atlas only | 16.517ms | 8.280ms | -50.09% |
| CJK4096, larger shape+atlas bounds | 21.331ms | 1.843ms | -91.37% |

224 timed processes in this cohort. Both columns are median process averages;
the paired change is the median of within-pair ratios, so it need not equal the
ratio of table medians. Command totals, resource uploads and maximum cache usage
match in each pair. The small-set gains are not attributed to indexing when its
threshold is never reached. The sparse prefix emits roughly 1000 commands/frame;
it is not a fully populated long-running sparse scene.

CJK32/64/128/256 are custom diagnostics: the original churn positions/control
bytes are preserved, but CJK scalars are mapped modulo a capped alphabet, keeping
two-cell occupancy. They are not unchanged TUI-Zoo tracks. The4096 tape is frozen
from TUI-Zoo unicode --case churn, dose 4096, seed 20261020, 32 frames, 384x83,
synchronized output. These new tapes omit final producer cleanup. Older normal
tapes include that cleanup in the last cut; both variants receive identical bytes.

## Attribution and rejected changes

Earlier indexed versions retained the same large-set improvement but regressed
normal Unicode by up to 6-12%; they were rejected. Preserving hot field offsets
and separating cold miss work reduced some regressions, leaving the table above.

A bounded private SIGPROF sample of 96000 sparse frames per variant collected
12619 control and 13463 candidate PCs. The extra samples mostly land in the
background/style full-grid scan, not hash lookup. This is diagnostic sampling,
not an independent timing claim or proof of a particular hardware mechanism.

Extracting that scan from glyph construction did not solve the issue. A
72-process three-way follow-up compared original, separated-background control
and separated-background+index. Sparse regressed 7.24% even without the index,
7.72% with it. The two separated background functions have identical instruction
sequences apart from relocated addresses/constants. This refactor was discarded.
The precise compiler/layout cause remains unproven; neither arbitrary alignment
tuning nor a supposedly free common-case path is justified by these observations.

Cold cost remains material. The first 4096-glyph update with both larger budgets
takes median 37.1ms in the control and 32.1ms indexed. A 1.84ms warm update does not
prove a 4.17ms cold frame or real 240Hz presentation.

## Compact-reference follow-up E

The dense ASCII tables used wider representations than the bounded caches need.
Shape references were optional usize values (16 bytes on this target); a one-based
u32 with zero for absence needs 4 bytes. Atlas ASCII records shrink from 16 to 12
bytes by using u32 entry references. Both reuse the same checked entry bound as
the new index. Key equality, placement range checks and cache capacities remain.

DWARF sizes on x86-64: shape owner 6224 -> 1680 bytes, atlas owner 6272 -> 4768
bytes. These are owner layouts, not total cache or process memory. With the
current SMP allocator the shape owner moves from an 8192-byte to 2048-byte size
class; the atlas owner remains in the 8192-byte class. The desktop shares the
shape Store by font recipe/size, so this is not a per-pane 6KiB RSS claim.

A separate 224-process paired cohort and 448 matched frame pairs in the field/pixel oracle give:

| Lane | Paired update change versus accepted control |
| --- | ---: |
| ASCII | -0.42% |
| UTF-8 | +0.00% |
| UTF-8/background | +0.92% |
| Sparse prefix | -3.51% |
| Rain | -1.97% |
| Emoji | -1.12% |
| Combining | +3.49% |
| CJK128 | -22.93% |
| CJK256 | -39.89% |
| CJK4096, larger atlas only | -49.77% |
| CJK4096, larger shape+atlas bounds | -91.35% |

Warm 4096 with both larger bounds takes median 1.809ms versus 21.200ms. All eight
combining pairs regress; sparse improves in seven of eight pairs and rain in all eight.
These findings require full-app qualification rather
than treating a smaller owner as a universally faster path. C and E are separate
cohorts, not additive percentage improvements.

## Memory and admission design

The index does not raise glyph/shape/atlas budgets. A 256-record table needs
512 u32 slots, about 2KiB per indexed cache; retained index storage is bounded by
the caller's entry limit and survives resets for reuse.

Raising pixel dimensions has a separate multiplicative cost. Alpha is eager;
RGBA is lazy but currently shares the same extent and shelf coordinates.

| Square extent | Alpha + RGBA after both used | Renderer + three publication pixel buffers |
| --- | ---: | ---: |
| 512 | 1.25MiB | up to 5MiB |
| 1024 | 5MiB | up to 20MiB |
| 2048 | 20MiB | up to 80MiB |

These are source-derived raw pixel bounds, not observed RSS or complete pane
memory. They exclude fonts, commands, graphics and GPU storage. Publication pixel
buffers retain their high-water capacity. This is why larger eager per-pane
defaults are not established as the right admission policy.

The next capacity design must jointly specify:

1. Independent alpha/colour packing or byte budgets, so a single emoji does not
   multiply a large alpha working set by five.
2. Bounded entry/shape lookup and an explicit maximum resident-byte policy.
3. Failure-atomic allocation/copy/commit and resource generations. Commands and
   retained rows carry resource extents, so growth during construction cannot
   silently change their interpretation.
4. Immutable previously published frames and exact backend residency behavior.
5. Cold fill, warm reuse, churn, resize and allocation-failure proofs, plus
   longest uninterrupted service/projection turns.

The resource envelope currently reserves exactly two glyph planes plus seven
terminal images. Paging therefore also changes the publication/backend resource
bounds; it is not confined to the shelf allocator. The runtime reserves frame
pixel scratch from the complete atlas byte bound before publication, which also
belongs in the memory accounting.

The local Alacritty reference uses a hash-based glyph cache and additional 1024
texture pages on packing pressure, with RGBA textures for both text and emoji.
That is useful behavioral evidence, but does not directly specify Howl
immutable CPU publications or bounded resource policy.

Complete frames and the existing pacer remain. Paging versus growth is not yet
decided. Neither a new worker nor per-cell command signatures follows from this
lookup result.

## Qualification

The indexed candidate passes Render Safe/Fast proofs, including collision chains,
full key equality, bounded full-table termination, alpha/RGBA packing, reset and
reinsertion, allocation failures during lazy index creation/growth and colour
plane allocation, plus entry-index configuration bounds. Root check/test,
consumer, protocol and audits pass: 341 steps, 1125 reported tests plus cached proofs. The LLVM ReleaseFast
app passes 153 tests. Eight native captures match exactly between control and
candidate for UTF-8/background, emoji, combining and CJK256; all are nonblank,
and different corpora have different pixel hashes.

## Complete app and decision

Two paired rounds per lane, fresh 8-second apps, reversed lane/variant order in
round two. Private 1920x1080 KWin seat, scale 1, native fullscreen 384x83/5x13.
Terminal-component user+system CPU is sampled after 1s warmup, strictly inside
the producer lifetime. Compositor, runner and producer CPU are excluded.
These are CPU costs under equal produced input, not counts or latency of displayed
frames. This is not a physical Hyprland 240Hz race.

The final E cohort has 24 qualified trials across six 240Hz lanes. Four additional
ASCII trials resolve its inconsistent first pair. Four matched combining trials
run at 20Hz. In total 32 qualified trials deliver 54,400 producer frames with zero
skipped producer slots. All outliers are retained.

| Lane | Complete-app paired CPU changes |
| --- | --- |
| Sparse | -7.94%, -2.26% |
| ASCII, four pairs | +5.95%, -0.40%, -0.98%, -0.07% |
| UTF-8/background | -3.79%, +1.72% |
| Rain | +2.51%, -2.84% |
| Capped CJK128 replay | -10.91%, -4.13% |
| Capped CJK256 replay | -21.13%, -18.01% |
| Combining, 20Hz | -0.26%, -1.95% |

The large-set gains survive in the app. Sparse improves in both pairs. ASCII,
rain and UTF-8/background do not support a robust general throughput claim.
ASCII's four-pair median is -0.24%; its adverse first pair remains in the result.
The isolated combining regression remains 3.49%, despite no observed complete-app
CPU increase at the matched lower cadence. The old indexed C version had a
consistent approximately 6% app rain penalty and was not accepted.

The first four live combining runs at 240Hz emitted only 212-216 frames and
skipped 1704-1716 producer slots. Their CPU comparisons are explicitly excluded
as unequal work. The 20Hz replacements each emit 160 frames, with matching writes,
codepoints, payload bytes and nominal cells. The initial legacy-alphabet driver
error also contributes no timing result. Failed and saturated receipts are
retained alongside the qualified runs.

Process anonymous peaks remain broadly in the same range, about 86-103MiB across
these private app lanes. No general RSS reduction is established by shrinking
the cache-owner structs. Pixel and publication bounds remain separate work.

The accepted change is bounded numeric lookup, compact dense references and
separation of warm resolution from miss work. It does not raise host budgets,
evict atlas pixels mid-frame, change the pacer, add a worker, or claim the durable
sparse reuse target is solved. Default 4096-glyph admission still fails CacheFull.
The next capacity slice must earn independent alpha/colour allocation, bounded
growth or pages, publication accounting and cold-turn behavior together.

Both final source and LLVM ReleaseFast app are pinned before the app tests.
App SHA-256: 9706270329a070751d99e6c8812b445db941e478a94a554cb0f45237fbb9fc84.
Control SHA-256: ef749f7bfad2755785db596a61bc65a684e90e719f575f7ce982d418e00510bb.
Raw bounded evidence and sealed job receipts live in the Home workstream
day-20261023/atlas-working-set, including summary-E.json,
desktop-summary-E.json, final-E-validation.json and E-pins.json.
