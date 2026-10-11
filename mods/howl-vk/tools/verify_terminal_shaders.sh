#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

shader_tmp=$(mktemp -d)
trap 'rm -rf -- "$shader_tmp"' EXIT HUP INT TERM

glslc -fshader-stage=vert src/shaders/terminal.vert -o "$shader_tmp/terminal.vert.spv"
glslc -fshader-stage=frag src/shaders/terminal.frag -o "$shader_tmp/terminal.frag.spv"
cmp "$shader_tmp/terminal.vert.spv" src/shaders/terminal.vert.spv
cmp "$shader_tmp/terminal.frag.spv" src/shaders/terminal.frag.spv
spirv-val src/shaders/terminal.vert.spv
spirv-val src/shaders/terminal.frag.spv
