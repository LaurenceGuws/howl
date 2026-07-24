#!/bin/sh
set -eu

printf '\033[2J\033[H'
printf 'Howl byte-to-pixels receipt\n'
printf 'ASCII: direct PTY -> VT -> retained visual -> GLES\n'
printf 'Unicode: λ café box \342\224\214\342\224\200\342\224\220\n'
printf '\033[31mred\033[0m \033[32mgreen\033[0m \033[34mblue\033[0m cursor -> '
sleep 15
