# Standalone native VT

The optional `howl_vt_native` static artifact and owned
`include/howl_vt_native.h` header let a C/C++ caller own a bare canonical VT.
Downstream builds link `dependency.artifact("howl_vt_native")` and receive the
installed header. The root forwards the exact child artifact and native module.

The native module's `owner` namespace contains one stable opaque Terminal and
uses an injected allocator. Only the C export root chooses libc. Ordinary
`howl_vt` stays independent of this optional root, libc, native records, Instance,
PTY, Server, Render and the optional observation codec. The caller owns transport,
process lifetime, time, scheduling, request policy and UI.

## Operations and lifetime

| Group | Entry points |
| --- | --- |
| Source capability | `hvt_observation_open`, `hvt_observation_release` |
| Owner / observation | `hvt_abi_version`, `hvt_create`, `hvt_release`, `hvt_observe` |
| Progress | `hvt_feed`, `hvt_resize`, `hvt_reset`, `hvt_service_animations` |
| Input | `hvt_encode_named_key`, `hvt_encode_unicode_key`, `hvt_encode_mouse`, `hvt_encode_focus`, `hvt_encode_paste` |
| Replies | `hvt_copy_replies`, `hvt_consume_replies` |
| Queries | `hvt_copy_cell`, `hvt_search`, `hvt_expand_selection`, `hvt_copy_selection`, `hvt_copy_hyperlink`, `hvt_copy_row_shapes`, `hvt_get_interaction` |
| Requests | `hvt_request_head`, `hvt_copy_request_payload`, `hvt_consume_request` |
| Named responses | `hvt_reply_clipboard`, `hvt_reply_pointer_shape`, `hvt_reply_color_preference`, `hvt_reply_container_state`, `hvt_reply_container_position`, `hvt_reply_container_screen_cells`, `hvt_reply_container_icon_title`, `hvt_decline_container` |

One serialized caller owns each handle. Copying its pointer creates no owner.
Creation requires a null publication slot and publishes only complete state.
Failures preserve the slot. Release clears it and accepts both a null slot pointer
and a null contained handle as no-ops, after all calls end.

Ordinary query records and byte ranges are caller-owned copies that survive
mutation and destruction. The separate `hvt_observation` capability has no
C-readable terminal storage and grants no mutation authority.

`hvt_observation_open` lazily creates one capability for this source occurrence
and returns a Reader reference. Later opens share its identity. The source
Controller, every successful open and every downstream retain count toward the
1,024-reference ceiling. Source allocation/reference-limit failure changes no
terminal state or revision and preserves the output slot.

Destroying the VT retires its capability without waiting for readers or retaining
terminal state. Existing Reader references remain safe to release; consumers
report source closure before touching VT. Allocator reuse by a new terminal cannot
revive an old capability. Source open/mutation/destruction and synchronous module
reads serialize externally. Independent retained references may release
concurrently. Copying a Reader pointer creates no reference.

The native `observation` namespace separates opaque Controller retirement
authority from Reader retain/read/release. The same helper lets the optional
Instance C owner lend its exact canonical VT observation. A consumer retains only
the small lifetime capability; it borrows const VT data during its serialized
read and keeps no canonical slice afterward. Standalone Render construction is
the next consumer under implementation.

Composed native artifacts must come from the same qualified Howl build and remain
loaded while their handles live. The C version is not a promise that private
opaque capabilities from unrelated build combinations may be mixed.

Fixed outputs/counts initialize before later validation. Data buffers remain
untouched on failed admission, shortage, stale/context rejection or canonical
operation failure. Excess tails remain untouched. Callers supply valid aligned
storage and keep fixed outputs/counts and owner slots disjoint from other argument
storage. Paste data aliasing is checked explicitly.

## Geometry and reset

Rows and columns are nonzero u16 values with checked product at most 1,048,576.
Primary history has caller-selected fixed u16 row capacity and canonical lazy
bounded backing. Large requested history can still return out-of-memory.

At creation, zero cell width and height mean initially unknown. On resize the
zero pair preserves current known-or-unknown pixels. Mixed zero/nonzero is invalid.
A nonzero pair replaces pixel geometry atomically with topology, generated replies
and revisions through prepared resize, including pixel-only changes. Failure
preserves old topology, pixels, revisions and retained work.

`hvt_observe` copies actual clamped history offset, stable history base/count,
cursor, geometry, bank and semantic/content revisions. It is a synchronous cut.

