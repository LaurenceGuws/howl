# Reusable modules

A module is machinery an embedder can consume without adopting a product's
entrypoint, window, listener, or application lifetime. A Zig package may expose
several modules. Being here does not make a package terminal core.

| Packages | Ownership |
| --- | --- |
| howl-vt, howl-pty, howl-instance, howl-text | accepted terminal foundations |
| howl-render | shared terminal-to-frame presentation machinery |
| server | optional Server runtime, model/service, wire, clients and private transport; separately selectable entry points |
| howl-vk, howl-wayland | experimental graphics/platform libraries |

The Server family is optional orchestration above Instance. Its single package
owns the listener and scheduler alongside the wire/client implementation.
Wire-only and client-only graphs consume the optional VT codec without importing
the canonical VT, PTY, Instance or Server lifetime. Client integration proofs use
the same family's model/service as fixtures.

Each package owns its public build exports, version, dependencies and proofs.
Package versions are recorded in the root [snapshot](../snapshot.json).
No reusable module package may depend upward on a hosts package.
