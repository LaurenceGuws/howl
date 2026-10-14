# server-client

`server-client` is the boring native client for one explicit Server control stream.
It owns private Unix/numeric-IPv4 TCP transport and both bounded Server control
and terminal interaction clients. `server_client.terminal` supplies terminal actions,
observations, selection, search, image retrieval and consequence handling.

It can inspect status/tree state, create or close Sessions and Instances, and attach
one exact nonzero (server_id, session_id, instance_id). A client keeps a catalog/CRUD
control connection and opens one independent connection for each attachment.
Successful attachment returns one opaque terminal Connection retaining the full
ready identity; identity() copies those accepted facts. It owns no listener, canonical lifetime,
discovery, authentication or supervision policy.

Target retains endpoint and all three nonzero identities. attach(allocator, target,
diagnostic, interrupt) checks the expected Server incarnation against welcome before
sending attach. Endpoint reuse never selects a new Server implicitly. Fresh control
browsing may learn the current incarnation from an endpoint.

Transport connect, Server welcome and attachment-ready share one 15-second setup
deadline and caller-owned Interrupt. Ready ends native construction; established
observations have no construction deadline. An ordinary control constructor instead
finishes at welcome, so idle control does not retain an expired setup deadline.
Each independent attachment starts its own bounded admission scope. The Web gateway forwards the
same ready response as the first binary WebSocket message; Wasm uses it directly.
There is no second terminal hello/welcome.

The public catalog Connection is opaque and exposes only control operations. Public
attach opens an independent setup connection and returns an opaque terminal Connection.
Neither public root exposes a stream constructor, allocator, socket storage or mutable
incarnation/revision fields. Private control_owner and terminal_owner module objects
supply construction and hostile fixtures without exporting those capabilities.

Construction failures release their owned socket/storage. Once terminal frame I/O
begins, transport, malformed framing, insufficient receive storage and partial-body
allocation failure retire the stream; later I/O reports ConnectionRetired. The handle
still needs one deinit after all outstanding calls return. Terminal actions, rich
observations and image retrieval also retire on malformed or incomplete semantic
responses. Recognized complete rejections, including geometry-authority loss, keep
the ordered stream usable. Snapshot/view owners have
their own independent release and may outlive the attachment.

## Caller-driven byte interface

The separately selectable `server_client_byte` module is also exposed as the exact
`server_client.terminal.byte` namespace. It drives one already-attached terminal
stream through typed starts, staged outgoing bytes and feed/finish response events.
Opaque state uses module-sized caller storage and explicit bounded buffers; it has
no allocator or native transport. Complete rejection remains a caller policy
decision. [Byte client](byte-client.md) defines setup, consumption, validation,
lifetimes and bounds. Native synchronous clients keep their existing direct API.

## Module boundary

Production server_client imports server_protocol and its own private transport
and terminal modules. The client imports no Instance, PTY or Server model. The family's model/service modules
are used only by integration proofs; they are not imported by the client module.
The same package owns the independently selected server_runtime listener/scheduler.

## Terminal interaction

It owns explicit endpoint parsing, portable POSIX connection and attachment, bounded framed I/O,
coherent interaction-state retrieval, canonical semantic client operations including
mouse facts, and one lossless Server v2 snapshot model with frozen `text_v1`,
`graphics_v2`, and complete bounded `properties_v1` state. Its rich, cached, and
coarse projections retain property bytes with the same snapshot lifetime.
Complete packed observation is transport-only: Server v2 `observe_packed`
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
selection, or listener policy in the terminal client. Instance
lifecycle, PTY/VT semantics, stale coordinate policy, UI, and rendering remain
outside that transport-neutral client.


The optional `server_client_render` adapter consumes these transported views through
canonical howl-render. Desktop Local ownership belongs to the consuming host.


## Optional native C ABI

The package publishes the exact `howl_server_client` static artifact and its owned
`include/howl_server_client.h` header. Downstream Zig builds may link
`dependency.artifact("howl_server_client")`; the root forwards that same artifact
and header. The ABI imports only the curated client graph. Maintained native
Flutter/Odin/CLI consumers use that same opaque Zig API; their UI-specific bridges
remain host-owned.

