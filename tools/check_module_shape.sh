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

require_file "howl-vt-core/src/vt_core.zig"
require_file "howl-vt-core/src/terminal.zig"
require_file "howl-session/src/root.zig"
require_file "howl-render-core/src/howl_render.zig"
require_file "howl-term/src/howl_term.zig"
require_file "howl-hosts/howl-linux-host/src/main.zig"
require_file "howl-hosts/howl-linux-host/src/test_host.zig"

# Package roots stay small and delegate implementation to owned files.
require_max_lines "howl-vt-core/src/vt_core.zig" 80
require_max_lines "howl-session/src/root.zig" 120
require_max_lines "howl-render-core/src/howl_render.zig" 120
require_max_lines "howl-hosts/howl-linux-host/src/test_host.zig" 80

require_pattern "howl-vt-core/src/vt_core.zig" 'pub const VtCore = terminal\.VtCore;'
reject_pattern "howl-vt-core/src/vt_core.zig" 'pub const VtCore = struct'
reject_pattern "howl-session/src/root.zig" 'pub const Session = struct'
reject_pattern "howl-render-core/src/howl_render.zig" 'pub const RenderCore = struct'

# Explicit exceptions: these are executable/runtime owner files, not package indexes.
require_pattern "howl-term/src/howl_term.zig" 'pub const HowlTerm = struct'
require_pattern "howl-hosts/howl-linux-host/src/main.zig" 'pub fn main'

printf '%s\n' 'module_shape_ok=1'
