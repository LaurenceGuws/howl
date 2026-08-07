#!/bin/sh
# Verifies the terminal shaders' checked source/binary identity and their
# shared push-constant ABI. The Zig oracle is the only owner of the host ABI;
# this tool independently reads the two tracked SPIR-V modules.
set -eu

cd "$(dirname "$0")/.."

# A source edit without a regenerated binary is an ABI failure, not a receipt.
sh tools/verify_terminal_shaders.sh

receipt_tmp=$(mktemp -d)
trap 'rm -rf -- "$receipt_tmp"' EXIT HUP INT TERM

verify_module() {
    module=$1
    atlas_member=$2
    disassembly="$receipt_tmp/$(basename "$module").dis"
    spirv-dis "$module" -o "$disassembly"

    awk -v atlas_member="$atlas_member" '
        BEGIN {
            names[0] = "surface";
            names[1] = "origin";
            names[2] = "grid";
            names[3] = "cell";
            names[4] = atlas_member;
            names[5] = "lines";
            names[6] = "cursor";
            names[7] = "cursor_colors";

            offsets[0] = 0;
            offsets[1] = 8;
            offsets[2] = 16;
            offsets[3] = 24;
            offsets[4] = 32;
            offsets[5] = 48;
            offsets[6] = 64;
            offsets[7] = 80;

            widths[0] = 8;
            widths[1] = 8;
            widths[2] = 8;
            widths[3] = 8;
            widths[4] = 8;
            widths[5] = 16;
            widths[6] = 16;
            widths[7] = 8;
        }
        $1 == "OpMemberName" && $2 == "%Push" {
            member = $3;
            name = $4;
            sub(/^"/, "", name);
            sub(/"$/, "", name);
            if (member < 0 || member > 7 || name != names[member]) {
                printf("unexpected Push member name %s %s\n", member, name) > "/dev/stderr";
                exit 1;
            }
            named[member]++;
        }
        $1 == "OpMemberDecorate" && $2 == "%Push" && $4 == "Offset" {
            member = $3;
            offset = $5;
            if (member < 0 || member > 7 || offset != offsets[member]) {
                printf("unexpected Push member offset %s %s\n", member, offset) > "/dev/stderr";
                exit 1;
            }
            decorated[member]++;
        }
        END {
            maximum_end = 0;
            for (member = 0; member < 8; member++) {
                if (named[member] != 1 || decorated[member] != 1) {
                    printf("missing or duplicate Push member %d\n", member) > "/dev/stderr";
                    exit 1;
                }
                end = offsets[member] + widths[member];
                if (end > maximum_end) maximum_end = end;
            }
            if (maximum_end != 88) {
                printf("Push accessed range is %d bytes, expected 88\n", maximum_end) > "/dev/stderr";
                exit 1;
            }
        }
    ' "$disassembly"
}

verify_module src/shaders/terminal.vert.spv atlas
verify_module src/shaders/terminal.frag.spv atlas_extent

# This test reads the same SPIR-V bytes and checks their member decorations
# against the private Zig struct offsets and exact 88-byte push range.
../.zig/zig test src/terminal_cells.zig -lc -lvulkan \
    --test-filter 'terminal shader push constant ABI has exact tracked SPIR-V layout'
