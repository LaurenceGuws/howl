#!/bin/sh
set -eu

old_stty=$(stty -g)
trap 'stty "$old_stty"' EXIT HUP INT TERM

stty raw -echo
printf '\033]52;c;SG93bC1PU0M1Mg==\033\\'
printf '\033]52;c;?\033\\'
reply=$(timeout 5 dd bs=1 count=25 2>/dev/null || true)
stty "$old_stty"

expected=$(printf '\033]52;c;SG93bC1PU0M1Mg==\033\\')
if [ "$reply" != "$expected" ]; then
    printf 'FAIL: unexpected OSC 52 reply bytes\n'
    printf '%s' "$reply" | od -An -tx1
    exit 1
fi

printf 'PASS: exact OSC 52 set/query reply; clipboard should contain Howl-OSC52\n'
printf 'Manual compositor receipt: paste in another client before this exits.\n'
sleep 15
