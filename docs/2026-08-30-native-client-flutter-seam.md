# Native Howl client -> Flutter seam checkpoint — 2026-08-30

## Status

The first native client-engine extraction is accepted enough to guide the next
experiment, but **no Flutter FFI ABI is accepted yet**.

`howl-session` + `howl-vt` remain canonical terminal truth. `howl-client` now
owns only reusable client-side mechanics and semantic observation/control:
connection/framing, negotiated client identity/features, coherent interaction
state, canonical non-coordinate actions, one hostile-safe lossless `text_v1`
decoder, and a compact projection over that rich native model. `howl-cli` owns
its command vocabulary and text/JSON presentation, including explicit rich
diagnostic output. The earlier generic NDJSON pressure experiment was retired
after its useful black-box proofs moved onto the CLI/client surfaces.

## What measurement says

The Android Flutter pressure client was measured in profile mode on the Note10
against one Brommer-owned canonical Howl session, with a fixed 1,600-line churn
workload and a nine-second CPU window.

- pre-cache Flutter client: about **99.3% of one CPU core**;
- bounded `TextPainter`/glyph-layout cache: about **62.9%**;
- same cache plus observation paced to Flutter presentation frames: about
  **57.5%**;
- total measured reduction from the pre-cache client: roughly **42%**;
- idle returns to 0% CPU after churn;
- post-churn PSS stayed flat-to-better in the measured runs (roughly 246 MiB
  pre-cache versus 226 MiB in the frame-paced run), so the CPU reduction did not
  buy itself by unbounded memory growth;
- all Flutter input/IME/touch/protocol tests remained green and the live Android
  client remained top-resumed without application errors.

The remaining hot seam is concrete. Flutter still owns about 1,030 lines of
frozen-wire decoding/model code (`lib/protocol.dart`) and constructs a complete
Dart cell model for every observed snapshot. A live 36x51 terminal contains
1,836 visible cells. The churn run advanced the canonical session through about
1,620 observation revisions. A lossless NDJSON *presentation* of one such final
snapshot was about 945 KiB; that number is JSON expansion rather than wire size,
but it illustrates how much rich per-cell state exists. The binary session wire
still transports the complete visible semantic grid for a snapshot.

This is therefore a better next native target than IME, touch, gestures, app
lifecycle, or arbitrary Dart line-count reduction.

## Coarse native snapshot experiment

The coarse-view hypothesis survived both native measurement and Android Flutter
pressure testing. The experiment deliberately began under ignored work space and
accepted no ABI or memory layout in advance.

A live linked 36x51 rich snapshot contained 1,836 cells, 780 Unicode scalars and
one hyperlink. Native `rich.request` used 860 allocator calls and retained about
121.5 KiB in its object graph after transient frame buffers were released. A
mechanically equivalent flat projection retained the same row, cell, scalar,
hyperlink and presentation facts in **78,032 bytes and exactly one allocation**.
Packing/freeing that view cost about **58.4 microseconds** per revision in the
100,000-iteration native probe. The projection consumes the already-decoded rich
model and adds no second `text_v1` parser.

Three temporary Flutter crossings were tested. `TransferableTypedData` was safe
but copied the whole view each revision. A raw pointer whose backing allocation
was recycled on the next observation was rejected after a deterministic SIGSEGV:
Flutter may still compare or paint the previous delegate while installing the next
one. The safe experiment therefore used an explicit native lease. A published
view remained immutable until Flutter released it after the following frame.

Against the same 1,600-line churn shape on the Note10, the explicit-lease native
path settled about **5.7 MiB lower PSS** than the accepted Dart rich-object path.
In a normalized 10.208-second run it used **6.038 CPU ticks per terminal paint**
versus **7.286** for Dart (about 17% less), and average Flutter build+raster time
fell from **60.617 ms to 53.452 ms** (about 12% less). It produced 106 paints
versus 70 in the same window. Total process CPU therefore rose because Flutter
presented substantially more frames, not because the native observation seam cost
more per presented frame.

