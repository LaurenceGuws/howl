#!/bin/sh
set -eu

fail() {
    printf '%s\n' "module_shape_error=$1" >&2
    exit 1
}

mark_open() {
    printf '%s\n' "module_shape_open=$1"
}

require_file() {
    test -f "$1" || fail "missing:$1"
}

require_max_lines() {
    file="$1"
    max="$2"
    lines=$(wc -l < "$file" | tr -d ' ')
    test "$lines" -le "$max" || fail "too_large:$file:${lines}>${max}"
}

reject_pattern() {
    file="$1"
    pattern="$2"
    if grep -Eq "$pattern" "$file"; then
        fail "forbidden_pattern:$file:$pattern"
    fi
}

require_pattern() {
    file="$1"
    pattern="$2"
    if ! grep -Eq "$pattern" "$file"; then
        fail "missing_pattern:$file:$pattern"
    fi
}

reject_tree_pattern() {
    dir="$1"
    pattern="$2"
    if grep -REn --include='*.zig' "$pattern" "$dir" >/dev/null 2>&1; then
        fail "forbidden_tree_pattern:$dir:$pattern"
    fi
}

reject_tree_pattern_java() {
    dir="$1"
    pattern="$2"
    if grep -REn --include='*.java' "$pattern" "$dir" >/dev/null 2>&1; then
        fail "forbidden_tree_pattern:$dir:$pattern"
    fi
}

require_package_root() {
    file="$1"
    max="$2"
    require_file "$file"
    require_max_lines "$file" "$max"
    reject_pattern "$file" 'pub fn main'
}

require_runtime_owner() {
    file="$1"
    owner_pattern="$2"
    require_file "$file"
    require_pattern "$file" "$owner_pattern"
}

require_catalog_root() {
    file="$1"
    max="$2"
    require_package_root "$file" "$max"
}

require_file "howl-vt-core/src/terminal.zig"
require_file "howl-session/src/session_namespace.zig"
require_file "howl-vt-core/src/vt_namespace.zig"
require_file "howl-render-core/src/render_namespace.zig"
require_file "howl-render-core/src/frame_metrics.zig"
require_file "howl-render-core/src/frame_pipeline.zig"
require_file "howl-render-core/src/frame_queue.zig"
require_file "howl-render-core/src/frame_snapshot.zig"
require_file "howl-term/src/term_namespace.zig"
require_file "howl-term/src/c_api/constants.zig"
require_file "howl-term/src/c_api/frame.zig"
require_file "howl-term/src/c_api/input.zig"
require_file "howl-term/src/c_api/lifecycle.zig"
require_file "howl-term/src/c_api/font.zig"
require_file "howl-term/src/c_api/viewport.zig"
require_file "howl-term/src/c_api/metrics.zig"
require_file "howl-term/src/c_api/surface.zig"
require_file "howl-term/src/runtime/thread.zig"
require_file "howl-term/src/runtime/query.zig"
require_file "howl-term/src/runtime/io_tick.zig"
require_file "howl-term/src/runtime/terminal_reply.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/thread.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/effects.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/frame.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/font_size.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/geometry.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/input_flow.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/lifecycle.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/links.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/query.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/scroll.zig"
require_file "howl-hosts/howl-linux-host/src/terminal/selection.zig"
if test -f "howl-term/src/wake/loop.zig"; then fail "forbidden_file:howl-term/src/wake/loop.zig"; fi
if test -f "howl-term/src/runtime/state.zig"; then fail "forbidden_file:howl-term/src/runtime/state.zig"; fi
if test -f "howl-term/src/c_api/state.zig"; then fail "forbidden_file:howl-term/src/c_api/state.zig"; fi
if test -f "howl-term/src/render/pipeline.zig"; then fail "forbidden_file:howl-term/src/render/pipeline.zig"; fi
if test -f "howl-term/src/render/queue.zig"; then fail "forbidden_file:howl-term/src/render/queue.zig"; fi
if test -f "howl-term/src/render/snapshot.zig"; then fail "forbidden_file:howl-term/src/render/snapshot.zig"; fi
if test -f "howl-hosts/howl-android-host/src/main/java/howl/term/terminal/NativeBinding.java"; then fail "forbidden_file:howl-hosts/howl-android-host/src/main/java/howl/term/terminal/NativeBinding.java"; fi
if test -f "howl-hosts/howl-android-host/src/main/java/howl/term/terminal/RenderTelemetry.java"; then fail "forbidden_file:howl-hosts/howl-android-host/src/main/java/howl/term/terminal/RenderTelemetry.java"; fi
if test -f "howl-hosts/howl-android-host/src/main/java/howl/term/widget/TerminalWidget.java"; then fail "forbidden_file:howl-hosts/howl-android-host/src/main/java/howl/term/widget/TerminalWidget.java"; fi

