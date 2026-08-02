#!/bin/sh
set -eu

sleep 1
printf '\033[2J\033[H'
printf 'Normal width\r\n'
printf '\033#6DOUBLE WIDTH\r\n'
printf '\033#3DOUBLE HEIGHT\r\n'
printf '\033#4DOUBLE HEIGHT\r\n'
printf '\033#5\033[73mraised\033[74mlowered\033[0m normal\r\n'
printf '\033[4;9;38;5;208mUnderline + strike\033[0m\r\n'
printf '\033[33mCursor check\033[0m'
sleep 30
