# howl-host

howl-host is Howl's native Linux direct-embed performance canary. Its job is
to make the shortest owned terminal path fast, measurable, and mechanically
obvious. It is not a remote client, Server frontend, Session browser, or shared
UI framework.

    howl-host
      |
      +-- howl-instance
      |     +-- howl-pty
      |     +-- howl-vt
      |
      +-- howl-render   (-Dclient_sources=false)
      |     +-- howl-text
      |     +-- direct VT observation adapter
      |
      +-- howl-vk
      +-- howl-wayland

The command line has one route:

    howl-host FONT [--fallback FONT ...]

The Host creates one in-process Instance. Input directly services its PTY/VT
lifetime and submits typed Instance input. Render borrows the canonical
Terminal.Observation only while projecting one frame, then releases the borrow
before Vulkan/DRM or compositor waits. Geometry is an explicit direct Instance
mutation. History is projected directly from canonical VT state.

There is deliberately no howl-client, client transport, HWLS, server-client,
Server, Session, endpoint, socketpair, or remote-target path in this package.
Those capabilities solve attachment, orchestration, and constrained-client
problems elsewhere in Howl; they are not part of this performance canary.

The primary font is the sole cell-metric authority. Ordered
--fallback FONT arguments are consulted only when the primary does not cover a
complete shaped cluster. The current native text atlas is alpha-mask based, so
fallbacks must currently be ordinary outline/mono/gray faces rather than
color-bitmap emoji fonts.

Current foundation:

- one Wayland window owner;
- one in-process Instance owning one PTY and canonical VT;
- one dedicated Input owner that services PTY/VT progress independently of
  presentation;
- synchronized-output publication with bounded timeout and lifecycle wakeups;
- direct canonical observation with row-generation based retained updates;
- howl-text shaping/rasterization and the source-neutral howl-render core;
- Vulkan/DRM rendering with explicit-sync DMA-BUF presentation;
- three presentation slots reused only after exact compositor release;
- direct resize, mouse, keyboard, focus, history, graphics, and image projection.

The live loop bounds presentation backlog by compositor release while canonical
Instance progress remains independently serviced. That makes Host the place to
measure throughput, latency under throughput, CPU/GPU cost, and memory without a
transport or orchestration layer muddying the result.
