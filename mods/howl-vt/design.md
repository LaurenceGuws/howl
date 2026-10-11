# howl-vt

`howl-vt` is a native Zig terminal emulator. Its public package root exports
`howl_vt.Terminal`; implementation files are not embedding interfaces.

The package separately exports `howl_vt_codec` for optional portable terminal
observation payload encoding/validation. Its text, graphics and property grammar
and decoded cells, scalar banks, palettes, links and manifests have no Server,
socket, live terminal parser or renderer dependency. Complete text decoding
returns one explicit owner for rows, scalar banks and URI bytes; raw, zlib and
packed zlib bodies share the same validation and cleanup. Publishers separately
specialize `codec.encoder.Encoder` on VT's read-only `Observation` type for
text, property and graphics encoding; the codec imports no live parser. The normal
`howl_vt` root never imports or re-exports this codec; local observation remains a
direct borrow. The codec does not schedule, publish or deliver observations.

The optional encoder's DeltaCache retains screen-local row generations for live
views, exact copied cells for historical views, and bounded row link memberships.
Changing screen bank, history offset or geometry requires a complete text baseline.
The caller authorizes the exact delivery predecessor; the cache holds no Server
revision. Encoding is provisional until the caller queues the whole observation:
a downstream failure must invalidate the cache before another delta is allowed.

## Ownership

VT owns:

- parsing bounded byte streams received from a PTY;
- primary and alternate screens, cells, history, cursor state, modes, colors,
  hyperlinks, terminal graphics, and protocol state;
- protocol-mandated reply bytes;
- keyboard, mouse, focus, and paste encoding where terminal modes determine
  the resulting bytes;
- bounded ordered semantic consequences that require an embedder decision;
- resize, reflow, hard reset, and soft-reset protocol behavior;
- borrowed semantic access to cells, history, metadata, and graphics.

The live Terminal never owns:

- process lifetime or byte-stream descriptors;
- caller scheduling, wakeups, event loops, or execution;
- endpoint publication, serialization, waits, or external identities;
- caller projection, shaping, damage, admission, or acknowledgement;
- retained viewport position, follow mode, or scrollbar policy;
- caller selection gestures, clipboard policy, or container policy;
- panes, tabs, layout, or application navigation.

An embedder may choose a history offset when borrowing a semantic view and may
supply a text range for extraction. Those arguments do not make viewport or
selection policy terminal state.

## Embedding lifecycle

1. Import `howl_vt` and initialize `howl_vt.Terminal` with an allocator and
   nonzero cell dimensions.
2. Feed arbitrary, fragmented PTY byte slices with `Terminal.feed`.
3. Borrow semantic state with `semanticView`, metadata observers, and graphics
   observers.
4. Write the ordered bytes borrowed from `replyBytes` back to the child and
   consume each written prefix with `consumeReplyBytes`.
5. Inspect `consequenceHead`, apply embedder policy, and consume the exact
   occurrence with `consumeConsequence` or its typed reply operation.
6. Encode child input with `encodeInput`.
7. Resize or reset the emulator when required.
8. Call `deinit` exactly once.

`Terminal.initWithHistory` selects a fixed projected scrollback-row capacity.
Projected history plus the visible primary screen are the complete cell and
future-reflow authority: once a row is older than `history_row_base`, widening
cannot make its cells return. Finalized output and the bounded semantic line at
the cursor are retained independently as byte evidence. A successful terminal
owns every allocation made through its initialization allocator until `deinit`.

## Borrows and allocations

Borrowed cells, history, metadata, graphics, reply bytes, and consequence
payloads remain valid only until the next terminal mutation.

Observation does not allocate unless the API explicitly returns a
caller-owned copy. `replyBytes`, `semanticView`, `consequenceHead`, and the
direct metadata observers borrow or copy bounded state; `copyLogicalOutput` and
text extraction allocate only through the allocator supplied by the caller.

At fixed geometry, ordinary screen mutation, logical-output finalization, and
borrowed observation perform no terminal-owned allocation after successful
initialization. Projected-history payload backing grows lazily to a bounded
high-water mark; allocation failure records history loss without preventing
terminal execution. Once a stable payload shape has reached its high-water,
history turnover and eviction are allocation-free. Resize and reflow remain an
explicit transactional reconfiguration boundary.

Allocating operations state their ownership in their Zig contracts:

- copied text and encoded protocol buffers belong to the allocator supplied by
  the caller;
- owned result structs expose `deinit` when cleanup requires more than freeing
  one slice;
- allocation failure leaves the caller responsible for no new allocation;
- `Terminal.deinit` releases terminal-owned allocations in owner order.

## Replies and consequences

Reply bytes are terminal state, retained in protocol order under a fixed byte
bound. `consumeReplyBytes` accepts only an available prefix, allocates nothing,
and preserves the complete queue when the requested count is invalid. Partial
consumption supports partial PTY writes.

Consequences are typed occurrences in one global order. Each accepted
occurrence receives a nonzero monotonic identity shared across protocol
families. Identity exhaustion is an exact failure; identities never wrap or
restart silently. Fixed count and byte bounds prevent unbounded retention.