`hvt_reset` applies canonical RIS and advances semantic/content identity once.
It resets visible banks, modes, properties, graphics, locator and related RIS
state while preserving dimensions, history/identity, pixels, allocations, queued
reply bytes and retained requests. Reply framing and pointer-reset identity retain
their canonical reset semantics. Preserved work still needs explicit service.
Reset does not restore constructor state or restart a byte stream; destruction
and construction start a fresh terminal lifetime. Parsed RIS shares one private
raw transition and advances once through feed completion.

## Byte progress, time and failures

One feed accepts at most 65,536 bytes and invokes canonical service-boundary feed
once. Successful nonempty input reports an exact positive consumed prefix.
A new reply, retained request or synchronized-output release may end it. The
caller advances by that count, services work and chooses continuation; a pending
host request adds no facade-level input gate.

A canonical feed error may follow an already-applied prefix. The core does not
report exact consumed bytes on error, so failed C progress is entirely zero and
invalid. The caller must not blindly replay that input. Observation, reply/request
service, explicit RIS and destruction remain available. There is no implicit
reset, replay, sticky retirement or application recovery policy.

Feed and animation service take caller-monotonic nanoseconds. VT owns image frame
selection and next-delay facts; the caller owns its clock and next wake.

## Input, queries and retained requests

Named-key, Unicode-key, mouse and focus calls require at least 512 writable bytes.
Paste requires input length+12 even when bracketed mode is off. These are minimum
admission bounds, not exact-size query calls. Success writes only actual bytes.

Metadata/capacity checks precede canonical encoding. Mouse input can queue locator
replies, so output shortage must precede those effects. Canonical locator
allocation/reply failure can still retain latest pointer facts. Button bits 0/1/2 are
left/middle/right; higher bits are invalid. All eight modifier bits are valid; absent
pixel coordinates ignore x/y. Plain committed bytes need no encoding wrapper.

Paste input is at most 65,536 bytes. Its exact input range and required output
prefix must be disjoint; adjacent ranges and unused output tail are valid.
Address arithmetic is checked before slices. Canonical plain-paste borrowing or
bracketed allocation ends after synchronous output copy/deinit; nothing is retained.

Reply copy reports exact queued bytes and is complete-or-untouched. Consume only
the prefix delivered by the caller's transport. Invalid over-consumption preserves
the queue; zero consumption is a true no-op preserving revisions.

Queries forward existing VT helpers. Search is exact case-sensitive UTF-8 within
rows, excludes concealed text and scans bounded retained history using canonical
cut/completion/scanned-snapshot semantics. It never joins soft wraps. This differs
from the Server client's immutable-viewport search contract. Selection/link lookup
requires matching columns/bank. Selection shortage writes nothing, returns
`HVT_BUFFER_TOO_SMALL` and written zero, without an exact required-size promise.
URI/request/reply copies report exact required bytes. Row shapes report exact rows
and write no partial array. Byte capacities are at most 1 MiB; search queries 4 KiB.

Request IDs name the exact FIFO head in one terminal lifetime. Clipboard,
container and color queries require typed replies; container also permits decline.
Pointer query-requested is distinct from reply-required, so policy may reply or
consume it. Other families are consumable. Stale/wrong-kind, required-reply,
allocation and queue-limit failures preserve the head. Native descriptors reuse
VT schemas; no Server packet vocabulary enters this contract.

Named reply bodies are at most 65,536 bytes at this boundary, with canonical queue,
pointer and title limits potentially smaller. Platform permissions and truthful
clipboard/window values belong to the caller. No automatic headless policy is added.

## Qualification

Linux/x86_64 is the initial native target. Package proofs include a real standalone
C/C++ lifecycle, every new record field/constant/function-signature, allocation
prefixes and hostile boundaries. The distribution consumer resolves all 35 symbols
through the exact artifact/header.

`zig build check test:native test:terminal test:foreign -Doptimize=ReleaseSafe`
qualifies affected owners, canonical units and actual foreign callers. Default
child/root graphs additionally run codec, fuzz, simulations, maintained consumers,
protocol and audits.

The full package now passes `zig build check test -Doptimize=ReleaseSafe -j2`
on stable Zig 0.17.0: codec, encoder, native contracts, canonical units, embedding,
fuzz, simulation and foreign callers are included. The former
`NondeterministicMemoryUsage` qualifier came from allocator-dependent successful
resize/remap changing the failure campaign's numbered allocation count. That one
campaign now forces allocation/copy growth, testing all 17 allocation points while
preserving every prefix, cache-revocation, cleanup and canonical-state assertion.
Production encoder/VT behavior is unchanged.

Direct foreign image/logical-output projection and other platform deployment
remain separate. Standalone Render construction belongs to the Render native
contract.
