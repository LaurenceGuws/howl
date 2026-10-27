# Hosts

Hosts compose modules into an application or a concrete runtime policy.

| Package | Composition |
| --- | --- |
| howl-app | Local-only Zig/SDL daily terminal |
| howl-host | direct Vulkan/Wayland performance canary |
| howl-flutter | **inactive historical reference only**; not a build, release or install entrypoint |

The CLI, Web and Odin products moved to howl-sessions with the Server family.
The original Flutter source is deliberately left here temporarily for its
bring-up evidence. Its native, Dart, iOS and installation scripts are unsupported;
only howl-app and howl-host are maintained direct-local host packages here.

Each active host owns its version; the root [snapshot](../snapshot.json) names
only the actively qualified package set.
