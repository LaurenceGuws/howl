Below is an implementation specification only. Do not treat any slice as permission to preserve compatibility aliases.
Fixed sprint order
1. Move host false buckets first.
2. Clean render ABI/frame ownership.
3. Delete final host terminal_panel.zig shape by cutting to terminal/context.zig.
Slice 1: Move host terminal/runtime/* into true owners
Source files
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/runtime/thread.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/runtime/progress.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/runtime/fonts_linux.zig
- /home/home/personal/projects/howl/howl-linux-host/src/main.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/terminal_panel.zig
- /home/home/personal/projects/howl/howl-linux-host/src/test/host.zig
- /home/home/personal/projects/howl/howl-linux-host/src/test/integration_entry.zig
Moves
1. Move:
- From: /home/home/personal/projects/howl/howl-linux-host/src/terminal/runtime/thread.zig
- To: /home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/wait_thread.zig
2. Move:
- From: /home/home/personal/projects/howl/howl-linux-host/src/terminal/runtime/progress.zig
- To: /home/home/personal/projects/howl/howl-linux-host/src/terminal/pty/pump.zig
3. Move:
- From: /home/home/personal/projects/howl/howl-linux-host/src/terminal/runtime/fonts_linux.zig
- To: /home/home/personal/projects/howl/howl-linux-host/src/terminal/render/fonts_linux.zig
Symbol updates
thread.zig -> pty/wait_thread.zig
Keep symbols, because names are already precise enough once under PTY ownership:
- State
- progressThreadMain
- wakePending
- ackWake
Rename only if worker chooses a direct cutover with all call sites:
- progressThreadMain -> waitThreadMain
If renamed, update:
- TerminalPanel.startRuntime() line 442 currently calls runtime_thread.progressThreadMain.
progress.zig -> pty/pump.zig
Keep:
- Outcome
- driveOnce
This file currently owns bounded PTY/VT progress, not generic runtime:
- pumpTransportSlice()
- progressRuntimeLocked()
- drainTerminalReplyLocked()
Do not rename to runtime or progress directory again.
fonts_linux.zig -> terminal/render/fonts_linux.zig
Keep:
- ResolvedFonts
- resolve()
This file uses render ABI constant HOWL_RENDER_MAX_FALLBACK_FONTS and belongs under render host-side support.
Import changes
In /home/home/personal/projects/howl/howl-linux-host/src/main.zig:
- Replace:
- const runtime_thread = @import("terminal/runtime/thread.zig");
- With:
- const pty_wait_thread = @import("terminal/pty/wait_thread.zig");
Update call sites:
- runtime_thread.wakePending(tab) -> pty_wait_thread.wakePending(tab)
In /home/home/personal/projects/howl/howl-linux-host/src/terminal/terminal_panel.zig:
- Replace:
- const runtime_progress = @import("runtime/progress.zig");
- const runtime_thread = @import("runtime/thread.zig");
- const fonts_linux = @import("runtime/fonts_linux.zig");
- With:
- const pty_pump = @import("pty/pump.zig");
- const pty_wait_thread = @import("pty/wait_thread.zig");
- const fonts_linux = @import("render/fonts_linux.zig");
Update call sites:
- runtime_thread.State -> pty_wait_thread.State
- runtime_thread.ackWake() -> pty_wait_thread.ackWake()
- runtime_thread.wakePending() -> pty_wait_thread.wakePending()
- runtime_thread.progressThreadMain -> pty_wait_thread.progressThreadMain or renamed target
- runtime_progress.Outcome -> pty_pump.Outcome
- runtime_progress.driveOnce() -> pty_pump.driveOnce()
In /home/home/personal/projects/howl/howl-linux-host/src/test/host.zig:
- Replace:
- pub const Thread = @import("../terminal/runtime/thread.zig");
- With:
- pub const PtyWaitThread = @import("../terminal/pty/wait_thread.zig");
In /home/home/personal/projects/howl/howl-linux-host/src/test/integration_entry.zig:
- Replace:
- _ = @import("host").Thread;
- With:
- _ = @import("host").PtyWaitThread;
No compatibility Thread alias.
Tests
Tests remain with moved files:
- Thread tests move with pty/wait_thread.zig.
- Progress tests move with pty/pump.zig.
- Font tests move with terminal/render/fonts_linux.zig.
Invariants
- Background PTY thread only wakes owner thread; it never drives terminal mutation itself.
- Bounded PTY/VT work remains in pty/pump.zig.
- Font path resolution remains host-side render support, not runtime.
Verification commands
From /home/home/personal/projects/howl:
- zig build check
- zig build test:unit
- zig build test:integration
Grep gates
Must return no matches:
- terminal/runtime
- runtime/thread.zig
- runtime/progress.zig
- runtime/fonts_linux.zig
Allowed temporary matches after Slice 1:
- TerminalPanel
- terminal/host
- terminal_panel.zig
Slice 2: Move host terminal/host/* into true owners
Source files
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/input.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/font_size.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/geometry.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/scroll.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/scrollbar.zig
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/terminal_panel.zig
Moves
1. Move:
- From: /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/input.zig
- To: /home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/input.zig
2. Move:
- From: /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/font_size.zig
- To: /home/home/personal/projects/howl/howl-linux-host/src/terminal/render/font_size.zig
3. Move:
- From: /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/geometry.zig
- To: /home/home/personal/projects/howl/howl-linux-host/src/terminal/render/frame_layout.zig
4. Move:
- From: /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/scroll.zig
- To: /home/home/personal/projects/howl/howl-linux-host/src/terminal/vt/viewport.zig
5. Move:
- From: /home/home/personal/projects/howl/howl-linux-host/src/terminal/host/scrollbar.zig
- To: /home/home/personal/projects/howl/howl-linux-host/src/window/scrollbar.zig
Symbol updates
terminal/vt/input.zig
Keep symbols:
- key
- mods
- mouseKind
- mouseButton
- buttons
- publishPaste
- publishKey
- publishMouse
- publishFocus
- wouldReportUnpressedMouseMotion
- wouldReportMouse
Ownership: VT input encoding plus PTY publication.
terminal/render/font_size.zig
Keep:
- adjust
- toggleStress
- reset
Ownership: render font-size mutation.
terminal/render/frame_layout.zig
Keep:
- State
- init
- resize
- maybeCommitGridResize
- syncFrameLayout
- frameLayoutSnapshot
- syncCurrentFrameLayout
- snapshotFrameLayoutLocked
Ownership: render frame-layout synchronization and PTY/VT resize consequences.
terminal/vt/viewport.zig
Keep:
- State
- invalidate
- setFocused
- handlePages
- byRows
- handleMouse
- wantsPassiveHoverWake
- layout
Update import inside this file:
- const scrollbar = @import("scrollbar.zig");
- To:
- const scrollbar = @import("../../window/scrollbar.zig");
window/scrollbar.zig
Keep:
- Model
- View
- MouseResult
- State
- Geometry
- focus
Ownership: pure presentation overlay model.
Import changes in terminal_panel.zig
Replace:
- const font_size = @import("host/font_size.zig");
- const geometry = @import("host/geometry.zig");
- const term_input = @import("host/input.zig");
- const scroll = @import("host/scroll.zig");
With:
- const font_size = @import("render/font_size.zig");
- const frame_layout = @import("render/frame_layout.zig");
- const term_input = @import("vt/input.zig");
- const viewport = @import("vt/viewport.zig");
Then update all symbols:
- geometry.State -> frame_layout.State
- geometry.init -> frame_layout.init
- geometry.resize -> frame_layout.resize
- geometry.maybeCommitGridResize -> frame_layout.maybeCommitGridResize
- geometry.syncFrameLayout -> frame_layout.syncFrameLayout
- geometry.frameLayoutSnapshot -> frame_layout.frameLayoutSnapshot
- geometry.syncCurrentFrameLayout -> frame_layout.syncCurrentFrameLayout
- geometry.snapshotFrameLayoutLocked -> frame_layout.snapshotFrameLayoutLocked
- scroll.State -> viewport.State
- scroll.handlePages -> viewport.handlePages
- scroll.wantsPassiveHoverWake -> viewport.wantsPassiveHoverWake
- scroll.layout -> viewport.layout
- scroll.setFocused -> viewport.setFocused
- scroll.invalidate -> viewport.invalidate
- scroll.handleMouse -> viewport.handleMouse
- scroll.byRows -> viewport.byRows
Tests
Tests move with files. Specific test rename pressure:
- "frame layout request ignores logical size" remains but should import/use frame_layout.
- Scrollbar tests move under window/scrollbar.zig.
- Font-size tests remain under terminal/render/font_size.zig.
Invariants
- No terminal/host namespace remains.
- VT input encoding remains under terminal/vt.
- Render layout/font-size mutation remains under terminal/render.
- Scrollbar overlay model is window-owned.
- Viewport/scrollback mutation is VT-owned.
Verification commands
From /home/home/personal/projects/howl:
- zig build check
- zig build test:unit
- zig build test:integration
Grep gates
Must return no matches:
- terminal/host
- host/input.zig
- host/font_size.zig
- host/geometry.zig
- host/scroll.zig
- host/scrollbar.zig
Allowed temporary matches after Slice 2:
- TerminalPanel
- terminal_panel.zig
Slice 3: Render ABI cleanup, no duplicated C type mirrors
Source files
- /home/home/personal/projects/howl/howl-render/include/howl_render.h
- /home/home/personal/projects/howl/howl-render/src/ffi.zig
- /home/home/personal/projects/howl/howl-render/src/libhowl_render.zig
- /home/home/personal/projects/howl/howl-render/build.zig
- /home/home/personal/projects/howl/howl-render/src/test/ffi.zig
- /home/home/personal/projects/howl/howl-render/src/frame/publication.zig
Required build changes
In /home/home/personal/projects/howl/howl-render/build.zig, add include paths to ffi_mod:
- ffi_mod.addIncludePath(b.path("include"));
- ffi_mod.addIncludePath(b.path("../howl-vt/include"));
This is required because ffi.zig must use @cImport against shipped C headers instead of mirroring ABI structs.
Required FFI change
In /home/home/personal/projects/howl/howl-render/src/ffi.zig, introduce:
const c = @cImport({
    @cInclude("howl_render.h");
});
Then replace all duplicated Ffi* and ABI enum/type mirrors with c.*.
Delete these mirrors from ffi.zig:
- c_size_t
- HowlRenderSurfaceText
- HowlRenderPreparedSurfaceObject
- SurfaceTextHandle
- PreparedSurfaceHandle
- HowlRenderCallStatus
- HowlRenderPrepareStatus
- HowlRenderSubmitStatus
- HowlRenderSubmitDecisionStatus
- every Ffi* extern struct
Use direct C ABI types:
- c.HowlRenderSurfaceTextHandle
- c.HowlRenderPreparedSurfaceHandle
- c.HowlRenderPixelSize
- c.HowlRenderFrameLayoutResult
- c.HowlRenderSurfaceTextConfig
- c.HowlRenderGeometry
- c.HowlRenderGeometryResponse
- c.HowlRenderPublishSlot
- c.HowlRenderPublishSlotCommit
- c.HowlRenderVtPublishResult
- c.HowlRenderPrepareRequest
- c.HowlRenderPreparedFrame
- c.HowlRenderPendingState
- c.HowlRenderPreparedSurfaceInfo
- c.HowlRenderPreparedSurfaceBuffer
- c.HowlRenderPreparedSurfaceDiagnostics
- c.HowlRenderSurfaceExecutionInput
- c.HowlRenderSurfaceFeedback
Status values must use C constants:
- c.HOWL_RENDER_CALL_OK
- c.HOWL_RENDER_CALL_MISSING_HANDLE
- c.HOWL_RENDER_CALL_INVALID_ARGUMENT
- c.HOWL_RENDER_CALL_FAILED
- c.HOWL_RENDER_PREPARE_IDLE
- c.HOWL_RENDER_PREPARE_READY
- c.HOWL_RENDER_PREPARE_FAILED
- c.HOWL_RENDER_SUBMIT_DECISION_*
- c.HOWL_RENDER_SUBMIT_*
Function return types currently returning Zig enums must return the C enum type or c_int consistently. Preferred direct cutover:
- takePrepareRequest() returns c_int
- takeSubmitDecision() returns c_int
- takeSubmitHandle() returns c_int
- prepareHandle() returns c_int
- submit() returns c_int
- submitHandle() returns c_int
No compatibility Zig enum aliases.
Publication mirror cleanup
Current /home/home/personal/projects/howl/howl-render/src/frame/publication.zig duplicates VT C types:
- Rgb8
- Color
- RenderColorState
- CellFlags
- CellAttrs
- Cell
- SelectionPos
- Selection
Delete this file as a C mirror.
Replace internal usage with one of two direct options:
Preferred option
Use c.HowlVtSurfaceCell, c.HowlVtRenderColorState, and c.HowlVtSelection at the FFI publication boundary only, then translate immediately into semantic render-owned internal structs in the new surface publication owner.
Minimum acceptable option for this sprint
Move these types into a new semantic owner and rename them so they are not C mirrors:
- Target file:
- /home/home/personal/projects/howl/howl-render/src/surface/publication_source.zig
- Types:
- Rgb8 -> SourceRgb
- Color -> SourceColor
- RenderColorState -> SourceColors
- CellFlags -> SourceCellFlags
- CellAttrs -> SourceCellAttrs
- Cell -> SourceCell
- SelectionPos -> SourceSelectionPoint
- Selection -> SourceSelection
But this option must not preserve field-for-field C naming blindly. The FFI conversion functions must be the only C-layout translators.
Test changes
In /home/home/personal/projects/howl/howl-render/src/test/ffi.zig:
- Replace all ffi.Ffi* uses with c.HowlRender*.
- Delete compile-time @sizeOf(ffi.Ffi*) == @sizeOf(c.HowlRender*) checks because the Zig mirror no longer exists.
- Keep tests that assert the shipped C constants and behavior.
Examples:
- ffi.FfiPendingState -> c.HowlRenderPendingState
- ffi.FfiPreparedSurfaceInfo -> c.HowlRenderPreparedSurfaceInfo
- ffi.FfiSurfaceExecutionInput -> c.HowlRenderSurfaceExecutionInput
- ffi.FfiVtCell -> c.HowlVtSurfaceCell
- ffi.FfiVtCellAttrs -> c.HowlVtSurfaceCellAttrs
Invariants
- ffi.zig translates C ABI only.
- No Zig duplicate of shipped C structs remains.
- Public product contract remains /home/home/personal/projects/howl/howl-render/include/howl_render.h.
- Host still consumes render only via C ABI.
Verification commands
From /home/home/personal/projects/howl:
- zig build check
- zig build test:abi
- zig build test:unit
- zig build test:integration
Grep gates
Must return no matches in /home/home/personal/projects/howl/howl-render/src:
- pub const Ffi
- extern struct
- HowlRenderCallStatus =
- HowlRenderPrepareStatus =
- HowlRenderSubmitStatus =
- HowlRenderSubmitDecisionStatus =
Allowed:
- @cImport
- C ABI type references through c.HowlRender* and c.HowlVt*
Slice 4: Render frame namespace deletion
Source directory to delete
- /home/home/personal/projects/howl/howl-render/src/frame/
Target directory
- /home/home/personal/projects/howl/howl-render/src/surface/
File moves and renames
Move:
- frame/surface.zig
- To: surface/types.zig
- frame/surface_text.zig
- To: surface/text.zig
- frame/pipeline.zig
- To: surface/tokens.zig
- frame/queue.zig
- To: surface/flow.zig
- frame/prepared_surface_owner.zig
- To: surface/prepared_owner.zig
- frame/surface_buffer.zig
- To: surface/buffer.zig
- frame/input.zig
- To: surface/input.zig
- frame/geometry.zig
- To: surface/geometry.zig
- frame/submit_feedback.zig
- To: surface/submit_feedback.zig
- frame/clip_rect.zig
- To: surface/clip_rect.zig
- frame/rgba.zig
- To: surface/rgba.zig
- frame/publication.zig
- Delete if Slice 3 preferred path completed.
- Otherwise move to surface/publication_source.zig with semantic renames from Slice 3.
Import changes
In /home/home/personal/projects/howl/howl-render/src/ffi.zig:
- frame/pipeline.zig -> surface/tokens.zig
- frame/prepared_surface_owner.zig -> surface/prepared_owner.zig
- frame/surface_text.zig -> surface/text.zig
- frame/queue.zig -> surface/flow.zig
- frame/surface.zig -> surface/types.zig
- frame/publication.zig -> deleted or surface/publication_source.zig
In /home/home/personal/projects/howl/howl-render/src/text/contract.zig:
- ../frame/rgba.zig -> ../surface/rgba.zig
In /home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/support.zig:
- ../../../frame/surface_text.zig -> ../../../surface/text.zig
- ../../../frame/surface.zig -> ../../../surface/types.zig
In /home/home/personal/projects/howl/howl-render/src/text/font/ft_hb/glyph_raster.zig:
- ../../../frame/surface_text.zig -> ../../../surface/text.zig
In /home/home/personal/projects/howl/howl-render/src/test/unit.zig:
- ../frame/geometry.zig -> ../surface/geometry.zig
- ../frame/surface.zig -> ../surface/types.zig
In /home/home/personal/projects/howl/howl-render/src/test/benchmark.zig:
- ../frame/surface.zig -> ../surface/types.zig
In /home/home/personal/projects/howl/howl-render/src/test/ffi.zig:
- ../frame/surface_text.zig -> ../surface/text.zig
Symbol rename pressure
Use direct owner names:
- pipeline.DamageKind -> tokens.DamageKind
- pipeline.SnapshotToken -> tokens.SnapshotToken
- pipeline.PreparedFrame -> tokens.PreparedSurfaceToken or keep PreparedFrame only if the C ABI still uses frame vocabulary.
- queue.Flow -> flow.State or flow.SurfaceFlow
- queue.PublicationSource -> flow.PublicationSource or publication_source.Source
- surface.PreparedSurface remains acceptable if in surface/types.zig.
Do not use:
- frame
- runtime
- host
- panel
- manager
- controller
Tests
Move tests with files. Update test names that include frame_input or frame geometry:
- "frame_input converts frame state to text scene input" -> "surface input converts VT source to text scene input"
- "frame geometry helpers derive grid deterministically" -> "surface geometry derives grid deterministically"
Invariants
- Render owns prepared render data and retained render state.
- Render does not own backend publication or presentation.
- submit means render consumes host execution feedback; it must not mean present/publish to backend.
Verification commands
From /home/home/personal/projects/howl:
- zig build check
- zig build test:unit
- zig build test:abi
Grep gates
Must return no matches in /home/home/personal/projects/howl/howl-render/src:
- @import("frame/
- @import("../frame
- src/frame
- /frame/
Slice 5: Final host context cutover, delete terminal_panel.zig
Source files
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/terminal_panel.zig
- /home/home/personal/projects/howl/howl-linux-host/src/main.zig
- /home/home/personal/projects/howl/howl-linux-host/src/test/host.zig
- /home/home/personal/projects/howl/howl-linux-host/src/test_root.zig
- /home/home/personal/projects/howl/howl-linux-host/src/test/integration_entry.zig
Move
- From:
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/terminal_panel.zig
- To:
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/context.zig
Type rename
- TerminalPanel -> Context
No aliases.
Main import changes
In /home/home/personal/projects/howl/howl-linux-host/src/main.zig:
Replace:
- const TerminalPanel = @import("terminal/terminal_panel.zig").TerminalPanel;
With:
- const TerminalContext = @import("terminal/context.zig").Context;
Then update:
- TabSlots.panels -> contexts or terms
- [max_tabs]TerminalPanel -> [max_tabs]TerminalContext
- active_tabs: [max_tabs]*TerminalPanel -> [max_tabs]*TerminalContext
- fn items(self: *TabSlots) []*TerminalPanel -> []*TerminalContext
- activePanel() -> activeContext()
- activeTab() may remain because it refers to tab index, but returned type is *TerminalContext
- all TerminalPanel.* nested types:
- TerminalPanel.DrainInputOutcome -> TerminalContext.DrainInputOutcome
- TerminalPanel.TurnResult -> TerminalContext.TurnResult
- TerminalPanel.TurnStep -> TerminalContext.TurnStep
Do not leave activePanel helper name. It contains banned panel vocabulary.
Test export changes
In /home/home/personal/projects/howl/howl-linux-host/src/test/host.zig:
Replace:
- pub const TerminalPanel = @import("../terminal/terminal_panel.zig");
With:
- pub const TerminalContext = @import("../terminal/context.zig");
In /home/home/personal/projects/howl/howl-linux-host/src/test_root.zig:
Replace:
- pub const TerminalPanel = Host.TerminalPanel;
With:
- pub const TerminalContext = Host.TerminalContext;
In /home/home/personal/projects/howl/howl-linux-host/src/test/integration_entry.zig:
Replace:
- _ = @import("host").TerminalPanel;
With:
- _ = @import("host").TerminalContext;
No TerminalPanel alias.
Internal context.zig symbol updates
Within moved file:
- pub const TerminalPanel = struct -> pub const Context = struct
- TerminalPanelOps -> ContextOps
- TerminalPanel.DrainInputOutcome -> Context.DrainInputOutcome
- TerminalPanel.ScrollMouseOutcome -> Context.ScrollMouseOutcome
- Test fake names containing FakePanel -> FakeContext
- Function names using panel local variable -> context
Field names that are not exported but contain panel vocabulary should be renamed:
- panel local variables -> context
- panels array in main -> contexts
Keep user-facing tab vocabulary where it truly means tab.
Invariants
- terminal/context.zig is per-terminal aggregate only.
- It composes true owners:
- terminal/pty/*
- terminal/vt/*
- terminal/render/*
- window/*
- It must not become a new runtime, host, panel, manager, or controller bucket.
- Host still uses only shipped C ABI through terminal/c.zig.
Verification commands
From /home/home/personal/projects/howl:
- zig build check
- zig build test:unit
- zig build test:integration
- zig build test
Final grep gates
Must return no matches under /home/home/personal/projects/howl/howl-linux-host/src:
- terminal_panel
- TerminalPanel
- activePanel
- FakePanel
- terminal/runtime
- terminal/host
- /runtime/
- /host/
Must not find replacement banned owners:
- manager
- controller
- runtime2
- host2
- panel
Cross-slice blockers / questions
1. Render C import feasibility:
- /home/home/personal/projects/howl/howl-render/src/ffi.zig currently exports functions through /home/home/personal/projects/howl/howl-render/src/libhowl_render.zig.
- Moving FFI parameter/return types to @cImport requires adding render/vt include paths to the library module in /home/home/personal/projects/howl/howl-render/build.zig.
- If Zig rejects exporting functions whose signatures use @cImport enum types, use c_int for statuses and direct c.HowlRender* extern structs for data types.
2. Render publication mirror depth:
- /home/home/personal/projects/howl/howl-render/src/frame/publication.zig is a duplicate of howl-vt/include/howl_vt.h surface structs.
- Preferred cleanup is immediate C-boundary translation into semantic render-owned structs.
- Minimum acceptable cleanup is semantic renaming plus strict FFI-only C layout conversion, but this should be reviewed harshly because it can become a disguised mirror.
3. submit naming:
- C ABI currently exposes:
- howl_render_surface_text_submit
- howl_render_surface_text_submit_handle
- The scratchpad allows submit only as “host consumed prepared output; render may update retained render-owned state.”
- Do not rename C ABI unless the sprint explicitly includes ABI breaking changes across host calls and tests.
4. Final Context size:
- /home/home/personal/projects/howl/howl-linux-host/src/terminal/terminal_panel.zig is still a god object after movement.
- Slice 5 only deletes banned panel vocabulary and path. Further splitting should be follow-up unless Context continues to own behavior that clearly belongs to child owners.