The embedder chooses policy for clipboard requests, notifications, container
requests, pointer shapes, file transfers, drag and drop, media-copy requests,
legacy terminal transitions, bells, and delegated control payloads. VT retains
their protocol meaning and ordering but performs no external action.

Stale consequence identity changes nothing. Consequences requiring a reply
remain retained until the corresponding typed reply operation serializes the
complete protocol response successfully.

## Failure

Public error sets name the owning failures. Recoverable failure preserves
previously committed semantic state, retained reply bytes, and consequence
order. Operations that require allocation or bounded output construct and
validate candidates before committing observable mutation.

Resize and reflow either commit coherent screen state or preserve the previous
terminal. Malformed child input is rejected or ignored according to the
protocol; it is not an embedder failure.

## Source ownership

- `src/howl_vt.zig` is the curated live-terminal embedding root.
- `src/codec.zig` is the separately selected portable observation payload codec;
  `src/codec/wire.zig` owns portable payload grammar/packing,
  `src/codec/decoded.zig` owns decoded values, validation and allocation cleanup,
  `src/codec/text.zig` owns complete text-body decoding/allocation lifetime,
  `src/codec/encode.zig` specializes synchronous read-only VT encoding,
  and `src/codec/properties.zig` owns bounded properties and borrowed decode.
- `src/parser.zig` recognizes bounded terminal syntax and materializes typed
  parser actions.
- `src/screen.zig` owns screen-bank cells, cursor state, margins, tab stops,
  fixed projected history, bounded logical-output evidence, SGR application,
  and transactional reflow of retained rows. Its owner proofs live in
  `src/screen/`.
- `src/sized_text.zig` owns OSC 66 field grammar, UTF-8 validation, clamped
  presentation values, and bounded cluster admission. Screen retains cell,
  scalar, cursor, wrapping, and scrolling mutation.
- `src/tab_stops.zig` owns explicit per-column tab-stop storage, default
  fallback semantics, resets, resize-prefix copying, and allocation lifetime.
  Screen retains cursor movement and routes tab-control actions.
- `src/modes.zig` owns ANSI/DEC mode state, saved DEC slots, and per-screen
  Kitty keyboard stacks. Kitty report serialization and all protocol routing
  remain in `src/terminal.zig`.
- `src/charset.zig` owns G0-G3 designations, GL/GR invocation, single shift,
  and the implemented character-set mappings. Parser dispatch and savepoint
  composition remain in `src/terminal.zig`.
- `src/input.zig` owns mode-directed key, mouse, focus, and paste encoding.
- `src/clipboard.zig` owns OSC 52 selection grammar, bounded Base64 codec,
  and child-directed query serialization. `src/consequences.zig` separately
  owns retained occurrence lifetime and ordering.
- `src/locator.zig` owns DEC locator reporting mode, filter and pointer state,
  and bounded locator reply serialization. Terminal routing supplies decoded
  controls and semantic mouse events without retaining a parallel copy.
- `src/mode_report.zig` owns pure ANSI/DEC mode-state classification and
  bounded DECRPM serialization. Terminal projects live mode and screen facts
  into one complete borrowed view.
- `src/fixed_report.zig` owns stateless terminal identity, status, geometry,
  title-stack, parameter, and checksum reply encoding from small value views.
- `src/iterm_control.zig` owns borrowed OSC 50, 133, and 1337 grammar for
  Howl's accepted iTerm subset. Terminal and Properties retain every resulting
  mutation, consequence, and owned byte lifetime.
- `src/stream_state.zig` owns parser allocation and bounded fragmented DCS,
  APC, PM, and SOS capture. Terminal retains semantic application, sixel
  placement, and Kitty graphics consequences after a capture completes.
- `src/replies.zig` owns bounded retained reply bytes and framing.
- `src/properties.zig` owns retained terminal metadata and presentation
  properties.
- `src/color_control.zig` owns xterm, Kitty, and accepted iTerm color-control
  grammar, bounded color replies, and cursor-color action projection.
- `src/consequences.zig` owns bounded globally ordered semantic occurrences.
- `src/terminal.zig` owns terminal composition, parser-to-domain narrowing,
  protocol routing and serialization, extraction, two-bank resize, and reset.
- `src/graphics.zig` owns bounded terminal images, animation frames, and
  cell-relative placements. Kitty image admission reclaims older retained data
  when the fixed quota is needed, preferring images with no placements.
- `src/kitty_placeholders.zig` owns Kitty U+10EEEE placeholder identity and the
  canonical row/column diacritic mapping used by terminal graphics projection.
- `src/sixel.zig` decodes bounded Sixel payloads into caller-owned pixels.

The remaining large `terminal.zig` owner is current source shape, not a promise
that unrelated terminal domains will remain in one file.

## Acceptance proof

`examples/0.1.4-dev` is an independent Zig package depending only on the public
`howl-vt` package. Its executable and tests are the versioned embedding proof.
They must remain small and must not become a PTY, caller-policy, or external
integration simulation.