# Package roots stay small and delegate implementation to owned files.
require_catalog_root "howl-vt-core/src/howl_vt.zig" 80
require_package_root "howl-session/src/howl_session.zig" 120
require_catalog_root "howl-render-core/src/howl_render.zig" 120
require_catalog_root "howl-hosts/howl-linux-host/src/test_host.zig" 80

require_pattern "howl-vt-core/src/howl_vt.zig" '@import\("vt_namespace\.zig"\)'
require_pattern "howl-vt-core/src/howl_vt.zig" 'pub const VtCore = vt\.VtCore;'
require_pattern "howl-session/src/howl_session.zig" '@import\("session_namespace\.zig"\)'
require_pattern "howl-render-core/src/howl_render.zig" '@import\("render_namespace\.zig"\)'
require_pattern "howl-session/src/session_namespace.zig" 'pub const c_api = if \(options\.c_abi\) @import\("ffi\.zig"\) else void;'
require_pattern "howl-vt-core/src/vt_namespace.zig" 'pub const c_api = if \(options\.c_abi\) @import\("ffi\.zig"\) else void;'
require_pattern "howl-render-core/src/render_namespace.zig" 'pub const c_api = if \(options\.c_abi\) @import\("ffi\.zig"\) else void;'
require_pattern "howl-term/src/term_namespace.zig" 'pub const c_api = if \(options\.c_abi\) @import\("ffi\.zig"\) else void;'
require_pattern "howl-session/src/session_namespace.zig" '@import\("pty\.zig"\)'
require_pattern "howl-session/src/session.zig" 'pub const TransportPumpLimits = struct'
require_pattern "howl-session/src/session.zig" 'pub const TransportPumpMode = enum'
require_pattern "howl-session/src/session.zig" 'pub const TransportPumpResult = struct'
require_pattern "howl-session/src/session.zig" 'pub const OutboundInputPump = struct'
require_pattern "howl-session/src/session.zig" 'pub const OwnedTransportConfig = struct'
require_pattern "howl-session/src/session.zig" 'pub const PtyConfig = struct'
require_pattern "howl-session/src/session.zig" 'owned_transport: \?OwnedTransport'
require_pattern "howl-session/src/session.zig" 'pub fn pumpTransport'
require_pattern "howl-session/src/session.zig" 'pub fn pumpTransportMode'
require_pattern "howl-session/src/session.zig" 'pub fn pumpOutboundInput'
require_pattern "howl-session/src/session.zig" 'pub fn publishHostInputAndPump'
require_pattern "howl-session/src/session.zig" 'pub fn waitReadableAfterOutbound'
require_pattern "howl-session/src/session.zig" 'pub fn initOwnedTransport'
require_pattern "howl-session/src/session.zig" 'pub fn initPty'
require_pattern "howl-session/src/session.zig" 'pub fn isActive'
require_pattern "howl-session/src/session_namespace.zig" 'pub const TransportPumpLimits = runtime_mod\.TransportPumpLimits;'
require_pattern "howl-session/src/session_namespace.zig" 'pub const TransportPumpMode = runtime_mod\.TransportPumpMode;'
require_pattern "howl-session/src/session_namespace.zig" 'pub const OutboundInputPump = runtime_mod\.OutboundInputPump;'
require_pattern "howl-session/src/session_namespace.zig" 'pub const OwnedTransportConfig = runtime_mod\.OwnedTransportConfig;'
require_pattern "howl-session/src/session_namespace.zig" 'pub const PtyConfig = runtime_mod\.PtyConfig;'
require_pattern "howl-render-core/src/render_namespace.zig" '@import\("renderer\.zig"\)'
require_pattern "howl-render-core/src/render_core.zig" '@import\("frame_metrics\.zig"\)'
require_pattern "howl-render-core/src/render_core.zig" '@import\("frame_pipeline\.zig"\)'
require_pattern "howl-render-core/src/render_core.zig" '@import\("frame_queue\.zig"\)'
require_pattern "howl-render-core/src/render_core.zig" '@import\("frame_snapshot\.zig"\)'
require_pattern "howl-render-core/src/render_core.zig" 'pub const FramePipeline = frame_pipeline;'
require_pattern "howl-render-core/src/render_core.zig" 'pub const FrameQueue = frame_queue;'
require_pattern "howl-render-core/src/render_core.zig" 'pub const FrameSnapshot = frame_snapshot\.Snapshot;'
require_pattern "howl-render-core/src/render_core.zig" 'pub const PrepareMetrics = frame_metrics\.PrepareMetrics;'
require_pattern "howl-render-core/src/render_core.zig" 'pub const RenderMetrics = frame_metrics\.RenderMetrics;'
require_pattern "howl-render-core/src/render_core.zig" 'pub const FramePixels = types\.FramePixels;'
require_pattern "howl-render-core/src/renderer.zig" 'pub const FrameRecord = struct'
require_pattern "howl-render-core/src/renderer.zig" 'pub fn renderMetrics\(self: \*const FrameRecord, submitted: Submitted, render_us: u64\) render_core\.RenderMetrics'
require_pattern "howl-render-core/src/renderer.zig" 'pub fn submittedFrame\(self: \*const FrameRecord, submitted: Submitted\) render_core\.FramePipeline\.SubmittedFrame'
require_pattern "howl-term/src/term_namespace.zig" '@import\("terminal\.zig"\)'
reject_pattern "howl-session/src/session_namespace.zig" 'pub const c_api = @import\("ffi\.zig"\)'
reject_pattern "howl-vt-core/src/vt_namespace.zig" 'pub const c_api = @import\("ffi\.zig"\)'
reject_pattern "howl-render-core/src/render_namespace.zig" 'pub const c_api = @import\("ffi\.zig"\)'
reject_pattern "howl-term/src/term_namespace.zig" 'pub const c_api = @import\("ffi\.zig"\)'
reject_pattern "howl-session/src/session_namespace.zig" '^pub fn '
reject_pattern "howl-vt-core/src/vt_namespace.zig" '^pub fn '
reject_pattern "howl-render-core/src/render_namespace.zig" '^pub fn '
reject_pattern "howl-term/src/term_namespace.zig" '^pub fn '
reject_pattern "howl-vt-core/src/howl_vt.zig" 'pub const VtCore = struct'
reject_pattern "howl-vt-core/src/howl_vt.zig" '@import\("(input|grid|parser|snapshot|selection|terminal|ffi)\.zig"\)'
reject_pattern "howl-session/src/howl_session.zig" 'pub const Session = struct'
reject_pattern "howl-session/src/howl_session.zig" '@import\("(session|pty|ffi)\.zig"\)'
reject_pattern "howl-render-core/src/howl_render.zig" 'pub const RenderCore = struct'
reject_pattern "howl-render-core/src/howl_render.zig" '@import\("(render_core|renderer|ffi)\.zig"\)'

