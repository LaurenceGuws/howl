#!/bin/sh
set -eu

old_stty=$(stty -g)
trap 'stty "$old_stty"' EXIT HUP INT TERM
stty raw -echo

printf '\033[11t\033[13t\033[19t\033[20t'
reply=$(timeout 5 dd bs=1 count=29 2>/dev/null || true)
expected=$(printf '\033[1t\033[3;0;0t\033[9;0;0t\033]LHowl\033\\')
stty "$old_stty"

if [ "$reply" != "$expected" ]; then
    printf 'FAIL: unexpected window-query bytes\n'
    printf '%s' "$reply" | od -An -tx1
    exit 1
fi

printf 'PASS: exact state, position, screen, and icon-title replies.\n'
printf 'Issuing one-way minimize request; the compositor may ignore it.\n'
printf '\033[2t'
sleep 10
