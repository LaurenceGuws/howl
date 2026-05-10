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

# Package roots stay small and delegate implementation to owned files.
require_catalog_root "howl-vt-core/src/howl_vt.zig" 80
require_package_root "howl-session/src/howl_session.zig" 120
require_catalog_root "howl-render-core/src/howl_render.zig" 120
require_catalog_root "howl-hosts/howl-linux-host/src/test_host.zig" 80

require_pattern "howl-vt-core/src/howl_vt.zig" '@import\("vt/main\.zig"\)'
require_pattern "howl-vt-core/src/howl_vt.zig" 'pub const VtCore = vt\.VtCore;'
require_pattern "howl-session/src/howl_session.zig" '@import\("session/main\.zig"\)'
reject_pattern "howl-vt-core/src/howl_vt.zig" 'pub const VtCore = struct'
reject_pattern "howl-vt-core/src/howl_vt.zig" '@import\("(input|grid|parser|snapshot|selection|terminal|ffi)\.zig"\)'
reject_pattern "howl-session/src/howl_session.zig" 'pub const Session = struct'
reject_pattern "howl-session/src/howl_session.zig" '@import\("(session|pty|ffi)\.zig"\)'
reject_pattern "howl-render-core/src/howl_render.zig" 'pub const RenderCore = struct'

# Explicit exception: this is an executable owner, not a package index.
require_runtime_owner "howl-hosts/howl-linux-host/src/main.zig" 'pub fn main'

# howl-term root target: catalog-shaped root, not runtime owner body.
require_file "howl-term/src/howl_term.zig"
if grep -Eq 'pub const HowlTerm = struct' "howl-term/src/howl_term.zig"; then
    mark_open "howl_term_root_not_catalog"
else
    require_catalog_root "howl-term/src/howl_term.zig" 140
    require_pattern "howl-term/src/howl_term.zig" 'pub const HowlTerm = [A-Za-z_][A-Za-z0-9_]*\.HowlTerm;'
    reject_pattern "howl-term/src/howl_term.zig" 'pub const HowlTerm = struct'
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

# FFI ABI fields stay stable unless an ABI-changing checkpoint says otherwise.
require_pattern "howl-term/src/ffi.zig" 'term_us: u64 = 0,'

# FFI implementation files talk to owner modules, not back through their public roots.
reject_pattern "howl-term/src/ffi.zig" '@import\("howl_term\.zig"\)'
reject_pattern "howl-session/src/ffi.zig" '@import\("howl_session\.zig"\)'
reject_pattern "howl-vt-core/src/ffi.zig" '@import\("vt_core\.zig"\)'
reject_pattern "howl-render-core/src/ffi.zig" '@import\("howl_render\.zig"\)'

# First-class module FFI routes are the next active route. Missing real routes stay open.
if ! grep -Eq 'pub const Ffi =' "howl-vt-core/src/howl_vt.zig"; then mark_open "vt_core_ffi_route_missing"; fi
if ! grep -Eq 'pub const Ffi =' "howl-session/src/howl_session.zig"; then mark_open "session_ffi_route_missing"; fi
if ! grep -Eq 'pub const Ffi =' "howl-render-core/src/howl_render.zig"; then mark_open "render_ffi_route_missing"; fi
require_pattern "howl-term/src/howl_term.zig" 'pub const Ffi = (ffi|@import\("ffi\.zig"\));'
if ! grep -Eq '@export' "howl-term/src/howl_term.zig"; then mark_open "term_ffi_root_export_route_missing"; fi

# Missing Android runtime proof remains explicit, not hidden by a fake pass.
require_pattern "tools/check_host_runtime_surface.sh" 'host_runtime_surface_skip=missing_android_runtime'

printf '%s\n' 'module_shape_ok=1'
