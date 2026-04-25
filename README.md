# Howl Workspace

Multi-repo workspace for the Howl terminal stack.

## Module Lanes

- `howl-vt-core` — terminal parser/model/runtime semantics
- `howl-session` — session lifecycle + transport orchestration
- `howl-term-surface` — embeddable terminal surface composition boundary
- `render/howl-render-core` — backend-agnostic renderer core
- `render/howl-render-*` — renderer backends (`gl`, `gles`, `metal`, `vulkan`, `software`)
- `howl-hosts/howl-sdl-host` — Linux SDL host application

## Cross-Module Authority

Use parent architecture docs for cross-module ownership and dependency rules:

- `architecture_docs/MODULE_MAP.md`
- `architecture_docs/DEPENDENCY_RULES.md`
- `architecture_docs/INTEGRATION_FLOW.md`

Child repos should document local scope and invariants only.
