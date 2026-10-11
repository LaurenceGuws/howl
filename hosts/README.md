# Hosts

Hosts compose modules into an application or a concrete runtime policy.

| Package | Composition |
| --- | --- |
| howl-app | Local-only Zig/SDL daily terminal |
| howl-cli | command-line entrypoint, including howl server run |
| server | optional Server listener and scheduling runtime consumed by the CLI |
| howl-host | direct Vulkan/Wayland performance canary |
| howl-odin | Odin/SDL desktop canary |
| howl-flutter | Flutter frontend and its native bridge |
| howl-web | browser frontend, gateway and internal Wasm proof packages |

The server is a host over Instance and optional orchestration modules. It is not
a terminal core module or a remote client. Its runtime is a build export so the
existing CLI can compose it without adding another executable.

Frontend-specific bridges and proof subpackages stay with their owning host.
Moving here changes source organization, not their qualification status.
Each host owns its version; the root [snapshot](../snapshot.json) names the tested set.
