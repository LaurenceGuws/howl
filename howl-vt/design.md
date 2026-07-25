# howl-vt

`howl-vt` is a native Zig terminal emulator. Its public package root exports
`howl_vt.Terminal`; implementation files are not embedding interfaces.

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

VT never owns:

- PTY or child-process lifetime;
- threads, wakeups, event loops, or scheduling;
- endpoints, remote transport, serialization, waits, or Control identities;
- renderer projection, shaping, damage, admission, or acknowledgement;
- retained viewport position, follow mode, or scrollbar policy;
- selection gestures or platform clipboard policy;
- window-system policy;
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

`Terminal.initWithHistory` selects a fixed retained-history capacity. A
successful terminal owns every allocation made through its initialization
allocator until `deinit`.

## Borrows and allocations

Borrowed cells, history, metadata, graphics, reply bytes, and consequence
payloads remain valid only until the next terminal mutation.

Observation does not allocate. `replyBytes`, `semanticView`,
`consequenceHead`, and the direct metadata observers return borrowed or copied
facts.

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

The embedder chooses policy for clipboard requests, notifications, window
requests, pointer shapes, file transfers, drag and drop, media-copy requests,
legacy terminal transitions, bells, and delegated control payloads. VT retains
their protocol meaning and ordering but performs no platform action.

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
protocol; it is not a host failure.

## Source ownership

- `src/howl_vt.zig` is the curated public package root.
- `src/parser.zig` recognizes bounded terminal syntax and materializes typed
  parser actions.
- `src/screen.zig` owns screen-bank cells, cursor state, margins, tab stops,
  retained history, logical-line retention, SGR application, and transactional
  reflow. Its owner proofs live in `src/screen/`.
- `src/terminal.zig` owns terminal composition, parser-to-screen narrowing,
  modes, input encoding, replies, consequences, extraction, two-bank resize,
  and reset.
- `src/graphics.zig` owns bounded terminal images, animation frames, and
  cell-relative placements.
- `src/sixel.zig` decodes bounded Sixel payloads into caller-owned pixels.

The remaining large `terminal.zig` owner is current source shape, not a promise
that unrelated terminal domains will remain in one file.

## Acceptance proof

`examples/0.1.4-dev` is an independent Zig package depending only on the public
`howl-vt` package. Its executable and tests are the versioned embedding proof.
They must remain small and must not become a PTY, renderer, window, or policy
simulation.
