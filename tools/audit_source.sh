#!/usr/bin/env bash
set -euo pipefail

status=0

root_public='pub const Terminal = terminal.Terminal;'
if [[ $(grep -Ec '^[[:space:]]*pub (const|fn|var|threadlocal)[[:space:]]' src/howl_vt.zig) -ne 1 ]] ||
    ! grep -Fxq "$root_public" src/howl_vt.zig; then
    printf 'src/howl_vt.zig: curated embedding root changed\n'
    status=1
fi

while IFS= read -r file; do
    if ! head -n 1 "$file" | grep -q '^//!'; then
        printf '%s:1: missing file owner contract\n' "$file"
        status=1
    fi

    # Public owner errors stay reviewable instead of widening through inference.
    awk '
        function check_signature() {
            if (signature ~ /\)[[:space:]]*![^=]/) {
                printf "%s:%d: public function has inferred error set\n", FILENAME, signature_line
                failed = 1
            }
            signature = ""
            signature_line = 0
        }
        signature != "" {
            signature = signature " " $0
            if ($0 ~ /\{[[:space:]]*$/) check_signature()
        }
        /^[[:space:]]*pub (const|fn|var|threadlocal)[[:space:]]/ {
            if (previous !~ /^[[:space:]]*\/\/\//) {
                printf "%s:%d: undocumented public declaration\n", FILENAME, NR
                failed = 1
            }
            if ($0 ~ /^[[:space:]]*pub fn[[:space:]]/) {
                signature = $0
                signature_line = NR
                if ($0 ~ /\{[[:space:]]*$/) check_signature()
            }
        }
        { previous = $0 }
        END { exit failed }
    ' "$file" || status=1
done < <(find src -type f -name '*.zig' -print | sort)

# Empty lifecycle names preserve no behavior or ownership and therefore add no contract.
empty_lifecycle_pattern='^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+(deinit|reset|clear)'
empty_lifecycle_pattern+='[[:space:]]*\([^)]*\)[^{]*\{[[:space:]]*\}[[:space:]]*$'
while IFS=: read -r file line _; do
    printf '%s:%s: empty lifecycle hook\n' "$file" "$line"
    status=1
done < <(grep -RnE "$empty_lifecycle_pattern" src --include='*.zig' || true)

# Result discards are limited to compile-only root and parser test probes.
root_test_start=$(grep -n '^test[[:space:]]*{' src/howl_vt.zig | cut -d: -f1)
parser_test_start=$(grep -n '^test "parser' src/parser.zig | head -n 1 | cut -d: -f1)
parser_test_end=$(grep -n '^const StyleChange' src/parser.zig | cut -d: -f1)
while IFS=: read -r file line text; do
    allowed=false
    if [[ "$file" == src/howl_vt.zig && "$line" -gt "$root_test_start" && "$text" == '    _ = terminal;' ]]; then
        allowed=true
    elif [[ "$file" == src/parser.zig && "$line" -gt "$parser_test_start" && "$line" -lt "$parser_test_end" ]] &&
        [[ "$text" == '    _ = parser.next('* || "$text" == '    _ = parser.entryPhase('* ]]; then
        allowed=true
    fi
    if [[ "$allowed" == false ]]; then
        printf '%s:%s: discarded source result\n' "$file" "$line"
        status=1
    fi
done < <(grep -RnE '^[[:space:]]*_[[:space:]]*=' src --include='*.zig' || true)

exit "$status"
