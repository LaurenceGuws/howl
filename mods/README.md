# Reusable modules

A module is machinery an embedder can consume without adopting a product's
entrypoint, window, listener, or application lifetime. A Zig package may expose
several modules. Being here does not make a package terminal core.

| Packages | Ownership |
| --- | --- |
| howl-vt, howl-pty, howl-instance, howl-text | accepted terminal foundations |
| howl-render | shared terminal-to-frame presentation machinery |
| howl-vk, howl-wayland | experimental graphics/platform libraries |

Server orchestration, its wire and observation codec, clients and presentation
adapters now belong to the separately released howl-sessions repository.
Neither their build steps nor their symbols can enter this terminal package
graph. VT exports only its pure OSC 52 validation grammar for that consumer.

Each package owns its public build exports, version, dependencies and proofs.
Package versions are recorded in the root [snapshot](../snapshot.json).
No reusable module package may depend upward on a hosts package.
