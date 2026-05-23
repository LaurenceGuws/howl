# Scratchpad

Purpose: comprehensive issue list for features implemented in VT or lower owners that become no-op above VT, or are left out of the product ABI without a justified boundary reason.

Rule:

- Ghostty first.
- Alacritty second.
- TigerBeetle third.
- The ABIs are the product.

## Cross-Repo

### 1. Hyperlink targets stop at `link_id`
- Description
  - VT interns hyperlink URIs and stamps visible cells with `link_id`, but the shipped ABI exposes no way to resolve that id back to a URI. Render preserves the id only transiently and the host has no lookup seam, so OSC 8 links can exist below while hover/open stays a no-op above VT.
- Complete picture needed
  - An ABI contract for hyperlink target lookup and lifetime tied to visible surface snapshots, plus a host-owned hover/open path that can resolve a cell back to a URI.
- Howl truth
  - `howl-vt/src/host/apply.zig:33-34`
  - `howl-vt/src/host/state.zig:52-53`
  - `howl-vt/src/host/state.zig:116-150`
  - `howl-vt/src/ffi.zig:187-203`
  - `howl-vt/include/howl_vt.h:111-123`
  - `howl-render/include/howl_render.h:153-165`
  - `howl-render/src/frame/surface_text_ffi.zig:522-534`
  - `howl-linux-host/src/input/input.zig:75-80`
  - `howl-linux-host/src/terminal/terminal_panel.zig:193-196`
- Reference locations
  - `utils/dev_references/terminals/ghostty/src/terminal/c/grid_ref.zig:94-123`
  - `utils/dev_references/terminals/ghostty/src/terminal/c/grid_ref.zig:221-249`
  - `utils/dev_references/terminals/ghostty/src/Surface.zig:1607-1673`
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:1233-1263`

### 2. VT-owned selection has no product boundary above VT
- Description
  - VT design and code treat selection as VT-owned truth, but the shipped C ABI exposes no selection contract. Render also has no selection ingress, and the host exposes no selection UX/copy path. Selection state therefore exists below but becomes absent above the ABI.
- Complete picture needed
  - A C ABI selection contract across viewport/history coordinates, plus render and host paths for selection presentation and copy behavior, or an explicit boundary statement that selection is intentionally out of scope.
- Howl truth
  - `howl-vt/design.md:64-67`
  - `howl-vt/design.md:161-189`
  - `howl-vt/src/selection.zig:3-10`
  - `howl-vt/src/selection/state.zig:12-97`
  - `howl-vt/include/howl_vt.h:186-238`
  - `howl-render/design.md:113-115`
  - `howl-render/include/howl_render.h:344-357`
  - `howl-linux-host/src/terminal/terminal_panel.zig:169-181`
  - `howl-linux-host/src/main.zig:525-537`
- Reference locations
  - `utils/dev_references/terminals/ghostty/src/terminal/c/selection.zig:4-16`
  - `utils/dev_references/terminals/ghostty/src/terminal/Selection.zig:23-35`
  - `utils/dev_references/terminals/ghostty/src/renderer/generic.zig:2802-2857`
  - `utils/dev_references/terminals/alacritty/alacritty/src/input/mod.rs:82-141`

### 3. OSC 52 clipboard requests stop below the host seam
- Description
  - VT implements clipboard retention and exposes `howl_vt_terminal_drain_pending_clipboard`, but the host never drains clipboard requests into platform clipboard behavior. Clipboard write support therefore exists below VT, but becomes a no-op above the current host/ABI flow.
- Complete picture needed
  - A host-owned clipboard handoff path that drains pending clipboard payloads after VT feed and applies policy, plus request/reply plumbing if clipboard reads are meant to work too.
- Howl truth
  - `howl-vt/include/howl_vt.h:208-215`
  - `howl-vt/src/host/state.zig:162-188`
  - `howl-vt/src/ffi.zig:402-418`
  - `howl-vt/src/test/terminal_osc_colors.zig:82-135`
  - `howl-linux-host/src/config/terminal.zig:22-29`
  - `howl-linux-host/src/window/window.zig:176-180`
  - `howl-linux-host/src/terminal/runtime/progress.zig:149-182`
- Reference locations
  - `utils/dev_references/terminals/ghostty/src/Surface.zig:6040-6059`
  - `utils/dev_references/terminals/ghostty/src/Surface.zig:6140-6169`
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:1902-1911`

### 5. Dynamic terminal color state never becomes render truth
- Description
  - VT implements OSC 4/10-19 style dynamic palette and special terminal colors, but render still resolves defaults from a fixed theme and there is no ABI path for VT-owned color state. Dynamic default fg/bg, cursor color, and related color state become visual no-ops above VT.
