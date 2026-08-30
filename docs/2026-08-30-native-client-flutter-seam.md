# Native Howl client -> Flutter seam checkpoint — 2026-08-30

## Status

The first native client-engine extraction is accepted enough to guide the next
experiment, but **no Flutter FFI ABI is accepted yet**.

`howl-session` + `howl-vt` remain canonical terminal truth. `howl-client` now
owns only reusable client-side mechanics and semantic observation/control:
connection/framing, negotiated client identity/features, coherent interaction
state, canonical non-coordinate actions, one hostile-safe lossless `text_v1`
decoder, and a compact projection over that rich native model. `howl-cli` owns
its command vocabulary and JSON/text formatting. `howl-transport` is an
experimental NDJSON formatter/black-box pressure tool and no longer parses
`text_v1` itself.

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

## Next experiment: coarse native snapshot consumption

Do **not** make Flutter call thousands of FFI getters or move decoding to Zig only
to recreate the same object-per-cell Dart graph. That would relocate work rather
than remove it.

The next experiment should let `howl-client` own a coarse, immutable native
snapshot/presentation view for one canonical revision. The Flutter side should
receive one explicit-lifetime handle or packed read-only view and consume rows,
cells, scalar pools and hyperlink/presentation metadata in batches. Exact ABI
layout is intentionally deferred until a small prototype measures:

1. native wire decode time;
2. Dart allocation/object count avoided;
3. crossing/copy cost at the FFI boundary;
4. Flutter paint/frame latency under the same fixed churn workload;
5. memory retained by one/two snapshot generations.

The handle/view must remain client state, never terminal truth. The canonical
revision stays owned by `howl-session`/`howl-vt`; slow or absent Flutter clients
must still be unable to pace PTY/VT progress. Snapshot lifetime must be explicit,
and a new observation must not silently mutate memory still owned by a painter.

Only after this native snapshot seam demonstrates a real win should we decide
whether Flutter should continue doing text layout or consume a deeper native
text/render model.

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

For now, do not make the Android pressure client architecture depend on a
committed/bundled Iosevka font asset merely to make the demo prettier. The font
request is useful pressure on the eventual native text seam, not justification
to couple `howl-client` to font files.

## Accepted versus deferred

Accepted now:

- one native `howl-client` package owns client connection/framing and semantic
  native observation/control;
- one rich `text_v1` parser exists, in `howl-client`;
- compact snapshots project from that rich model rather than parsing twice;
- CLI and transport remain presentation layers over the native engine;
- Flutter glyph-layout caching and frame-paced observation are measured wins;
- IosevkaTerm Nerd Font is the desired Home/Howl presentation reference.

Still experimental/deferred:

- any stable C/FFI ABI;
- packed snapshot memory layout;
- native snapshot ownership/lifetime API for Dart;
- moving shaping/rasterization from Flutter into `howl-text`;
- glyph atlas/image transfer strategy into Flutter;
- Android font provisioning/asset packaging;
- mouse/coordinate mutation in the CLI before stale-target identity can be
  enforced by the session boundary.
