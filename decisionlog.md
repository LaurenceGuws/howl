# Captain's decisions

## Separate terminal primitives from the Sessions product family

Recorded 2 November 2026 from Captain's explanation of the earlier decision.
This is the rationale for the existing split, not a new migration instruction.

**Decision:** Server, its supporting protocol/client owners, and Flutter belong
in the sibling Howl Sessions project. Howl retains its embeddable terminal
primitives and direct-local application hosts.

**Why:** Server and Flutter began as canaries, but their bring-up increasingly
dictated Howl's scope. Moving them out protects the terminal core from
orchestration and host-specific concerns. This was an intentional ownership
boundary, not an invitation to reunify the repositories for convenience.

The separate product consumes explicit core interfaces. It must not make a
local Instance depend on Server or Session merely to host a terminal.

See [Howl Sessions decisions](https://github.com/LaurenceGuws/howl-sessions/blob/main/decisionlog.md) for the product
promotion and fresh Flutter host rationale. Neither promotion means that all
features are complete or production-qualified.