The experiment earns one native API: `howl-client.view` projects a lossless rich
snapshot into an opaque, explicitly owned, immutable one-allocation view with
batched rows, cells, scalars, hyperlinks, URI bytes and presentation state. The
source snapshot may be released immediately after projection. The view must be
explicitly deinitialized only after all borrowers are finished. Public callers
cannot depend on its backing offsets or struct packing.

This remains client state, never terminal truth. `howl-session` and `howl-vt` stay
canonical and observers cannot pace PTY/VT progress. The temporary C ABI, Android
wrapper, raw addresses, byte offsets and Dart FFI layout were deleted rather than
canonized. Any future Flutter bridge must preserve the proven explicit-lifetime
rule and coarse crossing without treating today's private native layout as ABI.

The next performance pressure is presentation/text/raster work. If that earns a
native seam, it should flow through `howl-text` rather than grow another terminal
transport or Dart parser variant.

That pressure now has an independent native consumer and a measured cache decision.
`howl-render` projects an immutable `howl-client.view` through `howl-text` into
native glyph placements backed by one caller-bounded alpha atlas generation. Font
metrics, fallback selection, HarfBuzz shaping/source clusters, glyph identity and
FreeType rasterization all remain owned by `howl-text`; the renderer owns only
presentation placement and bounded raster reuse. There is still no Flutter, Dart,
Android, iOS or C ABI in this path.

The first uncached live probe exposed the reuse pressure: a real 36x51 session had
1,836 cells and 719 Unicode scalars, producing 717 shaped glyphs but only 68 unique
`(face,glyph)` identities. The subsequent 1,600-line churn measurement used the
exact Note10-provisioned Iosevka regular face plus an explicit Noto Sans Arabic
fallback and deliberately exercised indexed/bold style facts, Greek, combining
acute, box drawing, a Nerd Font marker, a real fallback glyph and a semantic
width-two lead/continuation. Across 657 coherent observations it saw 588,173 glyph
instances but only 73 unique glyph identities. A bounded 128-entry experiment hit
99.988%, with 73 cold misses and no evictions; the actual retained alpha payload
was 5,900 bytes. A deterministic one-pixel-gap shelf pressure test fit that working
set in a 128x128 (16 KiB) alpha image, while 80x80 and 96x96 did not. Those dimensions
are measurement inputs, not product constants.

A frozen settled churn frame separated the native cost directly: HarfBuzz shaping
cost about **1.192 ms/frame**, rerasterizing every glyph cost about **15.912
ms/frame**, and the old uncached `howl-render.terminal` projection cost about
**17.700 ms/frame**. The real bounded atlas implementation then measured **2.146
ms/frame** warm against **17.853 ms/frame** for that copied-raster path on the same
36x51 / 911-glyph view, an **8.32x** improvement. The copied-raster API had no
consumer and was deleted rather than retained as a slower compatibility surface.

The surviving atlas has no implicit eviction or reset. Atlas dimensions and entry
capacity are supplied by its presentation caller; entries append without moving
old rasters, and `CacheFull`, `AtlasFull` or `GlyphTooLarge` leave the current
generation valid. Only explicit `resetAtlas` advances the generation and
invalidates earlier references. A final live 1,600-line acceptance held one
caller-selected 128x128/128-entry atlas for 876 observations: it reached 73 entries,
never reset, and averaged **1.592 ms** native projection time while the style,
combining, width-two and fallback pressure remained present.

This earns bounded native glyph-raster reuse inside experimental `howl-render`. It
**does not** yet earn a Flutter glyph-atlas ABI. Flutter atlas upload/composition,
native-to-Dart crossing volume and platform text integration have not been measured,
so the accepted Flutter client keeps its current presentation path until a separate
pressure experiment proves a better bridge. Raw atlas packing, addresses, dimensions
and glyph structs are therefore native implementation/API facts, not stable FFI
layout.

