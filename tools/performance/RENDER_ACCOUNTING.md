# Render memory and cold turns · 24 October 2026

The large idle anonymous footprint appears during SDL renderer creation, before
the terminal pane exists. A separate cold-turn problem comes from admitting
thousands of new glyphs: raster misses dominate that work. These findings require
different remedies.

One narrow fix is accepted: Canvas reserves exact alpha-to-RGBA conversion
capacity. It fixes bounded-buffer admission and removes geometric reservation
slack. No general RSS or CPU improvement is established. VT, Text/Render/Instance
interfaces, immutable frames, font recipes, backend selection and pacing stay
unchanged.

## Diagnostic method

Control is a659d4a / LLVM ReleaseFast69eed7fa, Zig0.17.0. A private git archive
adds six allocation ledgers, all delegating to the same SMP allocator: host,
canonical Instance/VT, shared Text/shape Store, Render, publications and Canvas.
They count requested live/peak bytes, not allocator rounding or physical pages.
Every diagnostic process balances all six domains to zero requested bytes at
teardown; that is ownership balance, not proof that all process memory is freed.
Domain peaks must not be added.

Twelve bounded wall-time counters cover service, publication, refresh, frame
materialization, shape/raster misses, admission/growth and backend work.
Histograms reconcile with every call count. Snapshots keep the first16 paints
and every32nd thereafter, with a256-record limit; no overflow occurs.
Native follow-up records /proc/self/smaps_rollup and glibc mallinfo2 at constructor
boundaries. These metrics are not an atomic cross-thread/OS snapshot and must
not be stacked as equivalent memory categories.

V1 uses20 fresh processes in two reverse orders: idle, sparse, Unicode/background,
cold full-CJK and emoji, each with unmodified control and diagnostic. Native heap
follow-up has six processes. The private KWin surface is1920×1080 scale1,
384×83 cells at5×13 pixels. Emoji targets20 Hz; other active cases240 Hz.
Instrumented CPU/times are diagnostics, not ordinary acceptance. Present wall
time includes vsync waiting. No physical240 Hz, displayed-deadline or input-latency
claim follows. No builds overlap collection.

## Requested Zig ownership

MiB in one V1 order; the reverse is retained. High-water storage can remain after
producer cleanup clears the scene.

| Case | Host | Canonical | Shared text | Render | Publications | Canvas |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| idle | 4.26 | 8.66 | 0.28 | 0.88 | 0.85 | 0.00 |
| sparse | 4.26 | 8.66 | 0.28 | 2.85 | 5.28 | 1.50 |
| utf8-bg | 4.26 | 8.66 | 0.28 | 5.95 | 9.53 | 1.50 |
| churn | 4.26 | 8.66 | 0.58 | 2.62 | 4.53 | 6.00 |
| emoji | 4.26 | 8.66 | 0.28 | 1.98 | 3.03 | 1.50 |

Idle control anonymous peaks83.2/83.0 MiB; diagnostic83.3/81.8 MiB, with about14.93 MiB
live requested Zig storage. Sparse control peaks92.4/92.6 MiB. The shown sparse
Render/publication/Canvas requests total about9.63 MiB. Unicode/background retains
more command storage. Shared text/shape storage is small in these cases.

This is attribution rather than an exact subtraction: requested buffers can have
untouched pages; native allocations, stacks, allocator overhead and backend
storage have other ownership.

## Graphics startup

Representative native-heap idle startup, MiB:

| Completed stage | Anonymous resident | glibc in-use plus mmap chunks |
| --- | ---: | ---: |
| SDL/TTF initialization |1.92|0.44|
| Fontconfig discovery |2.98|1.58|
| Window creation |2.99|1.58|
| Three UI fonts opened |5.52|4.16|
| SDL renderer creation |72.16|62.36|
| First pane constructed |77.36|66.40|
| Warm idle snapshot |86.05|69.54|

The large jump is inside SDL_CreateRenderer, before Instance/VT construction.
The reported renderer is opengl. At that jump, free glibc arena chunks are
about1.77 MiB versus62.36 MiB reported in-use/mmap chunks. A large free arena alone
does not explain the jump. This does not prove every native allocation is useful
or identify its exact stack within SDL/window/graphics libraries.

Path-backed Text fonts use FT_New_Face rather than copying whole font files.
LLVM selection does not select the application's allocator: these Howl owners
still use SMP; native libraries have their own allocation paths.

A successful software-renderer control still reaches roughly72 MiB at renderer
creation and100 MiB idle anonymous memory. The installed SDL header documents
that window surfaces use3D acceleration by default through
SDL_HINT_FRAMEBUFFER_ACCELERATION. Selecting software alone is therefore not a
demonstrated low-memory presentation alternative here.

The explicit SDL_FRAMEBUFFER_ACCELERATION=0 control fails at SDL_CreateRenderer,
before the renderer snapshot or any pane. Its failure is retained. No working
unaccelerated backend, memory win or performance ranking is claimed from it.
Daily backend configuration is unchanged.

## Cold service turns

Cold-CJK maximum wall spans, forward/reverse diagnostic orders, milliseconds:

