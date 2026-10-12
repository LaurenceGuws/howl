# Optional Instance native contract

The package owns `howl_instance_native`, an optional shared library, and
`howl_instance_native.h`. Its header composes the VT-owned
`howl_vt_native.h` and Render-owned `howl_render_native.h`. The artifact selects the exact local `howl_instance`
specialization; its handles cannot be interchanged with headless or Server handles.
Ordinary Zig callers retain the direct Instance API. The separate
`howl_instance_native` Zig module shares native input validation with host adapters,
without emitting the artifact's C exports into those hosts.

Version 1 is an initial, unpresented Linux/x86_64-qualified lifecycle:
create, ordered semantic input, explicit geometry, process-group signals,
caller-driven bounded service, copied scalar/occupancy observation, and destroy.
Default service uses deterministic headless policy. Explicit per-turn retained
service, copied pending-request facts and named replies are now supported.
Standalone presented construction remains a subsequent cut.
The separate presentation endpoint now supports an existing presented Instance.
Odin uses the shared native input vocabulary and operation implementations while
preserving its existing retained-request policy and host runtime.

## Calling and memory

One owner thread serializes operations on each live constructor-owned handle.
An input/launch buffer need only survive its call; accepted input and launch state
are copied by the canonical owners. A copied `hvt_cell` survives later mutation
and destruction. Its x/y offsets distinguish continuation cells from their lead;
width/height describe the entire occupied cluster. Scalars resolve to that lead.
This record is not a renderer-complete cell.

Creation requires a null output slot and preserves it on failure. Destruction
clears a live owner slot, accepts an already-null slot, and invalidates other copies
of that handle. Live foreign pointers must be valid matching pointers; stale,
forged or concurrently mutated handles violate the caller contract. There is no
global handle registry. Versioned records cross the boundary explicitly; no Zig
union, enum, packed struct or slice layout is exported.

The explicit environment is bounded to 1024 input entries and 1 MiB of input bytes
including terminators. Final copied bytes, including canonical TERM/COLORTERM
replacements, are separately bounded to 1 MiB and 1024 entries. Duplicate names,
empty names, missing equals, and embedded NUL are rejected. Empty input means an
empty inherited environment, not capture of the embedding process. Canonical
Instance supplies `TERM=xterm-256color` and `COLORTERM=truecolor`.

Service takes caller monotonic nanoseconds and readiness, then reports copied
revision, I/O-pending, animation-delay, synchronized-output and exact process-exit
facts. A missing animation deadline differs from a zero delay. The POSIX fd is
borrowed: never close it. The caller owns polling, waits, wake sources, clocks and
threads. Re-query pending-write facts after input; an earlier result is stale.
Output records are zeroed before later validation/work. Operational service failure
may follow partial canonical progress; zero output is not a rollback promise.
The caller handles that failure explicitly rather than inferring a successful cut.

The Instance ABI version incorporates VT and Render native version 1. Changing an incorporated
record requires coordinated Instance ABI review/versioning; compile-time guards
reject silent version or scalar-capacity drift.

## Artifact and proof

The shared artifact uses the pinned compiler's self-hosted code generation/linker.
A minimal static-library graph with shared system-library dependencies reproduced
a compiler null-value panic. Shared linkage preserves the exact local graph without
a compiler substitution. The selected graph currently links FreeType/Harfbuzz,
even though this first constructor is unpresented. Do not claim a presentation-free
distribution or an idle-memory benefit. Those costs remain a packaging consideration
before broader foreign adoption.

`zig build test:native` runs an independent C lifecycle and C++ header/link proof.
The C caller owns poll/time, launches real commands, sends copied input, verifies
environment replacement, observes exit, checks malformed/limited arguments, and
copies wide/scaled Unicode occupancy across destruction. C/C++ assertions check
record sizes, offsets and alignment. The repository's separate distribution
consumer resolves the child-owned library and installed headers without private
source imports.

The complete default repository graph is separately required. An unchanged
VT-codec ReleaseSafe allocation-failure proof has reproduced
`NondeterministicMemoryUsage`; its failure is retained in workstream evidence and
must not be described as a green full-VT ReleaseSafe result.

## Presentation endpoint

The producer opens one native backend endpoint on its existing presented Instance,
publishes a fresh frame, then hands the endpoint to the backend thread. Opening
starts with empty backend residency and discards unread frames from the previous
backend. It never transfers the live mutable Instance to that thread.
`howl_instance_frames_native` is the exact module-owned Zig adapter used by Odin;
the optional artifact exports the matching `hi_frame_*` C operations.

An open endpoint pins publication storage, including between frame leases.
Checked Instance destruction refuses it before changing any owner state. The
backend closes the endpoint before the producer destroys its Instance. Calls on
one endpoint are serialized by its single backend owner. This is an explicit
thread handoff and lifetime contract, not a stale-pointer registry.

Acquire returns copied metadata for the newest complete immutable frame. Commands
and removals are copied in bulk into caller-owned arrays; insufficient capacity
leaves those arrays untouched. Only the actual leased command extent is written,
including when the caller supplies a larger capacity. The native contract does not
impose a maintained host command ceiling on an explicitly larger presented
Instance. Acquisition rejects any count above `UINT32_MAX` before advertising a
frame and leaves no active lease. Upload records are copied, while their pixel spans
borrow the frame until release, abandon or close. A later producer turn cannot
change those borrowed pixels. The caller may retain copied commands for redraw,
but must upload pixels before ending the lease.

Release reports the backend's actual resource residency. Invalid or busy feedback
leaves the lease active so the caller can correct or retry it. Abandon is valid
only when the candidate established no new backend resource state. Closing ends
the lease and endpoint; the next endpoint starts with empty residency.

