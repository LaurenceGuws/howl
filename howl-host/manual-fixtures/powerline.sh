#!/bin/sh
#
# Deterministic Powerline separator fixture for Howl's manual rendering gate.
# It emits UTF-8 bytes directly so the result does not depend on shell paste,
# prompt configuration, locale glyph entry, or an installed Powerline theme.

set -eu

escape=$(printf '\033')
right=$(printf '\356\202\260')
right_thin=$(printf '\356\202\261')
left=$(printf '\356\202\262')
left_thin=$(printf '\356\202\263')
right_round=$(printf '\356\202\264')
right_round_thin=$(printf '\356\202\265')
left_round=$(printf '\356\202\266')
left_round_thin=$(printf '\356\202\267')
bottom_left=$(printf '\356\202\270')
descending_left=$(printf '\356\202\271')
bottom_right=$(printf '\356\202\272')
ascending_right=$(printf '\356\202\273')
top_left=$(printf '\356\202\274')
ascending_right_alias=$(printf '\356\202\275')
top_right=$(printf '\356\202\276')
descending_left_alias=$(printf '\356\202\277')
right_extended=$(printf '\356\203\226')
left_extended=$(printf '\356\203\227')
progress_left=$(printf '\356\270\200')
progress_middle=$(printf '\356\270\201')
progress_right=$(printf '\356\270\202')
progress_left_filled=$(printf '\356\270\203')
progress_middle_filled=$(printf '\356\270\204')
progress_right_filled=$(printf '\356\270\205')
spinner_0=$(printf '\356\270\206')
spinner_1=$(printf '\356\270\207')
spinner_2=$(printf '\356\270\210')
spinner_3=$(printf '\356\270\211')
spinner_4=$(printf '\356\270\212')
spinner_5=$(printf '\356\270\213')

reset="${escape}[0m"
white="${escape}[38;2;242;242;242m"
blue_fg="${escape}[38;2;52;78;120m"
blue_bg="${escape}[48;2;52;78;120m"
slate_fg="${escape}[38;2;35;37;46m"
slate_bg="${escape}[48;2;35;37;46m"
gold_fg="${escape}[38;2;190;170;90m"
gold_bg="${escape}[48;2;190;170;90m"
purple_fg="${escape}[38;2;104;78;145m"
purple_bg="${escape}[48;2;104;78;145m"

trap 'printf "%s" "$reset"' 0 HUP INT TERM

printf '%sPowerline generated-glyph fixture%s\n\n' "$white" "$reset"

# Filled separators must meet both neighboring backgrounds without a seam.
printf 'filled   '
printf '%s%s main ' "$blue_bg" "$white"
printf '%s%s%s' "$slate_bg" "$blue_fg" "$right"
printf '%s git ' "$white"
printf '%s%s%s' "$purple_bg" "$slate_fg" "$right"
printf '%s nvim ' "$white"
printf '%s%s%s%s\n' "$reset" "$purple_fg" "$right" "$reset"

# Thin separators remain centered and retain factual stroke thickness.
printf 'thin     '
printf '%s%s left ' "$slate_bg" "$white"
printf '%s%s%s' "$blue_fg" "$right_thin" "$white"
printf ' middle '
printf '%s%s%s' "$gold_fg" "$right_thin" "$white"
printf ' right %s\n' "$reset"

# Rounded endings must join the final colored cell and clear into the default
# background without clipping their top, bottom, or curved outer edge.
printf 'rounded  '
printf '%s%s Top  1/8 ' "$gold_bg" "$slate_fg"
printf '%s%s%s%s\n' "$reset" "$gold_fg" "$right_round" "$reset"

# Repetition exposes duplicate draws, one-cell clipping, and boundary gaps.
printf 'pairs    '
printf '%s%s%s%s%s%s%s%s%s\n' \
    "$blue_fg" "$right" "$right" \
    "$white" "$right_thin" "$right_thin" \
    "$gold_fg" "$right_round" "$right_round"
printf '%s\n' "$reset"

# The complete U+E0B0-U+E0BF family is grouped in codepoint order. Spaces keep
# neighboring rasters visually independent so mirroring, curves, diagonals,
# corner fill, clipping, and accidental duplicate draws remain inspectable.
printf '\ncomplete family\n'
printf 'E0B0-3  %s%s%s %s %s %s%s\n' \
    "$slate_bg" "$white" "$right" "$right_thin" "$left" "$left_thin" "$reset"
printf 'E0B4-7  %s%s%s %s %s %s%s\n' \
    "$slate_bg" "$gold_fg" "$right_round" "$right_round_thin" \
    "$left_round" "$left_round_thin" "$reset"
printf 'E0B8-B  %s%s%s %s %s %s%s\n' \
    "$slate_bg" "$blue_fg" "$bottom_left" "$descending_left" \
    "$bottom_right" "$ascending_right" "$reset"
printf 'E0BC-F  %s%s%s %s %s %s%s\n' \
    "$slate_bg" "$purple_fg" "$top_left" "$ascending_right_alias" \
    "$top_right" "$descending_left_alias" "$reset"
printf 'E0D6-7  %s%s%s %s%s\n' \
    "$slate_bg" "$white" "$right_extended" "$left_extended" "$reset"

# Kitty's Fira Code progress family is generated independently of the selected
# font. Adjacent segments expose frame/fill discontinuities; spinner phases
# expose clipping, arc geometry, and stale shared-resource reuse.
printf '\nprogress and spinner family\n'
printf 'EE00-2  %s%s%s%s%s%s%s\n' \
    "$blue_fg" "$progress_left" "$progress_middle" "$progress_right" \
    "$white" "$progress_left" "$reset"
printf 'EE03-5  %s%s%s%s%s%s%s\n' \
    "$gold_fg" "$progress_left_filled" "$progress_middle_filled" \
    "$progress_right_filled" "$white" "$progress_middle_filled" "$reset"
printf 'EE06-B  %s%s %s %s %s %s %s%s\n' \
    "$purple_fg" "$spinner_0" "$spinner_1" "$spinner_2" "$spinner_3" \
    "$spinner_4" "$spinner_5" "$reset"

printf '\nGate: inspect joins, mirrored pairs, curves, diagonals, corners, progress frames/fills, spinner arcs, clipping, and duplicate overlays.\n'