# Explicit exception: this is an executable owner, not a package index.
require_runtime_owner "howl-hosts/howl-linux-host/src/main.zig" 'pub fn main'

# howl-term root target: catalog-shaped root, not runtime owner body.
require_file "howl-term/src/howl_term.zig"
if grep -Eq 'pub const HowlTerm = struct' "howl-term/src/howl_term.zig"; then
    mark_open "howl_term_root_not_catalog"
else
    require_catalog_root "howl-term/src/howl_term.zig" 140
    require_pattern "howl-term/src/howl_term.zig" '@import\("term_namespace\.zig"\)'
    require_pattern "howl-term/src/howl_term.zig" 'pub const HowlTerm = [A-Za-z_][A-Za-z0-9_]*\.HowlTerm;'
    reject_pattern "howl-term/src/howl_term.zig" 'pub const HowlTerm = struct'
    reject_pattern "howl-term/src/howl_term.zig" '@import\("(terminal|ffi)\.zig"\)'
fi

# Public-surface tests should reference root declarations directly.
require_pattern "howl-vt-core/src/howl_vt.zig" 'refAllDecls\((@This\(\)|lib)\)'
if ! grep -Eq 'refAllDecls' "howl-render-core/src/howl_render.zig"; then mark_open "render_root_ref_all_decls_missing"; fi
if ! grep -Eq 'refAllDecls' "howl-session/src/howl_session.zig"; then mark_open "session_root_ref_all_decls_missing"; fi
if ! grep -Eq 'refAllDecls' "howl-term/src/howl_term.zig"; then mark_open "term_root_ref_all_decls_missing"; fi