- Complete picture needed
  - An ABI-visible color-state contract from VT to render/host for the render-relevant palette and special colors, replacing render-local fixed defaults where VT owns the truth.
- Howl truth
  - `howl-vt/src/control/osc_color.zig:10-24`
  - `howl-vt/src/control/osc_color.zig:304-379`
  - `howl-vt/src/host/state.zig:208-210`
  - `howl-vt/include/howl_vt.h:87-170`
  - `howl-render/src/frame/input.zig:9-18`
  - `howl-render/src/frame/input.zig:52-67`
  - `howl-render/src/frame/input.zig:107-123`
  - `howl-render/src/frame/input.zig:319-324`
- Reference locations
  - `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:312-360`
  - `utils/dev_references/terminals/ghostty/src/renderer/generic.zig:2046-2085`
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:113-150`

## howl-vt

### 6. Kitty graphics state is implemented in VT but not exportable above VT
- Description
  - VT retains kitty graphics images, placements, frames, and uploads, but the shipped ABI exposes only text surface, pending output, clipboard drain, and input encoding. There is no ABI surface for a renderer or host to consume retained graphics state.
- Complete picture needed
  - An ABI-level contract for kitty graphics state and lifecycle relative to visible surface publication, or an explicit boundary statement that graphics are not part of the product ABI.
- Howl truth
  - `howl-vt/src/kitty/graphics.zig:17-25`
  - `howl-vt/src/kitty/graphics.zig:113-149`
  - `howl-vt/src/kitty/graphics.zig:195-260`
  - `howl-vt/src/kitty/state.zig:64-86`
  - `howl-vt/src/test/terminal_graphics.zig:18-101`
  - `howl-vt/include/howl_vt.h:83-244`
- Reference locations
  - `utils/dev_references/terminals/ghostty/src/lib_vt.zig:244-259`
  - `utils/dev_references/terminals/ghostty/src/terminal/c/terminal.zig:577-606`

### 7. OSC 52 clipboard read/query has no reply path through the ABI
- Description
  - VT retains clipboard payloads for writes, but clipboard read/query semantics are not completed through the ABI. Query behavior clears without yielding a host request/reply loop, leaving clipboard reads absent above VT.
- Complete picture needed
  - An ABI contract for clipboard read requests and reply injection, including target identity and encoded response flow back to VT.
- Howl truth
  - `howl-vt/src/xterm/osc.zig:36-56`
  - `howl-vt/src/host/state.zig:162-188`
  - `howl-vt/src/test/terminal_osc_colors.zig:82-120`
  - `howl-vt/include/howl_vt.h:211-214`
- Reference locations
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/term/mod.rs:1724-1746`
  - `utils/dev_references/terminals/ghostty/src/terminal/stream_terminal.zig:23-29`

## howl-pty

### 8. Child exit and transport-stop truth are collapsed out of the PTY ABI
- Description
  - The PTY owner detects child death and transport outcomes internally, but the shipped ABI reduces wait/read truth to generic booleans and byte counts. Above the seam, host/runtime code cannot distinguish timeout, kick-wake, EOF, child exit, or transport failure, and cannot obtain exit status.
- Complete picture needed
  - A typed lifecycle/result contract at the ABI boundary, including child-exited vs timed-out vs kicked vs transport-failed outcomes and exit-status metadata.
- Howl truth
  - `howl-pty/src/pty/pty_posix_owner.zig:155-170`
  - `howl-pty/src/session.zig:346-364`
  - `howl-pty/src/session.zig:440-468`
  - `howl-pty/src/ffi.zig:16-49`
  - `howl-pty/include/howl_pty.h:43-76`
  - `howl-pty/include/howl_pty.h:91-101`
- Reference locations
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs:382-402`
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/event_loop.rs:256-270`
  - `utils/dev_references/terminals/ghostty/src/termio/Exec.zig:284-297`

### 9. PTY resize success does not mean child-visible size was applied
- Description
  - Session resize updates requested geometry and reports success across the ABI even when the underlying PTY transport reports not-started or resize failure. Above the seam, geometry truth can be false-positive.
- Complete picture needed
  - ABI-visible applied-vs-requested resize state, or a typed resize result/error contract that reports transport application failure explicitly.
- Howl truth
  - `howl-pty/src/session.zig:100-116`
  - `howl-pty/src/session.zig:494-519`
  - `howl-pty/src/ffi.zig:143-147`
  - `howl-pty/include/howl_pty.h:43-52`
