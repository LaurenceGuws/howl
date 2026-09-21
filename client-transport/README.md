# client-transport

`client-transport` owns explicit native Unix and numeric-IPv4 TCP ordered streams,
cancellation, descriptor lifetime, bounded connect deadlines, and transport diagnostics.
It knows no HWLS, Server control framing, Instance, Session, Server, renderer, discovery,
authentication, or route-selection policy.

The module exists because both the Howl Instance client and the optional Server control
client need the same boring native carriage. It is not a protocol or runtime owner.
