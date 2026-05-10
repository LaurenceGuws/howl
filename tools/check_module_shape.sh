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
require_file "howl-hosts/howl-linux-host/src/terminal/thread.zig"
if test -f "howl-term/src/wake/loop.zig"; then fail "forbidden_file:howl-term/src/wake/loop.zig"; fi
if test -f "howl-term/src/runtime/state.zig"; then fail "forbidden_file:howl-term/src/runtime/state.zig"; fi
if test -f "howl-term/src/c_api/state.zig"; then fail "forbidden_file:howl-term/src/c_api/state.zig"; fi
if test -f "howl-term/src/render/pipeline.zig"; then fail "forbidden_file:howl-term/src/render/pipeline.zig"; fi
if test -f "howl-term/src/render/queue.zig"; then fail "forbidden_file:howl-term/src/render/queue.zig"; fi
if test -f "howl-term/src/render/snapshot.zig"; then fail "forbidden_file:howl-term/src/render/snapshot.zig"; fi

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
require_pattern "howl-session/src/session.zig" 'pub const TransportPumpResult = struct'
require_pattern "howl-session/src/session.zig" 'pub const OutboundInputPump = struct'
require_pattern "howl-session/src/session.zig" 'pub const OwnedTransportConfig = struct'
require_pattern "howl-session/src/session.zig" 'pub const PtyConfig = struct'
require_pattern "howl-session/src/session.zig" 'owned_transport: \?OwnedTransport'
require_pattern "howl-session/src/session.zig" 'pub fn pumpTransport'
require_pattern "howl-session/src/session.zig" 'pub fn pumpOutboundInput'
require_pattern "howl-session/src/session.zig" 'pub fn publishHostInputAndPump'
require_pattern "howl-session/src/session.zig" 'pub fn waitReadableAfterOutbound'
require_pattern "howl-session/src/session.zig" 'pub fn initOwnedTransport'
require_pattern "howl-session/src/session.zig" 'pub fn initPty'
require_pattern "howl-session/src/session.zig" 'pub fn isActive'
require_pattern "howl-session/src/session_namespace.zig" 'pub const TransportPumpLimits = runtime_mod\.TransportPumpLimits;'
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
reject_pattern "howl-hosts/howl-linux-host/build.zig" 'b\.dependency\("(vt_core|howl_session|howl_render|howl-vt-core|howl-session|howl-render-core)"'
require_pattern "howl-hosts/howl-linux-host/build.zig" 'check_host_runtime_surface'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'const howl_term = @import\("howl_term"\);'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'howl_term\.runtime\.FramePixels'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'howl_term\.surface\.State'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'howl_term\.viewport\.ScrollState'
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
require_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.pumpTransport'
require_pattern "howl-term/src/input/input.zig" 'term\.session\.publishHostInputAndPump'
require_pattern "howl-term/src/runtime/lifecycle.zig" 'howl_session\.Session\.initOwnedTransport'
require_pattern "howl-term/src/runtime/lifecycle.zig" 'howl_session\.Session\.initPty'
require_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.isActive\(\)'
require_pattern "howl-term/src/runtime/query.zig" 'term\.session\.isActive\(\)'
reject_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.ingestTransport'
reject_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.status|term\.session\.snapshot\(\)\.status'
reject_pattern "howl-term/src/runtime/query.zig" 'term\.session\.status|term\.session\.snapshot\(\)\.status'
reject_pattern "howl-term/src/runtime/thread.zig" 'term\.session\.(flushOutboundInput|hasPendingOutboundInput|waitReadable\()'
reject_pattern "howl-term/src/input/input.zig" 'term\.session\.(flushOutboundInput|hasPendingOutboundInput)'
reject_pattern "howl-term/src/terminal.zig" '^    transport: howl_session\.OwnedTransport,'
reject_pattern "howl-term/src/runtime/lifecycle.zig" 'howl_session\.initTransport|term\.session\.attachPty|term\.transport|transport\.pty\(|transport\.deinit\('
reject_pattern "howl-term/src/terminal.zig" 'worker_'
reject_pattern "howl-term/src/runtime/lifecycle.zig" 'worker_|workerMain'
reject_pattern "howl-term/src/runtime/thread.zig" 'worker_|workerMain'
require_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" '@import\("thread\.zig"\)'
require_pattern "howl-hosts/howl-linux-host/src/terminal/thread.zig" 'pub fn wakeThreadMain'
require_pattern "howl-hosts/howl-linux-host/src/terminal/thread.zig" 'pub fn prepareThreadMain'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/terminal.zig" 'worker_|wakeWorker|prepareWorker'
reject_pattern "howl-hosts/howl-linux-host/src/terminal/thread.zig" 'worker_|wakeWorker|prepareWorker'

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