## Flutter atlas pressure result

That separate Android pressure experiment has now been run and deliberately **did
not** promote its bridge. A disposable arm64 bridge cross-built the accepted
`howl-client.view -> howl-text -> howl-render.terminal` path with private experimental
FreeType/HarfBuzz copies, copied one packed placement batch per presented revision,
and copied the 128x128 atlas image only when native content changed. The accepted
Dart/TextPainter path remained available for direct A/B throughout. No temporary C
struct, address, packing offset, Android dependency, or atlas dimension became product
ABI.

Two profile-mode Note10 runs per path used fresh Brommer-local 36x51 `/bin/sh`
sessions and the same 1,600-line/5 ms churn. Averaged results were:

- Flutter build+raster fell from **50.098 ms/frame** to **43.989 ms/frame** (about
  **12.2% faster**);
- presented paints rose from **86.5** to **115** (about **33% more**);
- settled PSS stayed effectively flat: **230,212 KiB** Dart versus **229,982 KiB**
  native;
- the native crossing averaged about **18.5 KiB** of placement material per
  observation and exactly two **128 KiB** RGBA atlas uploads per run; the atlas held
  at most 62 entries, stayed in generation 1, and never reset;
- but CPU cost per presented paint regressed from **5.781** to **6.031 ticks**
  (about **4.3% worse**).

The regression is well localized. Native projection still averaged **10.446 ms per
coherent observation**, while private serialization averaged only **0.271 ms** and
atlas upload/copy volume stayed bounded. Earlier churn evidence showed only about 26
of 1,836 visible cells changing per observation on average, so full-grid reshaping and
placement reconstruction are now the dominant obvious waste.

The bridge was also held to a visual gate before measurement. Its first raw-image
version rendered almost blank and was rejected. After fixing premultiplied RGBA,
contiguous private records, natural 16 px Iosevka glyphs on the accepted 10x20 cell
lattice, and one presentation-only vertical alignment pixel, automated Note10
screenshot comparison reached about **1.99% differing pixels** with complete
row-for-row terminal structure. No canonical terminal or `howl-text` behavior was
changed merely to imitate Flutter.

Therefore the durable conclusion from that first crossing was narrower than “native
Flutter renderer wins”: the atlas crossing was a real frame-latency/throughput
opportunity, but full-grid shaping left it failing the end-to-end CPU criterion. The
bridge was deleted and shaped-run reuse was measured before Flutter was reconsidered.

## Bounded shaping reuse and second Flutter pressure result

The follow-up measurement found a much stronger reusable identity than spatial dirty
cells. Across a fresh 36x51 / 1,600-line churn, terminal projection asked for
**1,440,941** cell-local shapes but saw only **73 exact scalar sequences**. A
disposable exact-sequence cache produced a **99.9949%** hit rate after 73 cold misses.
All 1.44 million direct-versus-cached glyph comparisons matched after rebasing cached
relative source clusters into the current immutable view, including combining,
width-two, Nerd-font and real fallback sequences. The measured retained scalar, glyph
and metadata material was only **5,552 bytes**.

That result earns a presentation-owned `ShapeCache` in `howl-render.terminal`. Its
entry, scalar, glyph and maximum-sequence capacities are all supplied by the caller.
It owns one preallocated `howl-text.ShapeBuffer`, stores exact scalar sequences and
relative shaped runs for one fixed `FontSet`, allocates nothing after initialization,
does not evict implicitly, and may be reset independently from the glyph atlas because
no returned frame borrows shape-cache storage. Cache hits rebase clusters while
copying final placements; `howl-text` remains the sole owner of face selection and
HarfBuzz semantics.

On the Note10, the exact pre-cache renderer from pushed commit `9a17398` averaged
**1.928 ms/frame** warm on the same settled 36x51 / 911-glyph view. The bounded
shape-cache candidate averaged **0.178 ms/frame**, a **10.85x** reduction (about
**90.8% less terminal projection time**). The candidate first compared every
placement field against fresh direct `howl-text` output before timing.