Odin retains its worker, wake sources, frame credit, SDL textures and redraw policy.
Its worker opens/publishes the endpoint and hands it to the UI under the view
mutex. The UI copies one complete command array and borrows upload pixels. It
returns frame credit after presentation. Instance and Render own no GUI scheduler.

`zig build test:native-frames` uses a normal public presented Zig Instance and a C
peer that includes only the public headers. The peer retains pixels while the
producer advances, checks capacity/failure atomicity, exercises residency and
backend replacement, and proves teardown refusal both during and between leases.
C/C++ layout checks cover the copied envelope and Render-owned records. This proof
does not claim a C-only presented constructor. A second real 225×512 terminal
proof publishes beyond the maintained host command envelope and copies its exact
advertised extent through C; exact/insufficient/oversized capacities are checked
with trailing storage sentinels. An owner-module unit proof checks every native
count at `UINT32_MAX` and boundary plus one without allocating impossible buffers.

## Copied VT queries

VT's optional native root owns the search, selection, visual-row and interaction
records and their canonical projection. Instance's C artifact forwards its own
const observation to those helpers; Odin calls the same helpers under its sole
terminal-worker claim. Neither consumer defines another terminal observation
model or receives a mutable terminal pointer. Ordinary Zig VT/Instance roots do
not import the native query root.

Search is exact, case-sensitive UTF-8 within a projected row, across the currently
retained history. It excludes concealed text and returns stable row/column facts.
Search scratch is caller-allocated, bounded by row geometry and scalar capacity,
and released on success or failure. Stable coordinates must fit the signed native
row domain; the query reports a resource limit instead of narrowing a larger row.
No regex, cross-wrap search, UI paging or search worker is introduced.

Selection and link lookup require matching columns and alternate-screen context.
A changed context is explicit. Complete selected text is copied into caller storage
or fails without a partial byte write. A hyperlink capacity failure reports its
full required length without writing bytes. Row shapes report the required row
count on capacity failure and write only that actual extent on success. C text/link
capacities are bounded to 1 MiB; native search queries to 4096 bytes. Input/output
memory only needs to survive the synchronous call; successful copies survive
terminal mutation and destruction.

The foreign C lifecycle proof searches a real Instance, expands/copies a word,
checks stale context and capacity rejection, copies an OSC8 URI from a wide-cell
continuation, and reads stable interaction tags. VT-native proofs cover combining
characters, wide cells, concealed text, allocation failure cleanup and historical
row bounds. Odin consumes the same owned C/Odin layouts and retains query queues,
diagnostics, clipboard/browser policy and Find UI.

Word expansion crosses canonical soft wraps while skipping lower-row occupancy
of tall cells. Those fragments refer to an earlier cluster and are never new
characters in traversal. The exact OSC66 tall-cell plus soft-wrap case is proved
through both VT-native queries and a real C Instance; a space boundary also pins
backward traversal so a repeated fragment cannot jump over another word. The C
regression has a proof-owned deadline; the module owns no timer. Alternate-bank
rejection, evicted history and forward/reverse wide-cell origins have owner proofs.

## Pending terminal requests and named replies

VT owns the `hvt_request` descriptor and C/Odin layouts. Its public C tagged union
contains native fields for each canonical request family; no Zig union layout or
Server metadata is exported. `hi_request_head` copies those fields without
acknowledging or copying a potentially large body. No head is `HVT_REQUEST_NONE`.
`hi_copy_request_payload` checks the exact current occurrence, reports required
bytes on insufficient capacity, and copies the complete body or no bytes.
Successful caller copies remain valid across terminal mutation and destruction.
Occurrence IDs are valid only with their matching live owner.

`reply_required` means canonical consume refuses the head until a matching reply
or explicit container decline. Pointer-shape queries separately report
`query_requested`: canonical VT permits their consumption, while Odin's existing
policy still replies `default`. The descriptor clarifies that distinction rather
than choosing platform policy. Every union arm maps canonical tags explicitly;
optional drag/drop values have independent presence flags.

Instance owns exact-head consume and named native reply operations: clipboard,
pointer, color preference, container state, position, screen cells, icon title and
decline. Native enum tags are validated before mutation. Position and dimensions
are native integers, not packed byte bodies. Canonical VT owns reply serialization,
resource bounds and atomic head consumption. A stale or mismatched operation leaves
the request live. Accepted byte inputs are copied/serialized during the call.
Replies do not flush or wait; the caller re-queries service facts and drives I/O.

`hi_service_turn` retains its deterministic headless behavior.
`hi_service_turn_policy` explicitly selects `HI_SERVICE_HEADLESS` or
`HI_SERVICE_RETAIN` for that turn. The existing bounded pressure fallback is
preserved and reported through `retained_fallback`. Switching back to headless
drains pending requests on that same turn; no library authority, worker, clock or
platform handler is introduced.

Odin Local reads native facts under its terminal-worker claim and uses the shared
named module helpers. It keeps attention, clipboard, pointer, color and window
policy, queues, wakeups and diagnostics. Its old local Server-shaped request record
and big-endian reply handling are retired. The private Odin runtime bundle ABI is
17; module ABI 1 additions preserve existing native layouts and operations.

VT-native proofs cover every canonical request family, option/presence fields,
payload bounds, FIFO identity and required-versus-requested replies. The foreign
C consumer services a real retained clipboard query, proves invalid/stale/short
copy/mandatory-consume calls preserve it, replies and observes exact child bytes.
C++ and Odin prove descriptor/union layouts. A private Odin canary also observes
clipboard, pointer and exact screen-size replies through the real worker.