# Layering: lower modules must not import upper modules.
reject_tree_pattern "howl-vt-core/src" '@import\("howl_(session|render|term)"\)'
reject_tree_pattern "howl-session/src" '@import\("(vt_core|howl_render|howl_term)"\)'
reject_tree_pattern "howl-render-core/src" '@import\("(vt_core|howl_session|howl_term)"\)'

# Hosts depend on howl-term for terminal runtime, not lower module packages.
reject_tree_pattern "howl-hosts/howl-linux-host/src" '@import\("(vt_core|howl_session|howl_render)"\)'
reject_tree_pattern "howl-term/src" '@import\("[^"]*(pty|pty/|pty_(platform|unix|android|test)|render_core|renderer)\.zig"\)'
reject_tree_pattern "howl-term/src" '@import\("[^"]*render/(pipeline|queue)\.zig"\)'
reject_tree_pattern "howl-term/src" '@import\("[^"]*render/snapshot\.zig"\)'
reject_tree_pattern "howl-hosts/howl-linux-host/src" '@import\("[^"]*(pty|pty/|pty_(platform|unix|android|test)|render_core|renderer|backend/(gl|gles))'
reject_tree_pattern_java "howl-hosts/howl-android-host/src/main/java" 'package howl\.term\.terminal;'
reject_tree_pattern_java "howl-hosts/howl-android-host/src/main/java" '(^|[^A-Za-z0-9_])(presentAck|waitRenderWake|renderFrameSized|surfaceHandle|currentScrollbackCount|currentScrollbackOffset|setScrollbackOffset|followLiveBottom|bindNativeMethods|RenderTelemetry)([^A-Za-z0-9_]|$)'
reject_pattern "howl-hosts/howl-linux-host/build.zig" 'b\.dependency\("(vt_core|howl_session|howl_render|howl-vt-core|howl-session|howl-render-core)"'
require_pattern "howl-hosts/howl-linux-host/build.zig" 'check_host_runtime_surface'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'const howl_term = @import\("howl_term"\);'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'howl_term\.runtime\.FramePixels'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'howl_term\.surface\.State'
require_pattern "howl-hosts/howl-linux-host/src/terminal/scroll.zig" 'howl_term\.viewport\.ScrollState'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'HowlTerm\.(LifecycleState|FramePixels|SurfaceHandle|SurfaceMetrics|SurfaceState|ScrollState|LinkUnderlineStyle)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/input.zig" 'const howl_term = @import\("howl_term"\);'
require_pattern "howl-hosts/howl-linux-host/src/terminal/input.zig" 'const TermInput = howl_term\.Input;'
require_pattern "howl-term/src/test/root.zig" 'package root supports minimal non-SDL embedding flow'
require_pattern "howl-term/src/test/root.zig" 'root\.runtime\.FramePixels'

