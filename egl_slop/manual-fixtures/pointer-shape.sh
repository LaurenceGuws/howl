#!/bin/sh
set -eu

printf 'Keep the pointer inside this window.\n'
printf 'Expected phases: wait -> crosshair -> wait -> pointer -> wait -> default.\n'
printf '\033]22;wait\033\\Phase 1/6: wait (3 seconds)\n'
sleep 3
printf '\033]22;>crosshair\033\\Phase 2/6: crosshair (3 seconds)\n'
sleep 3
printf '\033]22;<\033\\Phase 3/6: wait after pop (3 seconds)\n'
sleep 3
printf '\033[?1049h\033]22;pointer\033\\Alternate bank: pointer (3 seconds)\n'
sleep 3
printf '\033[?1049lPrimary bank restored: wait (3 seconds)\n'
sleep 3
printf '\033cTerminal reset: default. Receipt complete; close the window.\n'
sleep 10
