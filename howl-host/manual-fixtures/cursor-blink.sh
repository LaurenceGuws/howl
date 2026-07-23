#!/bin/sh
set -eu

printf '\033[2J\033[H\033[?25h\033[?12h\033[1 q'
printf 'PASS condition: the block cursor after this text blinks twice per second -> '
sleep 15