# FFI ABI fields stay stable unless an ABI-changing checkpoint says otherwise.
require_pattern "howl-term/src/ffi.zig" 'term_us: u64 = 0,'
require_pattern "howl-term/src/ffi.zig" '@import\("c_api/constants\.zig"\)'
require_pattern "howl-term/src/ffi.zig" '@import\("c_api/frame\.zig"\)'
require_pattern "howl-term/src/ffi.zig" '@import\("c_api/input\.zig"\)'
require_pattern "howl-term/src/ffi.zig" '@import\("c_api/lifecycle\.zig"\)'
require_pattern "howl-term/src/ffi.zig" '@import\("c_api/font\.zig"\)'
require_pattern "howl-term/src/ffi.zig" '@import\("c_api/viewport\.zig"\)'
require_pattern "howl-term/src/ffi.zig" '@import\("c_api/metrics\.zig"\)'
require_pattern "howl-term/src/ffi.zig" '@import\("c_api/surface\.zig"\)'
reject_pattern "howl-term/src/ffi.zig" '^pub fn (modShift|keyEnter|mouseButtonNone|mousePress)'
reject_pattern "howl-term/src/ffi.zig" 'term\.publish(InputBytes|InputKey|Paste|MouseEvent|ControlSignal)'
reject_pattern "howl-term/src/ffi.zig" 'term\.setPrimaryFontPath'
reject_pattern "howl-term/src/ffi.zig" 'term\.(clearFallbackFontPaths|addFallbackFontPath)'
reject_pattern "howl-term/src/ffi.zig" 'term\.(renderedTextContains|visibleTextContains|beginSelection|updateSelection|finishSelection|clearSelection|setHoveredLinkAtPixel|copyHyperlinkUriAtPixel|drainPendingClipboardSet)'
reject_pattern "howl-term/src/ffi.zig" 'term\.(setScrollbackOffset|followLiveBottom)'
reject_pattern "howl-term/src/ffi.zig" 'term\.(viewportRows|currentScrollbackCount|currentScrollbackOffset|isAlternateScreen)'
reject_pattern "howl-term/src/ffi.zig" 'term\.(renderMissingGlyphs|renderFallbackHits|renderFallbackMisses|renderShapedClusters|renderResolveStage|lastRenderMetrics)'
reject_pattern "howl-term/src/ffi.zig" 'term\.(surfaceHandle|hasOutputProof|inputBytesApplied|snapshotEventSeq|renderedSnapshotSeq|copyCurrentTitle)'
reject_pattern "howl-term/src/ffi.zig" 'term\.(renderFrame|renderLatestSnapshot|renderFrameSized|awaitSnapshotEvent|syncFrameGeometry|wakeSnapshotWaiters)'
reject_pattern "howl-term/src/ffi.zig" 'runtime\.(hasQueuedRenderWork|needsFrame|needsPrepare|prepareNextFrame|renderReadyFrame|awaitRenderWakeTimeout|syncFrameGeometry|setRuntimeBackpressure)'
reject_pattern "howl-term/src/ffi.zig" 'HowlTerm\.initPty|std\.heap\.c_allocator|term\.(start|deinit|setFontSizePx|isAlive)'
reject_pattern "howl-term/src/ffi.zig" 'fn boolInt|boolInt\('
reject_pattern "howl-term/src/terminal.zig" 'canReuseFrameLayoutLocked'
require_pattern "howl-term/src/terminal.zig" 'frame_driver\.awaitRenderWakeTimeout'
require_pattern "howl-term/src/terminal.zig" 'howl_render\.Core\.FrameSnapshot'
require_pattern "howl-term/src/terminal.zig" 'howl_render\.Core\.FramePipeline'
require_pattern "howl-term/src/runtime/contract.zig" 'howl_render\.Core\.FrameQueue\.SurfaceExecutor'
require_pattern "howl-term/src/runtime/contract.zig" 'pub const PrepareMetrics = howl_render\.Core\.PrepareMetrics;'
require_pattern "howl-term/src/runtime/contract.zig" 'pub const RenderMetrics = howl_render\.Core\.RenderMetrics;'
require_pattern "howl-term/src/runtime/contract.zig" 'pub const FramePixels = howl_render\.Core\.FramePixels;'
require_pattern "howl-term/src/runtime/contract.zig" 'pub const PreparedRenderFrame = howl_render\.Renderer\.FrameRecord;'
reject_pattern "howl-term/src/runtime/contract.zig" '@import\("\.\./render/render\.zig"\)'
reject_pattern "howl-term/src/runtime/contract.zig" 'pub const (PrepareMetrics|RenderMetrics|FramePixels) = struct'
reject_pattern "howl-term/src/render/render.zig" 'pub const PreparedFrame = struct'
reject_pattern "howl-term/src/render/render.zig" 'pub const (Core|Renderer) = howl_render\.'
reject_pattern "howl-term/src/render/render.zig" 'report\.(sprite_draws|clear_draws|background_draws|decoration_draws|cursor_draws|raster_uploads_committed|full_redraw|scroll_up_px)'
reject_pattern "howl-term/src/render/render.zig" 'resolve_after\.'
require_pattern "howl-term/src/terminal.zig" 'inputs\.drainPendingClipboardSet'
require_pattern "howl-term/src/terminal.zig" 'wake\.stopSnapshotWaiters'
require_pattern "howl-term/src/terminal.zig" '@import\("runtime/query\.zig"\)'
require_pattern "howl-term/src/runtime/lifecycle.zig" '@import\("thread\.zig"\)'
require_pattern "howl-term/src/runtime/thread.zig" 'pub fn threadMain'
require_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.pumpOutboundInput'
require_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.waitReadableAfterOutbound'
require_pattern "howl-term/src/runtime/thread.zig" 'io_tick\.run\(term, scratch\[0\.\.\]\)'
require_pattern "howl-term/src/runtime/io_tick.zig" 'term\.session\.pumpTransportMode'
require_pattern "howl-term/src/runtime/io_tick.zig" 'term\.vt\.feedSlice\(bytes\)'
require_pattern "howl-term/src/runtime/io_tick.zig" 'term\.vt\.apply\(\)'
require_pattern "howl-term/src/runtime/io_tick.zig" 'term\.session\.hasOutboundInputBacklog\(\)'
require_pattern "howl-term/src/runtime/io_tick.zig" 'wake\.noteSnapshotEvent\(term\)'
require_pattern "howl-term/src/runtime/thread.zig" 'terminal_reply\.drain\(term\)'
require_pattern "howl-term/src/runtime/terminal_reply.zig" 'term\.vt\.pendingOutput\(\)'
require_pattern "howl-term/src/runtime/terminal_reply.zig" 'term\.session\.publishHostInput\(pending\) catch return;'
require_pattern "howl-term/src/runtime/terminal_reply.zig" 'term\.vt\.clearPendingOutput\(\)'
require_pattern "howl-term/src/input/input.zig" 'term\.session\.publishHostInputAndPump'
require_pattern "howl-term/src/runtime/lifecycle.zig" 'howl_session\.Session\.initOwnedTransport'
require_pattern "howl-term/src/runtime/lifecycle.zig" 'howl_session\.Session\.initPty'
require_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.isActive\(\)'
require_pattern "howl-term/src/runtime/query.zig" 'term\.session\.isActive\(\)'
reject_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.ingestTransport'
reject_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.pumpTransport|term\.session\.hasOutboundInputBacklog'
reject_pattern "howl-term/src/runtime/io_tick.zig" 'normal_reads|normal_bytes|backpressure_reads|backpressure_bytes|max_reads|max_bytes'
reject_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.status|term\.session\.snapshot\(\)\.status'
reject_pattern "howl-term/src/runtime/thread.zig" 'term\.vt\.|pendingOutput|clearPendingOutput|publishHostInput\(pending\)|noteSnapshotEvent|hasPendingRenderWork'
reject_pattern "howl-term/src/runtime/query.zig" 'term\.session\.status|term\.session\.snapshot\(\)\.status'
reject_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.(flushOutboundInput|hasPendingOutboundInput|waitReadable\()'
reject_pattern "howl-term/src/input/input.zig" 'term\.session\.(flushOutboundInput|hasPendingOutboundInput)'
reject_pattern "howl-term/src/terminal.zig" '^    transport: howl_session\.OwnedTransport,'
reject_pattern "howl-term/src/runtime/lifecycle.zig" 'howl_session\.initTransport|term\.session\.attachPty|term\.transport|transport\.pty\(|transport\.deinit\('
reject_pattern "howl-term/src/terminal.zig" 'worker_'
reject_pattern "howl-term/src/runtime/lifecycle.zig" 'worker_|workerMain'
reject_pattern "howl-term/src/runtime/thread.zig" 'worker_|workerMain'
require_pattern "howl-hosts/howl-linux-host/src/terminal/lifecycle.zig" '@import\("thread\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("effects\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("frame\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("font_size\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("geometry\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("input_flow\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("lifecycle\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("links\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("query\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("scroll\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/input_flow.zig" '@import\("selection\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/frame.zig" '@import\("effects\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/lifecycle.zig" '@import\("effects\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/effects.zig" 'copyCurrentTitle'
require_pattern "howl-hosts/howl-linux-host/src/terminal/effects.zig" 'setInputFocus'
require_pattern "howl-hosts/howl-linux-host/src/terminal/effects.zig" 'drainPendingClipboardSet'
require_pattern "howl-hosts/howl-linux-host/src/terminal/effects.zig" 'setClipboardText'
require_pattern "howl-hosts/howl-linux-host/src/terminal/effects.zig" 'pub fn setWindowFocused'
require_pattern "howl-hosts/howl-linux-host/src/terminal/effects.zig" 'pub fn setWidgetFocused'
require_pattern "howl-hosts/howl-linux-host/src/terminal/query.zig" 'surfaceState'
require_pattern "howl-hosts/howl-linux-host/src/terminal/query.zig" 'renderedTextContains'
require_pattern "howl-hosts/howl-linux-host/src/terminal/query.zig" 'scroll\.layout'
require_pattern "howl-hosts/howl-linux-host/src/terminal/query.zig" 'pub fn lifecycleState'
require_pattern "howl-hosts/howl-linux-host/src/terminal/frame.zig" 'awaitRenderWake'
require_pattern "howl-hosts/howl-linux-host/src/terminal/frame.zig" 'prepareNextFrame'
require_pattern "howl-hosts/howl-linux-host/src/terminal/frame.zig" 'renderReadyFrame'
require_pattern "howl-hosts/howl-linux-host/src/terminal/font_size.zig" 'min_font_px'
require_pattern "howl-hosts/howl-linux-host/src/terminal/font_size.zig" 'max_font_px'
require_pattern "howl-hosts/howl-linux-host/src/terminal/font_size.zig" 'setFontSizePx'
require_pattern "howl-hosts/howl-linux-host/src/terminal/font_size.zig" 'pub fn toggleStress'
require_pattern "howl-hosts/howl-linux-host/src/terminal/geometry.zig" 'pub const Mutex = struct'
require_pattern "howl-hosts/howl-linux-host/src/terminal/geometry.zig" 'std\.Io\.Threaded\.mutexLock'
require_pattern "howl-hosts/howl-linux-host/src/terminal/geometry.zig" 'SDL_GetTicksNS'
require_pattern "howl-hosts/howl-linux-host/src/terminal/geometry.zig" 'syncFrameGeometry'
require_pattern "howl-hosts/howl-linux-host/src/terminal/geometry.zig" 'pub fn maybeCommitGridResize'
require_pattern "howl-hosts/howl-linux-host/src/terminal/input_flow.zig" 'drainInputEvent'
require_pattern "howl-hosts/howl-linux-host/src/terminal/input_flow.zig" 'publishInputBytes'
require_pattern "howl-hosts/howl-linux-host/src/terminal/input_flow.zig" 'publishInputKey'
require_pattern "howl-hosts/howl-linux-host/src/terminal/input_flow.zig" 'publishMouseEvent'
require_pattern "howl-hosts/howl-linux-host/src/terminal/input_flow.zig" 'publishPaste'
require_pattern "howl-hosts/howl-linux-host/src/terminal/lifecycle.zig" 'HowlTerm\.initPty'
require_pattern "howl-hosts/howl-linux-host/src/terminal/lifecycle.zig" 'setPrimaryFontPath'
require_pattern "howl-hosts/howl-linux-host/src/terminal/lifecycle.zig" 'setFallbackFontPaths'
require_pattern "howl-hosts/howl-linux-host/src/terminal/lifecycle.zig" 'std\.Thread\.spawn'
require_pattern "howl-hosts/howl-linux-host/src/terminal/lifecycle.zig" 'wakeSnapshotWaiters'
require_pattern "howl-hosts/howl-linux-host/src/terminal/lifecycle.zig" 'SDL_DestroySemaphore'
require_pattern "howl-hosts/howl-linux-host/src/terminal/links.zig" 'setHoveredLinkAtPixel'
require_pattern "howl-hosts/howl-linux-host/src/terminal/links.zig" 'copyHyperlinkUriAtPixel'
require_pattern "howl-hosts/howl-linux-host/src/terminal/scroll.zig" 'scrollState'
require_pattern "howl-hosts/howl-linux-host/src/terminal/scroll.zig" 'setScrollbackOffset'
require_pattern "howl-hosts/howl-linux-host/src/terminal/scroll.zig" 'followLiveBottom'
require_pattern "howl-hosts/howl-linux-host/src/terminal/scroll.zig" 'scrollbar\.View'
require_pattern "howl-hosts/howl-linux-host/src/terminal/selection.zig" 'beginSelection'
require_pattern "howl-hosts/howl-linux-host/src/terminal/selection.zig" 'finishSelection'
require_pattern "howl-hosts/howl-linux-host/src/terminal/thread.zig" 'pub fn wakeThreadMain'
require_pattern "howl-hosts/howl-linux-host/src/terminal/thread.zig" 'pub fn prepareThreadMain'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'prepare_thread_signal_pending\.swap\(true, \.acq_rel\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'pub fn finishPrepareThreadJob'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'prepare_thread_signal_pending\.store\(false, \.release\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'if \(self\.term\.needsPrepare\(\)\) self\.signalPrepareThread\(\);'
require_pattern "howl-hosts/howl-linux-host/src/terminal/frame.zig" 'self\.finishPrepareThreadJob\(\)'
reject_tree_pattern "howl-hosts/howl-linux-host/src" 'std\.Thread\.sleep|sleep\('
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'worker_|wakeWorker|prepareWorker'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/thread.zig" 'worker_|wakeWorker|prepareWorker'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'setHoveredLinkAtPixel|copyHyperlinkUriAtPixel|beginSelection|updateSelection|finishSelection|selectionInProgress'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'scrollState|setScrollbackOffset|followLiveBottom|scrollbarView'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'publishInputBytes|publishInputKey|publishMouseEvent|publishPaste|drainInputEvent'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'HowlTerm\.initPty|setPrimaryFontPath|setFallbackFontPaths|std\.Thread\.spawn|wakeSnapshotWaiters|SDL_DestroySemaphore|copyCurrentTitle|setInputFocus'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'syncFrameGeometry|SDL_GetTicksNS|std\.Io\.Threaded\.mutexLock|geometrySnapshotLocked'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'drainPendingClipboardSet|setClipboardText|drainClipboardSet|\.window_focused = focused|\.widget_focused = focused'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'setFontSizePx|min_font_px|max_font_px|midpoint'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'self\.term\.surfaceState\(|self\.term\.renderedTextContains\(|presentSurfaceHandle|scroll\.layout\(@constCast\(self\), texture_rect\)'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/thread.zig" 'self\.term\.'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'awaitRenderWake|prepareNextFrame|renderReadyFrame'

# FFI implementation files talk to owner modules, not back through their public roots.
reject_pattern "howl-term/src/ffi.zig" '@import\("howl_term\.zig"\)'
reject_pattern "howl-session/src/ffi.zig" '@import\("howl_session\.zig"\)'
reject_pattern "howl-vt-core/src/ffi.zig" '@import\("vt_core\.zig"\)'
reject_pattern "howl-render-core/src/ffi.zig" '@import\("howl_render\.zig"\)'

# First-class module FFI routes are the next active route. Missing real routes stay open.
if ! grep -Eq 'pub const Ffi =' "howl-vt-core/src/howl_vt.zig"; then mark_open "vt_core_ffi_route_missing"; fi
if ! grep -Eq 'pub const Ffi =' "howl-session/src/howl_session.zig"; then mark_open "session_ffi_route_missing"; fi
if ! grep -Eq 'pub const Ffi =' "howl-render-core/src/howl_render.zig"; then mark_open "render_ffi_route_missing"; fi
require_pattern "howl-term/src/howl_term.zig" 'pub const Ffi = (c_api|term\.c_api);'
if ! grep -Eq '@export' "howl-term/src/howl_term.zig"; then mark_open "term_ffi_root_export_route_missing"; fi

# Missing Android runtime proof remains explicit, not hidden by a fake pass.
require_pattern "tools/check_host_runtime_surface.sh" 'host_runtime_surface_skip=missing_android_runtime'
require_pattern "design/term-embedding-surface-sprint.md" 'Sprint 7: Runtime Ownership Board'
require_pattern "design/term-embedding-surface-sprint.md" 'Checkpoint 1 Audit'
require_pattern "design/term-embedding-surface-sprint.md" 'work-not-clear'
require_pattern "design/term-embedding-surface-sprint.md" 'Android is parked until ownership boundaries are pristine'

printf '%s\n' 'module_shape_ok=1'
