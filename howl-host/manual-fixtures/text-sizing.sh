#!/bin/sh
set -eu

sleep 1
printf '\033[2J\033[H'
printf 'Kitty OSC 66 text sizing\r\n'
printf 'normal '
printf '\033]66;s=2;scale two\033\\'
printf '\r\n\r\n'
printf '\033]66;s=3;S3\033\\'
printf '\r\n\r\n\r\n'
printf '\033]66;s=2:w=3:n=1:d=2:v=0:h=0;TL\033\\'
printf '\r\n\r\n'
printf '\033]66;s=2:w=3:n=1:d=2:v=1:h=1;BR\033\\'
printf '\r\n\r\n'
printf '\033]66;s=2:w=3:n=1:d=2:v=2:h=2;CTR\033\\'
printf '\r\n\r\n'
printf '\033[4;9;38;5;208m\033]66;s=2:w=2;DEC\033\\\033[0m'
sleep 30
