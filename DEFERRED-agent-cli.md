# DEFERRED: agent-side Howl session CLI

> **On ice — 2026-08-27.**
>
> Do not implement this until Captain explicitly reopens it. The session wire is
> already the authority; this CLI is only another client.

## Goal

Give agents a small non-GUI way to attach to an existing `howl-sessiond` endpoint
using the frozen Howl session v1 byte stream. It should let an agent observe and
control the same canonical PTY/VT session that Captain Control and other clients
see, without inventing a second terminal model or transport.

## Boundary

- `howl-sessiond` remains the PTY/VT/session authority.
- The CLI accepts an explicit ordered-byte-stream endpoint such as
  `tcp://127.0.0.1:PORT`; endpoint discovery and remote reachability are separate
  concerns.
- No SSH semantics, Remoter semantics, Cloudflare semantics, node discovery, or
  authentication policy belong in the session protocol client.
- No TUI is required for the first slice. Agent-facing output should be bounded,
  deterministic, and machine-readable where useful.
- Use the existing framing/session v1 contract and `protocol/v1-vectors.json` as
  acceptance authority. Do not fork the protocol for the CLI.

## First slice when thawed

Prove only enough operations for agent co-op:

1. connect and negotiate `hello` / `welcome`;
2. request one coherent `text_v1` observation and render a bounded textual/JSON
   representation;
3. submit exact bytes or paste input;
4. expose explicit resize-leader / resize and fixed signal operations;
5. reconnect to the same session without changing terminal authority.

A later `watch` mode can repeat request-driven observations, but it must preserve
Howl's existing rule that a slow observer never paces the PTY or canonical VT.

## Language

Language choice is intentionally deferred. Zig is attractive for one tiny native
binary beside `howl-sessiond`; Python is attractive for fast agent-side glue and
already has an independent vector decoder. Choose when thawed based on deployment
needs, not aesthetics. The wire contract must make either implementation boring.

## Relationship to Captain Control

Captain Control and this CLI should be peers: two clients of the same Howl session
wire. Neither should relay terminal state through the other. Shared reusable client
logic is welcome only where it does not make one product the authority for the
other.
