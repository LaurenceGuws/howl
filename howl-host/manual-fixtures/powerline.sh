#!/bin/sh
#
# Deterministic Powerline separator fixture for Howl's manual rendering gate.
# It emits UTF-8 bytes directly so the result does not depend on shell paste,
# prompt configuration, locale glyph entry, or an installed Powerline theme.

set -eu

escape=$(printf '\033')
right=$(printf '\356\202\260')
right_thin=$(printf '\356\202\261')
right_round=$(printf '\356\202\264')

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

printf 'Gate: inspect filled joins, thin-stroke continuity, rounded edge, and duplicate overlays.\n'
