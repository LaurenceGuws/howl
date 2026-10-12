# Optional Instance native contract

The package owns `howl_instance_native`, an optional shared library, and
`howl_instance_native.h`. Its header composes the VT-owned
`howl_vt_native.h`. The artifact selects the exact local `howl_instance`
specialization; its handles cannot be interchanged with headless or Server handles.
Ordinary Zig callers retain the direct Instance API. The separate
`howl_instance_native` Zig module shares native input validation with host adapters,
without emitting the artifact's C exports into those hosts.

Version 1 is an initial, unpresented Linux/x86_64-qualified lifecycle:
create, ordered semantic input, explicit geometry, process-group signals,
caller-driven bounded service, copied scalar/occupancy observation, and destroy.
The service policy is explicitly deterministic headless. Retained host requests,
presented construction, publication leases, and complete observation contracts are
subsequent cuts; a consumer must not infer them from this first surface.
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

The Instance ABI version incorporates VT native version 1. Changing an incorporated
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