That native win was large enough to justify recreating the deleted Flutter atlas
pressure path once more. Three fresh profile-mode Note10 sessions per mode used
explicit begin/end terminal markers around the same 1,600-line/5 ms workload.
Averaged results were:

- CPU cost per presented paint: **6.114 Dart -> 4.703 native**, about **23.1% lower**;
- Flutter build+raster: **50.666 ms -> 38.521 ms/frame**, about **24.0% lower**;
- presented paints: **72.3 -> 104.3**, about **44.2% more**;
- settled PSS: **230,534 KiB -> 228,611 KiB**, about **1.9 MiB lower**.

Inside the measured native window, coarse view creation averaged **0.300 ms**,
cache-backed terminal projection **0.734 ms**, and private presentation serialization
**0.375 ms** per observation. Packed presentation material averaged about **20.35
KiB/observation**. Shape and glyph caches both topped out at 71 entries, atlas
generation remained 1, and no reset occurred. The atlas had already stabilized before
the begin marker, so no atlas image upload was needed during the timed window.

The recreated quality fixture retained indexed/bold style, Greek, combining text, box
drawing, Nerd-font content, a semantic width-two lead/continuation, and a real Arabic
fallback. Native and Dart screenshots retained the same complete terminal structure
and nearly identical content luminance distributions.

This second A/B therefore overturns the first experiment's CPU verdict: bounded native
presentation is now an end-to-end physical-device win for this workload. It still does
**not** canonize the disposable bridge. Its C ABI, Dart offsets, Android packaging,
private FreeType/HarfBuzz copies, 128x128 RGBA representation and FFI ownership glue
were deleted again. The next design question is the smallest durable ownership-oriented
native presentation seam that can preserve the measured win without exposing
`howl-render`'s private packing as ABI.

## Terminal Canvas producer and native presentation seam

The next pressure moved the decision one level higher than the specialized glyph
atlas bridge. `howl-render.canvas` already owns backend-neutral solids, alpha masks,
RGBA resources, resource identity/generation, clipping, composition and cursor
overlays. A disposable terminal mapper proved that the existing Canvas vocabulary
can express the tested terminal presentation without adding a terminal-specific draw
primitive: default/indexed/RGB colors, dim, cell and screen reverse, invisible text,
underline/strike and underline styles, combining text, semantic width-two cells,
Nerd-font and fallback glyphs, and cursor presentation all fit the existing contract.

The one ownership gap was topology, not drawing power. Terminal state can provide the
cursor target, semantic revision, shape and colors, but it cannot truthfully mint a
pane identity, Canvas source identity, visible-set revision or lifecycle revision.
The surviving API therefore requires an optional caller-supplied `CursorContext` for
those host-owned identities. `terminal.Content` combines that context with immutable
terminal facts and emits one complete `canvas.ProducerUpdate`; it never invents Host
or Composer topology.

`terminal.Content` is now the bounded native presentation owner. Its caller selects
the cell lattice, exact-sequence shaping bounds, atlas dimensions/capacity, cold-shape
scratch, raster scratch and Canvas command capacity. Construction performs all
allocation. Steady-state updates allocate nothing. Exact-sequence ShapeCache and the
append-only alpha atlas remain private implementation owners: neither evicts or resets
implicitly, and an explicit content-cache reset is the only presentation operation
which forgets them. Canvas resource generation advances only after a successful update
needs changed raster content; failures may warm private caches but cannot advance the
published producer revision or resource generation.

