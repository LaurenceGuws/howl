# howl-client

Reusable native Zig client engine for an existing Howl Instance interaction stream.

It owns explicit endpoint parsing, portable POSIX connection/handshake, bounded framed I/O,
coherent interaction-state retrieval, canonical semantic client operations including
mouse facts, and one lossless framing-v10 snapshot model with frozen `text_v1`,
`graphics_v2`, and complete bounded `properties_v1` state. Its rich, cached, and
coarse projections retain property bytes with the same snapshot lifetime.
Complete packed observation is transport-only: framing-v10 `observe_packed`
inflates `text_pack_v1`, reconstructs byte-identical frozen `text_v1`, then reuses
the same rich decoder as compressed/raw complete snapshots. Revision-relative
`RawCache` remains a distinct local/live optimization; there is still one semantic
snapshot model.

The coarse `view` projection owns one immutable allocation for a revision and
exposes rows, cells, scalars, hyperlinks, images, properties, and presentation facts
in batches. It resolves transported style bits, cursor-shape values, DEC row geometry,
and the Kitty image-placeholder scalar into semantic helpers before presentation code
consumes them. Its backing layout is private: it is not a C/FFI ABI. These models retain typed terminal facts;
they do not choose JSON, a renderer, a font, a platform UI, or a shell-command
vocabulary.

`search` owns exact client-local matching over one immutable projected row. It
returns stable canonical selection points rather than rendered byte offsets,
handles UTF-8/wide cells, and excludes concealed text. It deliberately does not
invent a cross-soft-wrap search contract; retained-history paging and search UI
remain presentation-client policy.

`selection.Range.textSpan` projects stable endpoints using canonical `RowShape`
facts from the same presented revision. It trims empty row tails and retains one
hard-newline marker without changing the canonical extraction request. It needs
no socket access or allocation during a selection gesture.

Unix sockets remain local endpoint mechanisms. TCP accepts explicit numeric IPv4
peers supplied by the caller; there is no DNS, discovery, authentication, route
selection, or listener policy here. Instance lifecycle, PTY/VT semantics, stale
coordinate policy, UI, and rendering are deliberately outside this package.

## Native carriers

The native client accepts explicit Unix streams and numeric IPv4 TCP peers supplied by the caller. It owns no DNS, discovery, authentication, SSH subprocess, bridge executable, Server lookup, or higher-level Session routing policy. Cancellation and bounded connection diagnostics are transport mechanics only.
