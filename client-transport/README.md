# client-transport

`client-transport` owns explicit native Unix and numeric-IPv4 TCP ordered streams,
cancellation, descriptor lifetime, bounded connect deadlines, and transport diagnostics.
It knows no HWLS, Server control framing, Instance, Session, Server, renderer, discovery,
authentication, or route-selection policy.

The module exists because both the Howl Instance client and the optional Server control
client need the same boring native carriage. It is not a protocol or runtime owner.

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