| Stage | Maximum forward / reverse |
| --- | ---: |
| canonical_service | 1.72 / 4.18 |
| host_service_and_prepare | 41.26 / 42.05 |
| render_refresh | 40.42 / 41.42 |
| frame_materialize | 0.68 / 0.75 |
| canvas_update | 2.59 / 2.98 |
| canvas_draw | 3.00 / 2.83 |

Unmodified cold producers skip6/6 slots; diagnostic producers skip8/9. Those
misses remain in the evidence. Previous warmed race results are a separate cohort.

Cumulative shape-miss spans total4.36/4.88 ms. Raster-miss spans total37.81/38.64 ms,
including nested atlas-admission spans2.24/2.37 ms. Shape-storage growth totals
0.14/0.61 ms, nested in shaping. Nested totals and maxima cannot be added as if
they described one frame. The raster-miss path dominates cold work; eager
allocation alone cannot remove most of it. Wall spans include scheduling and
observer effects.

Sparse has no corresponding bulk glyph admission. Its steady prepared/painted
reuse opportunity remains separate; dirty-row count alone still understates work.

## Exact conversion reservation

Each alpha upload replaces the whole scratch image. Its dimensions already give
the exact RGBA size, so geometric ArrayList growth buys no extra useful reuse.
Canvas now reserves precise capacity and sets its used length; high-water
retention otherwise stays the same.

Eight paired diagnostic processes reproduce these capacities in both orders:

| Required bytes | Old capacity | Precise capacity |
| ---: | ---: | ---: |
|1,048,576|1,572,992|1,048,576|
|4,194,304|6,291,584|4,194,304|

The same policy avoids about4 MiB of extra requested capacity at the configured
maximum alpha height, subject to device limits. Spare mmap pages may never be
resident. Diagnostic anonymous peaks are mixed: sparse control92.3/92.7 MiB versus
candidate93.5/95.3 MiB; full-CJK control99.7/98.3 MiB versus candidate102.5/97.9 MiB.
There is no resident-RAM reduction claim.

A maintained real-backend recovery proof now supplies exactly256×256×4 bytes,
after injected failed resource application and continued canonical service.
Old code fails that proof (153/154 app tests pass). Precise code passes154/154
in Safe and Fast, including successful recovery and drawing. Both converted
length and capacity fit the entire budget.

## Ordinary acceptance

The qualified artifact has no private accounting exports.24 uninstrumented
fresh eight-second trials use two reverse pairs per case and one-second warmup.
Terminal-component user+system CPU excludes producer, runner and compositor and
stays strictly inside producer lifetime. All paired doses/hashes reconcile.
Emoji targets20 Hz; others240 Hz. Full CJK is prewarmed on both sides.

39,040 frames, zero skipped slots:

| Case | CPU pair1 | CPU pair2 |
| --- | ---: | ---: |
| sparse | -3.88% | +2.94% |
| ascii | -2.77% | +7.52% |
| utf8-bg | -0.04% | +1.37% |
| rain | +4.14% | -6.50% |
| emoji | +0.91% | +0.06% |
| churn-warm | +0.67% | -3.01% |

The +7.52% ASCII observation remains recorded. Four additional reverse-order
ASCII pairs deliver15,360 frames, zero skips: -0.68/-3.86/+2.62/-1.72%, median-1.20%.
These mixed observations establish no general CPU win or persistent regression.
No adverse sample is discarded.

Total ordinary acceptance:32 processes,54,400 producer frames, zero skips.
Ten nonblank native captures form five exact old/new decoded-RGBA pairs:
Unicode/background, emoji, combining, cappedCJK256 and realCJK4096. Full-grid
four-corner calibration passes.

Source gates: app Safe12 steps/154 tests, Fast14 steps/154 tests; root
check/test/consumer/protocol/audit341 steps/954reported tests plus cached suites;
formatting and diff checks. Final qualification and collection jobs are sealed
with zero memory/task-limit events and CPU throttling.

Qualified LLVM ReleaseFast SHA-256:
0983f38b48ed3998215983a82d90a379dfefc74b211d70497834ae3f80feefdf

Rollback is the69eed7fa artifact. No native heap trimming, new tracing API, worker
or pacer change is retained.

## Next design constraints

A cold-admission budget must earn its extra restart work and first-full-frame
latency while preserving complete immutable frames. A synchronous borrowed VT
view cannot survive returning to canonical mutation. Cache recycling, skipped
observations and real capacity exhaustion must prove progress or bounded failure.

Construction/font transactions need special care: a candidate Renderer is
refreshed before replacement commits. Returning busy and destroying that
candidate on every retry would discard warming progress and could prevent
completion. A budget cannot simply be inserted at one miss.

Another projection worker would require owned input plus copy/memory/coalescing
budgets. Prewarming shifts work; shared raster retention could help later panes
but does not remove first-use work and adds memory. This diagnostic selects none
of those approaches.

Warm sparse work still points to durable mutation evidence, Render-owned
dependencies/prepared pieces, and reconciliation against the last successful
paint, with complete reconstruction and one backend lease. The graphics startup
floor is a separate host/backend investigation.

Raw workstream:
~/.local/state/workstreams/howl-current/day-20261024/render-accounting/
Includes fold-v1.json, fold-native.json, diagnostic source patches/pins,
allocation-exact-summary.json, ordinary-summary.json, followup-summary.json,
native pairs, source gates and sealed job receipts. Failed private compile/
launcher attempts and the failed unaccelerated control stay separate.