- Reference locations
  - `utils/dev_references/terminals/alacritty/alacritty_terminal/src/tty/unix.rs:406-419`
  - `utils/dev_references/terminals/ghostty/src/termio/Termio.zig:463-472`

### 10. PTY control-signal ABI lacks foreground-process identity truth
- Description
  - The public ABI exposes typed control signals, but not the foreground/job identity needed to know what is being signaled. Signal-target semantics remain incomplete above the PTY boundary.
- Complete picture needed
  - ABI-visible PTY process identity or foreground-group truth, plus explicit signal-target semantics tied to that truth.
- Howl truth
  - `howl-pty/src/pty/pty_posix_owner.zig:132-138`
  - `howl-pty/src/pty/pty_posix_owner.zig:296-301`
  - `howl-pty/src/pty/pty_platform.zig:98-129`
  - `howl-pty/include/howl_pty.h:26-32`
  - `howl-pty/include/howl_pty.h:93`
- Reference locations
  - `utils/dev_references/terminals/ghostty/src/pty.zig:268-317`
  - `utils/dev_references/terminals/ghostty/src/apprt/embedded.zig:1713-1727`

## howl-render

### 11. VT cell style and visibility attrs are dropped before scene prep
- Description
  - Render intake sees ABI cell attributes like bold, dim, italic, inverse, invisible, and link id, but later contracts collapse cells down to a narrower shape and renderables are forced to regular presentation. Style and visibility features implemented in VT become no-ops above the render seam.
- Complete picture needed
  - A render cell contract that preserves style, visibility, and presentation metadata from ABI ingestion through scene building.
- Howl truth
  - `howl-render/src/frame/surface.zig:153-181`
  - `howl-render/src/frame/surface_text_ffi.zig:514-535`
  - `howl-render/src/frame/input.zig:156-181`
  - `howl-render/src/text/contract.zig:76-86`
  - `howl-render/src/text/direct_normal.zig:289-308`
- Reference locations
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:214-219`
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:329-363`
  - `utils/dev_references/terminals/alacritty/alacritty/src/renderer/text/mod.rs:142-151`

## howl-linux-host

### 12. Dynamic VT title never reaches the actual SDL window title
- Description
  - VT title changes are retained and used for tab labels, but the SDL window title is fixed at creation time and never updated. Dynamic title support therefore exists below but is not carried through host presentation.
- Complete picture needed
  - An explicit host policy for active-tab title ownership of the SDL window title, and a post-create window-title update path if that policy is desired.
- Howl truth
  - `howl-linux-host/src/main.zig:203-207`
  - `howl-linux-host/src/main.zig:398-408`
  - `howl-linux-host/src/terminal/terminal_panel.zig:212-223`
  - `howl-linux-host/src/window/window.zig:36-52`
  - `howl-linux-host/src/window/window.zig:130-137`
  - `howl-linux-host/src/terminal/runtime/progress.zig:149-163`
- Reference locations
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:1867-1877`
  - `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:298-309`

### 13. Cursor blink state is lost at the VT surface and render seam
- Description
  - VT tracks cursor `shape` and `blink`, but the shipped surface contract exports only shape and visibility. Render consumes only static shape, so DECSCUSR blink variants are impossible to present above VT.
- Complete picture needed
  - Carry VT cursor `blink` truth through the shipped ABI, keep host-owned blink cadence as presentation policy, and add a host-configured default cursor style/blink policy that seeds VT default/reset behavior without overriding runtime DECSCUSR truth.
- Howl truth
  - `howl-vt/src/screen/cursor.zig:7-12`
  - `howl-vt/src/screen/apply.zig:149-157`
  - `howl-vt/include/howl_vt.h:140-145`
  - `howl-vt/src/ffi.zig:258-269`
  - `howl-render/include/howl_render.h:177-182`
  - `howl-render/src/frame/input.zig:319-324`
  - `howl-render/src/text/scene.zig:335-348`
  - `howl-render/src/frame/queue.zig`
- Reference locations
  - `utils/dev_references/terminals/ghostty/src/terminal/c/render.zig:95-113`
  - `utils/dev_references/terminals/ghostty/src/config/Config.zig:859-893`
  - `utils/dev_references/terminals/ghostty/src/termio/stream_handler.zig:880-918`
  - `utils/dev_references/terminals/ghostty/src/Surface.zig`
  - `utils/official_docs/xterm/ctlseqs.html.md:1539-1547`
  - `utils/dev_references/terminals/alacritty/alacritty/src/display/content.rs:51-62`
  - `utils/dev_references/terminals/alacritty/alacritty/src/event.rs:1620-1645`
  - `utils/dev_references/terminals/alacritty/alacritty/src/window_context.rs:229-231`
