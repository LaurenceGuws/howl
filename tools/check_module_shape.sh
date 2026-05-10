#!/bin/sh
set -eu

fail() {
    printf '%s\n' "module_shape_error=$1" >&2
    exit 1
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

require_file "howl-vt-core/src/terminal.zig"

# Package roots stay small and delegate implementation to owned files.
require_package_root "howl-vt-core/src/vt_core.zig" 80
require_package_root "howl-session/src/root.zig" 120
require_package_root "howl-render-core/src/howl_render.zig" 120
require_package_root "howl-hosts/howl-linux-host/src/test_host.zig" 80

require_pattern "howl-vt-core/src/vt_core.zig" 'pub const VtCore = terminal\.VtCore;'
reject_pattern "howl-vt-core/src/vt_core.zig" 'pub const VtCore = struct'
reject_pattern "howl-session/src/root.zig" 'pub const Session = struct'
reject_pattern "howl-render-core/src/howl_render.zig" 'pub const RenderCore = struct'

# Explicit exceptions: these are executable/runtime owner files, not package indexes.
require_runtime_owner "howl-term/src/howl_term.zig" 'pub const HowlTerm = struct'
require_runtime_owner "howl-hosts/howl-linux-host/src/main.zig" 'pub fn main'

# HowlTerm keeps only host-facing aliases at the public owner surface.
require_pattern "howl-term/src/howl_term.zig" 'pub const SurfaceHandle = contract\.SurfaceHandle;'
require_pattern "howl-term/src/howl_term.zig" 'pub const LinkUnderlineStyle = contract\.LinkUnderlineStyle;'
require_pattern "howl-term/src/howl_term.zig" 'pub const LifecycleState = contract\.LifecycleState;'
require_pattern "howl-term/src/howl_term.zig" 'pub const FramePixels = contract\.FramePixels;'
require_pattern "howl-term/src/howl_term.zig" 'pub const SurfaceMetrics = contract\.SurfaceMetrics;'
require_pattern "howl-term/src/howl_term.zig" 'pub const SurfaceState = contract\.SurfaceState;'
require_pattern "howl-term/src/howl_term.zig" 'pub const ScrollState = contract\.ScrollState;'
reject_pattern "howl-term/src/howl_term.zig" 'pub const (RenderPipeline|TerminalSurface|PreparedSlot|SurfaceExecutor|RenderSnapshotResult|ControlSignal|ClipboardRequest|Error|SelectionPoint|Dirty|Damage|DirtySnapshot|SyncMetrics|RenderMetrics|PrepareMetrics|PreparedRenderFrame|PtyLaunchConfig|MouseInput|LinkHoverResult|RenderCellSize|PrepareResult|RenderResult|SnapshotWake) ='

# Layering: lower modules must not import upper modules.
reject_tree_pattern "howl-vt-core/src" '@import\("howl_(session|render|term)"\)'
reject_tree_pattern "howl-session/src" '@import\("(vt_core|howl_render|howl_term)"\)'
reject_tree_pattern "howl-render-core/src" '@import\("(vt_core|howl_session|howl_term)"\)'

# Hosts depend on howl-term for terminal runtime, not lower module packages.
reject_tree_pattern "howl-hosts/howl-linux-host/src" '@import\("(vt_core|howl_session|howl_render)"\)'

# FFI ABI fields stay stable unless an ABI-changing checkpoint says otherwise.
require_pattern "howl-term/src/ffi.zig" 'term_us: u64 = 0,'

# Missing Android runtime proof remains explicit, not hidden by a fake pass.
require_pattern "tools/check_host_runtime_surface.sh" 'host_runtime_surface_skip=missing_android_runtime'

printf '%s\n' 'module_shape_ok=1'
