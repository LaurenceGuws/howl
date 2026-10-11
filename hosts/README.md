# Hosts

Hosts compose modules into an application or a concrete runtime policy.

| Package | Composition |
| --- | --- |
| howl-app | Local-only Zig/SDL daily terminal |
| howl-cli | command-line entrypoint, including howl server run |
| howl-host | direct Vulkan/Wayland performance canary |
| howl-odin | Odin/SDL desktop canary |
| howl-flutter | Flutter frontend and its native bridge |
| howl-web | browser frontend, gateway and internal Wasm proof packages |

The optional Server implementation belongs to [mods/server](../mods/server/README.md).
The CLI selects its runtime module without adding another executable.

Frontend-specific bridges and proof subpackages stay with their owning host.
Moving here changes source organization, not their qualification status.
Each host owns its version; the root [snapshot](../snapshot.json) names the tested set.
