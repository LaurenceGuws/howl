#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

command -v glslc >/dev/null
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

# This is the exact command used to produce the checked-in artifact.
glslc -o "$temporary_dir/trail.frag.spv" src/shaders/trail.frag

expected_source=6830222961deebf9fa2aea66b53c4a2b13aa39e03471ecf75a8f1bd2ad245b66
expected_spirv=c9ea5e2ffc78b12be9e4661990de4c6a4fd570733dd9fbe79c0ddde20d679d14
source_hash=$(sha256sum src/shaders/trail.frag | cut -d' ' -f1)
spirv_hash=$(sha256sum "$temporary_dir/trail.frag.spv" | cut -d' ' -f1)
[[ "$source_hash" == "$expected_source" ]]
[[ "$spirv_hash" == "$expected_spirv" ]]
cmp -- "$temporary_dir/trail.frag.spv" src/shaders/trail.frag.spv
printf '%s\n' 'trail shader reproducibility passed'
