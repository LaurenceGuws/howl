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
- Android may privately provision IosevkaTerm Nerd Font for optional Flutter
  presentation without making the font an app/repository asset.

Still experimental/deferred:

- any stable C/FFI ABI;
- packed snapshot or stable C/FFI memory layout;
- a durable Dart/Flutter binding for the native view;
- moving shaping/rasterization from Flutter into `howl-text`;
- glyph atlas/image transfer strategy into Flutter;
- stable cross-platform font provisioning or bundled font asset policy;
- mouse/coordinate mutation in the CLI before stale-target identity can be
  enforced by the session boundary.
