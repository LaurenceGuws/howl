# client-transport

`client-transport` owns explicit native Unix and numeric-IPv4 TCP ordered streams,
cancellation, descriptor lifetime, bounded connect deadlines, and transport diagnostics.
It knows no HWLS, Server control framing, Instance, Session, Server, renderer, discovery,
authentication, or route-selection policy.

The module exists because both the Howl Instance client and the optional Server control
client need the same boring native carriage. It is not a protocol or runtime owner.

TCP is optimized for Howl's small interactive request/response workload rather than
bulk-transfer throughput. Every TCP socket created by `connect`/`connectCancelable`
enables `TCP_NODELAY` before the ordered stream is handed to a protocol owner; failure
to establish that option is construction failure. Unix sockets do not receive TCP
policy. Generic raw-fd `adopt` cannot infer a socket family, so callers that create an
extra TCP leg must configure that leg before adoption. Managed Server -> HWLS handoff
keeps the same already-configured TCP fd.

A user-space TCP relay/proxy is therefore part of the latency path, not a transparent
implementation detail: it owns new TCP sockets and must apply the same NODELAY policy
on each interactive leg. A relay with default Nagle policy can reintroduce delayed-ACK
scale stalls even when both Howl endpoints themselves are configured correctly.

All constructors (including diagnosed and owned-fd adoption) start one 15-second
construction deadline. Protocol setup/handoff preserves it until `finishHandshake`;
ordinary read/write honors it while construction is pending. Unix connect is always
nonblocking, including without an Interrupt; full Linux Unix backlogs fail promptly
rather than blocking or mistaking SO_ERROR=0 for a connected stream. Once constructed,
reads may long-poll indefinitely with optional caller-owned interruption.

Linux and other platforms with MSG_NOSIGNAL suppress SIGPIPE per send. Darwin/BSD
sockets with SO_NOSIGPIPE enable it during ownership/adoption, including raw-stream
handshake adoption; option failure is construction failure. No process-global signal
policy is installed. Raw Stream literals are not initialized sockets: use `adopt`
or pass them directly into a protocol constructor before I/O.