A live Brommer Composer/software-backend proof then retained terminal updates through
`canvas.Composer`, maintained backend residency and derived final Canvas frames. On a
500-observation ReleaseFast churn the pre-fusion candidate measured about **1.193 ms**
for terminal Content, **0.525 ms** for `Composer.apply`, and **0.790 ms** for
`Composer.frame`, or **2.507 ms/frame** for the complete native Canvas boundary. Only
two 16 KiB resource replacements occurred. A backend-loss recovery frame reproduced
the complete latest resource deterministically. The software backend rendered the
same quality fixture as the tracked Flutter client; raw-RGB comparison retained the
known native-vs-TextPainter line-box personality, with best alignment dx=0/dy=1 and
about **2.89%** fixture-channel MAE on that host/device comparison.

That Composer proof strictly subsumed the earlier terminal-specific `Glyph` / `Frame`
/ `Scratch` / `project()` surface. No accepted consumer existed outside its tests, and
keeping it forced `Content` to reserve a second 72-byte-per-glyph placement array only
to translate it immediately into 72-byte Canvas inputs. The placement API was deleted
and Content now projects directly into Canvas commands in two ordered passes: all
backgrounds/decorations first, then glyph masks. This preserves wide-glyph paint order
while deleting the duplicate placement buffer and source-cluster rebasing that no
backend-neutral Canvas consumer needs. Shape/atlas cache handles and lifecycle
functions became private again; callers see only Content bounds, usage, errors and the
Canvas update contract.

### Physical-device Canvas crossing

A second disposable Android pressure client crossed the **derived final Canvas frame**,
not terminal cells, shaped glyph structs or atlas internals. Its private packet carried
only surface/frame revision, qualified Canvas resource generations, sparse resource
mutations, final solid/alpha/RGBA commands and pixel bytes. Cursor presentation had
already been resolved by Composer. Android C/FFI offsets, the packet format, NDK
header overlay, private FreeType/HarfBuzz packaging and Dart worker protocol all
remained ignored experiment material.

The first generic Flutter backend was deliberately kept in the evidence because it
lost badly: parsing every final Canvas command into Dart objects and issuing one image
draw per alpha mask cost about **48.4% more CPU per paint**, **21.1% more build+raster**
and roughly **14 MiB more PSS** than TextPainter. Native Content+Composer was not the
large cost; the Dart object/per-command backend was.

The same final Canvas semantics were then consumed by a terminal-agnostic batched
backend. It retained only resource descriptors plus a few paint segments, clipped
sprites mathematically and used Flutter `drawRawAtlas` to submit long same-resource
alpha runs as one draw. No terminal row/cell/style/font/cursor policy entered Dart.
Three fresh 36x51 Note10 sessions per mode, using the same marker-delimited 1,600-line
/ 5 ms workload, measured:

| metric | Dart/TextPainter | Batched final Canvas | delta |
| --- | ---: | ---: | ---: |
| CPU ticks / paint | **6.236** | **4.287** | **-31.25%** |
| build / frame | 22.112 ms | 4.865 ms | -78.0% |
| raster / frame | 29.959 ms | 1.649 ms | -94.5% |
| build+raster / frame | **52.071 ms** | **6.515 ms** | **-87.49%** |
| paints | 72.33 | 82.33 | **+13.82%** |
| settled PSS | 230,107 KiB | 224,848 KiB | **-5,259 KiB** |

The full device quality fixture preserved indexed/RGB backgrounds, dim/reverse,
underline/strike styles, combining text, width-two occupancy, Nerd glyphs, Arabic
fallback and Composer cursor output. Fixture-only raw RGB comparison to TextPainter
measured **2.516% MAE** with the same best dx=0/dy=1 backend alignment. The default
block cursor is filled by Composer while the old simplified Flutter painter outlines
that case; the difference is recorded rather than teaching native presentation to
imitate a weaker client convention.

After deleting the redundant terminal placement frame, the Android bridge was rebuilt
against the **exact fused source** and run once more on Note10 before checkpoint. That
canary measured **3.90 CPU ticks/paint**, **7.44 ms build+raster**, **100 paints** and
**226,120 KiB PSS**, with 71-entry shape/atlas working sets and no timed-window resource
upload. The fusion therefore preserved the winning physical-device regime rather than
only passing host tests.