Version 1 uses opaque control, attachment, interrupt, catalog, snapshot and image
handles. Constructor slots start null and publish an owner only after success.
Matching release functions clear the caller slot. Caller code releases an owner
once, after all in-flight calls return; copying a handle never creates a new owner.
Catalog/snapshot/image allocations are independent of connections. Names,
Unicode scalar banks, URIs, property bytes and RGBA8 pixels are immutable borrows
whose lifetime ends with the matching view/resource release. Strings are explicit
byte lengths, with no NUL-termination promise; property presence bits distinguish
absent and explicitly empty values.

The ABI is synchronous and caller-driven, with one I/O owner per connection.
It starts no worker thread and performs no implicit reconnect. A caller-owned
single-use Interrupt may cancel construction or blocked I/O from another thread;
keep it alive until every borrowing connection is released and every cancel call
has returned. Cancellation retires affected I/O, and attachment release detaches
without closing the Instance. Explicit catalog Instance close controls PTY/VT
lifetime.

The header fixes version, status codes, native C records, semantic key/mouse/signal
vocabulary, input ceilings and view bounds. Functions copy rows/cells/presentation/
graphics records field by field; they never expose Zig slices, enums, unions,
packed style bits, mutable owner storage or wire packet layout. Cell copying is
bounded by the caller's capacity and returns a written count. Observation keeps
exact text/style/link/property/presentation/graphics facts; image retrieval names
one exact manifest generation and owns its decoded pixels independently.

The C boundary covers catalog CRUD, dedicated attachment, semantic terminal
input, geometry, signals, complete packed observations and exact images. The
richer Zig API also exposes reusable raw/delta caching and selection/search;
those are not version-1 C entry points. Version 1 also exposes interaction state
and retained terminal request authority through native C entry points.
The public native ABI is independent of the renderer. Linux live qualification
is in `test/native_client.c`; other platform deployment remains separately qualified.

## Native terminal requests

`server_client_native` is an optional module selected alongside the client. It
composes the VT-owned `howl_vt_native.h` schemas with Server authority; no live
VT, PTY, Instance, Server model or renderer enters its dependency graph. Both the
C artifact and Odin's private bridge use the exact child-owned module. Wire
metadata decoding and named reply body encoding stay here, out of the embedder.

`hsc_request_observe` returns an independent immutable view. Its descriptor embeds
`hvt_request` and adds `authority_client_id`; payload bytes borrow that view and
survive connection teardown. Observation never acquires authority. The embedder
explicitly acquires authority on its dedicated attachment before expecting retained
requests; without an authority Server preserves its existing headless behavior.
Acquisition does not replay a request already handled headlessly. Server's existing
bounded expiry and pressure fallback remain in force.

Named clipboard, pointer, color and container replies supply native values. The
client privately serializes Server bodies. Complete stale/wrong-kind/authority
rejections leave the connection usable; malformed, truncated, mismatched or
allocation-interrupted responses retire it. A pointer query is optional in VT's
consume contract: `query_requested` carries that fact while `reply_required` stays
false. Platform choices (empty clipboard, default pointer, dark preference or
container decline) remain in the embedding app. Neither this module nor the C
artifact starts workers, schedules turns or reconnects.

Linux qualification includes a real Server/PTY clipboard query through C, explicit
independent attachment authority, stale reply recovery, a named empty reply and a
request view whose borrowed bytes survive attachment teardown. Hostile fixtures
cover malformed interaction/request endings, incomplete allocation failure,
complete Server rejection and exact named-reply body encoding.

Clipboard projection validates the complete OSC 52 payload with VT's canonical
clipboard grammar, including selector alphabet/separator, query versus set and
Base64 replacement validity. Kitty packets have no OSC selector and never imply
an OSC query/set. Contradictory metadata/body pairs retire the attachment.
Outgoing clipboard reply bodies are limited to 65,524 bytes (64 KiB request minus
12-byte reply header); pointer and icon-title replies are limited to 1,024 bytes.
These are Server transport limits, separate from incoming retained-request bounds.
Native/C rejection of an oversized body happens before allocation or I/O and
reports a caller resource limit; the same attachment remains usable.