The durable conclusion is now precise: **`canvas.ProducerUpdate` and the
Composer-derived Canvas frame are the native semantic presentation boundary.** A good
platform backend should batch compatible final Canvas commands, but batching policy
belongs to that backend and is not terminal semantics. No stable C ABI is accepted yet.
The experiment packet, native addresses/offsets, Android dependency packaging and Dart
representation were deleted; a future binding should adapt the already-proven Canvas
ownership/lifetime model instead of freezing renderer-private memory layout.

## Font policy: IosevkaTerm Nerd Font

Home's current terminal presentation family is **IosevkaTerm Nerd Font**. Kitty
and Ghostty both explicitly select it. Home resolves the regular face from the
Arch `ttf-iosevkaterm-nerd` package, currently version 3.5.1-2, licensed
`OFL-1.1-no-RFN`.

Font family is presentation policy. It must not enter `howl-session`, `howl-vt`,
or the transport/client-engine contracts. The client engine should remain able
to represent terminal semantics without a font installed.

For eventual Kitty-quality visual parity, prefer reusing `howl-text` for native
metrics, fallback, shaping, source-cluster identity, glyph lookup and bounded
rasterization rather than deepening a second long-lived text engine inside
Flutter. The presentation layer may choose IosevkaTerm (or another configured
family) and supply the selected font material to `howl-text`; that choice remains
outside canonical terminal state.

The Android pressure client now optionally loads an externally provisioned
`IosevkaTermNerdFont-Regular.ttf` from its app-private files directory before the
first frame, registering it as `IosevkaTerm Nerd Font` through Flutter's public
`FontLoader`. The file remains untracked and unbundled; absence falls back to
`monospace`. This is deliberately presentation/deployment policy and does not add
font material or font concepts to `howl-client`, `howl-session`, or `howl-vt`.

## Accepted versus deferred

Accepted now:

- one native `howl-client` package owns client connection/framing and semantic
  native observation/control;
- one rich `text_v1` parser exists, in `howl-client`;
- compact snapshots and the opaque coarse native view project from that rich model
  rather than parsing twice;
- the coarse view owns one immutable allocation with explicit lifetime and exposes
  semantic slices without accepting a C/FFI byte layout;
- CLI remains a presentation layer over the native engine;
- Flutter glyph-layout caching, frame-paced observation, and coarse native snapshot
  consumption are measured wins;
- experimental `howl-render.terminal.Content` consumes `howl-client.view` through
  `howl-text` and emits complete backend-neutral `canvas.ProducerUpdate` state; its
  bounded exact-sequence shaping and append-only alpha atlas are private caches with
  explicit reset and no implicit eviction;
- `canvas.ProducerUpdate` plus the Composer-derived Canvas frame are the measured
  semantic native presentation boundary; a batched terminal-agnostic Note10 backend
  beats the tracked TextPainter path without carrying terminal semantics into Dart;
- Android may privately provision IosevkaTerm Nerd Font for optional Flutter
  presentation without making the font an app/repository asset.

Still experimental/deferred:

- any stable C/FFI ABI;
- packed snapshot or stable C/FFI memory layout;
- a durable Dart/Flutter binding for the native view;
- replacing Flutter production text layout/rasterization with `howl-text` output;
- a stable C/FFI adapter for the accepted Canvas semantic boundary; the disposable
  Android final-Canvas packet and Dart worker won only after backend batching and were
  deleted rather than promoted as ABI;
- a production Flutter/iOS Canvas binding and its platform resource/batching policy;
- stable atlas dimensions, GPU representation, native packet layout, or FFI memory
  layout;
- dirty-region or retained-command reuse beyond the accepted exact-sequence shaping
  and Canvas resource-generation model;
- stable cross-platform font provisioning or bundled font asset policy;
- mouse/coordinate mutation in the CLI before stale-target identity can be
  enforced by the session boundary.
